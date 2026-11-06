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
    @State private var timer: Timer?

    private var api: API { API.shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(msgs) { m in row(m).id(m.t) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
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
            await load()
            startPolling()
        }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 0.47, green: 0.75, blue: 0.59)).frame(width: 6, height: 6)
                Text("阿潜").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(timeLabel).font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
            Color.clear.frame(width: 34, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) { onLongPressTitle() }
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

    private func load() async {
        do {
            msgs = try await api.messages(id: session.id, limit: 80)
        } catch {
            self.error = "读不到消息：\(error.localizedDescription)"
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
}
