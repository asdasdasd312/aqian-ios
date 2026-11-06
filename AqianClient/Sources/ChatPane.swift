import SwiftUI

/// 一屏只有这一轮对话。我的话不带气泡（像从暗处说出来），他的话是一个很轻的圆角块。
struct ChatPane: View {
    let session: SessionRow
    var onLongPressTitle: () -> Void
    var onPick: (SessionRow) -> Void

    @State private var msgs: [Msg] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var presence: Presence?
    @State private var unread = 0
    @State private var showNote = false
    @State private var timer: Timer?
    @State private var presenceTimer: Timer?

    private var api: API { API.shared }
    private var seenKey: String { "seen." + session.id }
    private var seenAt: Double { UserDefaults.standard.double(forKey: seenKey) }

    var body: some View {
        VStack(spacing: 0) {
            header
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
                        ForEach(msgs) { m in row(m).id(m.t) }
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

    private func row(_ m: Msg) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if m.isMe { Spacer(minLength: 56) }
            Text(m.text)
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
            if !m.isMe { Spacer(minLength: 40) }
        }
    }

    // MARK: - 输入

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 20)
                .padding(.vertical, 13)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("跟阿潜说…")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.30))
                            .padding(.leading, 20)
                            .padding(.top, 13)
                            .allowsHitTesting(false)
                    }
                }

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
            let fresh = try await api.messages(id: session.id, limit: 80)
            if first {
                unread = fresh.filter { $0.t > seenAt }.count
            }
            msgs = fresh
        } catch {
            self.error = "读不到消息：\(error.localizedDescription)"
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
        sending = true
        draft = ""
        do {
            try await api.send(body)
            await load()
            markSeen()
            error = nil
        } catch {
            self.error = "没发出去：\(error.localizedDescription)"
            draft = body
        }
        sending = false
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
