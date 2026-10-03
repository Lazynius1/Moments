import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Glassmorphic Story Video Player
struct GlassmorphicStoryVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    @Binding var isReadyToPlay: Bool
    let isMutedExternally: Bool
    let isHorizontalVideo: Bool
    let videoGravity: AVLayerVideoGravity
    let shouldLoop: Bool
    var initialSeek: TimeInterval = 0
    let onProgressUpdate: (Double) -> Void
    let onVideoComplete: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()


        // ✅ USAR VIDEOPRELOADER PARA INICIO INSTANTÁNEO
        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)

        let player: AVPlayer
        if shouldLoop {
            let queuePlayer = AVQueuePlayer(items: [playerItem])
            context.coordinator.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            player = queuePlayer
        } else {
            context.coordinator.playerLooper = nil
            player = AVPlayer(playerItem: playerItem)
        }

        player.isMuted = true
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .clear
        context.coordinator.player = player
        context.coordinator.updateAudioSession(playing: isPlaying, muted: isMutedExternally)
        context.coordinator.onProgressUpdate = onProgressUpdate
        context.coordinator.onVideoComplete = onVideoComplete
        context.coordinator.currentURL = url // ✅ Track initial URL
        context.coordinator.pendingSeek = initialSeek
        context.coordinator.didApplySeek = false

        // ✅ CONFIGURAR OBSERVERS PARA PROGRESO
        context.coordinator.setupObservers()
        context.coordinator.observeReadyToPlay(for: playerItem)

        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN
        context.coordinator.configureVideoGravity(for: controller)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // ✅ CRITICAL FIX: Use Coordinator's tracked URL instead of asset URL to avoid infinite loops
        // caused by mismatch between remote URL (view) and local cache URL (AVPlayer asset).
        if context.coordinator.currentURL != url {
             // URL changed, recreate player

            context.coordinator.setReadyToPlay(false)

            // 1. CLEANUP OLD PLAYER
            context.coordinator.cleanupObservers()
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true

            // 2. CREATE NEW PLAYER
            let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
            let newPlayer: AVPlayer
            if shouldLoop {
                let queuePlayer = AVQueuePlayer(items: [playerItem])
                context.coordinator.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                newPlayer = queuePlayer
            } else {
                context.coordinator.playerLooper = nil
                newPlayer = AVPlayer(playerItem: playerItem)
            }

            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.needsAudioForNewPlayer()

            // 3. UPDATE COORDINATOR
            context.coordinator.currentURL = url
            context.coordinator.setupObservers()
            if let item = newPlayer.currentItem {
                context.coordinator.observeReadyToPlay(for: item)
            }
            context.coordinator.pendingSeek = initialSeek
            context.coordinator.didApplySeek = false

            // 4. CONFIGURE GRAVITY
            context.coordinator.configureVideoGravity(for: uiViewController)
        }

        if uiViewController.videoGravity != videoGravity {
            uiViewController.videoGravity = videoGravity
        }

        context.coordinator.updateAudioSession(playing: isPlaying, muted: isMutedExternally)

        // ✅ EVITAR LOOP: Verificar estado actual del player
        let playerIsPlaying = uiViewController.player?.rate != 0.0
        if isMutedExternally || !isPlaying { uiViewController.player?.isMuted = true }

        if isPlaying && !playerIsPlaying {
            // ✅ Solo reproducir si no está reproduciéndose
            if let player = uiViewController.player, player.currentItem != nil {
                if isMutedExternally { player.isMuted = true }
                context.coordinator.applyPendingSeekIfNeeded()
                player.play()
            }
        } else if !isPlaying && playerIsPlaying {
            // ✅ Solo pausar si está reproduciéndose
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true // ✅ SILENCIAR AL PAUSAR
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        private let audioSession = MomentsAudioSessionLease()
        private var audioActivationTask: Task<Void, Never>?
        private var needsAudio = false
        private var interruptionObserver: NSObjectProtocol?
        func needsAudioForNewPlayer() { needsAudio = false }

        func updateAudioSession(playing: Bool, muted: Bool) {
            let needed = playing && !muted
            guard needed != needsAudio else { return }
            needsAudio = needed
            audioActivationTask?.cancel()
            player?.isMuted = true
            guard needed else { audioSession.deactivate(); return }
            audioActivationTask = Task { @MainActor [weak self] in
                guard let self, await self.audioSession.activate(mode: .moviePlayback),
                      !Task.isCancelled, self.needsAudio else { return }
                self.player?.isMuted = false
            }
        }

        var parent: GlassmorphicStoryVideoPlayer
        var player: AVPlayer?
        var playerLooper: AVPlayerLooper?
        var timeObserver: Any?
        var onProgressUpdate: ((Double) -> Void)?
        var onVideoComplete: (() -> Void)?
        var currentURL: URL? // ✅ Track the intended URL
        var pendingSeek: TimeInterval = 0
        var didApplySeek = false

        var completionObserver: NSObjectProtocol? // ✅ Track observer for cleanup
        private var statusObserver: NSKeyValueObservation?

        init(_ parent: GlassmorphicStoryVideoPlayer) {
            self.parent = parent
            super.init()
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: MomentsAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.audioActivationTask?.cancel()
                self?.player?.pause()
                self?.parent.isPlaying = false
                self?.audioSession.deactivate()
                self?.needsAudio = false
            }
            self.currentURL = parent.url // Initialize with current URL
        }

        func setReadyToPlay(_ ready: Bool) {
            DispatchQueue.main.async {
                self.parent.isReadyToPlay = ready
            }
        }

        func observeReadyToPlay(for playerItem: AVPlayerItem) {
            statusObserver?.invalidate()
            setReadyToPlay(playerItem.status == .readyToPlay)
            statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.setReadyToPlay(item.status == .readyToPlay)
                    if item.status == .readyToPlay {
                        self?.applyPendingSeekIfNeeded()
                    }
                }
            }
        }

        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN DEL VIDEO
        func configureVideoGravity(for controller: AVPlayerViewController) {
            controller.videoGravity = parent.videoGravity
        }

        func applyPendingSeekIfNeeded() {
            guard !didApplySeek, pendingSeek > 0.05, let player else { return }
            guard player.currentItem?.status == .readyToPlay else { return }
            didApplySeek = true
            let time = CMTime(seconds: pendingSeek, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        func cleanupObservers() {
            statusObserver?.invalidate()
            statusObserver = nil

            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            // ✅ LIMPIAR OBSERVER DE COMPLETACIÓN
            if let observer = completionObserver {
                NotificationCenter.default.removeObserver(observer)
                completionObserver = nil
            }
            // Fallback for selector-based observers if any
            NotificationCenter.default.removeObserver(self)
        }

        func setupObservers() {
            // ✅ RESET PROGRESO AL CONFIGURAR OBSERVERS
            onProgressUpdate?(0.0)

            // ✅ OBSERVER DE PROGRESO
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                queue: .main
            ) { [weak self] time in
                guard let self = self, let currentItem = self.player?.currentItem else { return }

                let duration = currentItem.duration
                if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                    let durationSeconds = CMTimeGetSeconds(duration)
                    if durationSeconds > 0 {
                        let currentSeconds = CMTimeGetSeconds(time)
                        let progress = min(max(currentSeconds / durationSeconds, 0.0), 1.0)
                        self.onProgressUpdate?(progress)
                    }
                }
            }

            // ✅ OBSERVER DE COMPLETACIÓN: avanzar a la siguiente historia al terminar
            completionObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onProgressUpdate?(0.0)
                if self?.parent.shouldLoop == true {
                    return
                }
                self?.onVideoComplete?()
            }
        }

        deinit {
            if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
            audioActivationTask?.cancel()
            audioSession.deactivate()
            cleanupObservers() // ✅ Ensure observers are removed

            player?.pause()
            player?.isMuted = true
            player?.replaceCurrentItem(with: nil)
            playerLooper = nil
            player = nil

            // ✅ CLEANUP DE AUDIO SESSION

        }
    }
}
