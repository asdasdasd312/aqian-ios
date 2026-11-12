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

struct AskQuestion: Decodable, Identifiable {
    let q: String
    let options: [String]
    var id: String { q }
}

struct AskBox: Decodable {
    let questions: [AskQuestion]
}

struct Msg: Decodable, Identifiable {
    let t: Double
    let role: String
    let text: String
    let ask: AskBox?
    // 同一秒里可能有好几条（连发、图+字），只用时间戳当 id 会撞，
    // 撞了 SwiftUI 就会把两条画在同一个位置（字重叠）并让滚动位置乱跳。
    var id: String { "\(t)#\(role)#\(text.count)#\(text.prefix(24))" }
    var isMe: Bool { role == "user" }

    /// 经 lamp 说出去的话（语音、表情、我主动找他）被宿主当成“他的话”追加进会话，
    /// 所以网关给这类文字盖了一个看不见的 U+2063。认出来就画在我这一侧，并把记号去掉。
    static let selfMark = "\u{2063}"
    enum CodingKeys: String, CodingKey { case t, role, text, ask }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        let r = try c.decode(String.self, forKey: .role)
        var x = try c.decode(String.self, forKey: .text)
        if x.hasPrefix(Msg.selfMark) {
            x.removeFirst()
            role = (r == "user") ? "assistant" : r
        } else {
            role = r
        }
        text = x
        ask = try c.decodeIfPresent(AskBox.self, forKey: .ask)
    }
}

struct SessionsResp: Decodable { let sessions: [SessionRow] }

struct Hit: Decodable, Identifiable {
    let sid: String
    let title: String
    let t: Double
    let role: String
    let text: String
    var id: String { sid + "-" + String(t) }
}

struct SearchResp: Decodable { let ok: Bool; let hits: [Hit] }
struct MessagesResp: Decodable {
    let messages: [Msg]
    let typing: Bool?
}
struct OkResp: Decodable { let ok: Bool }

/// /api/send 的回执：这条字最后排给了哪个房间（网关没认出 session 时会兜底到最近活跃的）。
struct SendAck: Decodable {
    let ok: Bool
    let to: String?
    let toTitle: String?
    enum CodingKeys: String, CodingKey { case ok, to, toTitle = "to_title" }
}

struct Sticker: Decodable, Identifiable {
    let hash: String
    let name: String
    let pack: String
    var id: String { hash }
}

struct StickerPack: Decodable, Identifiable {
    let key: String
    let label: String
    let count: Int?
    var id: String { key }
}

