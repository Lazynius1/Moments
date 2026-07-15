// ModernVideoPlayer.swift
import SwiftUI
import AVFoundation

// ✅ NUEVO: Video Manager global para controlar todos los videos
class GlobalVideoManager: ObservableObject {
    static let shared = GlobalVideoManager()
    
    @Published private(set) var activeVideoId: String?
    @Published private(set) var livePlaybackSeconds: [String: Double] = [:]
    private var allPlayers: [String: VideoPlayerManager] = [:]
    private var playbackPositionsByMomentId: [String: Double] = [:]
    private var preservedPlayerConsumerIds: Set<String> = []
    private var pendingDetailHandoffMomentIds: Set<String> = []
    private var volumeObservation: NSKeyValueObservation?
    
    // Si el usuario activa el sonido en algún video, todos los posteriores tienen sonido
    @Published private(set) var userHasEnabledSoundInSession: Bool = false
    
    private init() {
        // Pausar reproducción al salir a background / Control Center, sin resetear el mute de sesión.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        startVolumeObservation()
    }
    
    @objc private func appWillResignActive() {
        pauseAllVideos()
    }

    private func startVolumeObservation() {
        // Patrón IG: subir volumen físico con vídeo activo → unmute de sesión.
        volumeObservation = AVAudioSession.sharedInstance().observe(
            \.outputVolume,
            options: [.old, .new]
        ) { [weak self] _, change in
            guard let self,
                  let oldValue = change.oldValue,
                  let newValue = change.newValue,
                  newValue > oldValue,
                  self.activeVideoId != nil,
                  !self.userHasEnabledSoundInSession
            else { return }

            DispatchQueue.main.async {
                self.enableSoundForSession()
            }
        }
    }

