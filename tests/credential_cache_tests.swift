import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

func tempCacheURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("claudecat-cache-tests")
        .appendingPathComponent(name)
}

func writeCache(_ json: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try json.data(using: .utf8)!.write(to: url)
}

@main
struct CredentialCacheTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let validURL = tempCacheURL("valid.json")
        let expiringURL = tempCacheURL("expiring.json")
        let invalidURL = tempCacheURL("invalid.json")

        try? FileManager.default.removeItem(at: validURL.deletingLastPathComponent())

        try writeCache("""
        {"claudeAiOauth":{"accessToken":"access-valid","refreshToken":"refresh-valid","expiresAt":1700003600000}}
        """, to: validURL)
        let valid = loadClaudeCredsFromCache(cacheURL: validURL, now: now)
        assert(valid != nil, "valid future cache should be returned")

        try writeCache("""
        {"claudeAiOauth":{"accessToken":"access-expiring","refreshToken":"refresh-expiring","expiresAt":1700000100000}}
        """, to: expiringURL)
        let normalRead = loadClaudeCredsFromCache(cacheURL: expiringURL, now: now)
        assert(normalRead == nil, "cache expiring within refresh margin should be skipped for normal reads")

        let refreshRead = loadClaudeCredsFromCache(cacheURL: expiringURL, now: now, allowExpired: true)
        assert(refreshRead != nil, "expired cache should still be available for refresh-token reads")

        try writeCache("{}", to: invalidURL)
        assert(loadClaudeCredsFromCache(cacheURL: invalidURL, now: now) == nil, "cache without accessToken should be ignored")
    }
}
