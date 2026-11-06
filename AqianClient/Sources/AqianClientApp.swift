import SwiftUI

@main
struct AqianClientApp: App {
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
            SessionListView()
        }
    }
}

struct SetupView: View {
    @Binding var gwURL: String
    @Binding var gwKey: String
    @State private var url = ""
    @State private var key = ""

    var body: some View {
        Form {
            Section("网关地址") {
                TextField("https://…trycloudflare.com", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Section("口令") {
                TextField("phone_token", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("保存") {
                    gwURL = url.trimmingCharacters(in: .whitespaces)
                    gwKey = key.trimmingCharacters(in: .whitespaces)
                }
                .disabled(url.isEmpty || key.isEmpty)
            }
            Section {
                Text("地址和口令在电脑上：状态\\手机门.txt 和 状态\\phone_token.txt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // 装上就能用：预填当前的网关地址和口令（地址会变时在这里改）
            if gwURL.isEmpty {
                url = "https://activation-governance-engineers-crossword.trycloudflare.com"
                key = "BYPqsxmRuvce"
            } else {
                url = gwURL
                key = gwKey
            }
        }
    }
}