    private func configurePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback {
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
            }
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("GlobalVideoManager: failed to configure playback audio session — \(error)")
            #endif
        }
    }
    
    func registerPlayer(_ playerId: String, manager: VideoPlayerManager) {
        allPlayers[playerId] = manager
        
        // Si el usuario ya activó el sonido en esta sesión, aplicar a este video también
        if userHasEnabledSoundInSession {
            manager.setMuted(false, respectSilentMode: true)
        }
    }
    
    func unregisterPlayer(_ playerId: String, manager: VideoPlayerManager) {
        if allPlayers[playerId] === manager {
            allPlayers.removeValue(forKey: playerId)
            
            if activeVideoId == playerId {
                activeVideoId = nil
            }
        }
    }
    
    func isRegisteredPlayer(_ playerId: String, manager: VideoPlayerManager) -> Bool {
        return allPlayers[playerId] === manager
    }
    
    func playVideo(_ playerId: String) {
        // ✅ PAUSAR todos los otros videos primero
        if let currentActive = activeVideoId, currentActive != playerId {
            allPlayers[currentActive]?.pauseVideo()
        }
        
        // ✅ REPRODUCIR el nuevo video
        activeVideoId = playerId
        allPlayers[playerId]?.resumeVideo()
    }
    
    func pauseVideo(_ playerId: String) {
        if activeVideoId == playerId {
            activeVideoId = nil
        }
        allPlayers[playerId]?.pauseVideo()
    }
    
    func pauseAllVideos() {
        activeVideoId = nil
        for (_, manager) in allPlayers {
            manager.pauseVideo()
        }
    }
    
    /// El usuario activó sonido en Reels u otro reproductor fuera del registro de feed.
    func enableSoundForSession() {
        userHasEnabledSoundInSession = true
        configurePlaybackAudioSession()
        for (_, playerManager) in allPlayers {
            playerManager.setMuted(false, respectSilentMode: true)
        }
    }

    /// Remute simétrico: limpia la preferencia de sesión y mutea todos los players registrados.
    func disableSoundForSession() {
        userHasEnabledSoundInSession = false
        for (_, playerManager) in allPlayers {
            playerManager.setMuted(true)
        }
    }

    // Toggle mute que activa/desactiva el sonido para toda la sesión
    func toggleMute(_ playerId: String) {
        guard let manager = allPlayers[playerId] else { return }
        
        let wasMuted = manager.isMuted
        manager.toggleMute(respectSilentMode: true)
        
        if wasMuted && !manager.isMuted {
            enableSoundForSession()
        } else if !wasMuted && manager.isMuted {
            disableSoundForSession()
        }
    }
    
    // ✅ NUEVO: Obtener estado de mute de un video
    func isMuted(_ playerId: String) -> Bool {
        return allPlayers[playerId]?.isMuted ?? true
    }

    func setPlaybackPosition(seconds: Double, forMomentId momentId: String) {
        guard seconds.isFinite, seconds >= 0 else { return }
        playbackPositionsByMomentId[momentId] = seconds
        // Publicar cambio para que LiveVideoTimeLabel actualice en tiempo real.
        livePlaybackSeconds[momentId] = seconds
    }

    func playbackPosition(forMomentId momentId: String) -> Double {
        playbackPositionsByMomentId[momentId] ?? 0
    }

    func resetPlaybackPosition(forMomentId momentId: String) {
        playbackPositionsByMomentId[momentId] = 0
    }

    static func profileVideoConsumerId(for moment: Moment) -> String {
        moment.id ?? "video_\(moment.authorId)_\(Int(moment.timestamp.timeIntervalSince1970))"
    }

    /// Carrusel: id estable por slide para que GlobalVideoManager no colisione entre medias del mismo post.
    static func profileVideoConsumerId(for moment: Moment, mediaItem: MediaItem) -> String {
        "\(profileVideoConsumerId(for: moment))_\(mediaItem.id)"
    }

    /// `FeedVisibilityCoordinator` publica el moment id; los slides del carrusel usan `momentId_mediaId`.
    static func visibilityMatches(activeMomentId: String?, videoConsumerId: String) -> Bool {
        guard let activeMomentId else { return false }
        return videoConsumerId == activeMomentId
            || videoConsumerId.hasPrefix(activeMomentId + "_")
    }

    /// Hero → detalle: conservar `AVPlayer` y posición hasta que monte el player del detalle.
    func markProfileHeroHandoff(forMomentId momentId: String) {
        pendingDetailHandoffMomentIds.insert(momentId)
        preservedPlayerConsumerIds.insert(momentId)
    }

    func shouldPreserveSharedPlayer(consumerId: String) -> Bool {
        preservedPlayerConsumerIds.contains(consumerId)
    }

    func canReuseSharedPlayer(consumerId: String) -> Bool {
        guard preservedPlayerConsumerIds.contains(consumerId) else { return false }
        return SharedVideoPlayerPool.shared.hasActiveItem(for: consumerId)
    }

    func hasPendingProfileDetailHandoff(forMomentId momentId: String) -> Bool {
        pendingDetailHandoffMomentIds.contains(momentId)
    }

    /// Consumido una sola vez al montar el video en detalle tras transición hero.
    func consumeProfileDetailHandoff(forMomentId momentId: String) -> (reuseExistingItem: Bool, startAtSeconds: Double)? {
        guard pendingDetailHandoffMomentIds.remove(momentId) != nil else { return nil }
        preservedPlayerConsumerIds.remove(momentId)
        return (true, playbackPosition(forMomentId: momentId))
    }

    func clearProfilePlaybackHandoffState() {
        let orphanedPreservedPlayers = preservedPlayerConsumerIds
        pendingDetailHandoffMomentIds.removeAll()
        preservedPlayerConsumerIds.removeAll()
        for consumerId in orphanedPreservedPlayers {
            SharedVideoPlayerPool.shared.release(consumerId: consumerId)
        }
    }

    func releasePreservedPlayer(consumerId: String) {
        preservedPlayerConsumerIds.remove(consumerId)
        SharedVideoPlayerPool.shared.release(consumerId: consumerId)
    }

    /// Feed → Reels: conservar el slot del pool del momento visible mientras se navega en Reels.
    func markReelsFeedHandoff(for moment: Moment, mediaItem: MediaItem? = nil) {
        let consumerId: String
        if let mediaItem {
            consumerId = Self.profileVideoConsumerId(for: moment, mediaItem: mediaItem)
        } else {
            consumerId = Self.profileVideoConsumerId(for: moment)
        }
        preservedPlayerConsumerIds.insert(consumerId)
    }

    func completeReelsFeedHandoff(for moment: Moment, mediaItem: MediaItem? = nil) {
        let consumerId: String
        if let mediaItem {
            consumerId = Self.profileVideoConsumerId(for: moment, mediaItem: mediaItem)
        } else {
            consumerId = Self.profileVideoConsumerId(for: moment)
        }
        preservedPlayerConsumerIds.remove(consumerId)
    }
    
    // ✅ Verificar si el iPhone está en modo silencioso
    private func isDeviceInSilentMode() -> Bool {
        // En iOS, no hay una API directa para detectar el switch de silencio físico
        // Pero podemos usar el volumen del sistema como indicador aproximado
        // Si el volumen es 0, probablemente está en silencio
        let volume = AVAudioSession.sharedInstance().outputVolume
        return volume == 0.0
    }
}

