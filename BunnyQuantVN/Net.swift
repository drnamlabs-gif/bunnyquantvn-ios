// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import CryptoKit
import DeviceCheck
import Foundation

/// Máy chủ từ chối bằng một câu chữ trong "detail" cùng mã HTTP; giữ mã để từng màn hình xử lý riêng.
struct APIError: Error {
    enum Code { case quota, locked, notFound, unauthorized, busy, offline, timeout, server }
    var code: Code
    var status = 0
    var message = ""
}

enum Config {
    /// Gốc tên miền; đường dẫn gọi kèm `/api/...`. Đổi bằng build setting BQ_API_BASE để chạy với máy chủ dev.
    static let base: String = (Bundle.main.object(forInfoDictionaryKey: "BQ_API_BASE") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "https://bunnyquant.vn"
}

enum Http {
    /// Một hàm cho mọi lệnh gọi: thời hạn, thân JSON, giải mã lỗi. Trả về dữ liệu thô.
    static func send(_ path: String, method: String = "GET", body: Any? = nil, token: String? = nil) async throws -> Data {
        guard let url = URL(string: Config.base + path) else { throw APIError(code: .server, message: "bad url") }
        var req = URLRequest(url: url, timeoutInterval: 60)   // phân tích mất vài giây, tệ nhất ~30s
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) }
        catch let e as URLError { throw APIError(code: e.code == .timedOut ? .timeout : .offline, message: e.localizedDescription) }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        throw decode(status, data)
    }

    private static func decode(_ status: Int, _ data: Data) -> APIError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        var e = APIError(code: .server, status: status)
        if let s = json?["detail"] as? String { e.message = s }
        switch status {
        case 401: e.code = .unauthorized
        case 403: e.code = .locked
        case 404: e.code = .notFound
        case 429: e.code = .quota
        case 503: e.code = .busy        // nguồn dữ liệu giá tạm bận
        default: break
        }
        return e
    }

    static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Mỗi lần cài một tài khoản riêng: máy chủ cấp phiên sau khi Apple xác nhận đây là app thật trên máy thật (App Attest).
actor Auth {
    static let shared = Auth()

    struct Tokens: Codable {
        var access: String, refresh: String, expiresAt: Double
    }

    private var session: Tokens? = Auth.load("session.anon")
    private var inflight: Task<Tokens, Error>?

    private static func load(_ key: String) -> Tokens? {
        Keychain.get(key).flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }
    }
    private func save(_ t: Tokens?) {
        Keychain.set("session.anon", t.flatMap { try? JSONEncoder().encode($0) })
    }

    func accessToken() async throws -> String {
        if let t = session, t.expiresAt - Date().timeIntervalSince1970 > 60 { return t.access }
        return try await renew().access
    }

    /// Gọi sau khi nhận 401 một lần: làm mới rồi thử lại.
    func forceRefresh() async throws -> String {
        try await renew().access
    }

    /// Gộp các lệnh gọi đồng thời vào một lần làm mới / đăng ký, tránh tạo hai tài khoản.
    private func renew() async throws -> Tokens {
        if let inflight { return try await inflight.value }
        let task = Task { try await self.doRenew() }
        inflight = task
        defer { inflight = nil }
        return try await task.value
    }

    private func doRenew() async throws -> Tokens {
        if let s = session {
            do { return try await refresh(s) } catch let e as APIError where e.code == .offline || e.code == .timeout { throw e } catch {}
        }
        return try await register()
    }

    private func tokens(from json: [String: Any]) throws -> Tokens {
        guard let a = json["access_token"] as? String, let r = json["refresh_token"] as? String else {
            throw APIError(code: .server, message: "no session")
        }
        let ttl = (json["expires_in"] as? Double) ?? 3600
        return Tokens(access: a, refresh: r, expiresAt: Date().timeIntervalSince1970 + ttl)
    }

    private func register() async throws -> Tokens {
        let challenge = Http.json(try await Http.send("/api/ios/challenge"))["challenge"] as? String ?? ""
        var body: [String: Any] = ["challenge": challenge]
        if DCAppAttestService.shared.isSupported {
            // Mỗi khóa chỉ chứng thực được một lần, nên luôn tạo khóa mới cho lần đăng ký.
            let svc = DCAppAttestService.shared
            let keyId = try await svc.generateKey()
            let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
            let attestation = try await svc.attestKey(keyId, clientDataHash: hash)
            body["key_id"] = keyId
            body["attestation"] = attestation.base64EncodedString()
            Keychain.set("attest.key", Data(keyId.utf8))
        }
        let t = try tokens(from: Http.json(try await Http.send("/api/ios/register", method: "POST", body: body)))
        session = t; save(t)
        return t
    }

    private func refresh(_ s: Tokens) async throws -> Tokens {
        let t = try tokens(from: Http.json(try await Http.send("/api/ios/refresh", method: "POST", body: ["refresh_token": s.refresh])))
        session = t; save(t)
        return t
    }

    /// Sau khi xóa tài khoản: bỏ phiên, lần mở tiếp theo tự đăng ký tài khoản mới.
    func wipe() {
        session = nil
        ["session.anon", "attest.key"].forEach { Keychain.set($0, nil) }
    }
}

enum API {
    /// Lệnh gọi có đăng nhập. 401 thì làm mới phiên và thử lại đúng một lần.
    static func call(_ path: String, method: String = "GET", body: Any? = nil) async throws -> Data {
        let token = try await Auth.shared.accessToken()
        do { return try await Http.send(path, method: method, body: body, token: token) }
        catch let e as APIError where e.code == .unauthorized {
            let fresh = try await Auth.shared.forceRefresh()
            return try await Http.send(path, method: method, body: body, token: fresh)
        }
    }
}
