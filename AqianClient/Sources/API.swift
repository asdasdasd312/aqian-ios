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

final class API {
    static let shared = API()

    private var base: String {
        UserDefaults.standard.string(forKey: "gw_url") ?? "https://REPLACE-ME.trycloudflare.com"
    }
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
        guard let req = request("/api/sessions") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(SessionsResp.self, from: data).sessions
    }

    func messages(id: String, limit: Int = 60) async throws -> [Msg] {
        guard let req = request("/api/messages",
                                query: [URLQueryItem(name: "id", value: id),
                                        URLQueryItem(name: "limit", value: String(limit))])
        else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(MessagesResp.self, from: data).messages
    }

    func send(_ text: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["text": text])
        guard let req = request("/api/send", method: "POST", body: payload) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? JSONDecoder().decode(OkResp.self, from: data)
    }
}
