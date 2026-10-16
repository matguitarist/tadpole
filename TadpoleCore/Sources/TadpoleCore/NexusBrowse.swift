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
    /// Files in the same group are versions of the same file: the newest
    /// current one replaces the others.
    public let groupId: Int?
    /// What changed in this version, as the author wrote it on the file.
    public let changelogText: [String]?

    public init(fileId: Int, name: String, version: String?, category: String, sizeInBytes: String? = nil, date: Int,
                description: String? = nil, groupId: Int?, changelogText: [String]? = nil) {
        self.fileId = fileId
        self.name = name
        self.version = version
        self.category = category
        self.sizeInBytes = sizeInBytes
        self.date = date
        self.description = description
        self.groupId = groupId
        self.changelogText = changelogText
    }

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

    /// A collection known only by its slug (from a link): the rest loads
    /// with its revision.
    public init(slug: String) {
        self.init(slug: slug, name: slug, summary: nil, author: nil, endorsements: nil, totalDownloads: nil,
                  tileImageURL: nil, latestRevision: nil, modCount: nil, totalSize: nil)
    }

    init(slug: String, name: String, summary: String?, author: String?, endorsements: Int?, totalDownloads: Int?,
         tileImageURL: URL?, latestRevision: Int?, modCount: Int?, totalSize: Int64?) {
        self.slug = slug
        self.name = name
        self.summary = summary
        self.author = author
        self.endorsements = endorsements
        self.totalDownloads = totalDownloads
        self.tileImageURL = tileImageURL
        self.latestRevision = latestRevision
        self.modCount = modCount
        self.totalSize = totalSize
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
    /// Whether the mod's Nexus page lists Norbyte's Script Extender as a
    /// requirement, directly or through another mod of the collection.
    public internal(set) var scriptExtender: ScriptExtenderNeed?

    public var id: Int { fileID }
}

/// Why a mod needs the Script Extender, from the requirements its author
/// lists on Nexus. Authors don't always list it, so a mod without one may
/// still use it; installed mods are checked for its scripts (PakMod).
public enum ScriptExtenderNeed: Hashable, Sendable {
    case direct
    /// Requires another mod that needs it (that mod's name).
    case through(String)
}

/// A requirement listed on a mod's Nexus page: another Nexus mod, or a page
/// elsewhere (the Script Extender is usually listed as its GitHub page).
public struct NexusRequirement: Hashable, Sendable, Decodable {
    public let modId: String?
    public let modName: String?
    public let url: String?
    public let externalRequirement: Bool?
    /// The author's note ("only for the spells part"…).
    public let notes: String?

    public init(modId: String?, modName: String?, url: String?, externalRequirement: Bool?, notes: String? = nil) {
        self.modId = modId
        self.modName = modName
        self.url = url
        self.externalRequirement = externalRequirement
        self.notes = notes
    }

    /// Norbyte's Script Extender: its Nexus page (mod 2172) or its GitHub.
    public var isScriptExtender: Bool {
        if modId == String(ScriptExtender.nexusModID) && externalRequirement != true { return true }
        if let url, url.localizedCaseInsensitiveContains("bg3se") { return true }
        return externalRequirement == true && (modName ?? "").localizedCaseInsensitiveContains("script extender")
    }

    /// The Nexus mod this points to, when it's one.
    public var nexusModID: Int? { externalRequirement == true ? nil : modId.flatMap { Int($0) } }
}

public enum ScriptExtender {
    /// "Baldur's Gate 3 Script Extender (BG3SE)" on Nexus.
    public static let nexusModID = 2172

    /// For each mod, whether it needs the Script Extender: it lists it, or
    /// it lists a mod of `requirements` that does (followed through chains).
    public static func needs(requirements: [Int: [NexusRequirement]]) -> [Int: ScriptExtenderNeed] {
        var result: [Int: ScriptExtenderNeed] = [:]
        for (modID, required) in requirements where required.contains(where: \.isScriptExtender) {
            result[modID] = .direct
        }
        // Spread to mods that require those, until nothing changes.
        var changed = true
        while changed {
            changed = false
            for (modID, required) in requirements.sorted(by: { $0.key < $1.key }) where result[modID] == nil {
                if let through = required.first(where: { $0.nexusModID.map { result[$0] != nil } ?? false }) {
                    result[modID] = .through(through.modName ?? "Mod \(through.modId ?? "")")
                    changed = true
                }
            }
        }
        return result
    }
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
    /// What a mod's Nexus page lists as required: other Nexus mods, or pages
    /// elsewhere (the Script Extender's GitHub…).
    public func requirements(forMod modID: Int) async throws -> [NexusRequirement] {
        struct Response: Decodable {
            struct Mod: Decodable {
                struct Requirements: Decodable {
                    struct Page: Decodable { let nodes: [NexusRequirement] }
                    let nexusRequirements: Page?
                }
                let modRequirements: Requirements?
            }
            let mod: Mod
        }
        let response: Response = try await graphQL(
            """
            query Requirements($modId: ID!, $gameId: ID!) {
              mod(modId: $modId, gameId: $gameId) {
                modRequirements { nexusRequirements { nodes { modId modName url externalRequirement notes } } }
              }
            }
            """,
            variables: ["modId": String(modID), "gameId": String(Self.gameID)])
        return response.mod.modRequirements?.nexusRequirements?.nodes ?? []
    }

    public func files(forMod modID: Int) async throws -> [NexusFile] {
        struct Response: Decodable { let modFiles: [NexusFile] }
        let response: Response = try await graphQL(
            """
            query Files($modId: ID!, $gameId: ID!) {
              modFiles(modId: $modId, gameId: $gameId) {
                fileId name version category sizeInBytes date description groupId changelogText
              }
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
                        struct Mod: Decodable {
                            struct Requirements: Decodable {
                                struct Page: Decodable { let nodes: [NexusRequirement] }
                                let nexusRequirements: Page?
                            }
                            let name: String?
                            let modId: Int
                            let modRequirements: Requirements?
                        }
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
                modFiles { fileId optional version file { name modId size mod { name modId modRequirements { nexusRequirements { nodes { modId modName url externalRequirement } } } } } }
              }
            }
            """,
            variables: variables)
        let revision = response.collectionRevision
        var mods = revision.modFiles.compactMap { entry -> CollectionMod? in
            guard let file = entry.file, let modID = file.mod?.modId ?? file.modId else { return nil }
            return CollectionMod(modID: modID, fileID: entry.fileId, modName: file.mod?.name ?? file.name ?? "Mod \(modID)",
                                 fileName: file.name ?? "", version: entry.version, isOptional: entry.optional, sizeKB: file.size)
        }
        var requirements: [Int: [NexusRequirement]] = [:]
        for entry in revision.modFiles {
            if let mod = entry.file?.mod { requirements[mod.modId] = mod.modRequirements?.nexusRequirements?.nodes ?? [] }
        }
        let needs = ScriptExtender.needs(requirements: requirements)
        for index in mods.indices { mods[index].scriptExtender = needs[mods[index].modID] }
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
