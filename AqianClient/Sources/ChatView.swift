import SwiftUI

struct ChatView: View {
    let session: SessionRow

    @State private var msgs: [Msg] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(msgs) { m in
                            bubble(m).id(m.t)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last { withAnimation { proxy.scrollTo(last.t, anchor: .bottom) } }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            composer
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            startPolling()
        }
        .onDisappear { timer?.invalidate() }
    }

    private func bubble(_ m: Msg) -> some View {
        HStack {
            if m.isMe { Spacer(minLength: 40) }
            Text(m.text)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(m.isMe ? Color(red: 0.24, green: 0.32, blue: 0.45) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !m.isMe { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    private func load() async {
        do {
            msgs = try await API.shared.messages(id: session.id)
            error = nil
        } catch {
            self.error = "读不到消息：" + error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await API.shared.send(text)
            draft = ""
            await load()
        } catch {
            self.error = "没发出去：" + error.localizedDescription
        }
    }

    // 先轮询；等网关的 SSE 稳了再换
    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { await load() }
        }
    }
}
