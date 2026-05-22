import SwiftUI
import AVKit
import AVFoundation

/// A robust video player designed for Moments' chat and view-once media.
/// Supports infinite looping, progress tracking, and professional audio session management.
struct MomentsVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let isLooping: Bool
    let isPaused: Bool
    var isMuted: Bool = false
    var prioritizeSmoothPlayback: Bool = false
    var showsPlaybackControls: Bool = false
    var respectsExternalPauseState: Bool = true
    var shouldAutoplay: Bool = true
    let videoGravity: AVLayerVideoGravity
    var onDurationReceived: ((Double) -> Void)? = nil
    var onProgressUpdate: ((Double) -> Void)? = nil
    var onProgressFractionUpdate: ((Double) -> Void)? = nil
    var onVideoFinished: (() -> Void)? = nil
    var externalSeekTime: Binding<Double?>? = nil
    var sharedPlayer: Binding<AVPlayer?>? = nil
    

    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎬 MomentsVideoPlayer: makeUIViewController for URL: \(url.absoluteString)")
        let controller = AVPlayerViewController()
        
        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        configurePlayerItem(playerItem)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = prioritizeSmoothPlayback
        
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .black
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        context.coordinator.lastShouldAutoplay = shouldAutoplay
        context.coordinator.setupObservers(for: playerItem)
        
        DispatchQueue.main.async {
            self.sharedPlayer?.wrappedValue = player
        }
        
        setupAudioSession()
        
        if shouldAutoplay && (!respectsExternalPauseState || !isPaused) {
            print("🎬 MomentsVideoPlayer: Triggering initial play")
            player.play()
        }
        player.isMuted = isMuted
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.parent = self // ✅ Update parent reference
        
        if context.coordinator.lastURL?.absoluteString != url.absoluteString {
            print("🎬 MomentsVideoPlayer: updateUIViewController - URL Changed from \(context.coordinator.lastURL?.absoluteString ?? "nil") to \(url.absoluteString)")
            context.coordinator.lastURL = url
            
            let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
            configurePlayerItem(playerItem)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = prioritizeSmoothPlayback
            
            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.lastShouldAutoplay = shouldAutoplay
            context.coordinator.setupObservers(for: playerItem)
            
            DispatchQueue.main.async {
                self.sharedPlayer?.wrappedValue = newPlayer
            }
            
            if shouldAutoplay && (!respectsExternalPauseState || !isPaused) {
                newPlayer.play()
            }
        }
        
        if let player = uiViewController.player {
            if let time = externalSeekTime?.wrappedValue {
                player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                DispatchQueue.main.async {
                    self.externalSeekTime?.wrappedValue = nil
                }
            }
            player.isMuted = isMuted
            if respectsExternalPauseState {
                if isPaused {
                    if player.rate != 0 {
                        print("🎬 MomentsVideoPlayer: Pausing player")
                        player.pause()
                    }
                } else {
                    if player.rate == 0 && (player.status == .readyToPlay || player.currentItem?.status == .readyToPlay) {
                        print("🎬 MomentsVideoPlayer: Resuming player")
                        player.play()
                    }
                }
            } else if context.coordinator.lastShouldAutoplay != shouldAutoplay {
                context.coordinator.lastShouldAutoplay = shouldAutoplay
                if shouldAutoplay {
                    if player.rate == 0 && (player.status == .readyToPlay || player.currentItem?.status == .readyToPlay) {
                        player.play()
                    }
                } else if player.rate != 0 {
                    player.pause()
                }
            }
        }
    }
    
    private func setupAudioSession() {
        // Run on background to avoid blocking main thread during UI creation
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("🎬 MomentsVideoPlayer: Audio Session Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func configurePlayerItem(_ item: AVPlayerItem) {
        item.preferredForwardBufferDuration = prioritizeSmoothPlayback ? 8.0 : 2.5
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if #available(iOS 14.0, *) {
            item.preferredPeakBitRate = 0
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        coordinator.cleanup()
    }
    
    class Coordinator: NSObject {
        var parent: MomentsVideoPlayer
        var player: AVPlayer?
        var lastURL: URL?
        var lastShouldAutoplay: Bool?
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?
        private var playbackLikelyObserver: NSKeyValueObservation?
        private var playbackBufferEmptyObserver: NSKeyValueObservation?
        private var looper: AVPlayerLooper?
        private var didPlayToEndObserver: NSObjectProtocol?
        private var playbackStalledObserver: NSObjectProtocol?
        private var pendingRecoveryWorkItem: DispatchWorkItem?
        private var stallRetryCount = 0
        private let maxStallRetryCount = 5
        
        init(_ parent: MomentsVideoPlayer) {
            self.parent = parent
        }
        
        func setupObservers(for item: AVPlayerItem) {
            cleanup()
            stallRetryCount = 0
            
            // 1. Monitor Item Status (Critical for duration and errors)
            statusObserver = item.observe(\.status, options: [.new, .old]) { [weak self] item, change in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    print("🎬 MomentsVideoPlayer: Ready to play. Duration: \(CMTimeGetSeconds(item.duration))")
                    let itemDuration = CMTimeGetSeconds(item.duration)
                    if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                        DispatchQueue.main.async {
                            self.parent.onDurationReceived?(itemDuration)
                        }
                    } else {
                        // Fallback: load asset duration async (iOS 16+ non-deprecated API)
                        Task { [weak self] in
                            guard let self else { return }
                            if let assetDuration = try? await item.asset.load(.duration) {
                                let resolved = CMTimeGetSeconds(assetDuration)
                                if !resolved.isNaN && !resolved.isInfinite && resolved > 0 {
                                    await MainActor.run {
                                        self.parent.onDurationReceived?(resolved)
                                    }
                                }
                            }
                        }
                    }
                    if !self.parent.isPaused {
                        self.player?.play()
                    }
                    
                case .failed:
                    if let error = item.error {
                        print("❌ MomentsVideoPlayer: Player Item Failed with Error: \(error.localizedDescription)")
                        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                            print("❌ MomentsVideoPlayer: Underlying Error: \(underlyingError.localizedDescription)")
                        }
                    } else {
                        print("❌ MomentsVideoPlayer: Player Item Failed without specific error")
                    }
                    
                case .unknown:
                    print("🎬 MomentsVideoPlayer: Player status is unknown")
                @unknown default:
                    break
                }
            }
            
            playbackLikelyObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                guard item.isPlaybackLikelyToKeepUp else { return }
                self.pendingRecoveryWorkItem?.cancel()
                self.pendingRecoveryWorkItem = nil
                self.stallRetryCount = 0
                if !self.parent.isPaused, self.player?.rate == 0, item.status == .readyToPlay {
                    self.player?.play()
                }
            }
            
            playbackBufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                if item.isPlaybackBufferEmpty {
                    self.recoverFromPlaybackStall()
                }
            }
            
            playbackStalledObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.recoverFromPlaybackStall()
            }
            
            // 2. Looping Logic with AVPlayerLooper for better stability
            if parent.isLooping, let queuePlayer = player as? AVQueuePlayer {
                print("🎬 MomentsVideoPlayer: Enabling AVPlayerLooper")
                looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            } else {
                didPlayToEndObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    guard let self = self else { return }
                    if self.parent.isLooping {
                        self.player?.seek(to: .zero)
                        self.player?.play()
                    } else {
                        self.parent.onVideoFinished?()
                    }
                }
            }
            
            // 3. Periodic Progress Updates
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if !seconds.isNaN && !seconds.isInfinite {
                    self.parent.onProgressUpdate?(seconds)
                    if let currentItem = self.player?.currentItem {
                        let durationSeconds = CMTimeGetSeconds(currentItem.duration)
                        if durationSeconds.isFinite, durationSeconds > 0 {
                            let progress = min(max(seconds / durationSeconds, 0.0), 1.0)
                            self.parent.onProgressFractionUpdate?(progress)
                        }
                    }
                }
            }
        }
        
        private func recoverFromPlaybackStall() {
            guard !parent.isPaused else { return }
            guard let player = player, let item = player.currentItem else { return }
            guard item.status != .failed else { return }
            guard stallRetryCount < maxStallRetryCount else { return }
            guard pendingRecoveryWorkItem == nil else { return }
            
            stallRetryCount += 1
            player.pause()
            
            let delay = min(1.25, 0.25 + (Double(stallRetryCount) * 0.2))
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.pendingRecoveryWorkItem = nil
                guard !self.parent.isPaused else { return }
                self.player?.play()
            }
            pendingRecoveryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        
        func cleanup() {
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            statusObserver?.invalidate()
            statusObserver = nil
            playbackLikelyObserver?.invalidate()
            playbackLikelyObserver = nil
            playbackBufferEmptyObserver?.invalidate()
            playbackBufferEmptyObserver = nil
            if let didPlayToEndObserver {
                NotificationCenter.default.removeObserver(didPlayToEndObserver)
                self.didPlayToEndObserver = nil
            }
            if let playbackStalledObserver {
                NotificationCenter.default.removeObserver(playbackStalledObserver)
                self.playbackStalledObserver = nil
            }
            pendingRecoveryWorkItem?.cancel()
            pendingRecoveryWorkItem = nil
            stallRetryCount = 0
            looper = nil
        }
    }
}
