import Foundation

// 和网关的约定见 D:\阿潜\app\协议.md
struct SessionRow: Decodable, Identifiable {
    let id: String
    let proj: String
    let title: String
    let updated_ms: Double
    let last_role: String
    let last_text: String
    let busy: Bool
}

struct Msg: Decodable, Identifiable {
    let t: Double
    let role: String
    let text: String
    var id: Double { t }
    var isMe: Bool { role == "user" }
}

struct SessionsResp: Decodable { let sessions: [SessionRow] }
struct MessagesResp: Decodable { let messages: [Msg] }
struct OkResp: Decodable { let ok: Bool }

struct Presence: Decodable {
    let state: String   // busy / idle / away
    let idle_seconds: Int
    let note: String
    let t: Double
}

final class API {
    static let shared = API()

    private var bases: [String] {
        var out: [String] = []
        for k in ["gw_url", "gw_url2", "gw_url3"] {
            if let v = UserDefaults.standard.string(forKey: k)?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                out.append(v)
            }
        }
        return out.isEmpty ? ["https://REPLACE-ME.trycloudflare.com"] : out
    }

    /// 当前能用的那条；连上了就把它记回 gw_url，下次先试它。
    private(set) var liveBase: String = UserDefaults.standard.string(forKey: "gw_url") ?? "https://REPLACE-ME.trycloudflare.com"
    private var base: String { liveBase }
    private var key: String {
        UserDefaults.standard.string(forKey: "gw_key") ?? ""
    }

    private func request(_ path: String, query: [URLQueryItem] = [],
                         method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard var c = URLComponents(string: base.trimmingCharacters(in: .whitespaces)) else { return nil }
        c.path = path
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 30
        r.setValue(key, forHTTPHeaderField: "X-Aqian-Key")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func sessions() async throws -> [SessionRow] {
        try JSONDecoder().decode(SessionsResp.self, from: await get("/api/sessions")).sessions
    }

    func messages(id: String, limit: Int = 60) async throws -> [Msg] {
        let data = try await get("/api/messages",
                                 query: [URLQueryItem(name: "id", value: id),
                                         URLQueryItem(name: "limit", value: String(limit))])
        return try JSONDecoder().decode(MessagesResp.self, from: data).messages
    }

    /// 带自动换线的取数据：主地址失败就试备用地址，试通了的记回 gw_url。
    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var lastError: Error = URLError(.badURL)
        for candidate in bases {
            liveBase = candidate
            guard let req = request(path, query: query) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if candidate != bases.first {
                    UserDefaults.standard.set(candidate, forKey: "gw_url")
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func presence() async throws -> Presence {
        try JSONDecoder().decode(Presence.self, from: await get("/api/presence"))
    }

    func send(_ text: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["text": text])
        guard let req = request("/api/send", method: "POST", body: payload) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? JSONDecoder().decode(OkResp.self, from: data)
    }
}
