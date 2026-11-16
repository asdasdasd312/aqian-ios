import SwiftUI

/// 三个页签：聊天（原生）、房间（手机网页那套）、设置（写到电脑那边）。
struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }
            RoomTab()
                .tabItem { Label("房间", systemImage: "house") }
            SettingsTab()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(Color(red: 0.96, green: 0.72, blue: 0.36))
        .preferredColorScheme(.dark)
    }
}

/// 房间页：就是手机上那个 /m 页面，原样装进来。
struct RoomTab: View {
    @AppStorage("room_base") private var base: String = "http://192.168.0.233:8099"
    @AppStorage("room_token") private var token: String = ""

    @State private var loading = false
    @State private var failed = false
    @State private var reload = 0

    private var url: URL {
        let api = ChatAPI(base: base, token: token)
        return (try? api.roomURL(path: "/m")) ?? URL(string: "about:blank")!
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(url: url, isLoading: $loading, failed: $failed, reloadToken: reload)
                .ignoresSafeArea(edges: .bottom)
            HStack {
                if loading { ProgressView().scaleEffect(0.7) }
                Spacer()
                Button {
                    reload += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            if failed {
                VStack(spacing: 6) {
                    Text("没打开").font(.footnote)
                    Text(base).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// 设置页：读写电脑那边的 /api/settings，改完那边立刻生效。
struct SettingsTab: View {
    @AppStorage("room_base") private var base: String = "http://192.168.0.233:8099"
    @AppStorage("room_token") private var token: String = ""

    @State private var aiName = ""
    @State private var userName = ""
    @State private var lifeOn = true
    @State private var wechatOn = true
    @State private var wechatMax = "3"
    @State private var quietText = "23:30–07:30"
    @State private var persona = ""

    @State private var loading = false
    @State private var saving = false
    @State private var note = ""

    private var api: ChatAPI { ChatAPI(base: base, token: token) }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    TextField("房间地址", text: $base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("口令", text: $token)
                    Button("用这些连一次") { Task { await load() } }
                        .disabled(loading || token.isEmpty)
                }

                Section {
                    Toggle("她有她的生活", isOn: $lifeOn)
                    Text("开着：会主动开口、有自己的心事、心情会变。关掉：只陪你说话，不主动。")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("生活")
                }

                Section {
                    Toggle("允许往外部发消息（微信）", isOn: $wechatOn)
                    HStack {
                        Text("一小时最多")
                        TextField("3", text: $wechatMax)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("条")
                    }
                } header: {
                    Text("对外")
                }

                Section {
                    TextField("23:30–07:30", text: $quietText)
                    Text("这两个点之间她不主动说话。格式照上面写。")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("静默时段")
                }

                Section {
                    TextField("我叫", text: $aiName)
                    TextField("叫你", text: $userName)
                } header: {
                    Text("称呼")
                }

                Section {
                    TextEditor(text: $persona)
                        .frame(minHeight: 88)
                    Text("会贴在提示词最后，最多 600 字。")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("让她记着的话")
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView().scaleEffect(0.8) }
                            Text(saving ? "正在保存" : "保存到房间").bold()
                            Spacer()
                        }
                    }
                    .disabled(saving)
                    if !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("存的是电脑那边同一个文件，浏览器和 App 看到的是同一份。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .task { if !token.isEmpty { await load() } }
        }
    }

    private func load() async {
        loading = true
        do {
            let s = try await api.settings()
            aiName = s.ai_name
            userName = s.user_name
            lifeOn = s.life_on
            wechatOn = s.wechat_on
            wechatMax = String(s.wechat_max_per_hour)
            quietText = s.quiet_text
            persona = s.persona_extra
            note = "已读到电脑那边的设置"
        } catch {
            note = "读不到：" + error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let q = SettingsPayload.parseQuiet(quietText)
        var body: [String: Any] = [
            "ai_name": aiName,
            "user_name": userName,
            "life_on": lifeOn,
            "wechat_on": wechatOn,
            "persona_extra": persona,
        ]
        if let n = Int(wechatMax) { body["wechat_max_per_hour"] = n }
        if let q { body["quiet"] = q }
        do {
            _ = try await api.saveSettings(body)
            note = "已保存，电脑那边立即生效"
        } catch {
            note = "存不上：" + error.localizedDescription
        }
    }
}
