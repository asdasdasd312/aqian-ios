import SwiftUI
import AVKit

/// 一条视频消息：先出第一帧当缩略图，点一下才播（不在列表里自动播）。
/// 网关的 /api/file 已支持 Range，所以可以直接流式拖进度。
struct VideoBubble: View {
    let url: URL

    @State private var thumb: UIImage?
    @State private var showPlayer = false

    var body: some View {
        Button {
            showPlayer = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 300)

                if let img = thumb {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ProgressView().tint(.white.opacity(0.6))
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 6)
            }
        }
        .buttonStyle(.plain)
        .task {
            guard thumb == nil else { return }
            thumb = await Self.firstFrame(url)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            VideoPlayer2(url: url)
        }
    }

    /// 取第一帧当封面；取不到就留着播放键，点开照样能播。
    static func firstFrame(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 660, height: 900)
        let t = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let res = try? await gen.image(at: t) {
            return UIImage(cgImage: res.image)
        }
        return nil
    }
}

/// 全屏播放器：进来就播，点一下暂停/继续，右上角关掉。
private struct VideoPlayer2: View {
    let url: URL
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }
}
