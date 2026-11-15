import SwiftUI
import WebKit
import UIKit

struct RootView: View {
    @State private var token: String? = KeyStore.load()
    @State private var host: String = UserDefaults.standard.string(forKey: "lamp_host") ?? AppConfig.builtInHost
    @State private var state: NearWebView.LoadState = .idle
    @State private var reloadToken = 0
    @State private var showMenu = false

    private var url: URL? {
        guard let t = token, !t.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.queryItems = [URLQueryItem(name: "k", value: t)]
        return c.url
    }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.027, blue: 0.039).ignoresSafeArea()

            if let u = url {
                NearWebView(url: u, state: $state, reloadToken: reloadToken)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])

                topProgress
                if case let .failed(code, text) = state {
                    FailureCard(code: code, text: text,
                                onRetry: { reloadToken += 1 },
                                onKey: { showMenu = true })
                }
                cornerButton
            } else {
                SetupView(host: $host, onDone: { newToken, newHost in
                    KeyStore.save(newToken)
                    host = newHost
                    UserDefaults.standard.set(newHost, forKey: "lamp_host")
                    token = newToken
                    state = .idle
                })
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMenu) {
            MenuView(host: $host,
                     hasToken: (token?.isEmpty == false),
                     onApply: { newToken, newHost in
                         if let nt = newToken, !nt.isEmpty {
                             KeyStore.save(nt)
                             token = nt
                         }
                         host = newHost
                         UserDefaults.standard.set(newHost, forKey: "lamp_host")
                         state = .idle
                         reloadToken += 1
                     },
                     onWipe: {
                         KeyStore.clear()
                         WipeStore.clearAll()
                         token = nil
                         state = .idle
                     })
        }
    }

    @ViewBuilder private var topProgress: some View {
        VStack {
            if state == .loading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.85, green: 0.64, blue: 0.36))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: 1, y: 0.6, anchor: .top)
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var cornerButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { showMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.08)))
                }
                .opacity(0.5)
                .padding(.trailing, 10)
                .padding(.bottom, 6)
            }
        }
    }
}

// MARK: - 失败说清楚

private struct FailureCard: View {
    let code: Int
    let text: String
    let onRetry: () -> Void
    let onKey: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(red: 0.85, green: 0.64, blue: 0.36))
            Text("没接上")
                .font(.system(size: 17, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("错误码 \(code)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button("再试一次", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.85, green: 0.64, blue: 0.36))
                Button("换钥匙", action: onKey)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
        .padding(.horizontal, 28)
    }
}

// MARK: - 第一次：贴钥匙

private struct SetupView: View {
    @Binding var host: String
    let onDone: (String, String) -> Void

    @State private var raw = ""
    @State private var hostField = ""
    @State private var err: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("第一次用")
                        .font(.system(size: 26, weight: .bold))
                    Text("把那条带钥匙的链接贴进来，或者只贴钥匙本身。钥匙存在这台手机的钥匙串里，不进包、不外传。")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("钥匙")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $raw)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
                        .font(.system(size: 13, design: .monospaced))
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 10) {
                        Button("从剪贴板填入") {
                            if let s = UIPasteboard.general.string { raw = s }
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 13))
                        Button("清空") { raw = "" }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("服务地址")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(AppConfig.builtInHost, text: $hostField)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(11)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
                        .font(.system(size: 14, design: .monospaced))
                }

                if let e = err {
                    Text(e)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                }

                Button {
                    submit()
                } label: {
                    Text("进去")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.85, green: 0.64, blue: 0.36), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.04))
                }
                .padding(.top, 4)

                Text("钥匙丢了或者过期了，跟电脑上的阿潜说一声，他给你换一把。")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
        }
        .onAppear { if hostField.isEmpty { hostField = host } }
    }

    private func submit() {
        guard let t = KeyStore.extractToken(from: raw) else {
            err = "这串里没看出钥匙。整条链接贴进来也行，或者只贴那十几个字符。"
            return
        }
        var h = hostField.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.isEmpty { h = AppConfig.builtInHost }
        if h.hasPrefix("https://") { h = String(h.dropFirst(8)) }
        if h.hasPrefix("http://") { h = String(h.dropFirst(7)) }
        while h.hasSuffix("/") { h.removeLast() }
        err = nil
        onDone(t, h)
    }
}

// MARK: - 那个小菜单

private struct MenuView: View {
    @Binding var host: String
    let hasToken: Bool
    let onApply: (String?, String) -> Void
    let onWipe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hostField = ""
    @State private var raw = ""
    @State private var msg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务地址", text: $hostField)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, design: .monospaced))
                } header: {
                    Text("地址")
                } footer: {
                    Text("现在是 \(host)。换了域名才用改这里。")
                }

                Section {
                    TextField("换一把钥匙（可留空）", text: $raw, axis: .vertical)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .lineLimit(1...4)
                    Button("从剪贴板填入") {
                        if let s = UIPasteboard.general.string { raw = s }
                    }
                } header: {
                    Text("钥匙")
                } footer: {
                    Text(hasToken ? "已经存着一把了。这里留空就是不改。" : "还没存过钥匙。")
                }

                Section {
                    Button("保存并重连") {
                        var h = hostField.trimmingCharacters(in: .whitespacesAndNewlines)
                        if h.isEmpty { h = host }
                        if h.hasPrefix("https://") { h = String(h.dropFirst(8)) }
                        if h.hasPrefix("http://") { h = String(h.dropFirst(7)) }
                        while h.hasSuffix("/") { h.removeLast() }
                        var t: String? = nil
                        if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            t = KeyStore.extractToken(from: raw)
                            if t == nil {
                                msg = "这串里没看出钥匙，先没换。"
                                return
                            }
                        }
                        onApply(t, h)
                        dismiss()
                    }
                    Button("清掉钥匙，重新来一次", role: .destructive) {
                        onWipe()
                        dismiss()
                    }
                }

                if let m = msg {
                    Section { Text(m).font(.system(size: 12.5)).foregroundStyle(.secondary) }
                }

                Section {
                    Text("这个包是无签名的，装一次能用到证书失效。断了先看上面那条错误说的是哪一步。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关") { dismiss() }
                }
            }
            .onAppear { hostField = host }
        }
    }
}

// MARK: - 清缓存

enum WipeStore {
    static func clearAll() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }
}
