import SwiftUI
import UIKit

/// 三个页签：聊天 / 房间 / 设置。
/// 房间页是原生的——一张房间图 + 四个热点，不塞网页。
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)

            RoomTab(onSay: { tab = 0 })
                .tabItem { Label("房间", systemImage: "house") }
                .tag(1)

            SettingsTab()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(Color(red: 0.96, green: 0.72, blue: 0.36))
        .preferredColorScheme(.dark)
    }
}

// MARK: - 房间（原生）

struct RoomTab: View {
    var onSay: () -> Void

    @AppStorage("room_base") private var base = "http://192.168.0.233:8099"
    @AppStorage("room_token") private var token = ""

    @State private var img: UIImage?
    @State private var failed = ""
    @State private var tip = ""
    @State private var tipOn = false
    @State private var wakeNote: String?
    @State private var drag: CGSize = .zero
    @State private var loading = true
    @State private var cam = 0
    private let cams: [(String, CGFloat, CGSize)] = [
        ("全景", 1.00, CGSize(width: 0, height: 0)),
        ("窗边", 1.55, CGSize(width: -0.16, height: -0.02)),
        ("床前", 1.60, CGSize(width: 0.16, height: 0.03)),
        ("门口", 1.55, CGSize(width: -0.05, height: -0.03)),
        ("相框", 1.95, CGSize(width: -0.03, height: 0.10))
    ]

    private var api: ChatAPI { ChatAPI(base: base, token: token) }

    private let hots: [(String, String, CGFloat, CGFloat)] = [
        ("床", "床铺得平平的。被子边角压了一下，是他昨晚起夜时蹭的。", 0.17, 0.46),
        ("相框", "墙上那个相框里是今天的桌面——一小时一张，我看着它换。", 0.53, 0.24),
        ("门", "门关着，门缝底下有一线暖光漏出来。", 0.72, 0.40),
        ("椅子", "椅子还在桌边，靠背朝我。他走的时候没推回去。", 0.87, 0.56),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.07, green: 0.09, blue: 0.12).ignoresSafeArea()

                if let img {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 1.08, height: geo.size.height)
                        .scaleEffect(cams[cam].1, anchor: .center)
                        .clipped()
                        .offset(x: drag.width + cams[cam].2.width * geo.size.width,
                                y: drag.height + cams[cam].2.height * geo.size.height)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    drag = CGSize(width: max(-26, min(26, v.translation.width * 0.35)),
                                                  height: max(-18, min(18, v.translation.height * 0.22)))
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.22)) { drag = .zero }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.22)) { drag = .zero }
                        }
                } else if loading {
                    ProgressView().tint(.white.opacity(0.6))
                }

                ForEach(hots, id: \.0) { hot in
                    Button {
                        show(hot.1)
                    } label: {
                        Text(hot.0)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                    }
                    .position(x: geo.size.width * hot.2, y: geo.size.height * hot.3)
                }

                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("房间").font(.system(size: 20, weight: .semibold))
                            Text(subtitle()).font(.system(size: 12)).opacity(0.6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18).padding(.top, 8)
                    Spacer()
                }

                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<cams.count, id: \.self) { i in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.5)) { cam = i }
                                } label: {
                                    Text(cams[i].0)
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(cam == i
                                                    ? Color(red: 0.98, green: 0.80, blue: 0.54).opacity(0.92)
                                                    : Color.white.opacity(0.10),
                                                    in: Capsule())
                                        .foregroundStyle(cam == i
                                                         ? Color(red: 0.16, green: 0.12, blue: 0.08)
                                                         : Color.white.opacity(0.85))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 6)
                    HStack(spacing: 10) {
                        Button { Task { await load(force: true) } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 14))
                                .padding(13).background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(.white)
                        }
                        Button { onSay() } label: {
                            Text("说话")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(Color(red: 0.98, green: 0.80, blue: 0.54), in: Capsule())
                                .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.08))
                        }
                        Button { Task { await knock() } } label: {
                            Text("叫醒")
                                .font(.system(size: 15))
                                .padding(.horizontal, 22).padding(.vertical, 15)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }

                if tipOn {
                    VStack {
                        Spacer()
                        Text(tip)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 88)
                    }
                    .transition(.opacity)
                }

                if !failed.isEmpty {
                    Text(failed)
                        .font(.system(size: 12)).multilineTextAlignment(.center)
                        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 30)
                }

                if let note = wakeNote {
                    VStack {
                        Text(note).font(.system(size: 12))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    .padding(.top, 70)
                }
            }
        }
        .task { if img == nil { await load() } }
    }

    private func subtitle() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 18 || h < 7 { return "夜里也亮着一盏" }
        if h < 11 { return "窗开着，光在地板上" }
        if h < 16 { return "下午，屋里安安静静" }
        return "太阳往窗台那边挪了"
    }

    private func show(_ s: String) {
        tip = s
        withAnimation(.easeOut(duration: 0.2)) { tipOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeIn(duration: 0.25)) { tipOn = false }
        }
    }

    private func load(force: Bool = false) async {
        guard !token.isEmpty else { failed = "先在设置里填地址和口令"; loading = false; return }
        loading = true; failed = ""
        do {
            let u = try api.roomURL(path: "/web/room-bg.jpg")
            var req = URLRequest(url: u)
            req.timeoutInterval = 25
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                throw NSError(domain: "room", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "图片 HTTP \(http.statusCode)"])
            }
            if let im = UIImage(data: data) { img = im } else { failed = "这张图打不开" }
        } catch {
            failed = "房间图没拉下来\n\(error.localizedDescription)"
        }
        loading = false
    }

    private func knock() async {
        do {
            struct Out: Decodable { var ok: Bool?; var note: String?; var err: String? }
            var req = URLRequest(url: try api.roomURL(path: "/api/wake"))
            req.httpMethod = "POST"
            req.timeoutInterval = 25
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            let out = try JSONDecoder().decode(Out.self, from: data)
            wakeNote = out.ok == true ? "叫了一声，她醒了" : (out.err ?? "没叫醒")
        } catch {
            wakeNote = "没叫醒：\(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { wakeNote = nil }
    }
}

