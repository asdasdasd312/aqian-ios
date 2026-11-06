import AVFoundation
import Foundation

/// 按住说话：按下去开始录，松开停，拿 URL 走上传。
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var recording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            guard ok else { return }
            DispatchQueue.main.async {
                let u = FileManager.default.temporaryDirectory
                    .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ]
                do {
                    let r = try AVAudioRecorder(url: u, settings: settings)
                    r.record()
                    self.recorder = r
                    self.url = u
                    self.recording = true
                } catch {
                    self.recording = false
                }
            }
        }
    }

    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let u = url else { return nil }
        url = nil
        return try? Data(contentsOf: u)
    }
}
