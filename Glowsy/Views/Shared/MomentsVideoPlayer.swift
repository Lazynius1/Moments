import SwiftUI
import AVKit
import AVFoundation

/// A robust video player designed for Moments' chat and view-once media.
/// Supports infinite looping, progress tracking, and professional audio session management.
struct MomentsVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let isLooping: Bool
    let isPaused: Bool
    let videoGravity: AVLayerVideoGravity
    var onDurationReceived: ((Double) -> Void)? = nil
    var onProgressUpdate: ((Double) -> Void)? = nil
    var onVideoFinished: (() -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎬 MomentsVideoPlayer: makeUIViewController for URL: \(url.absoluteString)")
        let controller = AVPlayerViewController()
        
        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        
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
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.parent = self // ✅ Update parent reference
        
        if context.coordinator.lastURL?.absoluteString != url.absoluteString {
            print("🎬 MomentsVideoPlayer: updateUIViewController - URL Changed from \(context.coordinator.lastURL?.absoluteString ?? "nil") to \(url.absoluteString)")
            context.coordinator.lastURL = url
            
            let playerItem = AVPlayerItem(url: url)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            
            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.setupObservers(for: playerItem)
            
            if !isPaused {
                newPlayer.play()
            }
        }
        
        if let player = uiViewController.player {
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
        private var looper: AVPlayerLooper?
        
        init(_ parent: MomentsVideoPlayer) {
            self.parent = parent
        }
        
        func setupObservers(for item: AVPlayerItem) {
            cleanup()
            
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
            
            // 2. Looping Logic with AVPlayerLooper for better stability
            if parent.isLooping, let queuePlayer = player as? AVQueuePlayer {
                print("🎬 MomentsVideoPlayer: Enabling AVPlayerLooper")
                looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            } else {
                NotificationCenter.default.addObserver(
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
        
        func cleanup() {
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            statusObserver?.invalidate()
            statusObserver = nil
            looper = nil
            NotificationCenter.default.removeObserver(self)
        }
    }
}
