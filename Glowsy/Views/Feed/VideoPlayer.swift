// ModernVideoPlayer.swift - CON COMPORTAMIENTO INSTAGRAM
import SwiftUI
import AVFoundation

// ✅ NUEVO: Video Manager global para controlar todos los videos
class GlobalVideoManager: ObservableObject {
    static let shared = GlobalVideoManager()
    
    @Published private(set) var activeVideoId: String?
    private var allPlayers: [String: VideoPlayerManager] = [:]
    
    private init() {}
    
    func registerPlayer(_ playerId: String, manager: VideoPlayerManager) {
        allPlayers[playerId] = manager
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
}

// ✅ MODIFICADO: ModernVideoPlayer con control global
struct ModernVideoPlayer: View {
    let url: String
    let aspectRatio: CGFloat
    let videoId: String // ✅ NUEVO: ID único para este video
    
    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var globalManager = GlobalVideoManager.shared
    @State private var showControls = false
    @State private var showMuteButton = true
    @State private var progress: Double = 0
    @State private var isBuffering = false
    @State private var hasSetupPlayer = false
    @State private var isVisible = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = playerManager.player {
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
                
                // Mute/unmute button
                VStack {
                    Spacer()
                    HStack {
                        muteButton
                        Spacer()
                    }
                }
                .padding(12)
                
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
            
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
                    .scaleEffect(1.2)
                
                Text("Cargando video...")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white.opacity(0.8))
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
                    togglePlayback() // ✅ MODIFICADO: Usar nueva función
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 80, height: 80)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            if isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Buffering...")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
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
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
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
        guard !hasSetupPlayer else { return }
        guard let videoURL = URL(string: url) else { return }
        
        playerManager.setupPlayer(with: videoURL)
        hasSetupPlayer = true
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
        // Solo auto-reproducir si es visible y no hay otro video reproduciéndose
        if isVisible && globalManager.activeVideoId == nil {
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
    private var hasSetupPlayer = false
    
    func setupPlayer(with url: URL) {
        guard !hasSetupPlayer else { return }
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // ✅ CONFIGURACIÓN OPTIMIZADA
        player?.isMuted = true
        player?.automaticallyWaitsToMinimizeStalling = true
        
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
    
    func toggleMute() {
        guard let player = player else { return }
        player.isMuted.toggle()
        isMuted = player.isMuted
    }
    
    private func setupLooping(for playerItem: AVPlayerItem) {
        NotificationCenter.default.addObserver(
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
