import Foundation

let claudeCacheRefreshMargin: TimeInterval = 300

struct OAuthCreds: Decodable {
    let accessToken: String
    let expiresAt: Double?
}

struct CredsFile: Decodable {
    let claudeAiOauth: OAuthCreds?
}

enum CredSource {
    case keychain
    case file(URL)
    case cache(URL)
}

func defaultClaudeCredsCacheURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeCat")
        .appendingPathComponent("claude_credentials_cache.json")
}

func loadClaudeCredsFromCache(
    cacheURL: URL = defaultClaudeCredsCacheURL(),
    now: Date = Date(),
    allowExpired: Bool = false
) -> Data? {
    guard let data = try? Data(contentsOf: cacheURL),
          let parsed = try? JSONDecoder().decode(CredsFile.self, from: data),
          let oauth = parsed.claudeAiOauth,
          !oauth.accessToken.isEmpty else {
        return nil
    }

    if allowExpired { return data }
    guard let expiresAt = oauth.expiresAt else { return data }

    let expiry = Date(timeIntervalSince1970: expiresAt / 1000)
    return expiry > now.addingTimeInterval(claudeCacheRefreshMargin) ? data : nil
}

func saveClaudeCredsToCache(_ data: Data, cacheURL: URL = defaultClaudeCredsCacheURL()) {
    do {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmpURL = cacheURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: cacheURL)
    } catch {
        let message = "claude cache: write failed - \(error.localizedDescription)\n"
        FileHandle.standardError.write(message.data(using: .utf8) ?? Data())
    }
}
