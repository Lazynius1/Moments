import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct SocialVideoEditorView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
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
    @State private var draggingHandle: TrimHandleType? = nil
    @State private var lastDragLocation: CGPoint = .zero
    
    // Estados para compresión y procesamiento
    @State private var isProcessing = false
    @State private var processingMessage = "Procesando..."
    @State private var processingProgress: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Estados para thumbnails del timeline
    @State private var timelineThumbnails: [UIImage] = []
    @State private var isGeneratingThumbnails = false
    
    // Estados para thumbnail picker
    @State private var showingThumbnailPicker = false
    @State private var selectedThumbnailTime: Double = 0
    @State private var customThumbnailImage: UIImage? = nil
    
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
        
        var toProcessedMediaAspectRatio: CreatorMedia.AspectRatio {
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
    
    var currentVideo: CreatorMedia? {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        return videoItems.indices.contains(selectedClipIndex) ? videoItems[selectedClipIndex] : nil
    }
    
    var body: some View {

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
        .frame(width: UIScreen.main.bounds.width) // ✅ FORZAR ANCHO ESTRICTO: Nada puede salirse de la pantalla
        .clipped() // ✅ Recortar cualquier contenido que intente desbordarse
        .overlay(
            ZStack(alignment: .top) {
                // ✅ FORZAR FONDO DE STATUS BAR: Asegura contraste correcto
                Color(colorScheme == .dark ? .black : .white)
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)
                
                if isProcessing {
                    processingOverlay
                }
            }
        )
        .statusBar(hidden: false) // ✅ FORZAR VISIBILIDAD
        .navigationBarHidden(true)
        .background(colorScheme == .dark ? Color.black : Color.white)
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
        .alert(NSLocalizedString("videoEditor.error.title", comment: "Error"), isPresented: $showingError) {
            Button(NSLocalizedString("videoEditor.ok", comment: "OK")) { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingThumbnailPicker) {
            ThumbnailPickerView(
                videoURL: currentVideo?.videoURL,
                selectedTime: $selectedThumbnailTime,
                selectedImage: $customThumbnailImage,
                onDismiss: {
                    showingThumbnailPicker = false
                }
            )
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
                        .stroke(Color.pink, lineWidth: 4)
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
                    
                    Text("videoEditor.optimizing")
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(isProcessing)
            
            Spacer()
            
            Text(NSLocalizedString("videoEditor.edit", comment: "Edit Video"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            if !isProcessing {
                GlowSharePill(
                    title: "creator.next",
                    icon: "chevron.right",
                    isSmall: true
                ) {
                    processAndContinue()
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea(edges: .top)
        )
        .zIndex(10)
    }
    
    // MARK: - Video Preview
    private var videoPreviewSection: some View {
        ZStack {
            if let video = currentVideo {
                // Fondo Cinemático (Blur)
                if let thumbnail = video.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 500)
                        .blur(radius: 30)
                        .opacity(0.6)
                        .overlay(Color.black.opacity(0.3))
                }

                // Contenedor del video con aspecto correcto
                // Contenedor del video con aspecto correcto - SIMPLIFICADO
                VideoPlayerWrapper(player: player)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)                .aspectRatio(selectedFormat.ratio, contentMode: .fit)
                .frame(maxWidth: UIScreen.main.bounds.width) // ✅ Limitar ancho a la pantalla
                .frame(maxHeight: 480) // Limitar altura máxima
                .padding(.vertical, 10)
                
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
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            }
            
            // Indicador de volumen (temporal al cambiar)
            if showingVolumeSlider {
                 Text("\(Int(volume * 100))%")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .transition(.opacity)
            }
            
            // Aspect Ratio Guides (se muestran al cambiar formato)
            if showingFormatPicker {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(.white.opacity(0.5))
                    .aspectRatio(selectedFormat.ratio, contentMode: .fit)
                    .padding(20)
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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text("\(formatTime(trimEndTime - trimStartTime)) de \(formatTime(duration))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text(formatTime(trimEndTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .padding(.horizontal, 20)
            
            // Timeline con frames del video
            timelineView
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .opacity(isProcessing ? 0.5 : 1.0)
    }
    
    private var timelineView: some View {
        GeometryReader { geometry in
            let frameWidth: CGFloat = 60
            let totalFrames = min(timelineThumbnails.count, Int(geometry.size.width / frameWidth))
            
            ZStack {
                // Fondo del timeline con gradiente moderno
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                    )
                
                // Thumbnails del video
                if !timelineThumbnails.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(0..<totalFrames, id: \.self) { index in
                            Image(uiImage: timelineThumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: frameWidth - 1, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                } else {
                    // Placeholder mientras se generan thumbnails
                    HStack(spacing: 1) {
                        ForEach(0..<totalFrames, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.pink.opacity(0.3),
                                            Color.purple.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: frameWidth - 1, height: 80)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                )
                        }
                    }
                }
                
                // Overlay de selección
                let startX = CGFloat(trimStartTime / duration) * geometry.size.width
                let endX = CGFloat(trimEndTime / duration) * geometry.size.width
                let selectedWidth = endX - startX
                
                // Área oscurecida (antes del inicio)
                if startX > 0 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.8),
                                    Color.black.opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: startX, height: 90)
                        .position(x: startX / 2, y: 45)
                }
                
                // Área oscurecida (después del final)
                if endX < geometry.size.width {
                    let remainingWidth = geometry.size.width - endX
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: remainingWidth, height: 90)
                        .position(x: endX + remainingWidth / 2, y: 45)
                }
                
                // Bordes de selección con glow
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(isDraggingTrimHandle ? 1.0 : 0.8),
                                Color.pink.opacity(isDraggingTrimHandle ? 0.8 : 0.6),
                                Color.purple.opacity(isDraggingTrimHandle ? 1.0 : 0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: isDraggingTrimHandle ? 4 : 3
                    )
                    .frame(width: selectedWidth, height: 90)
                    .position(x: startX + selectedWidth / 2, y: 45)
                    .shadow(color: Color.pink.opacity(isDraggingTrimHandle ? 0.8 : 0.5), radius: isDraggingTrimHandle ? 6 : 4, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.2), value: isDraggingTrimHandle)
                
                // Handle izquierdo
                trimHandle(isStart: true)
                    .position(x: startX, y: 45)
                
                // Handle derecho
                trimHandle(isStart: false)
                    .position(x: endX, y: 45)
                
                // Overlay invisible para capturar toques en el área del timeline
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: selectedWidth, height: 90)
                    .position(x: startX + selectedWidth / 2, y: 45)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false) // No interferir con los handles
                
                // Indicador de tiempo actual
                let playheadX = CGFloat(currentTime / duration) * geometry.size.width
                ZStack {
                    // Línea principal
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 3, height: 100)
                        .shadow(color: Color.white.opacity(0.5), radius: 2, x: 0, y: 0)
                    
                    // Círculo superior
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 12, height: 12)
                        .offset(y: -50)
                        .shadow(color: Color.white.opacity(0.3), radius: 2, x: 0, y: 0)
                }
                .position(x: playheadX, y: 45)
            }
        }
        .frame(height: 90)
        .padding(.horizontal, 20) // ✅ Padding ANTES del frame para que sea parte del ancho total
        .frame(maxWidth: UIScreen.main.bounds.width) // ✅ Limitar al ancho de pantalla
        .clipped()
        .allowsHitTesting(!isProcessing)
    }
    
    private func trimHandle(isStart: Bool) -> some View {
        let isDragging = draggingHandle == (isStart ? .start : .end)
        
        return ZStack {
            // Fondo principal del handle
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: isDragging ? [
                            Color.purple.opacity(1.0),
                            Color.pink.opacity(0.9)
                        ] : [
                            Color.purple.opacity(0.9),
                            Color.pink.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: isDragging ? 16 : 12, height: 90)
                .shadow(color: Color.pink.opacity(isDragging ? 0.8 : 0.5), radius: isDragging ? 6 : 4, x: 0, y: 2)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragging)
            
            // Borde brillante
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDragging ? 1.0 : 0.8),
                            Color.white.opacity(isDragging ? 0.6 : 0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isDragging ? 2 : 1
                )
                .frame(width: isDragging ? 16 : 12, height: 90)
                .animation(.easeInOut(duration: 0.2), value: isDragging)
            
            // Handle completamente limpio sin elementos decorativos
        }
        .contentShape(Rectangle().inset(by: -20)) // Área táctil más grande
        .scaleEffect(isDragging ? 1.1 : 1.0) // Escalar todo el handle cuando se arrastra
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isProcessing {
                        handleTrimDrag(value: value, isStart: isStart)
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDraggingTrimHandle = false
                        draggingHandle = nil
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    // Haptic feedback para confirmar el toque
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    // Marcar inmediatamente que se está arrastrando para feedback visual
                    withAnimation(.easeInOut(duration: 0.1)) {
                        draggingHandle = isStart ? .start : .end
                    }
                }
        )
        .onTapGesture {
            // Feedback visual inmediato al tocar
            withAnimation(.easeInOut(duration: 0.1)) {
                draggingHandle = isStart ? .start : .end
            }
            
            // Reset después de un breve momento
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if draggingHandle == (isStart ? .start : .end) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        draggingHandle = nil
                    }
                }
            }
        }
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
            HStack(spacing: 15) {
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
                
                // Portada
                controlButton(
                    icon: "photo.on.rectangle",
                    title: "Portada",
                    subtitle: customThumbnailImage == nil ? "Auto" : "Manual",
                    action: {
                        if !isProcessing {
                            showingThumbnailPicker = true
                        }
                    }
                )
                
                // Volumen
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .onTapGesture {
                                toggleVolume()
                            }
                        
                        Slider(value: $volume, in: 0...1.0)
                            .accentColor(colorScheme == .dark ? .white : .black)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .frame(width: 120)
                }
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
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            
                            if index == selectedClipIndex {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.pink, lineWidth: 2)
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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 30, height: 30)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
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
                Button(NSLocalizedString("videoEditor.cancel", comment: "Cancel")) {
                    showingSpeedPicker = false
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                Text("videoEditor.speed")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(NSLocalizedString("videoEditor.done", comment: "Done")) {
                    showingSpeedPicker = false
                    applyPlaybackSpeed()
                }
                .foregroundColor(.pink)
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
                                    .fill(playbackSpeed == speed ? Color.pink : Color.gray.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: speed.icon)
                                    .font(.title)
                                    .foregroundColor(playbackSpeed == speed ? .white : .gray)
                            }
                            
                            Text(speed.rawValue)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(playbackSpeed == speed ? .pink : .primary)
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
                Button(NSLocalizedString("videoEditor.cancel", comment: "Cancel")) {
                    showingFormatPicker = false
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                Text("videoEditor.format")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(NSLocalizedString("videoEditor.done", comment: "Done")) {
                    showingFormatPicker = false
                }
                .foregroundColor(.pink)
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
                                .foregroundColor(selectedFormat == format ? .pink : .gray)
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
                                    .foregroundColor(.pink)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(selectedFormat == format ? Color.pink.opacity(0.1) : Color.clear)
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
        
        // Generar thumbnails para el timeline
        generateTimelineThumbnails()
        
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
        
        // ✅ DETECTAR ASPECT RATIO AUTOMÁTICAMENTE
        Task {
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                let ratio = abs(size.width / size.height)
                
                await MainActor.run {
                    if ratio > 1.2 {
                        self.selectedFormat = .landscape
                    } else if ratio < 0.85 {
                        self.selectedFormat = .reels
                    } else {
                        self.selectedFormat = .square
                    }
                }
            } catch {
                print("Error detectando aspect ratio: \(error)")
            }
        }
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    // MARK: - Generación de Thumbnails del Timeline
    private func generateTimelineThumbnails() {
        guard let video = currentVideo, let videoURL = video.videoURL else { return }
        
        isGeneratingThumbnails = true
        timelineThumbnails.removeAll()
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 80) // Tamaño para timeline
        
        // Generar thumbnails cada 2 segundos
        let thumbnailCount = 20 // Número de thumbnails en el timeline
        let timeInterval = duration / Double(thumbnailCount)
        
        Task {
            do {
                for i in 0..<thumbnailCount {
                    let time = CMTime(seconds: Double(i) * timeInterval, preferredTimescale: 600)
                    
                    do {
                        let cgImage = try await imageGenerator.image(at: time).image
                        let uiImage = UIImage(cgImage: cgImage)
                        
                        await MainActor.run {
                            timelineThumbnails.append(uiImage)
                        }
                    } catch {
                        // Si falla un thumbnail, usar uno por defecto
                        await MainActor.run {
                            timelineThumbnails.append(createDefaultThumbnail())
                        }
                    }
                }
                
                await MainActor.run {
                    isGeneratingThumbnails = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingThumbnails = false
                    // Generar thumbnails por defecto si falla
                    for _ in 0..<thumbnailCount {
                        timelineThumbnails.append(createDefaultThumbnail())
                    }
                }
            }
        }
    }
    
    private func createDefaultThumbnail() -> UIImage {
        let size = CGSize(width: 120, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Fondo con gradiente
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor
                ] as CFArray,
                locations: [0, 1]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // Icono de video
            let iconSize: CGFloat = 30
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: iconRect)
            
            // Triángulo de play
            let trianglePath = UIBezierPath()
            trianglePath.move(to: CGPoint(x: iconRect.midX + 5, y: iconRect.midY - 8))
            trianglePath.addLine(to: CGPoint(x: iconRect.midX + 5, y: iconRect.midY + 8))
            trianglePath.addLine(to: CGPoint(x: iconRect.midX + 13, y: iconRect.midY))
            trianglePath.close()
            
            UIColor.systemBlue.setFill()
            trianglePath.fill()
        }
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
        // Usar tolerancia más alta para seek más rápido
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }
    
    private func handleTrimDrag(value: DragGesture.Value, isStart: Bool) {
        // Marcar qué handle se está arrastrando
        draggingHandle = isStart ? .start : .end
        
        // Actualizar posición del drag
        lastDragLocation = value.location
        
        // Usar coordenadas globales para mejor precisión
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 40
        let availableWidth = screenWidth - padding
        
        // Calcular nueva posición basada en el drag con mejor precisión
        let dragLocation = value.location.x
        let newTimePercent = max(0, min(1, (dragLocation - padding/2) / availableWidth))
        let newTime = newTimePercent * duration
        
        // Aplicar restricciones inmediatas para mejor respuesta
        if isStart {
            let minTime = 0.0
            let maxTime = trimEndTime - 1.0
            trimStartTime = max(minTime, min(newTime, maxTime))
        } else {
            let minTime = trimStartTime + 1.0
            let maxTime = duration
            trimEndTime = max(minTime, min(newTime, maxTime))
        }
        
        // Seek inmediato para mejor respuesta
        seekTo(time: isStart ? trimStartTime : trimEndTime)
        
        isDraggingTrimHandle = true
        
        // Haptic feedback solo cada cierto número de cambios para no saturar
        if abs(value.location.x - lastDragLocation.x) > 10 {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
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
                    }
                    
                case .failure(let error):
                    allSuccess = false
                }
            }
        }
        
        group.notify(queue: .main) {
            self.processingProgress = 1.0
            self.processingMessage = "Finalizando..."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                
                
                // PASO 2: Calcular resolución objetivo
                let targetSize = calculateOptimalSize(currentSize: currentSize, targetFormat: format)
                let needsCompression = shouldCompress(currentSize: currentSize, targetSize: targetSize)
                
                
                // PASO 3: Generar thumbnail PRIMERO
                let thumbnailURL: URL
                let thumbnailImage: UIImage
                
                if let customImg = customThumbnailImage {
                    // Si el usuario eligió una portada manualmente, usar esa
                    thumbnailImage = customImg
                    
                    let tempDir = FileManager.default.temporaryDirectory
                    let customURL = tempDir.appendingPathComponent("thumbnail_custom_\(UUID().uuidString).jpg")
                    
                    guard let jpegData = customImg.jpegData(compressionQuality: 0.8) else {
                        throw ProcessingError.thumbnailGenerationFailed
                    }
                    
                    try jpegData.write(to: customURL)
                    thumbnailURL = customURL
                } else {
                    // Si no hay portada manual, generar una automática
                    let result = try await generateThumbnail(from: asset, targetSize: targetSize)
                    thumbnailURL = result.0
                    thumbnailImage = result.1
                }
                
                // PASO 4: Comprimir video si es necesario
                let finalVideoURL: URL
                if needsCompression {
                    finalVideoURL = try await compressVideo(
                        inputURL: videoURL,
                        targetSize: targetSize,
                        targetBitrate: format.targetBitrate
                    )
                } else {
                    finalVideoURL = videoURL
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
        
        
        // ✅ SI EL ASPECT RATIO YA ES CORRECTO, SOLO REDUCIR RESOLUCIÓN SI ES NECESARIO
        if abs(currentAspectRatio - targetAspectRatio) < tolerance {
            
            // Determinar dimensión máxima según formato
            let maxDimension: CGFloat = targetFormat == .landscape ? 1920 : 1080
            
            // Solo reducir si es demasiado grande
            if max(currentSize.width, currentSize.height) > maxDimension * 1.2 {
                return calculateOptimalSizePreservingRatio(currentSize: currentSize, maxDimension: maxDimension)
            } else {
                return currentSize // ✅ MANTENER TAMAÑO ORIGINAL
            }
        }
        
        
        // ✅ SI EL ASPECT RATIO ES DIFERENTE, AJUSTAR PERO INTENTAR PRESERVAR CONTENIDO
        if abs(currentAspectRatio - targetAspectRatio) > 0.3 {
            // Diferencia muy grande: mantener aspect ratio original pero limitar resolución
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
            return false
        }
        
        // Comprimir si la resolución actual es significativamente mayor
        let currentPixels = currentSize.width * currentSize.height
        let targetPixels = targetSize.width * targetSize.height
        let pixelRatio = currentPixels / targetPixels
        
        let shouldCompress = pixelRatio > 1.2 // Comprimir si tiene 20% más píxeles
        
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
                
                
                if let videoURL = selectedMediaItems[index].videoURL {
                }
                
                // Los datos de thumbnail, duración, etc. ya están guardados en el ProcessedMedia
                // desde el proceso de compresión anterior
                if let videoInfo = selectedMediaItems[index].videoInfo {
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

// MARK: - Thumbnail Picker View
struct ThumbnailPickerView: View {
    let videoURL: URL?
    @Binding var selectedTime: Double
    @Binding var selectedImage: UIImage?
    var onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var previewImage: UIImage?
    @State private var isGenerating = false
    @State private var imageGenerator: AVAssetImageGenerator?
    
    // Timeline thumbnails para el scrubber
    @State private var timelineThumbnails: [UIImage] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Preview Area
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.1))
                        .aspectRatio(9/16, contentMode: .fit) // Referencia visual
                    
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                    } else if isGenerating {
                        ProgressView()
                            .tint(.pink)
                    }
                }
                .padding()
                .frame(maxHeight: 500)
                
                Spacer()
                
                // Scrubber Section
                VStack(spacing: 12) {
                    Text("Desliza para seleccionar la portada")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    ZStack(alignment: .leading) {
                        // Background Timeline
                        HStack(spacing: 0) {
                            if timelineThumbnails.isEmpty {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 60)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(0..<timelineThumbnails.count, id: \.self) { index in
                                    Image(uiImage: timelineThumbnails[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 60)
                                        .clipped()
                                }
                            }
                        }
                        .frame(height: 60)
                        .cornerRadius(8)
                        .opacity(0.6)
                        
                        // Scrubber Slider Custom
                        Slider(value: $currentTime, in: 0...max(duration, 0.1))
                            .accentColor(.pink)
                            .onChange(of: currentTime) { newValue in
                                generateFrame(at: newValue)
                            }
                    }
                    .padding(.horizontal)
                    
                    Text(formatTime(currentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.pink)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Seleccionar Portada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                    }
                    .foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        selectedTime = currentTime
                        selectedImage = previewImage
                        onDismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
                }
            }
            .onAppear {
                setupGenerator()
                loadDurationAndGenerateTimeline()
            }
        }
    }
    
    private func setupGenerator() {
        guard let url = videoURL else { return }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.imageGenerator = generator
    }
    
    private func loadDurationAndGenerateTimeline() {
        guard let url = videoURL else { return }
        let asset = AVAsset(url: url)
        
        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                
                await MainActor.run {
                    self.duration = durationSeconds
                    // Generar thumbnails para el fondo del scrubber
                    generateTimelineThumbnails(for: asset, duration: durationSeconds)
                    // Generar primer frame
                    generateFrame(at: 0)
                }
            } catch {
                print("Error loading asset duration: \(error)")
            }
        }
    }
    
    private func generateFrame(at time: Double) {
        guard let generator = imageGenerator else { return }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        Task {
            do {
                let (cgImage, _) = try await generator.image(at: cmTime)
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.previewImage = image
                    self.isGenerating = false
                }
            } catch {
                print("Error generating frame: \(error)")
            }
        }
    }
    
    private func generateTimelineThumbnails(for asset: AVAsset, duration: Double) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 150, height: 150)
        
        let count = 10
        var times: [NSValue] = []
        let step = duration / Double(count)
        
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            times.append(NSValue(time: time))
        }
        
        generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
            if let cgImage = cgImage {
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.timelineThumbnails.append(image)
                }
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
