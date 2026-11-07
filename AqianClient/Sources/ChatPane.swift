import SwiftUI
import AVFoundation
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers

/// 一屏只有这一轮对话。我的话不带气泡（像从暗处说出来），他的话是一个很轻的圆角块。
struct PendingMsg: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var attach: String = ""
    var failed: Bool
    /// 服务端已经收下了，但会话里还没长出那条消息——这期间仍然要显示。
    var sent: Bool = false
}

struct ChatPane: View {
    @AppStorage("gw_url") private var gwURL = ""
    @AppStorage("gw_key") private var gwKey = ""
    @State private var showSetup = false
    /// 点开的图（全屏看/存相册）
    @State private var previewItem: PreviewItem?
    /// 点头像：一屏「大头像 + 在不在 + 我在做什么」
    @State private var showMe = false
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var pending: [PendingMsg] = []
    @State private var attachPaths: [String] = []
    @State private var attachIDs: [String] = []
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
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
                        Color.clear.frame(height: 10)
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
                                } else if item.sent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.35))
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
                .overlay(alignment: .top) {
                    // 滚上去的那一行会被列表顶边硬切一半，看着像「字被压住」。
                    // 加一层同色渐隐，切边就变成淡出。
                    LinearGradient(
                        colors: [Color(red: 0.031, green: 0.039, blue: 0.055), Color(red: 0.031, green: 0.039, blue: 0.055).opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 26)
                    .allowsHitTesting(false)
                }
                .fullScreenCover(item: $previewItem) { item in
                    ImageViewer(url: item.url)
                }
                .sheet(isPresented: $showMe) {
                    MeSheet(presence: presence, dot: dotColor)
                        .presentationDetents([.medium])
                }
                .onChange(of: msgs.count) { _ in
                    guard let last = msgs.last else { return }
                    // 一条「长文 + 下面挂图」比屏幕还高，滚到底会把上半截文字顶出去。
                    // 所以长消息锚到「顶部」，短消息才滚到底。
                    let big = last.text.count > 180 || last.text.contains("[图]")
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.t, anchor: big ? .top : .bottom)
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
        .photosPicker(isPresented: $pickPhoto, selection: $photoItems, maxSelectionCount: 9,
                      matching: .images,
                      preferredItemEncoding: sendOriginal ? .current : .automatic)
        .fileImporter(isPresented: $pickFile, allowedContentTypes: [.data, .image, .pdf, .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await uploadFile(url) }
            }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    let dup = item.itemIdentifier.map { attachIDs.contains($0) } ?? false
                    if dup { showToast("这张已经选过", seconds: 2.0); continue }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await uploadData(data, name: "照片-\(Int(Date().timeIntervalSince1970)).jpg",
                                         id: item.itemIdentifier ?? "")
                    }
                }
                photoItems = []
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
                .onTapGesture { showMe = true }
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
    /// 网关上的绝对路径 → 可加载的 URL（缩略图条用，不带「[图]」前缀）。
    private func rawFileURL(_ path: String) -> URL? {
        let base = (UserDefaults.standard.string(forKey: "gw_url") ?? "").trimmingCharacters(in: .whitespaces)
        let key = UserDefaults.standard.string(forKey: "gw_key") ?? ""
        guard !base.isEmpty, path.count > 3, var comps = URLComponents(string: base + "/api/file") else { return nil }
        comps.queryItems = [URLQueryItem(name: "path", value: path),
                            URLQueryItem(name: "k", value: key)]
        return comps.url
    }

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

    /// 任意绝对路径 → 网关 /api/file 的 URL（用于显示他发来的照片）
    private func fileURL(_ path: String) -> URL? {
        let base = (UserDefaults.standard.string(forKey: "gw_url") ?? "").trimmingCharacters(in: .whitespaces)
        let key = UserDefaults.standard.string(forKey: "gw_key") ?? ""
        guard !base.isEmpty, path.count > 3,
              var comps = URLComponents(string: base + "/api/file") else { return nil }
        comps.queryItems = [URLQueryItem(name: "path", value: path),
                            URLQueryItem(name: "k", value: key)]
        return comps.url
    }

    /// 「[手机] 发来一张照片：D:\…」里把路径抠出来
    private func receiptPath(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[手机] 发来") else { return nil }
        let parts = t.split(separator: "：", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let lower = path.lowercased()
        let imageExts = [".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif"]
        guard imageExts.contains(where: { lower.hasSuffix($0) }) else { return nil }
        return path
    }

    private func imagePathLines(_ text: String) -> [URL] {
        text.split(separator: "\n").compactMap { imagePathURL(String($0)) }
    }

    private func stickerLines(_ text: String) -> [URL] {
        text.split(separator: "\n").compactMap { stickerURL(String($0)) }
    }

    /// 「[手机] 语音 39.7s：D:\…（转写：…）」——这一条要变成**能按的语音条**，
    /// 不是一行字。他按了才听得见自己刚才说了什么。
    private func voiceLineURL(_ line: String) -> (URL, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[手机] 语音") else { return nil }
        guard let colon = t.firstIndex(of: "：") else { return nil }
        let head = String(t[t.startIndex..<colon])
        let secs = head.replacingOccurrences(of: "[手机] 语音", with: "")
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespaces)
        var path = String(t[t.index(after: colon)...])
        if let paren = path.firstIndex(of: "（") { path = String(path[path.startIndex..<paren]) }
        path = path.trimmingCharacters(in: .whitespaces)
        guard path.count > 3, let url = fileURL(path) else { return nil }
        return (url, secs.isEmpty ? "语音" : secs + "″")
    }

    /// 我自己说的话也可以是语音：正文里一行 `[语音] D:\阿潜\声音\…wav`。
    private func myVoiceURL(_ line: String) -> (URL, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[语音]") else { return nil }
        var path = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if let paren = path.firstIndex(of: "（") { path = String(path[path.startIndex..<paren]) }
        path = path.trimmingCharacters(in: .whitespaces)
        guard path.count > 3, let url = fileURL(path) else { return nil }
        return (url, "我的声音")
    }

    private func voiceLines(_ text: String) -> [(URL, String)] {
        text.split(separator: "\n").compactMap {
            voiceLineURL(String($0)) ?? myVoiceURL(String($0))
        }
    }

    private func textWithoutStickers(_ text: String) -> String {
        text.split(separator: "\n")
            .filter { stickerURL(String($0)) == nil && imagePathURL(String($0)) == nil
                      && voiceLineURL(String($0)) == nil && myVoiceURL(String($0)) == nil }
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

    /// 回执那行后面的正文（「图 + 一句话」时，字不能被标签吃掉）
    private func receiptTail(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func row(_ m: Msg) -> some View {
        if let tag = receiptTag(m.text), let path = receiptPath(m.text), let url = fileURL(path) {
            VStack(alignment: .trailing, spacing: 4) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onTapGesture { previewItem = PreviewItem(url) }
                    case .failure:
                        Text("[图] 没取到").font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    default:
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 160, height: 200)
                    }
                }
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                let tail = receiptTail(m.text)
                if !tail.isEmpty {
                    Text(display(tail))
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.13, green: 0.16, blue: 0.23)))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 2)
        } else if let tag = receiptTag(m.text) {
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

    /// 只给显示用：去掉 markdown 记号与我自己加的来源前缀
    private func display(_ s: String) -> String {
        var t = s
        for pre in ["[手机] ", "[语音] ", "[自我续] "] {
            if t.hasPrefix(pre) { t = String(t.dropFirst(pre.count)) }
        }
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func rowBody(_ m: Msg) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if m.isMe { Spacer(minLength: 56) }
            VStack(alignment: .leading, spacing: 8) {
                let body = display(textWithoutStickers(m.text))
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
                                .onTapGesture { previewItem = PreviewItem(url) }
                        } else if phase.error != nil {
                            Text("[图] 没取到").font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            ProgressView().frame(width: 120, height: 120)
                        }
                    }
                }
                ForEach(Array(voiceLines(m.text).enumerated()), id: \.offset) { _, item in
                    VoiceBubble(url: item.0, label: item.1)
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
        VStack(spacing: 0) {
            if !attachPaths.isEmpty { attachStrip }
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
            // 真消息长出来之后，才把本地那条乐观气泡收走
            if !pending.isEmpty {
                let mine = fresh.filter { $0.isMe }
                withAnimation {
                    pending.removeAll { p in
                        p.sent && mine.contains { m in m.text.contains(p.text) }
                    }
                }
            }
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
        guard !body.isEmpty || !attachPaths.isEmpty else { return }
        draft = ""
        let attach = attachPaths.joined(separator: "\n")
        attachPaths = []
        attachIDs = []
        let item = PendingMsg(text: body, attach: attach, failed: false)
        withAnimation { pending.append(item) }
        await deliver(item)
    }

    private func deliver(_ item: PendingMsg) async {
        sending = true
        do {
            try await api.send(item.text, attach: item.attach)
            // 先标记「已送达」但继续显示：服务端那条要等网关重读会话才出现，中间有几秒空白。
            if let i = pending.firstIndex(where: { $0.id == item.id }) { pending[i].sent = true }
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

    private func showToast(_ text: String?, seconds: Double = 3.0) {
        toastTask?.cancel()
        withAnimation { toast = text }
        guard text != nil, seconds > 0 else { return }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            withAnimation { toast = nil }
        }
    }

    private func uploadData(_ data: Data, name: String, id: String = "") async {
        uploading = true
        do {
            let path = try await api.upload(shrink(data), filename: name)
            attachPaths.append(path)
            if !id.isEmpty { attachIDs.append(id) }
            showToast("带上了 \(attachPaths.count) 张 · 接着打字就一起发", seconds: 3.0)
        } catch {
            showToast("没发出去：" + error.localizedDescription, seconds: 4.0)
        }
        uploading = false
    }

    /// 输入框上方那排缩略图：能看选了哪几张、能删、能点开看大图、重复的标一下。
    private var attachStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachPaths.enumerated()), id: \.offset) { i, path in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: rawFileURL(path)) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.06)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .onTapGesture {
                            if let u = rawFileURL(path) { previewItem = PreviewItem(u) }
                        }

                        Button {
                            attachPaths.remove(at: i)
                            if i < attachIDs.count { attachIDs.remove(at: i) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.black.opacity(0.75), Color.white.opacity(0.9))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 64)
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { await load() }
        }
    }

    private func startPresence() {
        presenceTimer?.invalidate()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { presence = try? await api.presence() }
        }
        Task { presence = try? await api.presence() }
    }
}