// ✅ MODIFICADO: ModernVideoPlayer con control global
struct ModernVideoPlayer: View {
    let url: String
    let aspectRatio: CGFloat
    let videoId: String // ✅ NUEVO: ID único para este video
    let hideMuteButton: Bool // Legacy; socialReels ignora mute persistente
    let chromeStyle: VideoPlaybackChromeStyle
    let allowsPauseInteraction: Bool
    let posterURLString: String?
    let mediaItem: MediaItem?
    let moment: Moment?
    let activationMode: VideoPlaybackActivationMode
    let consumesDetailHandoff: Bool

    private var usesSocialChrome: Bool { chromeStyle == .socialReels }
    
    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var globalManager = GlobalVideoManager.shared
    @State private var showControls = false
    @State private var showMuteButton = true
    @State private var progress: Double = 0
    @State private var isBuffering = false
    @State private var hasSetupPlayer = false
    @State private var isVisible = false
    @State private var setupRetries = 0
    @State private var setupGeneration = 0
    @State private var hasLoadError = false
    @ObservedObject private var visibilityCoordinator = FeedVisibilityCoordinator.shared
    
    private let maxSetupRetries = 2
    private let setupTimeoutSeconds: Double = 4.0
    
    init(
        url: String,
        aspectRatio: CGFloat,
        videoId: String,
        hideMuteButton: Bool = false,
        chromeStyle: VideoPlaybackChromeStyle = .classic,
        allowsPauseInteraction: Bool = true,
        posterURLString: String? = nil,
        mediaItem: MediaItem? = nil,
        moment: Moment? = nil,
        activationMode: VideoPlaybackActivationMode = .feedVisibility,
        consumesDetailHandoff: Bool = true
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.videoId = videoId
        self.hideMuteButton = hideMuteButton
        self.chromeStyle = chromeStyle
        self.allowsPauseInteraction = allowsPauseInteraction
        self.posterURLString = posterURLString
        self.mediaItem = mediaItem
        self.moment = moment
        self.activationMode = activationMode
        self.consumesDetailHandoff = consumesDetailHandoff
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = playerManager.player, !hasLoadError {
                    let contentMode: ContentMode = usesSocialChrome ? .fill : .fit

                    VideoPlayerRepresentable(
                        player: player,
                        videoGravity: usesSocialChrome ? .resizeAspectFill : .resizeAspect,
                        showControls: $showControls,
                        progress: $progress,
                        isBuffering: $isBuffering
                    )
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .clipped()

                    VideoPosterOverlay(
                        posterURLString: posterURLString,
                        isReadyToPlay: playerManager.isReadyToPlay
                    )
                } else {
                    ZStack {
                        VideoPosterOverlay(
                            posterURLString: posterURLString,
                            isReadyToPlay: false
                        )
                        modernLoadingView
                    }
                }
                
                if usesSocialChrome {
                    if !playerManager.isPlaying, allowsPauseInteraction {
                        SocialVideoPausedControls(
                            isMuted: playerManager.isMuted,
                            onToggleMute: { globalManager.toggleMute(videoId) },
                            onTogglePlay: { togglePlayback() }
                        )
                    }
                } else {
                    controlsOverlay

                    if !hideMuteButton {
                        VStack {
                            Spacer()
                            HStack {
                                muteButton
                                Spacer()
                            }
                        }
                        .padding(12)
                    }

                    VStack {
                        Spacer()
                        if playerManager.duration > 0 {
                            VideoFeedProgressBar(progress: progress)
                        }
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
            globalManager.registerPlayer(videoId, manager: playerManager)
            isVisible = true
            applyActivationMode(activeId: visibilityCoordinator.activeVideoMomentId)
        }
        .onDisappear {
            isVisible = false
            let isCurrent = globalManager.isRegisteredPlayer(videoId, manager: playerManager)
            if isCurrent {
                globalManager.pauseVideo(videoId)
                globalManager.unregisterPlayer(videoId, manager: playerManager)
            }
            let preservePool = globalManager.shouldPreserveSharedPlayer(consumerId: videoId)
            playerManager.cleanup(releaseFromPool: !preservePool)
            hasSetupPlayer = false
            hasLoadError = false
            setupRetries = 0
            setupGeneration += 1
        }
        .onChange(of: visibilityCoordinator.activeVideoMomentId) { _, activeId in
            applyActivationMode(activeId: activeId)
        }
        .onTapGesture {
            if allowsPauseInteraction {
                handleTap()
            }
        }
        // ✅ NUEVO: Listener para cuando la app va a background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            globalManager.pauseAllVideos()
        }
        .onChange(of: playerManager.currentTime) { _, newTime in
            guard usesSocialChrome, moment != nil else { return }
            globalManager.setPlaybackPosition(
                seconds: newTime,
                forMomentId: videoId
            )
        }
    }
    
