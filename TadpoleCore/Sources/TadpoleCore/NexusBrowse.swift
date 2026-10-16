// Browsing Nexus Mods: mods, their files, and collections (curated lists of
// mods pinned to exact files). These use the public v2 GraphQL API, which
// needs no key.

import Foundation

public struct NexusMod: Identifiable, Hashable, Sendable, Decodable {
    public let modId: Int
    public let name: String
    public let summary: String?
    public let author: String?
    public let version: String?
    public let downloads: Int?
    public let endorsements: Int?
    public let thumbnailUrl: String?
    public let pictureUrl: String?
    public let updatedAt: String?

    public var id: Int { modId }
    public var pageURL: URL { NexusClient.modPageURL(modId) }
    public var thumbnailURL: URL? { thumbnailUrl.flatMap(URL.init(string:)) }
    public var pictureURL: URL? { pictureUrl.flatMap(URL.init(string:)) }
}

public struct NexusFile: Identifiable, Hashable, Sendable, Decodable {
    public let fileId: Int
    public let name: String
    public let version: String?
    public let category: String      // MAIN, OPTIONAL, UPDATE, MISCELLANEOUS, OLD_VERSION, ARCHIVED…
    public let sizeInBytes: String?  // BigInt comes back as a string
    public let date: Int             // unix seconds
    public let description: String?

    public var id: Int { fileId }
    public var uploadedAt: Date { Date(timeIntervalSince1970: TimeInterval(date)) }
    public var byteCount: Int64? { sizeInBytes.flatMap { Int64($0) } }
    public var isCurrent: Bool { !["OLD_VERSION", "ARCHIVED", "REMOVED", "DELETED"].contains(category) }

    /// Lower sorts first: main files at the top, like on the website.
    public var categoryOrder: Int {
        ["MAIN", "UPDATE", "OPTIONAL", "MISCELLANEOUS", "OLD_VERSION", "ARCHIVED"].firstIndex(of: category) ?? 99
    }
}

public enum NexusSort: String, CaseIterable, Sendable {
    case endorsements, downloads, updatedAt, createdAt
}

public struct NexusCollection: Identifiable, Hashable, Sendable {
    public let slug: String
    public let name: String
    public let summary: String?
    public let author: String?
    public let endorsements: Int?
    public let totalDownloads: Int?
    public let tileImageURL: URL?
    public let latestRevision: Int?
    public let modCount: Int?
    public let totalSize: Int64?  // bytes

    public var id: String { slug }
    public var pageURL: URL {
        URL(string: "https://www.nexusmods.com/games/\(NexusClient.gameDomain)/collections/\(slug)")!
    }
}

/// One pinned file in a collection revision.
public struct CollectionMod: Identifiable, Hashable, Sendable {
    public let modID: Int
    public let fileID: Int
    public let modName: String
    public let fileName: String
    public let version: String?
    public let isOptional: Bool
    public let sizeKB: Int?

    public var id: Int { fileID }
}

public struct CollectionRevision: Sendable {
    public let collection: NexusCollection
    public let revisionNumber: Int
    public let mods: [CollectionMod]
}

public enum CollectionSort: String, CaseIterable, Sendable {
    case endorsements, downloads, updatedAt, createdAt
}

private struct CollectionNode: Decodable {
    struct Image: Decodable { let url: String?; let thumbnailUrl: String? }
    struct User: Decodable { let name: String? }
    struct Revision: Decodable { let revisionNumber: Int?; let modCount: Int?; let totalSize: String? }

    let slug: String
    let name: String
    let summary: String?
    let endorsements: Int?
    let totalDownloads: Int?
    let tileImage: Image?
    let user: User?
    let latestPublishedRevision: Revision?

    static let fields = """
        slug name summary endorsements totalDownloads
        tileImage { url thumbnailUrl(size: med) }
        user { name }
        latestPublishedRevision { revisionNumber modCount totalSize }
        """

    var model: NexusCollection {
        NexusCollection(slug: slug, name: name, summary: summary, author: user?.name, endorsements: endorsements,
                        totalDownloads: totalDownloads,
                        tileImageURL: (tileImage?.thumbnailUrl ?? tileImage?.url).flatMap(URL.init(string:)),
                        latestRevision: latestPublishedRevision?.revisionNumber, modCount: latestPublishedRevision?.modCount,
                        totalSize: latestPublishedRevision?.totalSize.flatMap { Int64($0) })
    }
}

extension NexusClient {
    private static let graphQLURL = URL(string: "https://api.nexusmods.com/v2/graphql")!
    private static let modFields = "modId name summary author version downloads endorsements thumbnailUrl pictureUrl updatedAt"

    public struct Page<Item: Sendable>: Sendable {
        public let items: [Item]
        public let totalCount: Int
    }

