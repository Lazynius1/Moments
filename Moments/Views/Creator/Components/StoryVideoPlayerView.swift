import AVFoundation
import SwiftUI
import UIKit

struct StoryVideoPlayerView: UIViewRepresentable {
    let videoURL: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var isMuted: Bool = false
    var trimStart: Double = 0.0
    var trimEnd: Double = 0.0
    var previewTime: Double? = nil
    var onPlayProgress: ((Double) -> Void)? = nil

    func makeUIView(context: Context) -> PlayerUIView {
        let playerView = PlayerUIView()
        playerView.onPlayProgress = onPlayProgress
        playerView.update(
            with: videoURL,
            gravity: videoGravity,
            isMuted: isMuted,
            trimStart: trimStart,
            trimEnd: trimEnd,
            previewTime: previewTime
        )
        return playerView
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.onPlayProgress = onPlayProgress
        uiView.update(
            with: videoURL,
            gravity: videoGravity,
            isMuted: isMuted,
            trimStart: trimStart,
            trimEnd: trimEnd,
            previewTime: previewTime
        )
    }
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentURL: URL?
    private var currentGravity: AVLayerVideoGravity?
    private var timeObserverToken: Any?

    var onPlayProgress: ((Double) -> Void)?
    private var trimStart: Double = 0.0
    private var trimEnd: Double = 0.0
    private var isScrubbing: Bool = false

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
        ) { [weak self] _ in
            self?.cleanupPlayer()
        }
    }

    func update(
        with url: URL,
        gravity: AVLayerVideoGravity = .resizeAspect,
        isMuted: Bool = false,
        trimStart: Double,
        trimEnd: Double,
        previewTime: Double?
    ) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd

        if currentURL != url || player == nil || playerLayer == nil {
            configurePlayer(with: url, gravity: gravity, isMuted: isMuted)
        } else {
            if currentGravity != gravity {
                currentGravity = gravity
                playerLayer?.videoGravity = gravity
            }
            player?.isMuted = isMuted
        }

        // Handle scrubbing seek vs normal playback
        if let preview = previewTime {
            if !isScrubbing {
                isScrubbing = true
                player?.pause()
            }
            let targetTime = CMTime(seconds: preview, preferredTimescale: 600)
            player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            if isScrubbing {
                isScrubbing = false
                // Seek to current trimStart when finishing scrubbing drag, then play
                let targetTime = CMTime(seconds: trimStart, preferredTimescale: 600)
                player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    self?.player?.play()
                }
            }
        }
    }

    private func configurePlayer(with url: URL, gravity: AVLayerVideoGravity, isMuted: Bool) {
        cleanupTimeObserver()
        player?.pause()
        playerLayer?.removeFromSuperlayer()

        currentURL = url
        currentGravity = gravity
        player = AVPlayer(url: url)
        player?.isMuted = isMuted

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        layer.frame = bounds
        self.playerLayer = layer
        self.layer.addSublayer(layer)

        setupTimeObserver()
        player?.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let targetTime = CMTime(seconds: self.trimStart, preferredTimescale: 600)
            self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            self.player?.play()
        }
    }

    private func setupTimeObserver() {
        guard let player = player else { return }
        cleanupTimeObserver()

        // 0.05 seconds interval (20 times per second) for highly smooth playhead movement
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentSeconds = time.seconds

            // Invoke progress callback
            self.onPlayProgress?(currentSeconds)

            // Loop range boundary checking: only loop if we're not scrubbing and active trim is specified (trimEnd > 0)
            if !self.isScrubbing && self.trimEnd > 0.0 && (currentSeconds >= self.trimEnd || currentSeconds < self.trimStart - 0.2) {
                let targetTime = CMTime(seconds: self.trimStart, preferredTimescale: 600)
                self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.player?.play()
            }
        }
    }

    private func cleanupTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func cleanupPlayer() {
        cleanupTimeObserver()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