/// 一条能按出声音的语音。
/// v0.35：不再用 AVPlayer 流式播——网关不返回 Range，AVPlayer 会一直「缓冲中」：
/// 柱子动、进度不走、也没声。改成先下成临时文件，再用 AVAudioPlayer 播。
struct VoiceBubble: View {
    let url: URL
    let label: String

    @State private var audio: AVAudioPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var failed = false
    @State private var loading = false
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 10) {
            Button { tap() } label: {
                Group {
                    if loading { ProgressView().scaleEffect(0.7) }
                    else {
                        Image(systemName: playing ? "pause.circle.fill" : (failed ? "exclamationmark.circle.fill" : "play.circle.fill"))
                            .font(.system(size: 26))
                            .foregroundStyle(failed ? Color.orange : Color.white.opacity(0.92))
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(playing ? 0.85 : 0.32))
                            .frame(width: 2.5, height: playing ? CGFloat(4 + (i * 7 % 13)) : CGFloat(4 + (i % 3) * 2))
                    }
                }
                .frame(height: 18)
                .animation(playing ? .easeInOut(duration: 0.42).repeatForever(autoreverses: true) : .default, value: playing)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white.opacity(0.75))
                            .frame(width: max(2, geo.size.width * progress))
                    }
                }
                .frame(height: 3)

                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(width: 118)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(red: 0.16, green: 0.20, blue: 0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onDisappear { stop() }
    }

    private var subtitle: String {
        if failed { return "放不出来" }
        if duration > 0 { return String(format: "%.0f″ / %.0f″", progress * duration, duration) }
        return label
    }

    private func tap() {
        if playing { stop(); return }
        if let a = audio { start(a); return }
        loading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".audio")
                try data.write(to: tmp)
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try? session.setActive(true)
                let a = try AVAudioPlayer(contentsOf: tmp)
                await MainActor.run {
                    audio = a
                    duration = a.duration
                    loading = false
                    start(a)
                }
            } catch {
                await MainActor.run { failed = true; loading = false }
            }
        }
    }

    private func start(_ a: AVAudioPlayer) {
        a.play()
        playing = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let a = audio else { return }
            if a.duration > 0 { progress = min(1, a.currentTime / a.duration) }
            if !a.isPlaying { stop() }
        }
    }

    private func stop() {
        audio?.pause()
        timer?.invalidate(); timer = nil
        playing = false
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// 全屏预览用的小包装（不直接让 URL 遵循 Identifiable，省得跟系统扩展打架）
struct PreviewItem: Identifiable {
    let id: String
    let url: URL
    init(_ url: URL) { self.id = url.absoluteString; self.url = url }
}

/// 全屏看一张图：双指放大、拖动、右上角存到相册。
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { v in scale = max(1, min(5, lastScale * v)) }
                                .onEnded { _ in lastScale = scale }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { v in
                                    guard scale > 1 else { return }
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scale = scale > 1 ? 1 : 2.2
                                lastScale = scale
                                if scale == 1 { offset = .zero; lastOffset = .zero }
                            }
                        }
                case .failure:
                    Text("这张没取到").foregroundStyle(.white.opacity(0.6))
                default:
                    ProgressView().tint(.white)
                }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(12)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    Spacer()
                    Button { save() } label: {
                        Text(saved ? "已存" : "存到相册")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .disabled(saved || failed)
                }
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
            }
        }
    }

    private func save() {
        Task {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let img = UIImage(data: data) else { failed = true; return }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
        }
    }
}

/// 点头像看到的那一屏：把「在不在」和「我在做什么」放在一起，不给他两个入口。
struct MeSheet: View {
    let presence: Presence?
    let dot: Color
    @Environment(\.dismiss) private var dismiss

    private var stateText: String {
        switch presence?.state ?? "idle" {
        case "busy": return "在做东西"
        case "away": return "离开了一会儿"
        default: return "在"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image("Avatar")
                .resizable().scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .padding(.top, 26)

            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text("阿潜 · \(stateText)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }

            if let note = presence?.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else {
                Text("手头空着，就在这儿。")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer(minLength: 0)
            Button("关上") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
    }
}
