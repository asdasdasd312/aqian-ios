import Foundation

struct ChatRow: Identifiable, Codable {
    var id = UUID()
    var t: String
    var role: String
    var text: String
}

struct Ev: Codable {
    var kind: String
    var t: String?
    var text: String?
    var name: String?
    var summary: String?
    var note: String?
}

struct EventsPage {
    var evs: [Ev]
    var next: Int
    var done: Bool
}

/// 电脑那边 /api/settings 的形状（缺字段给默认值，免得老版本报错）。
struct RoomSettings: Decodable {
    var speak: Bool = true
    var life_on: Bool = true
    var wechat_on: Bool = true
    var wechat_max_per_hour: Int = 3
    var quiet_text: String = "23:30–07:30"
    var persona_extra: String = ""
    var ai_name: String = "阿潜"
    var user_name: String = "老大"

    enum CodingKeys: String, CodingKey {
        case speak, life_on, wechat_on, wechat_max_per_hour, quiet_text, persona_extra, ai_name, user_name
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        speak = (try? c.decode(Bool.self, forKey: .speak)) ?? true
        life_on = (try? c.decode(Bool.self, forKey: .life_on)) ?? true
        wechat_on = (try? c.decode(Bool.self, forKey: .wechat_on)) ?? true
        wechat_max_per_hour = (try? c.decode(Int.self, forKey: .wechat_max_per_hour)) ?? 3
        quiet_text = (try? c.decode(String.self, forKey: .quiet_text)) ?? "23:30–07:30"
        persona_extra = (try? c.decode(String.self, forKey: .persona_extra)) ?? ""
        ai_name = (try? c.decode(String.self, forKey: .ai_name)) ?? "阿潜"
        user_name = (try? c.decode(String.self, forKey: .user_name)) ?? "老大"
    }

    init() {}
}

enum SettingsPayload {
    /// "23:30–07:30" → [1410, 450]（分钟）；认不出就返回 nil，不传这个字段。
    static func parseQuiet(_ s: String) -> [Int]? {
        let parts = s.replacingOccurrences(of: "~", with: "–")
            .split(whereSeparator: { "–-— 到".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        func mins(_ t: String) -> Int? {
            let hm = t.split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
            return (h % 24) * 60 + min(59, max(0, m))
        }
        guard let a = mins(parts[0]), let b = mins(parts[1]) else { return nil }
        return [a, b]
    }
}

/// 只做两件事：读她说过的话、把我说的话送过去。
struct ChatAPI {
    var base: String
    var token: String

    private func url(_ path: String, _ extra: [String: String] = [:]) throws -> URL {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { b = "http://192.168.0.233:8099" }
        if !b.hasPrefix("http://") && !b.hasPrefix("https://") { b = "http://" + b }
        while b.hasSuffix("/") { b.removeLast() }

        var comps = URLComponents(string: b + path)!
        var items = [URLQueryItem(name: "t", value: token)]
        for (k, v) in extra { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        guard let u = comps.url else { throw URLError(.badURL) }
        return u
    }

    private func get<T: Decodable>(_ path: String, _ extra: [String: String] = [:]) async throws -> T {
        var req = URLRequest(url: try url(path, extra))
        req.timeoutInterval = 25
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["err"] as? String
            throw NSError(domain: "room", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func history(limit: Int = 30) async throws -> [ChatRow] {
        let a = URLSession.shared
        _ = a // keep simple
        struct Wrap: Decodable { var rows: [RawRow] }
        struct RawRow: Decodable { var t: String; var role: String; var text: String }
        let w: Wrap = try await get("/api/history", ["limit": String(limit)])
        return w.rows.map { ChatRow(t: $0.t, role: $0.role, text: $0.text) }
    }

    func say(_ text: String) async throws -> String {
        struct Out: Decodable { var turn: String?; var err: String? }
        var req = URLRequest(url: try url("/api/say"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "room", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        let out = try JSONDecoder().decode(Out.self, from: data)
        if let t = out.turn, !t.isEmpty { return t }
        throw NSError(domain: "room", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: out.err ?? "没拿到 turn"])
    }

    /// 给 WKWebView 用的地址（URLComponents 会帮忙把 t 编码好）。
    func roomURL(path: String) throws -> URL { try url(path) }

    func settings() async throws -> RoomSettings {
        try await get("/api/settings")
    }

    func saveSettings(_ body: [String: Any]) async throws -> RoomSettings {
        var req = URLRequest(url: try url("/api/settings"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "room", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        struct Out: Decodable { var ok: Bool?; var settings: RoomSettings? }
        let out = try JSONDecoder().decode(Out.self, from: data)
        if let s = out.settings { return s }
        throw NSError(domain: "room", code: 1, userInfo: [NSLocalizedDescriptionKey: "没回设置"])
    }

    func events(turn: String, since: Int) async throws -> EventsPage {
        struct Page: Decodable { var events: [Ev]; var next: Int?; var done: Bool? }
        let p: Page = try await get("/api/events", ["turn": turn, "since": String(since)])
        return EventsPage(evs: p.events, next: p.next ?? since, done: p.done ?? false)
    }
}