    // MARK: - Modern Loading View (igual que antes)
    private var modernLoadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .aspectRatio(min(aspectRatio, 0.8), contentMode: .fit)
            
            if hasLoadError {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(NSLocalizedString("feed.video.loadError", comment: "Video load error"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Button(NSLocalizedString("feed.video.retry", comment: "Retry video load")) {
                        forceReloadPlayer()
                    }
                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
            } else {
                // ✅ HALO ANIMATION: También en la carga inicial
                HaloLoadingView(cornerRadius: 0)
                
                VStack(spacing: 12) {
                    Text(NSLocalizedString("feed.video.loading", comment: "Video loading state"))
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Controls Overlay (igual que antes)
    private var controlsOverlay: some View {
        ZStack {
            if showControls {
                Color.black.opacity(0.3)
                    .transition(.opacity)
                
                Button(action: {
                    togglePlayback()
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .momentsChromeGlass(in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .transition(MotionPolicy.Transition.enterPop)
            }
            
            if isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
//                    Text("Buffering...")
//                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
//                        .foregroundStyle(.white.opacity(0.8))
                }
                .transition(.opacity)
            }
            // ✅ HALO ANIMATION: Mostrar el borde giratorio cuando está haciendo buffering
            // Solo mostrar si NO estamos mostrando los controles (para no saturar)
            if isBuffering && !showControls {
                HaloLoadingView(cornerRadius: 0)
                    .transition(.opacity)
            }
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: showControls), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: isBuffering)
    }
    
    // MARK: - Mute Button (igual que antes)
    private var muteButton: some View {
        Button(action: {
            globalManager.toggleMute(videoId)
        }) {
            Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .momentsChromeGlass(in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .opacity(showMuteButton ? 1.0 : 0.0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: showMuteButton), value: showMuteButton)
    }
    
    // MARK: - Functions
    private func setupPlayer() {
        let signpostID = PerformanceSignposts.makeID()
        PerformanceSignposts.begin("VideoPlayerSetup", id: signpostID)
        defer { PerformanceSignposts.end("VideoPlayerSetup", id: signpostID) }

        guard let videoURL = resolvedPlaybackURL() else {
            hasLoadError = true
            return
        }
        
        hasLoadError = false
        setupGeneration += 1

        let playbackSource = resolvedPlaybackSource()
        let handoff = consumesDetailHandoff
            ? moment.flatMap {
                globalManager.consumeProfileDetailHandoff(
                    forMomentId: GlobalVideoManager.profileVideoConsumerId(for: $0)
                )
            }
            : nil
        let reuseExistingItem = handoff?.reuseExistingItem
            ?? globalManager.canReuseSharedPlayer(consumerId: videoId)
        let startAtSeconds: Double? = {
            if let handoff, handoff.startAtSeconds > 0.05 {
                return handoff.startAtSeconds
            }
            return nil
        }()

        playerManager.setupPlayer(
            with: videoURL,
            consumerId: videoId,
            startAtSeconds: startAtSeconds,
            reuseExistingItem: reuseExistingItem,
            mediaItem: mediaItem,
            moment: moment,
            initialTier: playbackSource?.tier
        )
        hasSetupPlayer = true
        scheduleSetupTimeout(for: setupGeneration)

        if activationMode == .alwaysWhenVisible {
            globalManager.playVideo(videoId)
        }
    }

    private func resolvedPlaybackURL() -> URL? {
        resolvedPlaybackSource()?.playbackURL
    }

    private func resolvedPlaybackSource() -> VideoPlaybackSource? {
        if let mediaItem,
           let source = VideoPlaybackSelector.shared.source(for: mediaItem, moment: moment) {
            return source
        }
        if let moment, let source = VideoPlaybackSelector.shared.source(for: moment) {
            return source
        }
        guard let url = normalizedVideoURL(from: url) else { return nil }
        return VideoPlaybackSource(
            playbackURL: url,
            tier: VideoPlaybackSelector.shared.recommendedTier(),
            preheatURLStrings: [url.absoluteString]
        )
    }
    
    private func normalizedVideoURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed) {
            return url
        }
        let encoded = trimmed.replacingOccurrences(of: " ", with: "%20")
        return URL(string: encoded)
    }
    
    private func scheduleSetupTimeout(for generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + setupTimeoutSeconds) {
            guard isVisible else { return }
            guard generation == setupGeneration else { return }
            guard playerManager.player != nil else { return }
            
            let status = playerManager.player?.currentItem?.status ?? .unknown
            let hasStartedPlayback = playerManager.currentTime > 0.05
            if status == .readyToPlay || hasStartedPlayback {
                return
            }
            
            if setupRetries < maxSetupRetries {
                setupRetries += 1
                hasSetupPlayer = false
                playerManager.cleanup()
                setupPlayer()
            } else {
                hasLoadError = true
            }
        }
    }
    
    private func forceReloadPlayer() {
        hasLoadError = false
        setupRetries = 0
        hasSetupPlayer = false
        playerManager.cleanup()
        setupPlayer()
        if isVisible {
            applyActivationMode(activeId: visibilityCoordinator.activeVideoMomentId)
        }
    }

    private func applyActivationMode(activeId: String?) {
        switch activationMode {
        case .feedVisibility:
            updatePlaybackForVisibility(activeId: activeId)
        case .alwaysWhenVisible:
            guard isVisible else { return }
            globalManager.playVideo(videoId)
        }
    }
    
    // ✅ NUEVO: Toggle playback que usa el manager global
    private func togglePlayback() {
        if playerManager.isPlaying {
            // Pausar este video
            globalManager.pauseVideo(videoId)
        } else {
            // Reproducir este video (pausará otros automáticamente)
            globalManager.playVideo(videoId)
        }
    }
    
    private func updatePlaybackForVisibility(activeId: String?) {
        guard isVisible else { return }
        if GlobalVideoManager.visibilityMatches(activeMomentId: activeId, videoConsumerId: videoId) {
            globalManager.playVideo(videoId)
        } else {
            globalManager.pauseVideo(videoId)
        }
    }
    
    private func handleTap() {
        if usesSocialChrome {
            withAnimation(.easeInOut(duration: 0.2)) {
                togglePlayback()
            }
            return
        }

        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
            showControls.toggle()
        }

        if showControls {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                    showControls = false
                }
            }
        }

