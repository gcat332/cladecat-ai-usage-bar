import Foundation
import Security

func loadClaudeCredsRaw(allowExpiredCache: Bool = false, skipCache: Bool = false) -> (data: Data, source: CredSource)? {
    if !skipCache, let data = loadClaudeCredsFromCache(allowExpired: allowExpiredCache) {
        return (data, .cache(defaultClaudeCredsCacheURL()))
    }

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: claudeKeychainService,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
        saveClaudeCredsToCache(data)
        return (data, .keychain)
    }

    let credsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")
    if let data = try? Data(contentsOf: credsURL) {
        saveClaudeCredsToCache(data)
        return (data, .file(credsURL))
    }
    return nil
}

func saveClaudeCredsRaw(_ data: Data, to source: CredSource) {
    switch source {
    case .keychain, .cache:
        saveClaudeCredsToCache(data)
    case .file(let url):
        try? data.write(to: url)
        saveClaudeCredsToCache(data)
    }
}

func readClaudeCredentials(skipCache: Bool = false) -> (creds: OAuthCreds?, error: String?) {
    guard let (data, _) = loadClaudeCredsRaw(allowExpiredCache: true, skipCache: skipCache),
          let parsed = try? JSONDecoder().decode(CredsFile.self, from: data),
          let oauth = parsed.claudeAiOauth else {
        return (nil, "ไม่พบ creds — เปิด Claude Code / login ก่อน")
    }
    return (oauth, nil)
}

func refreshClaudeToken(completion: @escaping (OAuthCreds?, OAuthRefreshFailure?) -> Void) {
    guard let (data, source) = loadClaudeCredsRaw(allowExpiredCache: true),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          var oauth = root["claudeAiOauth"] as? [String: Any],
          let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
        completion(nil, OAuthRefreshFailure(message: "ไม่มี refresh token ใน creds", statusCode: 0, retryAfter: nil))
        return
    }

    var req = URLRequest(url: claudeOAuthTokenURL, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(claudeUserAgent, forHTTPHeaderField: "User-Agent")
    let body: [String: Any] = [
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": claudeOAuthClientID,
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: req) { data, resp, error in
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        guard error == nil, code == 200, let data = data,
              let r = try? JSONDecoder().decode(OAuthRefreshResponse.self, from: data) else {
            let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let message = "refresh ล้มเหลว (HTTP \(code))"
            log("claude refresh: HTTP \(code) retry-after=\(retryAfter.map { String(Int($0)) } ?? "-") — \(String(b.prefix(200)))")
            completion(nil, OAuthRefreshFailure(message: message, statusCode: code, retryAfter: retryAfter))
            return
        }

        let newExpMs = (Date().timeIntervalSince1970 + (r.expires_in ?? 3600)) * 1000
        oauth["accessToken"] = r.access_token
        if let rt = r.refresh_token, !rt.isEmpty { oauth["refreshToken"] = rt }
        oauth["expiresAt"] = newExpMs
        root["claudeAiOauth"] = oauth
        if let out = try? JSONSerialization.data(withJSONObject: root) {
            saveClaudeCredsRaw(out, to: source)
        }
        log("claude refresh: 200 OK — token ใหม่ (exp +\(Int(r.expires_in ?? 3600))s)")
        completion(OAuthCreds(accessToken: r.access_token, expiresAt: newExpMs), nil)
    }.resume()
}

func claudeTokenExpired(_ creds: OAuthCreds) -> Bool {
    guard let exp = creds.expiresAt else { return false }
    return Date(timeIntervalSince1970: exp / 1000) < Date().addingTimeInterval(60)
}
