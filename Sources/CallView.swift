import SwiftUI
import AVFoundation

/// 通话页（B1：按住说话，松开我回答）。
/// 音频：AVAudioEngine 采 16k 单声道 PCM16，20–100ms 一帧推给语音桥；
/// 桥回来的 wav 直接 AVAudioPlayer 播。
struct CallView: View {
    let base: URL          // 语音桥地址，例如 ws://192.168.1.5:57942/ws
    let key: String

    @Environment(\.dismiss) private var dismiss
    @State private var ws: URLSessionWebSocketTask?
    @State private var engine: AVAudioEngine?
    @State private var player: AVAudioPlayer?
    @State private var talking = false
    @State private var status = "按下说话"
    @State private var lines: [(String, Bool)] = []   // (文本, 是不是我说的)
    @State private var connected = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(status)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, item in
                                HStack {
                                    if item.1 { Spacer(minLength: 40) }
                                    Text(item.0)
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(item.1 ? Color(red: 0.16, green: 0.20, blue: 0.28)
                                                             : Color.white.opacity(0.06))
                                        )
                                    if !item.1 { Spacer(minLength: 40) }
                                }
                                .id(i)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: lines.count) { _ in
                        withAnimation { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                    }
                }

                holdButton
                    .padding(.bottom, 24)
            }
            .background(Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea())
            .navigationTitle("通话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关") { hangup(); dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .onAppear { connect() }
            .onDisappear { hangup() }
        }
    }

    private var holdButton: some View {
        ZStack {
            Circle()
                .fill(talking ? Color(red: 0.72, green: 0.28, blue: 0.18)
                              : Color.white.opacity(0.10))
                .frame(width: 132, height: 132)
                .overlay(
                    Circle().stroke(Color.white.opacity(talking ? 0.35 : 0.12), lineWidth: 2)
                )
            Image(systemName: talking ? "waveform" : "mic.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .scaleEffect(talking ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.12), value: talking)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !talking { startTalking() } }
                .onEnded { _ in stopTalking() }
        )
        .accessibilityLabel("按住说话")
    }

    // MARK: 连接

    private func connect() {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "k", value: key)]
        guard let url = comps?.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        ws = task
        connected = true
        status = "按下说话"
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { result in
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    connected = false
                    status = "连不上语音桥"
                }
            case .success(let message):
                DispatchQueue.main.async { handle(message) }
                receiveLoop(task)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            player = try? AVAudioPlayer(data: data)
            player?.play()
        case .string(let text):
            guard let d = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let kind = obj["type"] as? String else { return }
            switch kind {
            case "ready":
                status = talking ? "在听…" : "按下说话"
            case "text":
                if let t = obj["text"] as? String, !t.isEmpty {
                    lines.append((t, true))
                }
            case "done":
                status = "按下说话"
            case "error":
                status = (obj["error"] as? String) ?? "出错了"
            default:
                break
            }
        @unknown default:
            break
        }
    }

    private func hangup() {
        stopTalking()
        ws?.cancel(with: .normalClosure, reason: nil)
        ws = nil
        connected = false
    }

    // MARK: 录音

    private func startTalking() {
        guard connected else { return }
        talking = true
        status = "在听…"
        send(["type": "start"])

        let e = AVAudioEngine()
        engine = e
        let input = e.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { buffer, _ in
            guard let pcm = Self.toPCM16(buffer: buffer, target: 16000) else { return }
            ws?.send(.data(pcm)) { _ in }
        }
        do {
            try e.start()
        } catch {
            status = "麦克风打不开：\(error.localizedDescription)"
            talking = false
        }
    }

    private func stopTalking() {
        guard talking else { return }
        talking = false
        status = "在想…"
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        send(["type": "end"])
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    /// 任意采样率的 Float32 缓冲 → 16k / mono / PCM16
    static func toPCM16(buffer: AVAudioPCMBuffer, target: Double) -> Data? {
        guard let src = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        let ch = Int(buffer.format.channelCount)
        guard frames > 0, ch > 0 else { return nil }

        // 先混成单声道
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<ch {
            let p = src[c]
            for i in 0..<frames { mono[i] += p[i] }
        }
        if ch > 1 { for i in 0..<frames { mono[i] /= Float(ch) } }

        // 再线性重采样到 16k
        let inRate = buffer.format.sampleRate
        let ratio = target / inRate
        let outCount = max(1, Int(Double(frames) * ratio))
        var out = Data(capacity: outCount * 2)
        for i in 0..<outCount {
            let pos = Double(i) / ratio
            let i0 = min(frames - 1, Int(pos))
            let i1 = min(frames - 1, i0 + 1)
            let frac = Float(pos - Double(i0))
            let v = mono[i0] * (1 - frac) + mono[i1] * frac
            var s = Int16(max(-1, min(1, v)) * 32767)
            withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
        }
        return out
    }
}