        showMuteButton = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                showMuteButton = false
            }
        }
    }
}

// ✅ MODIFICADO: VideoPlayerManager con control externo
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = true
    @Published var isReadyToPlay = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0

    private var timeObserver: Any?
    private var lastPublishedTime: Double = -1
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var consumerId: String?
    private var activeItem: AVPlayerItem?
    private var pendingSeekSeconds: Double?
    private var adaptiveController: VideoAdaptiveTierController?
    private var bufferEmptyObserver: NSKeyValueObservation?
    private var playbackLikelyObserver: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?

    func setupPlayer(
        with url: URL,
        consumerId: String,
        startAtSeconds: Double? = nil,
        reuseExistingItem: Bool = false,
        mediaItem: MediaItem? = nil,
        moment: Moment? = nil,
        initialTier: VideoPlaybackTier? = nil
    ) {
        self.consumerId = consumerId
        pendingSeekSeconds = startAtSeconds

        if let mediaItem, mediaItem.type == .video {
            let tier = initialTier
                ?? VideoPlaybackSelector.shared.source(for: mediaItem, moment: moment)?.tier
            adaptiveController = VideoAdaptiveTierController(
                mediaItem: mediaItem,
                moment: moment,
                initialTier: tier
            )
        } else {
            adaptiveController = nil
        }

        // Si el pool desaloja nuestro slot (reasigna el AVPlayer a otro contenido),
        // soltamos nuestras referencias/observers para no reproducir contenido cruzado.
        SharedVideoPlayerPool.shared.setEvictionHandler(for: consumerId) { [weak self] in
            DispatchQueue.main.async { self?.handlePoolEviction() }
        }

        let pooledPlayer = SharedVideoPlayerPool.shared.player(for: consumerId)

        if reuseExistingItem,
           let existingItem = pooledPlayer.currentItem,
           existingItem.status != .failed {
            player = pooledPlayer
            activeItem = existingItem
            isReadyToPlay = existingItem.status == .readyToPlay
            isPlaying = pooledPlayer.rate > 0
            applySessionMuteState(on: pooledPlayer)
            observeItemStatus(existingItem)
            setupAdaptiveObservers(for: existingItem)
            observePlayback()
            setupLooping(for: existingItem)
            applyPendingSeekIfPossible(on: pooledPlayer, item: existingItem)
            return
        }

        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        let tier = adaptiveController?.currentTier ?? VideoPlaybackSelector.shared.recommendedTier()
        VideoPlaybackSelector.shared.configure(playerItem: playerItem, tier: tier)

        pooledPlayer.replaceCurrentItem(with: playerItem)
        applySessionMuteState(on: pooledPlayer)
        pooledPlayer.automaticallyWaitsToMinimizeStalling = false

        player = pooledPlayer
        activeItem = playerItem
        isReadyToPlay = playerItem.status == .readyToPlay
        isPlaying = false

        observeItemStatus(playerItem)
        setupAdaptiveObservers(for: playerItem)
        observePlayback()
        setupLooping(for: playerItem)
        applyPendingSeekIfPossible(on: pooledPlayer, item: playerItem)
    }

    private func applySessionMuteState(on player: AVPlayer) {
        let shouldMute = !GlobalVideoManager.shared.userHasEnabledSoundInSession
        player.isMuted = shouldMute
        isMuted = shouldMute
    }

    private func applyPendingSeekIfPossible(on player: AVPlayer, item: AVPlayerItem) {
        guard let seconds = pendingSeekSeconds, seconds > 0.05 else { return }
        guard item.status == .readyToPlay else { return }
        pendingSeekSeconds = nil
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Llamado por el pool cuando nuestro slot fue reasignado a otro consumer.
    /// Limpia observers y suelta el player SIN devolverlo al pool (ya no es nuestro).
    private func handlePoolEviction() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        teardownAdaptiveObservers()
        adaptiveController = nil
        player = nil
        activeItem = nil
        isPlaying = false
        isReadyToPlay = false
        lastPublishedTime = -1
    }

    private func observeItemStatus(_ playerItem: AVPlayerItem) {
        statusObserver?.invalidate()
        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReadyToPlay = item.status == .readyToPlay
                if item.status == .readyToPlay, let player = self.player {
                    self.applyPendingSeekIfPossible(on: player, item: item)
                }
            }
        }
    }

    private func setupAdaptiveObservers(for playerItem: AVPlayerItem) {
        teardownAdaptiveObservers()

        bufferEmptyObserver = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard item.isPlaybackBufferEmpty else { return }
                self?.recoverFromPlaybackStall()
            }
        }

        playbackLikelyObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    self?.adaptiveController?.notePlaybackHealthy()
                }
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.recoverFromPlaybackStall()
        }
    }

    private func teardownAdaptiveObservers() {
        bufferEmptyObserver?.invalidate()
        bufferEmptyObserver = nil
        playbackLikelyObserver?.invalidate()
        playbackLikelyObserver = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
    }

    private func recoverFromPlaybackStall() {
        guard let player else { return }
        VideoPlaybackRecovery.recoverFromStall(
            player: player,
            isPlaying: isPlaying,
            adaptive: adaptiveController
        ) { [weak self] newItem in
            guard let self else { return }
            self.activeItem = newItem
            self.observeItemStatus(newItem)
            self.setupAdaptiveObservers(for: newItem)
            self.setupLooping(for: newItem)
        }
    }
    
    // ✅ NUEVO: Función para reproducir controlada externamente
    func resumeVideo() {
        guard let player = player else { return }
        // Solo el vídeo activo bufferiza en red mientras está pausado momentáneamente.
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.play()
        isPlaying = true
    }
    
    // ✅ NUEVO: Función para pausar controlada externamente
    func pauseVideo() {
        guard let player = player else { return }
        player.pause()
        // Evita que un vídeo fuera de pantalla siga consumiendo red/CPU/batería.
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        isPlaying = false
    }
    
    // ✅ MANTENER: Toggle manual (para cuando el usuario toca play/pause)
    func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    // Toggle mute respetando el modo silencioso del iPhone
    func toggleMute(respectSilentMode: Bool = false) {
        guard let player = player else { return }
        
        if respectSilentMode {
            // ✅ Verificar si el iPhone está en modo silencioso
            let volume = AVAudioSession.sharedInstance().outputVolume
            if volume == 0.0 {
                // Si está en silencio, no hacer nada (el usuario debe activar el volumen primero)
                return
            }
        }
        
        player.isMuted.toggle()
        isMuted = player.isMuted
    }
    
    // ✅ NUEVO: Establecer mute directamente (usado por GlobalVideoManager)
    func setMuted(_ muted: Bool, respectSilentMode: Bool = false) {
        guard let player = player else { return }
        
        if respectSilentMode {
            let volume = AVAudioSession.sharedInstance().outputVolume
            if volume == 0.0 && !muted {
                // Si está en silencio y queremos activar sonido, no hacer nada
                return
            }
        }
        
        player.isMuted = muted
        isMuted = muted
    }
    
    private func setupLooping(for playerItem: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            // ✅ LOOP: Solo si sigue reproduciéndose
            if self?.isPlaying == true {
                self?.player?.seek(to: .zero)
                self?.player?.play()
            }
        }
    }
    
    private func observePlayback() {
        guard let player = player else { return }

        // Evitar acumular observers (p. ej. en el path reuseExistingItem).
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // 0.25s es suficiente para la UI de progreso y reduce el trabajo en main thread.
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = player.currentItem else { return }
            
            let duration = currentItem.duration
            if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                let durationSeconds = CMTimeGetSeconds(duration)
                let currentSeconds = CMTimeGetSeconds(time)
                
                if !durationSeconds.isNaN && !currentSeconds.isNaN && durationSeconds > 0 {
                    if abs(self.duration - durationSeconds) > 0.01 {
                        self.duration = durationSeconds
                    }
                    if abs(self.lastPublishedTime - currentSeconds) >= 0.08 {
                        self.lastPublishedTime = currentSeconds
                        self.currentTime = currentSeconds
                    }
                }
            }
        }
    }
    
    func cleanup(releaseFromPool: Bool = true) {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil
        teardownAdaptiveObservers()
        adaptiveController = nil
        
        let isCurrent = consumerId.map { GlobalVideoManager.shared.isRegisteredPlayer($0, manager: self) } ?? true
        
        if isCurrent {
            player?.pause()
        }
        if let consumerId, releaseFromPool && isCurrent {
            SharedVideoPlayerPool.shared.release(consumerId: consumerId)
        }
        player = nil
        activeItem = nil
        self.consumerId = nil
        
        NotificationCenter.default.removeObserver(self)
        
        isPlaying = false
        isReadyToPlay = false
        lastPublishedTime = -1
    }
    
    deinit {
        cleanup()
    }
}

