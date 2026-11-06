import SwiftUI
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers

/// 一屏只有这一轮对话。我的话不带气泡（像从暗处说出来），他的话是一个很轻的圆角块。
struct PendingMsg: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var attach: String = ""
    var failed: Bool
}

struct ChatPane: View {
    @AppStorage("gw_url") private var gwURL = ""
    @AppStorage("gw_key") private var gwKey = ""
    @State private var showSetup = false
    let session: SessionRow
    var onLongPressTitle: () -> Void
    var onPick: (SessionRow) -> Void

    @State private var msgs: [Msg] = []
    @State private var typing = false
    @StateObject private var voice = VoiceRecorder()
    @State private var voiceBusy = false
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var presence: Presence?
    @State private var voiceMode = false
    @State private var unread = 0
    @State private var showNote = false
    @State private var timer: Timer?
    @State private var presenceTimer: Timer?
    @State private var linkDown = false
    @State private var failCount = 0
    @State private var justBack = false
    @State private var pickPhoto = false
    @State private var pickFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var pending: [PendingMsg] = []
    @State private var attachPath = ""
    @State private var attachTask: Task<Void, Never>?
    @State private var toast: String?
    @AppStorage("send_original") private var sendOriginal = true

    private var api: API { API.shared }
    private var seenKey: String { "seen." + session.id }
    private var seenAt: Double { UserDefaults.standard.double(forKey: seenKey) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if linkDown || justBack {
                Text(linkDown ? "正在重连（第 \(failCount) 次）…" : "回来了")
                    .font(.system(size: 11))
                    .foregroundStyle(linkDown ? Color.orange.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.03))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: linkDown)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if unread > 0 {
                            Button {
                                if let first = msgs.first(where: { $0.t > seenAt }) {
                                    withAnimation { proxy.scrollTo(first.t, anchor: .top) }
                                }
                            } label: {
                                Text("上次之后 \(unread) 条")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.vertical, 5).padding(.horizontal, 12)
                                    .background(Capsule().fill(Color.white.opacity(0.05)))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(msgs.enumerated()), id: \.element.id) { idx, m in
                            if showDay(idx) {
                                Text(dayLabel(m.t))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 6)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                row(m)
                                if !m.isMe { askBox(m) }
                            }
                            .id(m.t)
                        }
                        ForEach(pending) { item in
                            HStack(alignment: .center, spacing: 8) {
                                Text(item.attach.isEmpty ? item.text : (item.text.isEmpty ? "（图片）" : "（图片）" + item.text))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(item.failed ? 0.55 : 0.75))
                                    .padding(.vertical, 11).padding(.horizontal, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.red.opacity(item.failed ? 0.45 : 0), lineWidth: 1)
                                    )
                                if item.failed {
                                    Button("重发") { Task { await resend(item) } }
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.45))
                                } else {
                                    ProgressView().scaleEffect(0.6)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 4)
                        }

                        if typing {
                            HStack(spacing: 6) {
                                ForEach(0..<3) { i in
                                    Circle()
                                        .fill(Color.white.opacity(0.45))
                                        .frame(width: 6, height: 6)
                                        .opacity(0.35 + 0.25 * Double(i))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                            .padding(.leading, 2)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.t, anchor: .bottom)
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red.opacity(0.8))
                    .padding(.bottom, 4)
            }
            composer
        }
        .task {
            await load(first: true)
            markSeen()
            startPolling()
            startPresence()
        }
        .onDisappear {
            timer?.invalidate(); presenceTimer?.invalidate()
            markSeen()
        }
        .sheet(isPresented: $showSetup) {
            SetupView(gwURL: $gwURL, gwKey: $gwKey)
        }
        .photosPicker(isPresented: $pickPhoto, selection: $photoItem, matching: .images,
                      preferredItemEncoding: sendOriginal ? .current : .automatic)
        .fileImporter(isPresented: $pickFile, allowedContentTypes: [.data, .image, .pdf, .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await uploadFile(url) }
            }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await uploadData(data, name: "照片-\(Int(Date().timeIntervalSince1970)).jpg")
                }
                photoItem = nil
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        VStack(spacing: 8) {
            Image("Avatar")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .onLongPressGesture(minimumDuration: 0.5) { showSetup = true }

            Button {
                showNote = true
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                        .opacity(presence?.state == "busy" ? 0.6 : 1)
                    Text("阿潜")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .buttonStyle(.plain)

            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.26))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) { onLongPressTitle() }
        .alert("阿潜", isPresented: $showNote) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(noteText)
        }
    }

    private var dotColor: Color {
        switch presence?.state ?? "idle" {
        case "busy":  return Color(red: 0.95, green: 0.75, blue: 0.42)
        case "away":  return Color(red: 0.45, green: 0.47, blue: 0.52)
        default:      return Color(red: 0.47, green: 0.75, blue: 0.59)
        }
    }

    private var noteText: String {
        guard let p = presence else { return "还没问到。" }
        var s: String
        switch p.state {
        case "busy": s = "在，正忙着。"
        case "away": s = "不在——电脑那边已经 \(max(1, p.idle_seconds / 60)) 分钟没动静了。"
        default:     s = "在，暂时空着。"
        }
        if !p.note.isEmpty { s += "\n\n" + p.note }
        return s
    }

    private var timeLabel: String {
        guard let last = msgs.last else { return "" }
        let d = Date(timeIntervalSince1970: Double(last.t) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "今天 HH:mm" : "M月d日 HH:mm"
        return f.string(from: d)
    }

    // MARK: - 一行话

    /// 消息里的表情包是 `![名字](http://127.0.0.1:57936/.../hash.gif)`，
    /// 手机上 127.0.0.1 指的是它自己，所以这里把地址换到网关的 /sticker/。
    private func stickerURL(_ line: String) -> URL? {
        guard line.hasPrefix("!["), let open = line.range(of: "]("),
              let close = line.range(of: ")", options: .backwards) else { return nil }
        let raw = String(line[open.upperBound..<close.lowerBound])
        guard let hash = raw.split(separator: "/").last else { return nil }
        let base = (UserDefaults.standard.string(forKey: "gw_url") ?? "").trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/sticker/" + hash)
    }

    /// 我要给他看一张图时，正文里会写一行 `[图] D:\阿潜\画-xxx.jpg`。
    /// 手机上那个路径没有意义，换成网关的 /api/file 去取。
    private func imagePathURL(_ line: String) -> URL? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[图]") else { return nil }
        let path = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard path.count > 3 else { return nil }
        let base = (UserDefaults.standard.string(forKey: "gw_url") ?? "").trimmingCharacters(in: .whitespaces)
        let key = UserDefaults.standard.string(forKey: "gw_key") ?? ""
        guard !base.isEmpty, var comps = URLComponents(string: base + "/api/file") else { return nil }
        comps.queryItems = [URLQueryItem(name: "path", value: path),
                            URLQueryItem(name: "k", value: key)]
        return comps.url
    }

    private func imagePathLines(_ text: String) -> [URL] {
        text.split(separator: "\n").compactMap { imagePathURL(String($0)) }
    }

    private func stickerLines(_ text: String) -> [URL] {
        text.split(separator: "\n").compactMap { stickerURL(String($0)) }
    }

    private func textWithoutStickers(_ text: String) -> String {
        text.split(separator: "\n")
            .filter { stickerURL(String($0)) == nil && imagePathURL(String($0)) == nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「[手机] 发来一个文件：D:\…」这类是我这边收到东西的回执，
    /// 把路径整条摊在他眼前很难看，换成一个小标签。
    private func receiptTag(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[手机] 发来") else { return nil }
        if t.contains("照片") { return "照片 · 已收到" }
        if t.contains("语音") { return "语音 · 已收到" }
        return "文件 · 已收到"
    }

    @ViewBuilder
    private func row(_ m: Msg) -> some View {
        if let tag = receiptTag(m.text) {
            HStack {
                Spacer()
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                Spacer()
            }
            .padding(.vertical, 2)
        } else {
            rowBody(m)
        }
    }

    @ViewBuilder
    private func rowBody(_ m: Msg) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if m.isMe { Spacer(minLength: 56) }
            VStack(alignment: .leading, spacing: 8) {
                let body = textWithoutStickers(m.text)
                if !body.isEmpty {
                    Text(body)
                        .font(.system(size: 17))
                        .lineSpacing(6)
                        .foregroundStyle(m.isMe ? Color.white.opacity(0.88) : Color.white.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(.horizontal, m.isMe ? 16 : 0)
                        .padding(.vertical, m.isMe ? 11 : 0)
                        .background(
                            Group {
                                if m.isMe {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color(red: 0.13, green: 0.16, blue: 0.23))
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                ForEach(imagePathLines(m.text), id: \.absoluteString) { url in
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                                .frame(maxWidth: 240, maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else if phase.error != nil {
                            Text("[图] 没取到").font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            ProgressView().frame(width: 120, height: 120)
                        }
                    }
                }
                ForEach(stickerLines(m.text), id: \.absoluteString) { url in
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit().frame(maxWidth: 132, maxHeight: 132)
                        } else {
                            ProgressView().frame(width: 56, height: 56)
                        }
                    }
                }
            }
            if !m.isMe { Spacer(minLength: 40) }
        }
    }


    // MARK: - 按天分组

    private func showDay(_ i: Int) -> Bool {
        guard i < msgs.count else { return false }
        if i == 0 { return true }
        return dayLabel(msgs[i].t) != dayLabel(msgs[i - 1].t)
    }

    private func dayLabel(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    /// 我在等他选的时候，手机上要能直接点——不是只看到一句「问你个事」
    @ViewBuilder
    private func askBox(_ m: Msg) -> some View {
        if let ask = m.ask {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ask.questions) { q in
                    if !q.q.isEmpty {
                        Text(q.q)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.top, 2)
                    }
                    ForEach(q.options, id: \.self) { opt in
                        Button {
                            draft = opt
                            Task { await send() }
                        } label: {
                            Text(opt)
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.leading, 2)
        }
    }

    // MARK: - 输入

    private var composer: some View {
        HStack(spacing: 10) {
            Menu {
                Button { pickPhoto = true } label: { Label(sendOriginal ? "照片（原图）" : "照片", systemImage: "photo") }
                Button { pickFile = true } label: { Label("文件", systemImage: "doc") }
                Toggle("发原图", isOn: $sendOriginal)
            } label: {
                Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 34, height: 34)
            }
            .padding(.leading, 12)

            Button {
                voiceMode.toggle()
            } label: {
                Image(systemName: voiceMode ? "keyboard" : "mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(voiceBusy ? 0.25 : 0.55))
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }

            if voiceMode {
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(voice.recording ? 0.16 : 0.08))
                    Text(voice.recording ? "松开发送" : "按住 说话")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(height: 46)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !voice.recording && !voiceBusy { voice.start() }
                        }
                        .onEnded { _ in
                            guard let data = voice.stop() else { return }
                            voiceBusy = true
                            Task {
                                _ = try? await api.voice(data)
                                voiceBusy = false
                                await load()
                            }
                        }
                )
            } else {
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 6)
                .padding(.vertical, 13)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("跟阿潜说…")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.30))
                            .padding(.leading, 6)
                            .padding(.top, 13)
                            .allowsHitTesting(false)
                    }
                }

            }
            if !voiceMode {
            Button(action: { Task { await send() } }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(draft.isEmpty || sending ? 0.35 : 0.95))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(Color.white.opacity(draft.isEmpty || sending ? 0.06 : 0.14))
                    )
            }
            .disabled(draft.isEmpty || sending)
            .padding(.trailing, 7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.055, green: 0.065, blue: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // MARK: - 数据

    private func load(first: Bool = false) async {
        do {
            let resp = try await api.messages(id: session.id, limit: 80)
            let fresh = resp.messages
            typing = resp.typing ?? false
            if first {
                unread = fresh.filter { $0.t > seenAt }.count
                try? await UNUserNotificationCenter.current().setBadgeCount(unread)
            }
            msgs = fresh
            error = nil
            if linkDown {
                linkDown = false
                justBack = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    justBack = false
                }
            }
            failCount = 0
        } catch {
            failCount += 1
            if failCount >= 2 { linkDown = true }
            if failCount == 1 {
                self.error = "读不到消息：\(error.localizedDescription)"
            } else {
                self.error = nil
            }
        }
    }

    private func markSeen() {
        if let last = msgs.last {
            UserDefaults.standard.set(last.t, forKey: seenKey)
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        attachTask?.cancel()
        let attach = attachPath
        attachPath = ""
        let item = PendingMsg(text: body, attach: attach, failed: false)
        withAnimation { pending.append(item) }
        await deliver(item)
    }

    private func deliver(_ item: PendingMsg) async {
        sending = true
        do {
            try await api.send(item.text, attach: item.attach)
            withAnimation { pending.removeAll { $0.id == item.id } }
            await load()
            markSeen()
            self.error = nil
        } catch {
            withAnimation { setFailed(item.id) }
            self.error = "没发出去（点那条消息的「重发」）"
        }
        sending = false
    }

    private func setFailed(_ id: UUID) {
        if let i = pending.firstIndex(where: { $0.id == id }) {
            pending[i].failed = true
        }
    }

    private func resend(_ item: PendingMsg) async {
        if let i = pending.firstIndex(where: { $0.id == item.id }) {
            pending[i].failed = false
        }
        await deliver(item)
    }

    private func uploadFile(_ url: URL) async {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        if let data = try? Data(contentsOf: url) {
            await uploadData(data, name: name)
        }
    }

    /// 原图（5700×4300、四五兆）在这种链路上传一半就断，先缩到长边 2600。
    /// 看图纸、看远处的字够用了；真要原图，走「文件」那条，不要走照片。
    private func shrink(_ data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let long = max(img.size.width, img.size.height)
        guard long > 2600 else { return data }
        let scale = 2600 / long
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return out.jpegData(compressionQuality: 0.85) ?? data
    }

    private func uploadData(_ data: Data, name: String) async {
        uploading = true
        do {
            let path = try await api.upload(shrink(data), filename: name)
            attachPath = path
            withAnimation { toast = "图片待发送——接着打字就一起发" }
            attachTask?.cancel()
            attachTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                if !attachPath.isEmpty, draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    let only = attachPath
                    attachPath = ""
                    await deliver(PendingMsg(text: "", attach: only, failed: false))
                }
            }
        } catch {
            withAnimation { toast = "没发出去：\(error.localizedDescription)" }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { toast = nil }
            }
        }
        uploading = false
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { await load() }
        }
    }

    private func startPresence() {
        presenceTimer?.invalidate()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { presence = try? await api.presence() }
        }
        Task { presence = try? await api.presence() }
    }
}
