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
        // Evitar PiP / fullscreen del sistema (sale del ScreenshotProtectedView).
        // Deployment target ≥ iOS 18.6.
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        context.coordinator.lastShouldAutoplay = shouldAutoplay
        context.coordinator.setupObservers(for: playerItem)
        
        DispatchQueue.main.async {
            self.sharedPlayer?.wrappedValue = player
        }
        
        player.isMuted = true
        context.coordinator.updateAudioSession()
        
        if shouldAutoplay && (!respectsExternalPauseState || !isPaused) {
            print("🎬 MomentsVideoPlayer: Triggering initial play")
            player.play()
        }
        if isMuted { player.isMuted = true }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if context.coordinator.parent.isPaused != isPaused || context.coordinator.lastURL != url {
            context.coordinator.interrupted = false
        }
        context.coordinator.parent = self // ✅ Update parent reference
        context.coordinator.updateAudioSession()
        
        if context.coordinator.lastURL?.absoluteString != url.absoluteString {
            print("🎬 MomentsVideoPlayer: updateUIViewController - URL Changed from \(context.coordinator.lastURL?.absoluteString ?? "nil") to \(url.absoluteString)")
            context.coordinator.lastURL = url
            
            let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
            configurePlayerItem(playerItem)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            newPlayer.isMuted = true
            newPlayer.automaticallyWaitsToMinimizeStalling = prioritizeSmoothPlayback
            
            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.updateAudioSession(force: true)
            context.coordinator.lastShouldAutoplay = shouldAutoplay
            context.coordinator.setupObservers(for: playerItem)
            
            DispatchQueue.main.async {
                self.sharedPlayer?.wrappedValue = newPlayer
            }
            
            if shouldAutoplay && (!respectsExternalPauseState || !isPaused) {
                newPlayer.play()
            }
        }
        
        if context.coordinator.interrupted { uiViewController.player?.pause(); return }
        if let player = uiViewController.player {
            if let time = externalSeekTime?.wrappedValue {
                player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                DispatchQueue.main.async {
                    self.externalSeekTime?.wrappedValue = nil
                }
            }
            if isMuted { player.isMuted = true }
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
    
    private func configurePlayerItem(_ item: AVPlayerItem) {
        let tier = VideoPlaybackSelector.shared.recommendedTier()
        VideoPlaybackSelector.shared.configure(playerItem: item, tier: tier)
        if prioritizeSmoothPlayback {
            item.preferredForwardBufferDuration = 8.0
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        coordinator.cleanup()
    }
    
    class Coordinator: NSObject {
        private let audioSession = MomentsAudioSessionLease()
        private var audioActivationTask: Task<Void, Never>?
        var interrupted = false
        private var needsAudio = false
        private var interruptionObserver: NSObjectProtocol?

        func updateAudioSession(force: Bool = false) {
            let needed = !interrupted && !parent.isMuted && parent.shouldAutoplay && (!parent.respectsExternalPauseState || !parent.isPaused)
            guard force || needed != needsAudio else { return }
            needsAudio = needed
            audioActivationTask?.cancel()
            guard needed else {
                player?.isMuted = true
                audioSession.deactivate()
                return
            }
            audioActivationTask = Task { @MainActor [weak self] in
                guard let self, await self.audioSession.activate(mode: .moviePlayback),
                      !Task.isCancelled, self.needsAudio else { return }
                self.player?.isMuted = false
            }
        }

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
            super.init()
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: MomentsAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.interrupted = true
                self?.audioActivationTask?.cancel()
                self?.player?.pause()
                self?.audioSession.deactivate()
                self?.needsAudio = false
            }
        }
        
        func setupObservers(for item: AVPlayerItem) {
            cleanup(releasingAudio: false)
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
                    if !self.interrupted && !self.parent.isPaused {
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
                if !self.interrupted && !self.parent.isPaused, self.player?.rate == 0, item.status == .readyToPlay {
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
            guard !interrupted && !parent.isPaused else { return }
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
                guard !self.interrupted && !self.parent.isPaused else { return }
                self.player?.play()
            }
            pendingRecoveryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        
        func cleanup(releasingAudio: Bool = true) {
            if releasingAudio {
                audioActivationTask?.cancel()
                audioSession.deactivate()
                if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
            }
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
