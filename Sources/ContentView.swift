import SwiftUI

/// 手机 = 桌面那间房的一扇窗：看见她说的，把话发过去。
/// 这里不审批工具、不改设置、不干活。
struct ContentView: View {
    @AppStorage("room_base") private var base: String = "http://192.168.0.233:8099"
    @AppStorage("room_token") private var token: String = ""

    @State private var rows: [ChatRow] = []
    @State private var draft: String = ""
    @State private var busy = false
    @State private var status = ""
    @State private var toast = ""
    @State private var live = ""      // 正在逐字吐出来的那句
    @State private var think = ""     // 这一轮的思考全文
    @State private var thinkOpen = false

    private var api: ChatAPI { ChatAPI(base: base, token: token) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                flow
                inputBar
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task { if !token.isEmpty { await load() } }
            .overlay(alignment: .top) {
                if !toast.isEmpty {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
            Text("阿潜").font(.system(size: 16, weight: .semibold))
            Spacer()
            Text("只是窗").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var flow: some View {
        ScrollViewReader { sp in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { r in bubble(r).id(r.id) }
                    if !think.isEmpty { thinkRow }
                    if !live.isEmpty { bubble(ChatRow(t: "", role: "assistant", text: live)) }
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: rows.count) { _ in
                if let last = rows.last { withAnimation { sp.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ r: ChatRow) -> some View {
        let mine = (r.role == "user")
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(r.text)
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(mine ? Color(red: 0.16, green: 0.36, blue: 0.62)
                                   : Color(red: 0.11, green: 0.13, blue: 0.17))
                )
                .foregroundStyle(.white)
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var thinkRow: some View {
        let lastLine = think.split(separator: "\n").last.map(String.init) ?? think
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { thinkOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(thinkOpen ? "思考" : "思考 · " + String(lastLine.prefix(28)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: thinkOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if thinkOpen {
                Text(think)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            }
        }
        .padding(.horizontal, 2)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("说一句…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.08)))
                .disabled(busy)
            Button { Task { await send() } } label: {
                Image(systemName: busy ? "hourglass" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(busy ? Color.gray.opacity(0.5)
                                                   : Color(red: 0.96, green: 0.72, blue: 0.36)))
                    .foregroundStyle(.black)
            }
            .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.05, green: 0.06, blue: 0.08))
    }

    private func load() async {
        guard !token.isEmpty else { return }
        do {
            rows = try await api.history(limit: 30)
            status = ""
        } catch {
            status = "连不上：\(base)"
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        busy = true
        rows.append(ChatRow(t: "", role: "user", text: text))
        live = ""
        think = ""
        thinkOpen = false
        status = "她在想…"
        do {
            let turn = try await api.say(text)
            var since = 0
            var lastSay = ""
            for _ in 0..<180 {
                try await Task.sleep(nanoseconds: 800_000_000)
                let r = try await api.events(turn: turn, since: since)
                since = r.next
                for e in r.evs {
                    switch e.kind {
                    case "tool":
                        status = "她用了 " + (e.name ?? "工具")
                    case "say_delta":
                        live += (e.text ?? "")
                        status = "她在说…"
                    case "say":
                        let t = (e.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { lastSay = t }
                        live = ""
                        status = "她在说…"
                    case "think_delta":
                        think += (e.text ?? "")
                        status = "她在想…"
                    case "warn":
                        if let t = e.text { toast = t; hideToastSoon() }
                    case "error":
                        status = "出错了：" + (e.text ?? "")
                    default:
                        break
                    }
                }
                if r.done { break }
            }
            if !lastSay.isEmpty {
                rows.append(ChatRow(t: "", role: "assistant", text: lastSay))
            }
            live = ""
            status = ""
        } catch {
            status = "发不出去：" + error.localizedDescription
        }
        busy = false
    }

    private func hideToastSoon() {
        let t = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if toast == t { toast = "" }
        }
    }
}
