import SwiftUI

@main
struct AqianClientApp: App {
    @UIApplicationDelegateAdaptor(PushBridge.self) private var push

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @AppStorage("gw_url") private var gwURL = ""
    @AppStorage("gw_key") private var gwKey = ""

    var body: some View {
        if gwURL.isEmpty || gwKey.isEmpty {
            SetupView(gwURL: $gwURL, gwKey: $gwKey)
        } else {
            LampRootView()
        }
    }
}

struct SetupView: View {
    @ObservedObject private var bridge = PushState.shared
    @Binding var gwURL: String
    @Binding var gwKey: String
    @State private var url = ""
    @State private var url2 = ""
    @State private var url3 = ""
    @State private var key = ""
    @AppStorage("voice_url") private var voiceURL = ""

    var body: some View {
        Form {
            Section("网关地址") {
                TextField("https://…trycloudflare.com", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Section("备用地址（可不填）") {
                TextField("第二个地址", text: $url2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("第三个地址", text: $url3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Section("口令") {
                TextField("phone_token", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("语音桥（打电话用）") {
                TextField("wss://… 或留空按网关主机推", text: $voiceURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("留空时用 ws://<网关主机>:57942/ws，只在同一局域网内可用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("推送（实验）") {
                Button("申请通知权限") { PushBridge.ask() }
                Text(bridge.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !bridge.token.isEmpty {
                    Text(bridge.token)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("保存") {
                    gwURL = url.trimmingCharacters(in: .whitespaces)
                    gwKey = key.trimmingCharacters(in: .whitespaces)
                    UserDefaults.standard.set(url2.trimmingCharacters(in: .whitespaces), forKey: "gw_url2")
                    UserDefaults.standard.set(url3.trimmingCharacters(in: .whitespaces), forKey: "gw_url3")
                }
                .disabled(url.isEmpty || key.isEmpty)
            }
            Section {
                Text("地址和口令在电脑上：状态\\手机门.txt 和 状态\\phone_token.txt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text("版本 " + v + "（build " + b + "）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // 装上就能用：预填当前的网关地址和口令（地址会变时在这里改）
            if gwURL.isEmpty {
                url = ""
                key = ""
            } else {
                url = gwURL
                key = gwKey
            }
            url2 = UserDefaults.standard.string(forKey: "gw_url2") ?? ""
            url3 = UserDefaults.standard.string(forKey: "gw_url3") ?? ""
        }
    }
}
