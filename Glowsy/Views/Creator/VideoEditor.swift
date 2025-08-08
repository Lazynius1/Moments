import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct SocialVideoEditorView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 60
    @State private var isPlaying: Bool = false
    
    // Controles principales
    @State private var trimStartTime: Double = 0
    @State private var trimEndTime: Double = 0
    @State private var selectedClipIndex = 0
    @State private var playbackSpeed: PlaybackSpeed = .normal
    @State private var selectedFormat: VideoFormat = .reels
    @State private var volume: Float = 1.0
    
    // Estados de UI
    @State private var showingSpeedPicker = false
    @State private var showingFormatPicker = false
    @State private var isDraggingTrimHandle = false
    @State private var trimHandleType: TrimHandleType = .start
    @State private var showingVolumeSlider = false
    
    // Estados para compresión y procesamiento
    @State private var isProcessing = false
    @State private var processingMessage = "Procesando..."
    @State private var processingProgress: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""
    
    enum PlaybackSpeed: String, CaseIterable {
        case slow = "0.3x"
        case normal = "1x"
        case fast = "2x"
        case veryFast = "3x"
        
        var multiplier: Float {
            switch self {
            case .slow: return 0.3
            case .normal: return 1.0
            case .fast: return 2.0
            case .veryFast: return 3.0
            }
        }
        
        var icon: String {
            switch self {
            case .slow: return "tortoise"
            case .normal: return "play"
            case .fast: return "hare"
            case .veryFast: return "hare.fill"
            }
        }
    }
    
    enum VideoFormat: String, CaseIterable {
        case reels = "9:16"
        case square = "1:1"
        case landscape = "16:9"
        
        var ratio: CGFloat {
            switch self {
            case .reels: return 9.0/16.0
            case .square: return 1.0
            case .landscape: return 16.0/9.0
            }
        }
        
        // Resoluciones objetivo para compresión
        var targetSize: CGSize {
            switch self {
            case .reels: return CGSize(width: 1080, height: 1920)
            case .square: return CGSize(width: 1080, height: 1080)
            case .landscape: return CGSize(width: 1920, height: 1080)
            }
        }
        
        // Bitrate objetivo (Mbps)
        var targetBitrate: Int {
            switch self {
            case .reels: return 6000000 // 6 Mbps
            case .square: return 5000000 // 5 Mbps
            case .landscape: return 8000000 // 8 Mbps
            }
        }
        
        var toProcessedMediaAspectRatio: ProcessedMedia.AspectRatio {
            switch self {
            case .reels: return .nineBySixteen
            case .square: return .square
            case .landscape: return .landscape
            }
        }
        
        var displayName: String {
            switch self {
            case .reels: return "Reels"
            case .square: return "Cuadrado"
            case .landscape: return "Horizontal"
            }
        }
        
        var icon: String {
            switch self {
            case .reels: return "rectangle.portrait.fill"
            case .square: return "square.fill"
            case .landscape: return "rectangle.fill"
            }
        }
    }
    
    enum TrimHandleType {
        case start, end
    }
    
    // Struct para datos de video procesado
    struct ProcessedVideoData {
        let compressedVideoURL: URL
        let thumbnailURL: URL
        let duration: Double
        let fileSize: Int64
        let resolution: CGSize
        let thumbnailImage: UIImage // Añadir thumbnail como imagen
    }
    
    var currentVideo: ProcessedMedia? {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        return videoItems.indices.contains(selectedClipIndex) ? videoItems[selectedClipIndex] : nil
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header estilo redes sociales
                headerView
                
                // Preview del video
                videoPreviewSection
                
                // Timeline de recorte
                if let _ = currentVideo {
                    trimTimelineSection
                }
                
                // Controles inferiores
                controlsSection
                
                Spacer()
            }
            
            // Overlay de procesamiento
            if isProcessing {
                processingOverlay
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupVideoPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .sheet(isPresented: $showingSpeedPicker) {
            speedPickerSheet
        }
        .sheet(isPresented: $showingFormatPicker) {
            formatPickerSheet
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Processing Overlay
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Indicador de progreso circular
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: processingProgress)
                        .stroke(Color.blue, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: processingProgress)
                    
                    Text("\(Int(processingProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 8) {
                    Text(processingMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Optimizando para máxima calidad")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: goBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                    Text("Atrás")
                        .font(.body)
                }
                .foregroundColor(.white)
            }
            .disabled(isProcessing)
            
            Spacer()
            
            Text("Editar")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: processAndContinue) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text(isProcessing ? "Procesando..." : "Siguiente")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isProcessing ? .white.opacity(0.7) : .blue)
            }
            .disabled(isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
    
    // MARK: - Video Preview
    private var videoPreviewSection: some View {
        ZStack {
            if let video = currentVideo, let videoURL = video.videoURL {
                // Contenedor del video con aspecto correcto
                GeometryReader { geometry in
                    let videoSize = calculateVideoSize(for: geometry.size)
                    
                    ZStack {
                        // Fondo negro
                        Rectangle()
                            .fill(Color.black)
                        
                        // Player del video
                        VideoPlayerWrapper(player: player)
                            .frame(width: videoSize.width, height: videoSize.height)
                            .clipped()
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
                .aspectRatio(selectedFormat.ratio, contentMode: .fit)
                .frame(maxHeight: 500)
                .background(Color.black)
                
                // Overlay de controles de reproducción
                videoOverlayControls
            }
        }
        .onTapGesture {
            if !isProcessing {
                togglePlayback()
            }
        }
    }
    
    private var videoOverlayControls: some View {
        ZStack {
            // Indicador de velocidad
            if playbackSpeed != .normal {
                VStack {
                    HStack {
                        VStack {
                            Image(systemName: playbackSpeed.icon)
                                .font(.title2)
                            Text(playbackSpeed.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
            
            // Botón de play/pausa (solo cuando está pausado)
            if !isPlaying && !isProcessing {
                Button(action: togglePlayback) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Indicador de volumen
            if volume == 0 {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "speaker.slash.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }
    
    // MARK: - Timeline de Recorte
    private var trimTimelineSection: some View {
        VStack(spacing: 16) {
            // Tiempo actual / duración
            HStack {
                Text(formatTime(max(trimStartTime, currentTime)))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(formatTime(trimEndTime - trimStartTime)) de \(formatTime(duration))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text(formatTime(trimEndTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            
            // Timeline con frames del video
            timelineView
        }
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.1))
        .opacity(isProcessing ? 0.5 : 1.0)
    }
    
    private var timelineView: some View {
        GeometryReader { geometry in
            let frameWidth: CGFloat = 50
            let totalFrames = Int(geometry.size.width / frameWidth)
            
            ZStack {
                // Fondo del timeline
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 60)
                
                // Frames del video (simulados con rectángulos)
                HStack(spacing: 2) {
                    ForEach(0..<totalFrames, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: frameWidth - 2, height: 56)
                            .overlay(
                                // Simular thumbnail del video
                                Rectangle()
                                    .fill(LinearGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                    }
                }
                
                // Overlay de selección
                let startX = CGFloat(trimStartTime / duration) * geometry.size.width
                let endX = CGFloat(trimEndTime / duration) * geometry.size.width
                let selectedWidth = endX - startX
                
                // Área oscurecida (antes del inicio)
                if startX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: startX, height: 60)
                        .position(x: startX / 2, y: 30)
                }
                
                // Área oscurecida (después del final)
                if endX < geometry.size.width {
                    let remainingWidth = geometry.size.width - endX
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: remainingWidth, height: 60)
                        .position(x: endX + remainingWidth / 2, y: 30)
                }
                
                // Bordes de selección
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: selectedWidth, height: 60)
                    .position(x: startX + selectedWidth / 2, y: 30)
                
                // Handle izquierdo
                trimHandle(isStart: true)
                    .position(x: startX, y: 30)
                
                // Handle derecho
                trimHandle(isStart: false)
                    .position(x: endX, y: 30)
                
                // Indicador de tiempo actual
                let playheadX = CGFloat(currentTime / duration) * geometry.size.width
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 80)
                    .position(x: playheadX, y: 30)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
        .clipped()
        .allowsHitTesting(!isProcessing)
    }
    
    private func trimHandle(isStart: Bool) -> some View {
        Rectangle()
            .fill(Color.yellow)
            .frame(width: 20, height: 60)
            .overlay(
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: 20)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isProcessing {
                            handleTrimDrag(value: value, isStart: isStart)
                        }
                    }
                    .onEnded { _ in
                        isDraggingTrimHandle = false
                    }
            )
    }
    
    // MARK: - Controles Inferiores
    private var controlsSection: some View {
        VStack(spacing: 20) {
            // Clip selector (si hay múltiples videos)
            let videoItems = selectedMediaItems.filter { $0.type == .video }
            if videoItems.count > 1 {
                clipSelectorView
            }
            
            // Botones principales
            HStack(spacing: 30) {
                // Velocidad
                controlButton(
                    icon: playbackSpeed.icon,
                    title: "Velocidad",
                    subtitle: playbackSpeed.rawValue,
                    action: {
                        if !isProcessing {
                            showingSpeedPicker = true
                        }
                    }
                )
                
                // Formato
                controlButton(
                    icon: selectedFormat.icon,
                    title: "Formato",
                    subtitle: selectedFormat.displayName,
                    action: {
                        if !isProcessing {
                            showingFormatPicker = true
                        }
                    }
                )
                
                // Volumen
                controlButton(
                    icon: volume > 0 ? "speaker.2" : "speaker.slash",
                    title: "Audio",
                    subtitle: volume > 0 ? "Activado" : "Silenciado",
                    action: {
                        if !isProcessing {
                            toggleVolume()
                        }
                    }
                )
            }
            .padding(.horizontal)
            .opacity(isProcessing ? 0.5 : 1.0)
        }
        .padding(.vertical, 20)
    }
    
    private var clipSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                let videoItems = selectedMediaItems.filter { $0.type == .video }
                ForEach(0..<videoItems.count, id: \.self) { index in
                    Button(action: {
                        if !isProcessing {
                            switchToClip(index: index)
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 80)
                            
                            VStack(spacing: 4) {
                                Image(systemName: "play.rectangle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            
                            if index == selectedClipIndex {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: 60, height: 80)
                            }
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func controlButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .disabled(isProcessing)
    }
    
    // MARK: - Sheets
    private var speedPickerSheet: some View {
        VStack(spacing: 0) {
            // Header del sheet
            HStack {
                Button("Cancelar") {
                    showingSpeedPicker = false
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                Text("Velocidad")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Listo") {
                    showingSpeedPicker = false
                    applyPlaybackSpeed()
                }
                .foregroundColor(.blue)
                .fontWeight(.semibold)
            }
            .padding()
            
            Divider()
            
            // Opciones de velocidad
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 20) {
                ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                    Button(action: {
                        playbackSpeed = speed
                    }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(playbackSpeed == speed ? Color.blue : Color.gray.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: speed.icon)
                                    .font(.title)
                                    .foregroundColor(playbackSpeed == speed ? .white : .gray)
                            }
                            
                            Text(speed.rawValue)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(playbackSpeed == speed ? .blue : .primary)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
        }
        .presentationDetents([.height(400)])
    }
    
    private var formatPickerSheet: some View {
        VStack(spacing: 0) {
            // Header del sheet
            HStack {
                Button("Cancelar") {
                    showingFormatPicker = false
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                Text("Formato")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Listo") {
                    showingFormatPicker = false
                }
                .foregroundColor(.blue)
                .fontWeight(.semibold)
            }
            .padding()
            
            Divider()
            
            // Opciones de formato con preview de resolución
            VStack(spacing: 20) {
                ForEach(VideoFormat.allCases, id: \.self) { format in
                    Button(action: {
                        selectedFormat = format
                    }) {
                        HStack {
                            Image(systemName: format.icon)
                                .font(.title2)
                                .foregroundColor(selectedFormat == format ? .blue : .gray)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Text(format.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Text("• \(Int(format.targetSize.width))x\(Int(format.targetSize.height))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(selectedFormat == format ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
            
            Spacer()
        }
        .presentationDetents([.height(350)])
    }
    
    // MARK: - Funciones Principales
    
    private func setupVideoPlayer() {
        guard let video = currentVideo, let videoURL = video.videoURL else { return }
        
        player = AVPlayer(url: videoURL)
        
        // Obtener duración del video
        let asset = AVAsset(url: videoURL)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = min(CMTimeGetSeconds(duration), 60) // Max 60 segundos
                    self.trimEndTime = self.duration
                }
            } catch {
                print("Error loading duration: \(error)")
            }
        }
        
        // Observer para tiempo actual
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = CMTimeGetSeconds(time)
            
            // Auto-loop en el rango seleccionado
            if self.currentTime >= self.trimEndTime {
                self.seekTo(time: self.trimStartTime)
            }
        }
        
        // Configurar volumen inicial
        player?.volume = volume
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Si estamos al final, volver al inicio
            if currentTime >= trimEndTime {
                seekTo(time: trimStartTime)
            }
            player.play()
            isPlaying = true
        }
    }
    
    private func seekTo(time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
    
    private func handleTrimDrag(value: DragGesture.Value, isStart: Bool) {
        // Calcular nueva posición basada en el drag
        let screenWidth = UIScreen.main.bounds.width - 40 // Padding
        let newTimePercent = max(0, min(1, value.location.x / screenWidth))
        let newTime = newTimePercent * duration
        
        if isStart {
            trimStartTime = max(0, min(newTime, trimEndTime - 1))
        } else {
            trimEndTime = min(duration, max(newTime, trimStartTime + 1))
        }
        
        // Seek al nuevo tiempo para preview
        seekTo(time: isStart ? trimStartTime : trimEndTime)
        isDraggingTrimHandle = true
    }
    
    private func switchToClip(index: Int) {
        selectedClipIndex = index
        cleanupPlayer()
        setupVideoPlayer()
    }
    
    private func applyPlaybackSpeed() {
        player?.rate = playbackSpeed.multiplier
    }
    
    private func toggleVolume() {
        if volume > 0 {
            volume = 0
            player?.volume = 0
        } else {
            volume = 1.0
            player?.volume = 1.0
        }
    }
    
    private func calculateVideoSize(for containerSize: CGSize) -> CGSize {
        let targetRatio = selectedFormat.ratio
        let containerRatio = containerSize.width / containerSize.height
        
        if containerRatio > targetRatio {
            // Container es más ancho, ajustar por altura
            let height = containerSize.height
            let width = height * targetRatio
            return CGSize(width: width, height: height)
        } else {
            // Container es más alto, ajustar por ancho
            let width = containerSize.width
            let height = width / targetRatio
            return CGSize(width: width, height: height)
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func goBack() {
        currentFlow = .mediaSelection
    }
    
    // MARK: - Procesamiento Principal
    
    private func processAndContinue() {
        isProcessing = true
        processingProgress = 0
        processingMessage = "Iniciando procesamiento..."
        
        processAllVideos { success in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                if success {
                    self.updateSelectedMedia()
                    self.currentFlow = .captionAndDetails
                } else {
                    self.showError("Error procesando videos. Inténtalo de nuevo.")
                }
            }
        }
    }
    
    // MARK: - Procesamiento de Videos
    
    private func processAllVideos(completion: @escaping (Bool) -> Void) {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        
        guard !videoItems.isEmpty else {
            completion(true)
            return
        }
        
        print("🎥 Procesando \(videoItems.count) videos...")
        
        let group = DispatchGroup()
        var allSuccess = true
        var processedCount = 0
        
        for (index, mediaItem) in videoItems.enumerated() {
            guard let videoURL = mediaItem.videoURL else { continue }
            
            group.enter()
            
            DispatchQueue.main.async {
                self.processingMessage = "Procesando video \(index + 1)/\(videoItems.count)"
                self.processingProgress = Double(index) / Double(videoItems.count)
            }
            
            processVideoWithThumbnail(videoURL: videoURL, format: selectedFormat) { result in
                defer { group.leave() }
                
                switch result {
                case .success(let processedData):
                    DispatchQueue.main.async {
                        // Actualizar el media item con los datos procesados
                        if let originalIndex = self.selectedMediaItems.firstIndex(where: { $0.id == mediaItem.id }) {
                            var updatedMedia = self.selectedMediaItems[originalIndex]
                            
                            // Actualizar con datos procesados
                            updatedMedia.videoURL = processedData.compressedVideoURL
                            updatedMedia.image = processedData.thumbnailImage // Guardar thumbnail como image
                            
                            self.selectedMediaItems[originalIndex] = updatedMedia
                        }
                        
                        processedCount += 1
                        self.processingProgress = Double(processedCount) / Double(videoItems.count)
                        print("✅ Video \(processedCount)/\(videoItems.count) procesado")
                    }
                    
                case .failure(let error):
                    print("❌ Error procesando video: \(error)")
                    allSuccess = false
                }
            }
        }
        
        group.notify(queue: .main) {
            self.processingProgress = 1.0
            self.processingMessage = "Finalizando..."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print(allSuccess ? "✅ Todos los videos procesados" : "⚠️ Algunos videos fallaron")
                completion(allSuccess)
            }
        }
    }
    
    // MARK: - Procesamiento Individual de Video
    
    private func processVideoWithThumbnail(videoURL: URL, format: VideoFormat, completion: @escaping (Result<ProcessedVideoData, Error>) -> Void) {
        
        Task {
            do {
                // PASO 1: Analizar video original
                let asset = AVAsset(url: videoURL)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                
                guard let videoTrack = videoTracks.first else {
                    throw ProcessingError.noVideoTrack
                }
                
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let duration = try await asset.load(.duration)
                
                let transformedSize = naturalSize.applying(transform)
                let currentSize = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
                
                print("🔍 Video original: \(Int(currentSize.width))x\(Int(currentSize.height))")
                
                // PASO 2: Calcular resolución objetivo
                let targetSize = calculateOptimalSize(currentSize: currentSize, targetFormat: format)
                let needsCompression = shouldCompress(currentSize: currentSize, targetSize: targetSize)
                
                print("🎯 Resolución objetivo: \(Int(targetSize.width))x\(Int(targetSize.height))")
                print("📦 Necesita compresión: \(needsCompression)")
                
                // PASO 3: Generar thumbnail PRIMERO
                let (thumbnailURL, thumbnailImage) = try await generateThumbnail(from: asset, targetSize: targetSize)
                print("🖼️ Thumbnail generado")
                
                // PASO 4: Comprimir video si es necesario
                let finalVideoURL: URL
                if needsCompression {
                    finalVideoURL = try await compressVideo(
                        inputURL: videoURL,
                        targetSize: targetSize,
                        targetBitrate: format.targetBitrate
                    )
                    print("🗜️ Video comprimido")
                } else {
                    finalVideoURL = videoURL
                    print("✅ Video mantenido original")
                }
                
                // PASO 5: Obtener datos finales
                let finalFileSize = try getFileSize(url: finalVideoURL)
                let finalDuration = CMTimeGetSeconds(duration)
                
                let processedData = ProcessedVideoData(
                    compressedVideoURL: finalVideoURL,
                    thumbnailURL: thumbnailURL,
                    duration: finalDuration,
                    fileSize: finalFileSize,
                    resolution: targetSize,
                    thumbnailImage: thumbnailImage
                )
                
                await MainActor.run {
                    completion(.success(processedData))
                }
                
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Generación de Thumbnail
    
    private func generateThumbnail(from asset: AVAsset, targetSize: CGSize) async throws -> (URL, UIImage) {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Calcular tamaño de thumbnail respetando el formato elegido
        let thumbnailSize = calculateThumbnailSize(for: selectedFormat)
        imageGenerator.maximumSize = thumbnailSize
        
        // Generar thumbnail del segundo 1 o la mitad del video
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: min(1.0, CMTimeGetSeconds(duration) / 2), preferredTimescale: 600)
        
        let cgImage = try await imageGenerator.image(at: time).image
        let uiImage = UIImage(cgImage: cgImage)
        
        // Guardar en directorio temporal
        let tempDir = FileManager.default.temporaryDirectory
        let thumbnailURL = tempDir.appendingPathComponent("thumbnail_\(UUID().uuidString).jpg")
        
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw ProcessingError.thumbnailGenerationFailed
        }
        
        try jpegData.write(to: thumbnailURL)
        
        print("🖼️ Thumbnail generado: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height)) para formato \(selectedFormat.displayName)")
        
        return (thumbnailURL, uiImage)
    }
    
    // MARK: - Cálculo de Tamaño de Thumbnail
    
    private func calculateThumbnailSize(for format: VideoFormat) -> CGSize {
        // Generar thumbnails apropiados según el formato
        switch format {
        case .reels:
            // Para reels 9:16, generar thumbnail que sirva tanto para feed (4:5) como para detalle (9:16)
            return CGSize(width: 720, height: 1280) // 9:16 de alta calidad
        case .square:
            // Para cuadrado, thumbnail cuadrado
            return CGSize(width: 1080, height: 1080) // 1:1
        case .landscape:
            // Para landscape, thumbnail horizontal
            return CGSize(width: 1280, height: 720) // 16:9
        }
    }
    
    // MARK: - Compresión de Video
    
    private func compressVideo(inputURL: URL, targetSize: CGSize, targetBitrate: Int) async throws -> URL {
        let asset = AVAsset(url: inputURL)
        
        // URL de salida
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        
        // Limpiar si existe
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Crear composición para reescalar
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        
        // Configurar tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }
        
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        
        // Configurar audio si existe
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
        
        // CONFIGURAR VIDEO COMPOSITION PARA REESCALAR
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
        
        // Calcular transform correctamente para videos rotados
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Calcular el tamaño visible real después del transform
        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let actualSize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
        
        // ✅ DETECTAR SI NECESITA REESCALADO O SOLO COMPRESIÓN
        let needsRescaling = abs(actualSize.width - targetSize.width) > 10 || abs(actualSize.height - targetSize.height) > 10
        
        if needsRescaling {
            print("🔄 Reescalando video de \(Int(actualSize.width))x\(Int(actualSize.height)) a \(Int(targetSize.width))x\(Int(targetSize.height))")
            
            // Calcular escala para ajustar al target manteniendo aspect ratio
            let scaleX = targetSize.width / actualSize.width
            let scaleY = targetSize.height / actualSize.height
            let scale = min(scaleX, scaleY) // Scale to fit (evita recorte excesivo)
            
            // Calcular posición centrada
            let scaledSize = CGSize(width: actualSize.width * scale, height: actualSize.height * scale)
            let translateX = (targetSize.width - scaledSize.width) / 2
            let translateY = (targetSize.height - scaledSize.height) / 2
            
            // Aplicar transforms en orden correcto
            let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
            let translateTransform = CGAffineTransform(translationX: translateX, y: translateY)
            let finalTransform = preferredTransform.concatenating(scaleTransform).concatenating(translateTransform)
            
            transformer.setTransform(finalTransform, at: .zero)
        } else {
            print("✅ Manteniendo tamaño original, solo aplicando rotación")
            // Solo aplicar la rotación/orientación original, sin escalado
            transformer.setTransform(preferredTransform, at: .zero)
        }
        
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        // CREAR EXPORT SESSION CON PRESET QUE SÍ FUNCIONA
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProcessingError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        
        print("🎬 Comprimiendo a \(Int(targetSize.width))x\(Int(targetSize.height)) con HighestQuality")
        
        // USAR PROGRESO REAL DEL EXPORT SESSION
        return try await withCheckedThrowingContinuation { continuation in
            // Timer para actualizar progreso
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    self.processingProgress = Double(exportSession.progress) * 0.8 + 0.2 // 20-100%
                }
            }
            
            exportSession.exportAsynchronously {
                progressTimer.invalidate()
                
                DispatchQueue.main.async {
                    switch exportSession.status {
                    case .completed:
                        self.processingProgress = 1.0
                        continuation.resume(returning: outputURL)
                    case .failed:
                        let error = exportSession.error ?? ProcessingError.compressionFailed
                        print("❌ Export falló: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    case .cancelled:
                        continuation.resume(throwing: ProcessingError.compressionCancelled)
                    default:
                        continuation.resume(throwing: ProcessingError.unexpectedState)
                    }
                }
            }
        }
    }
    
    // MARK: - Funciones de Utilidad
    
    private func calculateOptimalSize(currentSize: CGSize, targetFormat: VideoFormat) -> CGSize {
        let targetSize = targetFormat.targetSize
        let currentAspectRatio = currentSize.width / currentSize.height
        let targetAspectRatio = targetSize.width / targetSize.height
        let tolerance: CGFloat = 0.1
        
        print("📐 Aspect ratios - Actual: \(String(format: "%.3f", currentAspectRatio)), Objetivo: \(String(format: "%.3f", targetAspectRatio))")
        
        // ✅ SI EL ASPECT RATIO YA ES CORRECTO, SOLO REDUCIR RESOLUCIÓN SI ES NECESARIO
        if abs(currentAspectRatio - targetAspectRatio) < tolerance {
            print("✅ Aspect ratio correcto, preservando contenido")
            
            // Determinar dimensión máxima según formato
            let maxDimension: CGFloat = targetFormat == .landscape ? 1920 : 1080
            
            // Solo reducir si es demasiado grande
            if max(currentSize.width, currentSize.height) > maxDimension * 1.2 {
                return calculateOptimalSizePreservingRatio(currentSize: currentSize, maxDimension: maxDimension)
            } else {
                print("✅ Resolución ya es adecuada, no comprimir")
                return currentSize // ✅ MANTENER TAMAÑO ORIGINAL
            }
        }
        
        print("🔄 Aspect ratio diferente, ajustando al formato objetivo")
        
        // ✅ SI EL ASPECT RATIO ES DIFERENTE, AJUSTAR PERO INTENTAR PRESERVAR CONTENIDO
        if abs(currentAspectRatio - targetAspectRatio) > 0.3 {
            // Diferencia muy grande: mantener aspect ratio original pero limitar resolución
            print("⚠️ Diferencia muy grande en aspect ratio, preservando original")
            let maxDimension: CGFloat = 1080
            return calculateOptimalSizePreservingRatio(currentSize: currentSize, maxDimension: maxDimension)
        }
        
        // Diferencia pequeña: usar el tamaño objetivo (puede recortar ligeramente)
        return targetSize
    }

    // ✅ NUEVA FUNCIÓN HELPER
    private func calculateOptimalSizePreservingRatio(currentSize: CGSize, maxDimension: CGFloat) -> CGSize {
        let currentRatio = currentSize.width / currentSize.height
        
        if currentSize.width > currentSize.height {
            // Horizontal: limitar ancho
            let width = min(currentSize.width, maxDimension)
            let height = width / currentRatio
            return CGSize(width: width, height: height)
        } else {
            // Vertical: limitar alto
            let height = min(currentSize.height, maxDimension)
            let width = height * currentRatio
            return CGSize(width: width, height: height)
        }
    }
    
    private func shouldCompress(currentSize: CGSize, targetSize: CGSize) -> Bool {
        // ✅ NO COMPRIMIR si el tamaño objetivo es igual al actual (preservación)
        if currentSize == targetSize {
            print("✅ Tamaños idénticos, no comprimir")
            return false
        }
        
        // Comprimir si la resolución actual es significativamente mayor
        let currentPixels = currentSize.width * currentSize.height
        let targetPixels = targetSize.width * targetSize.height
        let pixelRatio = currentPixels / targetPixels
        
        let shouldCompress = pixelRatio > 1.2 // Comprimir si tiene 20% más píxeles
        print("📊 Píxeles - Actual: \(Int(currentPixels)), Objetivo: \(Int(targetPixels)), Ratio: \(String(format: "%.2f", pixelRatio))")
        print("🤔 ¿Comprimir? \(shouldCompress)")
        
        return shouldCompress
    }
    
    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func updateSelectedMedia() {
        // Actualizar los medios con las configuraciones seleccionadas
        for index in selectedMediaItems.indices {
            if selectedMediaItems[index].type == .video {
                selectedMediaItems[index] = selectedMediaItems[index].with(
                    aspectRatio: selectedFormat.toProcessedMediaAspectRatio,
                    hasEdits: true // Marcar que el video ha sido editado
                )
                
                print("✅ Video configurado:")
                print("  - ID: \(selectedMediaItems[index].id)")
                print("  - Formato: \(selectedFormat.displayName)")
                print("  - Velocidad: \(playbackSpeed.rawValue)")
                print("  - Recorte: \(formatTime(trimStartTime)) - \(formatTime(trimEndTime))")
                print("  - Audio: \(volume > 0 ? "Activado" : "Silenciado")")
                print("  - Has Edits: \(selectedMediaItems[index].hasEdits)")
                
                if let videoURL = selectedMediaItems[index].videoURL {
                    print("  - Video URL: \(videoURL.lastPathComponent)")
                }
                
                // Los datos de thumbnail, duración, etc. ya están guardados en el ProcessedMedia
                // desde el proceso de compresión anterior
                if let videoInfo = selectedMediaItems[index].videoInfo {
                    print("  - Duración: \(String(format: "%.1f", videoInfo.duration))s")
                    print("  - Tamaño: \(String(format: "%.1f", Double(videoInfo.fileSize)/1024.0/1024.0)) MB")
                }
            }
        }
    }
    
    // NUEVA FUNCIÓN: Convertir ProcessedMedia a MediaItems para upload
    func convertToMediaItems() -> [MediaItem] {
        return selectedMediaItems.compactMap { processedMedia in
            switch processedMedia.type {
            case .video:
                guard let videoURL = processedMedia.videoURL else { return nil }
                
                let videoInfo = processedMedia.videoInfo
                let resolution = "\(Int(selectedFormat.targetSize.width))x\(Int(selectedFormat.targetSize.height))"
                
                return MediaItem(
                    type: .video,
                    url: videoURL.absoluteString,
                    thumbnailUrl: nil, // Se subirá por separado durante el upload a Firebase
                    videoDuration: videoInfo?.duration,
                    videoFileSize: videoInfo?.fileSize,
                    videoResolution: resolution
                )
                
            case .image:
                // Para imágenes, necesitarás implementar la lógica de upload
                return MediaItem(
                    type: .image,
                    url: "", // URL se asignará después del upload
                    thumbnailUrl: nil,
                    videoDuration: nil,
                    videoFileSize: nil,
                    videoResolution: nil
                )
            }
        }
    }
    
    // FUNCIÓN PARA OBTENER THUMBNAIL COMO IMAGEN
    func getThumbnailImage(for videoIndex: Int) -> UIImage? {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        if videoItems.indices.contains(videoIndex) {
            return videoItems[videoIndex].image // El thumbnail se guardó en el campo image
        }
        return nil
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Errores de Procesamiento

enum ProcessingError: LocalizedError {
    case noVideoTrack
    case thumbnailGenerationFailed
    case exportSessionCreationFailed
    case compressionFailed
    case compressionCancelled
    case unexpectedState
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No se encontró pista de video"
        case .thumbnailGenerationFailed:
            return "Error generando thumbnail"
        case .exportSessionCreationFailed:
            return "Error creando sesión de exportación"
        case .compressionFailed:
            return "Error comprimiendo video"
        case .compressionCancelled:
            return "Compresión cancelada"
        case .unexpectedState:
            return "Estado inesperado durante el procesamiento"
        }
    }
}

// MARK: - Wrapper para VideoPlayer
struct VideoPlayerWrapper: UIViewControllerRepresentable {
    let player: AVPlayer?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
