// ModernVideoPlayer.swift - CON COMPORTAMIENTO INSTAGRAM
import SwiftUI
import AVFoundation

// ✅ NUEVO: Video Manager global para controlar todos los videos
class GlobalVideoManager: ObservableObject {
    static let shared = GlobalVideoManager()
    
    @Published private(set) var activeVideoId: String?
    private var allPlayers: [String: VideoPlayerManager] = [:]
    
    // ✅ ESTILO INSTAGRAM: Si el usuario activa el sonido en algún video, todos los posteriores tienen sonido
    @Published private(set) var userHasEnabledSoundInSession: Bool = false
    
    private init() {
        // ✅ Escuchar cuando la app entra en background para resetear la sesión
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterBackground() {
        // ✅ Resetear la sesión de sonido cuando la app entra en background
        userHasEnabledSoundInSession = false
    }
    
    func registerPlayer(_ playerId: String, manager: VideoPlayerManager) {
        allPlayers[playerId] = manager
        
        // ✅ ESTILO INSTAGRAM: Si el usuario ya activó el sonido en esta sesión, aplicar a este video también
        if userHasEnabledSoundInSession {
            manager.setMuted(false, respectSilentMode: true)
        }
    }
    
    func unregisterPlayer(_ playerId: String) {
        allPlayers.removeValue(forKey: playerId)
        
        if activeVideoId == playerId {
            activeVideoId = nil
        }
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
        for (id, manager) in allPlayers {
            manager.pauseVideo()
        }
    }
    
    // ✅ ESTILO INSTAGRAM: Toggle mute que activa el sonido para toda la sesión
    func toggleMute(_ playerId: String) {
        guard let manager = allPlayers[playerId] else { return }
        
        let wasMuted = manager.isMuted
        manager.toggleMute(respectSilentMode: true)
        
        // ✅ Si el usuario desmutea (activa el sonido), activar sonido para toda la sesión
        if wasMuted && !manager.isMuted {
            userHasEnabledSoundInSession = true
            
            // ✅ Aplicar sonido a todos los videos activos
            for (id, playerManager) in allPlayers {
                if id != playerId {
                    playerManager.setMuted(false, respectSilentMode: true)
                }
            }
        }
    }
    
    // ✅ NUEVO: Obtener estado de mute de un video
    func isMuted(_ playerId: String) -> Bool {
        return allPlayers[playerId]?.isMuted ?? true
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
    let hideMuteButton: Bool // ✅ NUEVO: Para ocultar el botón de mute (usado en reels)
    
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
    
    private let maxSetupRetries = 2
    private let setupTimeoutSeconds: Double = 4.0
    
    init(url: String, aspectRatio: CGFloat, videoId: String, hideMuteButton: Bool = false) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.videoId = videoId
        self.hideMuteButton = hideMuteButton
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = playerManager.player, !hasLoadError {
                    VideoPlayerRepresentable(
                        player: player,
                        showControls: $showControls,
                        progress: $progress,
                        isBuffering: $isBuffering
                    )
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipped()
                } else {
                    modernLoadingView
                }
                
                // Controls overlay
                controlsOverlay
                
                // Mute/unmute button (solo si no está oculto)
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
                
                // Progress bar
                VStack {
                    Spacer()
                    if playerManager.duration > 0 {
                        progressBar
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
            globalManager.registerPlayer(videoId, manager: playerManager)
            
            // ✅ NUEVO: Detectar visibilidad
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
                checkAutoPlay()
            }
        }
        .onDisappear {
            isVisible = false
            globalManager.unregisterPlayer(videoId)
            playerManager.cleanup()
            // Importante: permitir re-setup al reaparecer la celda en feed.
            hasSetupPlayer = false
            hasLoadError = false
            setupRetries = 0
            setupGeneration += 1
        }
        .onTapGesture {
            handleTap()
        }
        // ✅ NUEVO: Listener para cuando la app va a background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            globalManager.pauseAllVideos()
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
                        .foregroundColor(.white.opacity(0.9))
                    Text(NSLocalizedString("feed.video.loadError", comment: "Video load error"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Button(NSLocalizedString("feed.video.retry", comment: "Retry video load")) {
                        forceReloadPlayer()
                    }
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.white)
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
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.white.opacity(0.8))
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
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .liquidGlass(in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            if isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
//                    Text("Buffering...")
//                        .font(.custom("Poppins-Medium", size: 12))
//                        .foregroundColor(.white.opacity(0.8))
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
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: isBuffering)
    }
    
    // MARK: - Mute Button (igual que antes)
    private var muteButton: some View {
        Button(action: {
            playerManager.toggleMute()
        }) {
            Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .liquidGlass(in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .opacity(showMuteButton ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: showMuteButton)
    }
    
    // MARK: - Progress Bar (igual que antes)
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 2)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress, height: 2)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 0)
        .padding(.bottom, 0)
    }
    
    // MARK: - Functions
    private func setupPlayer() {
        if hasSetupPlayer && playerManager.player != nil {
            return
        }
        guard let videoURL = normalizedVideoURL(from: url) else {
            hasLoadError = true
            return
        }
        
        hasLoadError = false
        setupGeneration += 1
        playerManager.setupPlayer(with: videoURL)
        hasSetupPlayer = true
        scheduleSetupTimeout(for: setupGeneration)
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
            checkAutoPlay()
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
    
    // ✅ NUEVO: Auto-play inteligente
    private func checkAutoPlay() {
        // ✅ Auto-play al hacerse visible: este vídeo pasa a ser el activo
        // GlobalVideoManager se encarga de pausar los demás
        if isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.isVisible {
                    self.globalManager.playVideo(self.videoId)
                }
            }
        }
    }
    
    private func handleTap() {
        // ✅ MODIFICADO: Siempre mostrar controles al tocar
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        
        if showControls {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
        
        showMuteButton = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut(duration: 0.3)) {
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
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var hasSetupPlayer = false
    
    func setupPlayer(with url: URL) {
        guard !hasSetupPlayer else { return }
        
        // ✅ INSTANT PLAYBACK: Usar item precargado si existe
        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        
        // ✅ OPTIMIZED BUFFER: Buffer inicial 2-3s (equilibrado)
        // Empiezan a reproducir con solo 2-3s cargados, luego siguen cargando en background
        playerItem.preferredForwardBufferDuration = 2.5 // Buffer inicial (2.5s) - balance perfecto
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true // Seguir cargando mientras está pausado
        
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        player?.automaticallyWaitsToMinimizeStalling = false // ✅ Inicio instantáneo (aunque arriesgue stall)
        // ✅ Priorizar velocidad sobre calidad para inicio más rápido
        if #available(iOS 14.0, *) {
            playerItem.preferredPeakBitRate = 0 // Sin límite de bitrate, usar toda la velocidad disponible
        }
        
        // ✅ NO AUTO-PLAY - El GlobalVideoManager decidirá cuándo reproducir
        isPlaying = false
        
        observePlayback()
        setupLooping(for: playerItem)
        hasSetupPlayer = true
        
    }
    
    // ✅ NUEVO: Función para reproducir controlada externamente
    func resumeVideo() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
    }
    
    // ✅ NUEVO: Función para pausar controlada externamente
    func pauseVideo() {
        guard let player = player else { return }
        player.pause()
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
    
    // ✅ ESTILO INSTAGRAM: Toggle mute respetando el modo silencioso del iPhone
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
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = player.currentItem else { return }
            
            let duration = currentItem.duration
            if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                let durationSeconds = CMTimeGetSeconds(duration)
                let currentSeconds = CMTimeGetSeconds(time)
                
                if !durationSeconds.isNaN && !currentSeconds.isNaN && durationSeconds > 0 {
                    self.duration = durationSeconds
                    self.currentTime = currentSeconds
                }
            }
        }
    }
    
    func cleanup() {
        
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        NotificationCenter.default.removeObserver(self)
        
        isPlaying = false
        hasSetupPlayer = false
    }
    
    deinit {
        cleanup()
    }
}

// ✅ MANTENER: VideoPlayerRepresentable (sin cambios)
struct VideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    @Binding var showControls: Bool
    @Binding var progress: Double
    @Binding var isBuffering: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        
        context.coordinator.playerLayer = playerLayer
        context.coordinator.setupObservers(player: player, progress: $progress, isBuffering: $isBuffering)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var playerLayer: AVPlayerLayer?
        private var timeObserver: Any?
        
        func setupObservers(player: AVPlayer, progress: Binding<Double>, isBuffering: Binding<Bool>) {
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
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
                playerLayer?.player?.removeTimeObserver(timeObserver)
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