// ✅ MANTENER: VideoPlayerRepresentable (sin cambios)
struct VideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    @Binding var showControls: Bool
    @Binding var progress: Double
    @Binding var isBuffering: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = videoGravity
        view.layer.addSublayer(playerLayer)
        
        context.coordinator.playerLayer = playerLayer
        context.coordinator.setupObservers(player: player, progress: $progress, isBuffering: $isBuffering)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
            playerLayer.videoGravity = videoGravity
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var playerLayer: AVPlayerLayer?
        private var timeObserver: Any?
        // Referencia fuerte al player observado para poder remover el observer con seguridad en deinit.
        private var observedPlayer: AVPlayer?
        
        func setupObservers(player: AVPlayer, progress: Binding<Double>, isBuffering: Binding<Bool>) {
            if let timeObserver = timeObserver {
                observedPlayer?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            observedPlayer = player
            let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                guard let currentItem = player.currentItem else { return }
                let duration = currentItem.duration
                
                if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                    let durationSeconds = CMTimeGetSeconds(duration)
                    let currentSeconds = CMTimeGetSeconds(time)
                    
                    if !durationSeconds.isNaN && !currentSeconds.isNaN && durationSeconds > 0 {
                        DispatchQueue.main.async {
                            progress.wrappedValue = currentSeconds / durationSeconds
                        }
                    }
                }
                
                let isPlaybackBufferEmpty = currentItem.isPlaybackBufferEmpty
                let isPlaybackLikelyToKeepUp = currentItem.isPlaybackLikelyToKeepUp
                
                DispatchQueue.main.async {
                    isBuffering.wrappedValue = isPlaybackBufferEmpty && !isPlaybackLikelyToKeepUp
                }
            }
        }
        
        deinit {
            if let timeObserver = timeObserver {
                observedPlayer?.removeTimeObserver(timeObserver)
            }
        }
    }
}
// ✅ NUEVO: Halo Loading Animation (Borde giratorio)
struct HaloLoadingView: View {
    let cornerRadius: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Capa de gradiente que gira (FONDO)
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0),
                        Color.purple.opacity(0.4),
                        Color.pink,
                        Color.orange,
                        Color.pink,
                        Color.purple.opacity(0.4),
                        Color.purple.opacity(0)
                    ]),
                    center: .center
                )
                .scaleEffect(1.5) // Asegurar cobertura al girar
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0)) // Gira el COLOR, no la forma
                .mask(
                    // MASCARA: El borde estático
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(lineWidth: 4)
                )
                .animation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
                
                // 2. Brillo sutil interno (ESTÁTICO)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.pink.opacity(0.3), lineWidth: 1)
                    .blur(radius: 4)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
