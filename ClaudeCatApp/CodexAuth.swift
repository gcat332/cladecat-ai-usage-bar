import Foundation

func codexAuthURL() -> URL {
    if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
        return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
}

func readCodexCredentials() -> (token: String?, accountId: String?, error: String?) {
    guard let data = try? Data(contentsOf: codexAuthURL()) else {
        return (nil, nil, "login Codex ก่อน (รัน `codex`)")
    }
    guard let parsed = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
          let token = parsed.tokens?.access_token, !token.isEmpty else {
        return (nil, nil, "auth.json parse ไม่ออก")
    }
    return (token, parsed.tokens?.account_id, nil)
}

func formURLEncoded(_ params: [String: String]) -> Data? {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let pairs = params.map { k, v -> String in
        let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
        let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
        return "\(ek)=\(ev)"
    }
    return pairs.joined(separator: "&").data(using: .utf8)
}

func refreshCodexToken(completion: @escaping (String?, String?, String?) -> Void) {
    let url = codexAuthURL()
    guard let data = try? Data(contentsOf: url),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          var tokens = root["tokens"] as? [String: Any],
          let refreshToken = tokens["refresh_token"] as? String, !refreshToken.isEmpty else {
        completion(nil, nil, "ไม่มี refresh token ใน auth.json")
        return
    }
    let accountId = tokens["account_id"] as? String

    var req = URLRequest(url: codexOAuthTokenURL, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = formURLEncoded([
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": codexOAuthClientID,
    ])

    URLSession.shared.dataTask(with: req) { data, resp, error in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, (200..<300).contains(code), let data = data,
              let r = try? JSONDecoder().decode(CodexRefreshResponse.self, from: data),
              let newAccess = r.access_token, !newAccess.isEmpty else {
            let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            log("codex refresh: HTTP \(code) — \(String(b.prefix(200)))")
            completion(nil, nil, "refresh ล้มเหลว (HTTP \(code))")
            return
        }
        tokens["access_token"] = newAccess
        if let idt = r.id_token, !idt.isEmpty { tokens["id_token"] = idt }
        if let rt = r.refresh_token, !rt.isEmpty { tokens["refresh_token"] = rt }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? out.write(to: url)
        }
        log("codex refresh: 200 OK — token ใหม่")
        completion(newAccess, accountId, nil)
    }.resume()
}
