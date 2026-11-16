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

    func events(turn: String, since: Int) async throws -> EventsPage {
        struct Page: Decodable { var events: [Ev]; var next: Int?; var done: Bool? }
        let p: Page = try await get("/api/events", ["turn": turn, "since": String(since)])
        return EventsPage(evs: p.events, next: p.next ?? since, done: p.done ?? false)
    }
}
