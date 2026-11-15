import Foundation
import Security

/// 一点配置：默认连哪里。
/// 放在 Info.plist 里而不是写死在代码里——打包后还能在包里查到这个值，
/// 出了事对得上账，改起来也不用动 Swift。
enum AppConfig {
    /// 没存过设置时，连这个地址。
    static var builtInHost: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "AqianDefaultHost") as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "m.aqian-lamp.cn"
    }
}

/// 钥匙只存在这台机器的钥匙串里，不写进包、不上报。
enum KeyStore {
    private static let service = "com.aqian.near"
    private static let account = "lamp-token"

    static func load() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty
        else { return nil }
        return s
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func clear() -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }

    /// 从一段粘贴进来的东西里把钥匙挑出来。
    /// 接受三种写法：完整链接、只有 k=xxx、只贴那串钥匙本身。
    static func extractToken(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if let comps = URLComponents(string: s),
           let k = comps.queryItems?.first(where: { $0.name == "k" })?.value,
           !k.isEmpty {
            return k
        }
        if let range = s.range(of: "k=") {
            let tail = String(s[range.upperBound...])
            let cut = tail.prefix { $0 != "&" && $0 != "#" && $0 != " " }
            if !cut.isEmpty { return String(cut) }
        }
        // 整串都当钥匙：不许带空格、斜杠、问号
        let bad = CharacterSet(charactersIn: " /?#&")
        if s.rangeOfCharacter(from: bad) == nil, s.count >= 8, s.count <= 128 {
            return s
        }
        return nil
    }
}
