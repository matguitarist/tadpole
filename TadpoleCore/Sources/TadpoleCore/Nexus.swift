// Nexus Mods: the account behind a personal API key, and download links.
//
// Download links come from the v1 REST API and need the user's API key.
// Premium accounts can ask for any file; free accounts need the one-time
// key/expires pair from an nxm:// link, which the website hands out when
// you click "Mod Manager Download" (or "Slow download" after it).
//
// Nexus API acceptable use policy:
// https://help.nexusmods.com/article/114-api-acceptable-use-policy

import Foundation

public struct NexusUser: Sendable, Equatable, Decodable {
    public let name: String
    public let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isPremium = "is_premium"
    }

    public init(name: String, isPremium: Bool) {
        self.name = name
        self.isPremium = isPremium
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
    }
}

/// A Nexus "Mod Manager Download" link, e.g.
/// nxm://baldursgate3/mods/141/files/12345?key=abc&expires=1700000000&user_id=42
public struct NXMLink: Sendable, Equatable {
    public let gameDomain: String
    public let modID: Int
    public let fileID: Int
    public let key: String?
    public let expires: String?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "nxm",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "mods", parts[2] == "files",
              let modID = Int(parts[1]), let fileID = Int(parts[3])
        else { return nil }

        let query = components.queryItems ?? []
        gameDomain = host.lowercased()
        self.modID = modID
        self.fileID = fileID
        key = query.first { $0.name == "key" }?.value
        expires = query.first { $0.name == "expires" }?.value
    }

    public var isForBG3: Bool { gameDomain == NexusClient.gameDomain }
}

/// What went wrong talking to Nexus. The app words these for the user;
/// `serverMessage` is Nexus's own text, when it sent one.
public enum NexusError: Error, Sendable, Equatable {
    case noAPIKey
    case keyRejected(serverMessage: String?)
    case premiumOnly(serverMessage: String?)
    case rateLimited
    case failed(status: Int, serverMessage: String?)
    case noDownloadLink
}

public struct NexusClient: Sendable {
    public static let gameDomain = "baldursgate3"
    public static let gameID = 3474  // Baldur's Gate 3's numeric Nexus game ID

    public static let homeURL = URL(string: "https://www.nexusmods.com/\(gameDomain)")!
    public static let signInURL = URL(string: "https://users.nexusmods.com/auth/sign_in")!
    public static let apiKeyPageURL = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api")!

    public static func modPageURL(_ modID: Int) -> URL {
        URL(string: "https://www.nexusmods.com/\(gameDomain)/mods/\(modID)")!
    }

    /// Nexus's API policy asks for a consistent Application-Name and the
    /// current Application-Version on every request.
    static let applicationName = "Tadpole"
    private static let restBaseURL = URL(string: "https://api.nexusmods.com/v1/")!

    let apiKey: String?
    let appVersion: String
    let session: URLSession

    public init(apiKey: String?, appVersion: String, session: URLSession = .shared) {
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.appVersion = appVersion
        self.session = session
    }

    public func validateKey() async throws -> NexusUser {
        try await get("users/validate.json")
    }

    /// The mod's name on Nexus.
    public func modName(_ modID: Int) async throws -> String {
        struct Mod: Decodable { let name: String }
        let mod: Mod = try await get("games/\(Self.gameDomain)/mods/\(modID).json")
        return mod.name
    }

    /// A short-lived CDN URL for one file. Free accounts must pass the
    /// key/expires values from an nxm:// link; Premium accounts can omit them.
    public func downloadURL(modID: Int, fileID: Int, key: String? = nil, expires: String? = nil) async throws -> URL {
        struct Mirror: Decodable { let URI: String }
        var query: [URLQueryItem] = []
        if let key, let expires {
            query = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "expires", value: expires)]
        }
        let mirrors: [Mirror] = try await get("games/\(Self.gameDomain)/mods/\(modID)/files/\(fileID)/download_link.json", query: query)
        guard let url = mirrors.first.flatMap({ URL(string: $0.URI) }) else { throw NexusError.noDownloadLink }
        return url
    }

    /// The download link for an nxm:// link.
    public func downloadURL(for link: NXMLink) async throws -> URL {
        try await downloadURL(modID: link.modID, fileID: link.fileID, key: link.key, expires: link.expires)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let apiKey else { throw NexusError.noAPIKey }
        var url = Self.restBaseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue(Self.applicationName, forHTTPHeaderField: "Application-Name")
        request.setValue(appVersion, forHTTPHeaderField: "Application-Version")
        request.setValue("Tadpole-macOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        struct Message: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Message.self, from: data))?.message
        switch http.statusCode {
        case 401: throw NexusError.keyRejected(serverMessage: message)
        case 403: throw NexusError.premiumOnly(serverMessage: message)
        case 429: throw NexusError.rateLimited
        default: throw NexusError.failed(status: http.statusCode, serverMessage: message)
        }
    }
}

/// Downloads a file with progress. URLSession's async download API doesn't
/// report progress, so this wraps a delegate-based download task.
public enum FileDownloader {
    /// Downloads `url` into a new temporary folder, keeping the server's
    /// file name (so the archive's extension is kept).
    public static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = Delegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempFile, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NexusError.failed(status: http.statusCode, serverMessage: nil)
        }
        let name = response.suggestedFilename.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.lastPathComponent.removingPercentEncoding
            ?? "download.zip"
        let folder = FileManager.default.temporaryDirectory.appending(path: "tadpole-download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        // Only touched from the session's serial delegate queue.
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        let progress: @Sendable (Double) -> Void

        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // `location` is deleted when this method returns, so move it first.
            let keep = FileManager.default.temporaryDirectory.appending(path: "tadpole-dl-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: keep)
                if let response = downloadTask.response {
                    continuation?.resume(returning: (keep, response))
                } else {
                    continuation?.resume(throwing: NexusError.failed(status: 0, serverMessage: nil))
                }
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
}