    public func searchMods(query: String, sort: NexusSort, offset: Int = 0, count: Int = 30) async throws -> Page<NexusMod> {
        var filter: [String: Any] = [
            "gameDomainName": [["value": Self.gameDomain, "op": "EQUALS"]],
            "adultContent": [["value": false, "op": "EQUALS"]],
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { filter["name"] = [["value": trimmed, "op": "WILDCARD"]] }
        struct Response: Decodable {
            struct Mods: Decodable { let totalCount: Int; let nodes: [NexusMod] }
            let mods: Mods
        }
        let response: Response = try await graphQL(
            """
            query Search($filter: ModsFilter, $sort: [ModsSort!], $offset: Int, $count: Int) {
              mods(filter: $filter, sort: $sort, offset: $offset, count: $count) { totalCount nodes { \(Self.modFields) } }
            }
            """,
            variables: ["filter": filter, "sort": [[sort.rawValue: ["direction": "DESC"]]], "offset": offset, "count": count])
        return Page(items: response.mods.nodes, totalCount: response.mods.totalCount)
    }

    public func mod(id modID: Int) async throws -> NexusMod {
        struct Response: Decodable { let mod: NexusMod }
        let response: Response = try await graphQL(
            "query Mod($modId: ID!, $gameId: ID!) { mod(modId: $modId, gameId: $gameId) { \(Self.modFields) } }",
            variables: ["modId": String(modID), "gameId": String(Self.gameID)])
        return response.mod
    }

    /// A mod's files, main files first and newest first within a section.
    public func files(forMod modID: Int) async throws -> [NexusFile] {
        struct Response: Decodable { let modFiles: [NexusFile] }
        let response: Response = try await graphQL(
            """
            query Files($modId: ID!, $gameId: ID!) {
              modFiles(modId: $modId, gameId: $gameId) { fileId name version category sizeInBytes date description }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)])
        return response.modFiles.sorted { ($0.categoryOrder, -$0.date) < ($1.categoryOrder, -$1.date) }
    }

    public func searchCollections(query: String, sort: CollectionSort, offset: Int = 0, count: Int = 30) async throws -> Page<NexusCollection> {
        var filter: [String: Any] = [
            "gameDomain": [["value": Self.gameDomain, "op": "EQUALS"]],
            "adultContent": [["value": false, "op": "EQUALS"]],
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { filter["generalSearch"] = [["value": trimmed, "op": "WILDCARD"]] }
        struct Response: Decodable {
            struct Page: Decodable { let totalCount: Int; let nodes: [CollectionNode] }
            let collectionsV2: Page
        }
        let response: Response = try await graphQL(
            """
            query Collections($filter: CollectionsSearchFilter, $sort: [CollectionsSearchSort!], $offset: Int, $count: Int) {
              collectionsV2(filter: $filter, sort: $sort, offset: $offset, count: $count) {
                totalCount
                nodes { \(CollectionNode.fields) }
              }
            }
            """,
            variables: ["filter": filter, "sort": [[sort.rawValue: ["direction": "DESC"]]], "offset": offset, "count": count])
        return Page(items: response.collectionsV2.nodes.map(\.model), totalCount: response.collectionsV2.totalCount)
    }

    /// A collection's pinned files. `revision` nil means the latest published one.
    public func collectionRevision(slug: String, revision: Int? = nil) async throws -> CollectionRevision {
        struct Response: Decodable {
            struct Revision: Decodable {
                struct ModFile: Decodable {
                    struct File: Decodable {
                        struct Mod: Decodable { let name: String?; let modId: Int }
                        let name: String?
                        let modId: Int?
                        let size: Int?
                        let mod: Mod?
                    }
                    let fileId: Int
                    let optional: Bool
                    let version: String?
                    let file: File?
                }
                let revisionNumber: Int
                let collection: CollectionNode
                let modFiles: [ModFile]
            }
            let collectionRevision: Revision
        }
        var variables: [String: Any] = ["slug": slug, "domainName": Self.gameDomain]
        if let revision { variables["revision"] = revision }
        let response: Response = try await graphQL(
            """
            query Revision($slug: String!, $revision: Int, $domainName: String) {
              collectionRevision(slug: $slug, revision: $revision, domainName: $domainName) {
                revisionNumber
                collection { \(CollectionNode.fields) }
                modFiles { fileId optional version file { name modId size mod { name modId } } }
              }
            }
            """,
            variables: variables)
        let revision = response.collectionRevision
        let mods = revision.modFiles.compactMap { entry -> CollectionMod? in
            guard let file = entry.file, let modID = file.mod?.modId ?? file.modId else { return nil }
            return CollectionMod(modID: modID, fileID: entry.fileId, modName: file.mod?.name ?? file.name ?? "Mod \(modID)",
                                 fileName: file.name ?? "", version: entry.version, isOptional: entry.optional, sizeKB: file.size)
        }
        return CollectionRevision(collection: revision.collection.model, revisionNumber: revision.revisionNumber, mods: mods)
    }

    func graphQL<T: Decodable>(_ query: String, variables: [String: Any]) async throws -> T {
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.applicationName, forHTTPHeaderField: "Application-Name")
        request.setValue(appVersion, forHTTPHeaderField: "Application-Version")
        request.setValue("Tadpole-macOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)

        let envelope = try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: data)
        if let result = envelope.data { return result }
        throw NexusError.failed(status: 200, serverMessage: envelope.errors?.map(\.message).joined(separator: "\n"))
    }
}

private struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct GraphQLError: Decodable { let message: String }
    let data: T?
    let errors: [GraphQLError]?
}

extension String {
    /// Nexus summaries can hold BBCode and HTML entities; this keeps the text.
    public var strippingNexusMarkup: String {
        var text = replacing(/\[\/?[a-zA-Z]+(=[^\]]*)?\]/, with: "")
        for (entity, character) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "<br />": "\n", "<br>": "\n"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
