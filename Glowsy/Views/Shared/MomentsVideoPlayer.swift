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
    let videoGravity: AVLayerVideoGravity
    var onDurationReceived: ((Double) -> Void)? = nil
    var onProgressUpdate: ((Double) -> Void)? = nil
    var onVideoFinished: (() -> Void)? = nil
    
    private static let playerItemCache = PlayerItemCache()
    
    private final class PlayerItemCache {
        private let cache = NSCache<NSURL, AVPlayerItem>()
        
        init() {
            cache.countLimit = 30
        }
        
        func makeItem(for url: URL) -> AVPlayerItem {
            let key = url as NSURL
            if let cachedItem = cache.object(forKey: key),
               let copiedItem = cachedItem.copy() as? AVPlayerItem {
                return copiedItem
            }
            
            let newItem = AVPlayerItem(url: url)
            cache.setObject(newItem, forKey: key)
            if let copiedItem = newItem.copy() as? AVPlayerItem {
                return copiedItem
            }
            return AVPlayerItem(url: url)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎬 MomentsVideoPlayer: makeUIViewController for URL: \(url.absoluteString)")
        let controller = AVPlayerViewController()
        
        let playerItem = Self.playerItemCache.makeItem(for: url)
        configurePlayerItem(playerItem)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = prioritizeSmoothPlayback
        
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .black
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        context.coordinator.setupObservers(for: playerItem)
        
        setupAudioSession()
        
        if !isPaused {
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
            
            let playerItem = Self.playerItemCache.makeItem(for: url)
            configurePlayerItem(playerItem)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = prioritizeSmoothPlayback
            
            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.setupObservers(for: playerItem)
            
            if !isPaused {
                newPlayer.play()
            }
        }
        
        if let player = uiViewController.player {
            player.isMuted = isMuted
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
                    let duration = CMTimeGetSeconds(item.duration)
                    if !duration.isNaN && !duration.isInfinite {
                        DispatchQueue.main.async {
                            self.parent.onDurationReceived?(duration)
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