// MARK: - 设置

struct SettingsTab: View {
    @AppStorage("room_base") private var base = "http://192.168.0.233:8099"
    @AppStorage("room_token") private var token = ""

    @State private var lifeOn = true
    @State private var wechatOn = true
    @State private var wechatMax = 3
    @State private var quiet = "23:30–07:30"
    @State private var aiName = "阿潜"
    @State private var userName = "老大"
    @State private var persona = ""
    @State private var note = ""
    @State private var busy = false

    private var api: ChatAPI { ChatAPI(base: base, token: token) }

    var body: some View {
        Form {
            Section("连哪间房") {
                TextField("地址", text: $base)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("口令", text: $token)
                Button {
                    Task { await load() }
                } label: { Text(busy ? "正在连…" : "用这些连一次，读回现在的设置") }
                .disabled(busy)
            }

            Section {
                Toggle("她有她的生活", isOn: $lifeOn)
            } header: { Text("生活") } footer: {
                Text("开着：她会有心情、自己找事做、也会主动来找你。关掉：只陪你说话，不自己忙。")
            }

            Section("对外") {
                Toggle("允许往外发消息（微信）", isOn: $wechatOn)
                Stepper("一小时最多 \(wechatMax) 条", value: $wechatMax, in: 0...10)
            }

            Section {
                TextField("23:30–07:30", text: $quiet)
            } header: { Text("静默时段") } footer: {
                Text("这两个点之间她不主动说话。写成 23:30–07:30 这样。")
            }

            Section("称呼") {
                TextField("我叫", text: $aiName)
                TextField("叫你", text: $userName)
            }

            Section {
                TextEditor(text: $persona).frame(minHeight: 110)
            } header: { Text("让她记着的话") } footer: {
                Text("会贴在提示词最后，最多 600 字。存的是电脑那边同一个文件。")
            }

            Section {
                Button {
                    Task { await save() }
                } label: { Text(busy ? "保存中…" : "保存到房间").frame(maxWidth: .infinity) }
                .disabled(busy)
                if !note.isEmpty {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } footer: {
                Text("改完点保存，电脑那边的房间和网页立刻生效，不用重启。")
            }
        }
        .task { if !token.isEmpty { await load() } }
    }

    private func load() async {
        busy = true; defer { busy = false }
        do {
            let s = try await api.settings()
            lifeOn = s.life_on
            wechatOn = s.wechat_on
            wechatMax = s.wechat_max_per_hour
            quiet = s.quiet_text
            aiName = s.ai_name
            userName = s.user_name
            persona = s.persona_extra
            note = "读到了，改完点保存"
        } catch {
            note = "连不上：\(error.localizedDescription)"
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        var body: [String: Any] = [
            "life_on": lifeOn,
            "wechat_on": wechatOn,
            "wechat_max_per_hour": wechatMax,
            "ai_name": aiName,
            "user_name": userName,
            "persona_extra": String(persona.prefix(600)),
        ]
        if let q = SettingsPayload.parseQuiet(quiet) { body["quiet"] = q }
        do {
            let s = try await api.saveSettings(body)
            lifeOn = s.life_on; wechatOn = s.wechat_on; wechatMax = s.wechat_max_per_hour
            quiet = s.quiet_text; aiName = s.ai_name; userName = s.user_name; persona = s.persona_extra
            note = "已保存 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch {
            note = "没存上：\(error.localizedDescription)"
        }
    }
}
