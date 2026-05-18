import AVFoundation
import SwiftUI
import UIKit

struct StoryVideoPlayerView: UIViewRepresentable {
    let videoURL: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerUIView {
        let playerView = PlayerUIView()
        playerView.update(with: videoURL, gravity: videoGravity)
        return playerView
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.update(with: videoURL, gravity: videoGravity)
    }
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentURL: URL?
    private var currentGravity: AVLayerVideoGravity?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPlayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayer()
    }

    private func setupPlayer() {
        backgroundColor = .clear

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CleanupVideoPlayer"),
            object: nil,
            queue: .main
        ) { _ in
            self.cleanupPlayer()
        }
    }

    func update(with url: URL, gravity: AVLayerVideoGravity = .resizeAspect) {
        if currentURL != url || player == nil || playerLayer == nil {
            configurePlayer(with: url, gravity: gravity)
            return
        }

        if currentGravity != gravity {
            currentGravity = gravity
            playerLayer?.videoGravity = gravity
        }
    }

    private func configurePlayer(with url: URL, gravity: AVLayerVideoGravity) {
        player?.pause()
        playerLayer?.removeFromSuperlayer()

        currentURL = url
        currentGravity = gravity
        player = AVPlayer(url: url)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        layer.frame = bounds
        self.playerLayer = layer
        self.layer.addSublayer(layer)

        player?.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func cleanupPlayer() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        cleanupPlayer()
    }
}

struct VideoControlsOverlay: View {
    @State private var isPlaying = true
    @State private var showControls = false

    var body: some View {
        HStack {
            if showControls {
                Button(action: {
                    isPlaying.toggle()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .transition(.opacity)

                Spacer()

                Button(action: {}) {
                    Image(systemName: "gobackward")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .transition(.opacity)
            }
        }
        .padding()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}