struct StickerCatalog: Decodable {
    let ok: Bool
    let packs: [StickerPack]
    let items: [Sticker]
}

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

    func search(_ q: String) async throws -> [Hit] {
        let data = try await get("/api/search", query: [URLQueryItem(name: "q", value: q)])
        return try JSONDecoder().decode(SearchResp.self, from: data).hits
    }

    func messages(id: String, limit: Int = 60) async throws -> MessagesResp {
        let data = try await get("/api/messages",
                                 query: [URLQueryItem(name: "id", value: id),
                                         URLQueryItem(name: "limit", value: String(limit))])
        return try JSONDecoder().decode(MessagesResp.self, from: data)
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

    func registerPush(_ token: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["token": token, "env": "production"])
        guard let req = request("/api/push/register", method: "POST", body: payload) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? JSONDecoder().decode(OkResp.self, from: data)
    }

    /// 大文件分片上传：经隧道单次 >200KB 会被掐断，切成 100KB 一块。
    private func uploadChunked(_ data: Data, filename: String) async throws -> String {
        let upid = UUID().uuidString
        let chunkSize = 100_000
        let chunks = stride(from: 0, to: data.count, by: chunkSize).map {
            data[$0 ..< min($0 + chunkSize, data.count)]
        }
        var path = ""
        for (idx, part) in chunks.enumerated() {
            var lastError: Error = URLError(.unknown)
            var ok = false
            for _ in 1...3 {
                do {
                    guard var c = URLComponents(string: base.trimmingCharacters(in: .whitespaces)) else {
                        throw URLError(.badURL)
                    }
                    c.path = "/api/upload"
                    guard let url = c.url else { throw URLError(.badURL) }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 60
                    req.setValue(key, forHTTPHeaderField: "X-Aqian-Key")
                    req.setValue(filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file",
                                 forHTTPHeaderField: "X-Filename")
                    req.setValue(upid, forHTTPHeaderField: "X-Upload-Id")
                    req.setValue(String(idx), forHTTPHeaderField: "X-Chunk")
                    req.setValue(String(chunks.count), forHTTPHeaderField: "X-Chunks")
                    req.setValue(String(data.count), forHTTPHeaderField: "X-Total-Bytes")
                    req.setValue("1", forHTTPHeaderField: "X-No-Queue")
                    req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    let (respData, resp) = try await URLSession.shared.upload(for: req, from: part)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    if let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                       let p = obj["path"] as? String, !p.isEmpty {
                        path = p
                    }
                    ok = true
                    break
                } catch {
                    lastError = error
                }
            }
            if !ok { throw lastError }
        }
        guard !path.isEmpty else { throw URLError(.cannotParseResponse) }
        return path
    }

    func upload(_ data: Data, filename: String) async throws -> String {
        if data.count > 120_000 {
            return try await uploadChunked(data, filename: filename)
        }
        let upid = UUID().uuidString
        var lastError: Error = URLError(.unknown)
        for attempt in 1...2 {
            do {
                guard var c = URLComponents(string: base.trimmingCharacters(in: .whitespaces)) else {
                    throw URLError(.badURL)
                }
                c.path = "/api/upload"
                guard let url = c.url else { throw URLError(.badURL) }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 120
                req.setValue(key, forHTTPHeaderField: "X-Aqian-Key")
                req.setValue(filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file",
                             forHTTPHeaderField: "X-Filename")
                req.setValue(upid, forHTTPHeaderField: "X-Upload-Id")
                req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                // 图 + 字会合成一条走 /api/send，这里别再单独报一次
                req.setValue("1", forHTTPHeaderField: "X-No-Queue")
                let (respData, resp) = try await URLSession.shared.upload(for: req, from: data)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                guard let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                      let path = obj["path"] as? String, !path.isEmpty else {
                    throw URLError(.cannotParseResponse)
                }
                return path
            } catch {
                lastError = error
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }
        throw lastError
    }

    /// 语音：把 m4a 丢给网关，网关转成字再进会话
    func voice(_ data: Data, session: String = "") async throws -> String {
        guard var c = URLComponents(string: base.trimmingCharacters(in: .whitespaces)) else {
            throw URLError(.badURL)
        }
        c.path = "/api/voice"
        guard let url = c.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue(key, forHTTPHeaderField: "X-Aqian-Key")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !session.isEmpty { req.setValue(session, forHTTPHeaderField: "X-Aqian-Session") }
        let (data2, resp) = try await URLSession.shared.upload(for: req, from: data)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct R: Decodable { let ok: Bool; let text: String? }
        return (try? JSONDecoder().decode(R.self, from: data2).text) ?? ""
    }

    /// session：当前看的是哪个房间。网关据此把这条字只投进那个会话；
    /// 不传（或网关认不出）时网关兜底给最近活跃的房间，回执里告诉我们发给了谁。
    func stickers() async throws -> StickerCatalog {
        let data = try await get("/api/stickers")
        return try JSONDecoder().decode(StickerCatalog.self, from: data)
    }

    /// 发一个表情包：网关把它变成 lamp 里一条 `![名字](sticker://hash)`。
    func sendSticker(hash: String, name: String, session: String = "") async throws -> SendAck {
        var payload: [String: Any] = ["hash": hash, "name": name]
        if !session.isEmpty { payload["session"] = session }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let req = request("/api/sticker/send", method: "POST", body: data) else { throw URLError(.badURL) }
        let (resp, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode(SendAck.self, from: resp)) ?? SendAck(ok: true, to: nil, toTitle: nil)
    }

    func send(_ text: String, attach: String = "", session: String = "") async throws -> SendAck {
        var payload: [String: Any] = ["text": text]
        if !attach.isEmpty { payload["attach"] = attach }
        if !session.isEmpty { payload["session"] = session }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let req = request("/api/send", method: "POST", body: data) else { throw URLError(.badURL) }
        let (resp, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode(SendAck.self, from: resp)) ?? SendAck(ok: true, to: nil, toTitle: nil)
    }
}
