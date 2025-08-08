import UIKit
import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth

// MARK: - Story Editing View with Video Preview
struct StoryEditingView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem?
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var storyText = ""
    @State private var textPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width / 2, y: 100)
    @State private var selectedStickers: [StickerItem] = []
    @State private var showingTextEditor = false
    @State private var showingStickerPicker = false
    @State private var showingDrawing = false
    @State private var isPublishing = false
    @State private var storyAudience: CaptionAndDetailsView.AudienceSetting = .everyone
    @State private var isLoadingUserSettings = true // NUEVO
    @State private var showingAudienceSelector = false
    @State private var selectedTextStyle: TextStyle = .modern
    @State private var drawingImage: UIImage?
    
    // ✅ NUEVAS VARIABLES para listas personalizadas
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []
    @State private var forceUpdate: Bool = false
    
    // ✅ PROPIEDADES para navegación
    @State private var showingUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var navigationPath = NavigationPath()
    

    
    @State private var showingLocationMap = false
    @State private var selectedLocationName = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    enum TextStyle {
        case modern, classic, neon, typewriter, bold
        
        var font: Font {
            switch self {
            case .modern: return .system(size: 28, weight: .medium)
            case .classic: return .custom("Georgia", size: 26)
            case .neon: return .system(size: 30, weight: .black)
            case .typewriter: return .custom("Courier New", size: 24)
            case .bold: return .system(size: 32, weight: .heavy)
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .modern: return Color.black.opacity(0.6)
            case .classic: return Color.clear
            case .neon: return Color.purple.opacity(0.8)
            case .typewriter: return Color.gray.opacity(0.7)
            case .bold: return Color.clear
            }
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Background media
                if let firstMedia = selectedMediaItems.first {
                    if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                        StoryVideoPlayerView(videoURL: videoURL)
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                            .clipped()
                            .ignoresSafeArea()
                    } else {
                        Image(uiImage: firstMedia.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                            .clipped()
                            .ignoresSafeArea()
                    }
                }
                
                // Drawing overlay
                if let drawing = drawingImage {
                    Image(uiImage: drawing)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .allowsHitTesting(false)
                }
                
                // Overlays
                StoryOverlaysView(
                    text: $storyText,
                    textPosition: $textPosition,
                    textStyle: $selectedTextStyle,
                    stickers: $selectedStickers,
                    drawingImage: $drawingImage,
                    onNavigateToProfile: { userId in
                        handleProfileNavigation(userId: userId)
                    },
                    onNavigateToLocation: { locationName, coordinate in  // ← AGREGAR ESTA LÍNEA
                        handleLocationNavigation(locationName: locationName, coordinate: coordinate)
                    }
                )
                .id(forceUpdate) // ✅ FORZAR RECONSTRUCCIÓN CUANDO CAMBIE

                
                // Controls
                VStack {
                    // Top bar
                    HStack {
                        Button(action: {
                            currentFlow = .storyCamera
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Media type indicator
                        if let firstMedia = selectedMediaItems.first {
                            HStack(spacing: 8) {
                                Image(systemName: firstMedia.type == .video ? "video.fill" : "photo.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                if firstMedia.type == .video {
                                    Text("Video")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Editing tools
                        HStack(spacing: 20) {
                            EditingToolIcon(icon: "textformat.alt") {
                                showingTextEditor = true
                            }
                            
                            EditingToolIcon(icon: "face.smiling") {
                                showingStickerPicker = true
                            }
                            
                            EditingToolIcon(icon: "scribble") {
                                showingDrawing = true
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            saveToGallery()
                        }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Video controls
                    if let firstMedia = selectedMediaItems.first, firstMedia.type == .video {
                        VideoControlsOverlay()
                    }
                    
                    // Bottom bar
                    HStack {
                        // Story settings - ✅ ACTUALIZADO con loading state
                        Button(action: {
                            if !isLoadingUserSettings {
                                showingAudienceSelector = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoadingUserSettings {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.white)
                                } else {
                                    Image(systemName: getAudienceIcon())
                                }
                                
                                Text(isLoadingUserSettings ? "Cargando..." : getAudienceText())
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Send button
                        Button(action: {
                            publishStory()
                        }) {
                            HStack(spacing: 8) {
                                Text("Compartir")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(isLoadingUserSettings ? 0.5 : 1.0))
                            .clipShape(Capsule())
                        }
                        .disabled(isPublishing || isLoadingUserSettings)
                    }
                    .padding()
                }
            }
            .navigationDestination(for: String.self) { userId in
                UserProfileView(userId: userId)
            }
            .onAppear {
                loadUserDefaultAudienceSettings()
                setupStickerListener()
                
                // ✅ AGREGAR STICKER INICIAL SI EXISTE
                if let initialSticker = initialSticker {
                    selectedStickers.append(initialSticker)
                }
            }
            .onDisappear {
                removeStickerListener()
            }
        }
        // ✅ SHEET ACTUALIZADO para selector de audiencia mejorado
        .sheet(isPresented: $showingAudienceSelector) {
            AudienceSelectionView(
                selectedAudience: convertToContentAudience(),
                selectedListId: $selectedListId,
                selectedListName: $selectedListName,
                customSelectedUsers: $customSelectedUsers
            )
            .onDisappear {
                updateAudienceSetting()
            }
        }
        .sheet(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: selectedLocationName,
                coordinate: selectedCoordinate,
                isPresented: $showingLocationMap
            )
        }
        .sheet(isPresented: $showingTextEditor) {
            StoryTextEditor(
                text: $storyText,
                selectedStyle: $selectedTextStyle
            )
        }
        .sheet(isPresented: $showingStickerPicker) {
            StickerPickerView(selectedStickers: $selectedStickers)
        }
        .fullScreenCover(isPresented: $showingDrawing) {
            DrawingView(backgroundImage: selectedMediaItems.first?.image) { drawing in
                drawingImage = drawing
            }
        }
        .overlay(
            Group {
                if isPublishing {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Compartiendo historia...")
                            .foregroundColor(.white)
                    }
                }
            }
        )
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK") { }
        }
    }
    
    // ✅ NUEVAS FUNCIONES AUXILIARES
    private func getAudienceIcon() -> String {
        if storyAudience == .custom && selectedListId != nil {
            return "list.bullet.rectangle"
        }
        return storyAudience.icon
    }
    
    private func getAudienceText() -> String {
        if storyAudience == .custom {
            if let listName = selectedListName {
                return listName
            } else if !customSelectedUsers.isEmpty {
                return "\(customSelectedUsers.count) personas"
            }
        }
        return storyAudience.title
    }
    
    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch storyAudience {
                case .everyone: return .everyone
                case .mutuals: return .connections
                case .admirers: return .connections
                case .bestFriends: return .bestFriends
                case .custom:
                    return selectedListId != nil ? .customList : .custom
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: storyAudience = .everyone
                case .connections: storyAudience = .mutuals
                case .bestFriends: storyAudience = .bestFriends
                case .custom: storyAudience = .custom
                case .customList: storyAudience = .custom
                case .onlyMe: storyAudience = .everyone
                }
            }
        )
    }
    
    private func updateAudienceSetting() {
        // Esta función se llama cuando el sheet se cierra
        // La lógica ya está manejada por los bindings
    }
    
    // ✅ NUEVA FUNCIÓN: Cargar configuración por defecto del usuario
    private func loadUserDefaultAudienceSettings() {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoadingUserSettings = false
            return
        }
        
        FirestoreService().db.collection("users").document(userId).getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] {
                    
                    // Cargar audiencia por defecto
                    if let storyAudienceRaw = visibilitySettings["storyAudience"] as? String,
                       let contentAudience = ContentAudience(rawValue: storyAudienceRaw) {
                        
                        // Convertir ContentAudience a CaptionAndDetailsView.AudienceSetting
                        switch contentAudience {
                        case .everyone:
                            self.storyAudience = .everyone
                        case .connections:
                            self.storyAudience = .mutuals
                        case .bestFriends:
                            self.storyAudience = .bestFriends
                        case .custom:
                            self.storyAudience = .custom
                            self.customSelectedUsers = visibilitySettings["storyCustomUsers"] as? [String] ?? []
                        case .customList:
                            self.storyAudience = .custom
                            self.selectedListId = visibilitySettings["storyCustomListId"] as? String
                            self.selectedListName = visibilitySettings["storyCustomListName"] as? String
                        case .onlyMe:
                            self.storyAudience = .everyone
                        }
                    }
                }
                self.isLoadingUserSettings = false
            }
        }
    }
    
    private func handleProfileNavigation(userId: String) {
        print("🚀 Navegando al perfil del usuario: \(userId)")
        
        if let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId {
            print("❌ No se puede navegar al propio perfil desde aquí")
            return
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        navigationPath.append(userId)
    }
    
    private func handleLocationNavigation(locationName: String, coordinate: CLLocationCoordinate2D?) {
        print("🗺️ Navegando a ubicación: \(locationName)")
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        selectedLocationName = locationName
        selectedCoordinate = coordinate
        showingLocationMap = true
    }
    
    private func saveToGallery() {
        if let firstMedia = selectedMediaItems.first {
            if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                saveVideoToGallery(videoURL)
            } else {
                let finalImage = renderStoryWithOverlays()
                UIImageWriteToSavedPhotosAlbum(finalImage, nil, nil, nil)
            }
        }
        
        alertMessage = "Historia guardada en tu galería"
        showAlert = true
    }
    
    private func saveVideoToGallery(_ videoURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { success, error in
            // Video saved
        }
    }
    
    private func renderStoryWithOverlays() -> UIImage {
        guard let baseImage = selectedMediaItems.first?.image else {
            return UIImage()
        }
        
        let originalSize = baseImage.size
        let screenSize = UIScreen.main.bounds.size
        let scaleFactorX = originalSize.width / screenSize.width
        let scaleFactorY = originalSize.height / screenSize.height
        
        let renderer = UIGraphicsImageRenderer(size: originalSize)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: originalSize)
            
            baseImage.draw(in: rect)
            
            if let drawing = drawingImage {
                drawing.draw(in: rect, blendMode: .normal, alpha: 1.0)
            }
            
            if !storyText.isEmpty {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                var fontSize: CGFloat = 28 * max(scaleFactorX, scaleFactorY)
                var fontWeight: UIFont.Weight = .medium
                
                switch selectedTextStyle {
                case .modern:
                    fontSize = 28 * max(scaleFactorX, scaleFactorY)
                    fontWeight = .medium
                case .classic:
                    fontSize = 26 * max(scaleFactorX, scaleFactorY)
                    fontWeight = .regular
                case .neon:
                    fontSize = 30 * max(scaleFactorX, scaleFactorY)
                    fontWeight = .black
                case .typewriter:
                    fontSize = 24 * max(scaleFactorX, scaleFactorY)
                    fontWeight = .regular
                case .bold:
                    fontSize = 32 * max(scaleFactorX, scaleFactorY)
                    fontWeight = .heavy
                }
                
                let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textSize = storyText.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (textPosition.x * scaleFactorX) - textSize.width / 2,
                    y: (textPosition.y * scaleFactorY) - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                
                let scaleFactor = max(scaleFactorX, scaleFactorY)
                
                switch selectedTextStyle {
                case .modern:
                    UIColor.black.withAlphaComponent(0.6).setFill()
                    let backgroundRect = textRect.insetBy(dx: -16 * scaleFactor, dy: -8 * scaleFactor)
                    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8 * scaleFactor).fill()
                case .neon:
                    UIColor.purple.withAlphaComponent(0.8).setFill()
                    let backgroundRect = textRect.insetBy(dx: -16 * scaleFactor, dy: -8 * scaleFactor)
                    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8 * scaleFactor).fill()
                case .typewriter:
                    UIColor.gray.withAlphaComponent(0.7).setFill()
                    let backgroundRect = textRect.insetBy(dx: -16 * scaleFactor, dy: -8 * scaleFactor)
                    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8 * scaleFactor).fill()
                default:
                    break
                }
                
                storyText.draw(in: textRect, withAttributes: attributes)
            }
            
            for sticker in selectedStickers {
                                    // ✅ NO renderizar stickers interactivos en la imagen final
                    // Los stickers interactivos se mostrarán dinámicamente en la UI
                    if sticker.type == .mention || sticker.type == .poll || sticker.type == .question || sticker.type == .location || sticker.type == .hashtag || sticker.type == .weather {
                        continue
                    }
                
                context.cgContext.saveGState()
                
                let scaledPosition = CGPoint(
                    x: sticker.position.x * scaleFactorX,
                    y: sticker.position.y * scaleFactorY
                )
                
                // ✅ USAR DIMENSIONES REALES PARA STICKERS DE RESPUESTA
                let originalSize = sticker.image.size
                let scaledWidth: CGFloat
                let scaledHeight: CGFloat
                
                if sticker.type == .questionResponse {
                    // ✅ MANTENER PROPORCIONES ORIGINALES (320x100)
                    let scaleFactor = max(scaleFactorX, scaleFactorY)
                    scaledWidth = originalSize.width * scaleFactor
                    scaledHeight = originalSize.height * scaleFactor
                } else {
                    // ✅ OTROS STICKERS USAN TAMAÑO FIJO
                    let baseSize = 100 * max(scaleFactorX, scaleFactorY) * sticker.scale
                    scaledWidth = baseSize
                    scaledHeight = baseSize
                }
                
                context.cgContext.translateBy(x: scaledPosition.x, y: scaledPosition.y)
                context.cgContext.rotate(by: CGFloat(sticker.rotation.radians))
                context.cgContext.scaleBy(x: sticker.scale, y: sticker.scale)
                
                let stickerRect = CGRect(
                    x: -scaledWidth / 2,
                    y: -scaledHeight / 2,
                    width: scaledWidth,
                    height: scaledHeight
                )
                
                // ✅ SOLUCIÓN: NO renderizar stickers GIFs en la imagen final
                // Los GIFs se mostrarán animados en la UI, no en la imagen estática
                if !sticker.isAnimated {
                    // Solo renderizar stickers estáticos en la imagen final
                    sticker.image.draw(in: stickerRect)
                }
                // Los GIFs animados se mostrarán dinámicamente en la UI
                
                context.cgContext.restoreGState()
            }
        }
    }
    
    // ✅ FUNCIÓN ACTUALIZADA: Publicar historia con soporte para listas
    private func publishStory() {
        guard let userId = Auth.auth().currentUser?.uid,
              let media = selectedMediaItems.first else { return }
        
        print("🚀 === PUBLICACIÓN DE HISTORIA EN BACKGROUND ===")
        print("📱 Contenido: \(storyText)")
        print("👥 Audiencia: \(storyAudience)")
        
        // 🔥 RENDERIZAR IMAGEN FINAL CON OVERLAYS
        let finalRenderedImage = renderStoryWithOverlays()
        
        // 🔥 PREPARAR DATOS DE STICKERS - PASAR StickerItem DIRECTAMENTE
        let stickerData = selectedStickers
        
        // 🔥 PREPARAR DRAWING DATA
        let drawingData = drawingImage?.pngData()
        
        // 🔥 CONVERTIR storyAudience (CaptionAndDetailsView.AudienceSetting) a ContentAudience
        let contentAudience: ContentAudience
        switch storyAudience {
        case .everyone: contentAudience = .everyone
        case .mutuals: contentAudience = .connections
        case .admirers: contentAudience = .connections
        case .bestFriends: contentAudience = .bestFriends
        case .custom: contentAudience = selectedListId != nil ? .customList : .custom
        }
        
        // 🔥 USAR EL SERVICIO DE BACKGROUND UPLOAD
        let success = BackgroundStoryUploadService.shared.publishStoryInBackground(
            mediaItem: media,
            storyText: storyText,
            textPosition: storyText.isEmpty ? nil : textPosition,
            selectedTextStyle: storyText.isEmpty ? nil : selectedTextStyle,
            stickerData: stickerData,
            drawingData: drawingData,
            audienceSetting: contentAudience, // 🔥 PASAR ContentAudience
            customViewers: customSelectedUsers,
            customListId: selectedListId,
            selectedListName: selectedListName,
            finalRenderedImage: finalRenderedImage
        )
        
        if success {
            // 🔥 CERRAR PANTALLA INMEDIATAMENTE
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCreatorView = false
                
                print("✅ Historia agregada a la cola - pantalla cerrada")
                print("📊 El usuario verá el progreso en el header del feed")
                
                // 🎉 Feedback háptico de éxito
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                // 🧹 Limpiar formulario para próximo uso
                self.resetStoryForm()
                
                // 📊 Analytics
                AnalyticsService.shared.trackInteraction("story_published_background", details: [
                    "hasText": !storyText.isEmpty,
                    "hasStickers": !selectedStickers.isEmpty,
                    "hasDrawing": drawingImage != nil,
                    "audienceType": contentAudience.rawValue
                ])
                
                // ✅ ENVIAR NOTIFICACIONES DE MENCIONES DESPUÉS DE PUBLICAR
                // Las notificaciones se enviarán cuando se complete la publicación
                // con el storyId real desde BackgroundStoryUploadService
            }
        } else {
            // ❌ Error: No se pudo agregar historia al servicio
            print("❌ Error: No se pudo agregar historia al servicio")
            
            // Feedback háptico de error
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
            
            // Mostrar error
            alertMessage = "Error al iniciar la subida de historia"
            showAlert = true
        }
    }

    // 🧹 AÑADE esta nueva función para limpiar el formulario:
    private func resetStoryForm() {
        storyText = ""
        textPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: 100)
        selectedStickers = []
        drawingImage = nil
        selectedTextStyle = .modern
        
        print("🧹 Formulario de historia limpiado para próximo uso")
    }
    
    // ✅ ENVIAR NOTIFICACIONES DE MENCIONES DESPUÉS DE PUBLICAR HISTORIA
    private func sendMentionNotificationsAfterPublish(stickerData: [StickerItem]) {
        // ✅ Filtrar solo stickers de menciones
        let mentionStickers = stickerData.filter { $0.type == .mention }
        
        if !mentionStickers.isEmpty {
            print("📧 Enviando notificaciones de menciones para \(mentionStickers.count) stickers")
            
            // ✅ Usar la función estática de StickerPickerView
            StickerPickerView.sendMentionNotificationsForStory(
                storyId: "story_published", // ✅ Placeholder - se actualizará cuando tengamos storyId real
                stickers: mentionStickers
            )
        }
    }
    
    private func extractStickerContent(from sticker: StickerItem) -> String {
        guard let interactionData = sticker.interactionData else { return "" }
        
        switch sticker.type {
        case .mention:
            return interactionData.username ?? ""
        case .hashtag:
            return interactionData.hashtag ?? ""
        case .location:
            return interactionData.location ?? ""
        case .question:
            return interactionData.questionText ?? ""
        case .poll:
            return interactionData.pollData?.joined(separator: "|") ?? ""
        default:
            return ""
        }
    }
    
    // MARK: - Response Sticker Handling
    private func setupStickerListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddStickerToStoryEditor"),
            object: nil,
            queue: .main
        ) { notification in
            if let sticker = notification.object as? StickerItem {
                addStickerToStory(sticker)
            }
        }
    }
    
    private func removeStickerListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("AddStickerToStoryEditor"),
            object: nil
        )
    }
    
    private func addStickerToStory(_ sticker: StickerItem) {
        // Agregar el sticker a la lista de stickers seleccionados
        selectedStickers.append(sticker)
        
        // Feedback háptico
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // ✅ FORZAR ACTUALIZACIÓN DE LA VISTA
        DispatchQueue.main.async {
            self.forceUpdate.toggle()
        }
    }
}

// MARK: - Video Player View
struct StoryVideoPlayerView: UIViewRepresentable {
    let videoURL: URL
    
    func makeUIView(context: Context) -> PlayerUIView {
        let playerView = PlayerUIView()
        playerView.configure(with: videoURL)
        return playerView
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Update if needed
    }
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPlayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayer()
    }
    
    private func setupPlayer() {
        backgroundColor = .black
    }
    
    func configure(with url: URL) {
        player = AVPlayer(url: url)
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = bounds
        
        if let playerLayer = playerLayer {
            layer.addSublayer(playerLayer)
        }
        
        // Auto play and loop
        player?.play()
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
    }
}

// MARK: - Video Controls Overlay
struct VideoControlsOverlay: View {
    @State private var isPlaying = true
    @State private var showControls = false
    
    var body: some View {
        HStack {
            if showControls {
                Button(action: {
                    isPlaying.toggle()
                    // Toggle play/pause
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .transition(.opacity)
                
                Spacer()
                
                Button(action: {
                    // Restart video
                }) {
                    Image(systemName: "gobackward")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .transition(.opacity)
            }
        }
        .padding()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }
            
            // Auto-hide controls after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Helper Extensions
import Photos

private func requestPhotoLibraryPermission() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    return status == .authorized || status == .limited
}

// MARK: - Supporting Views and Components

struct EditingToolButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
    }
}

struct EditingToolIcon: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
    }
}

struct OptionRow: View {
    let icon: String
    let title: String
    let value: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .frame(width: 30)
                
                Text(title)
                    .foregroundColor(.white)
                
                Spacer()
                
                if let value = value {
                    Text(value)
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    }
}

struct ShareOptionToggle: View {
    let platform: String
    let icon: String
    let color: Color
    @State private var isOn = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(platform)
                .foregroundColor(.white)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct MediaLibraryItem: Identifiable {
    let id: String
    let thumbnail: UIImage
    let isVideo: Bool
    let duration: TimeInterval?
    let videoURL: URL?
    let phAsset: PHAsset? // Reference to actual PHAsset for loading full quality
    
    init(id: String, thumbnail: UIImage, isVideo: Bool, duration: TimeInterval? = nil, videoURL: URL? = nil, phAsset: PHAsset? = nil) {
        self.id = id
        self.thumbnail = thumbnail
        self.isVideo = isVideo
        self.duration = duration
        self.videoURL = videoURL
        self.phAsset = phAsset
    }
}

struct FilterSettings {
    let name: String
    let intensity: Double
}

struct StickerItem: Identifiable {
    let id: String // ID estable basado en posición y tipo
    let image: UIImage  // Para fallback y rendering final
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
    
    // ✅ NUEVAS PROPIEDADES para GIFs animados
    let gifURL: URL?  // URL del GIF para mostrar animado
    let isAnimated: Bool  // Flag para saber si es GIF
    
    let type: StickerType
    let interactionData: StickerInteractionData?
    
    enum StickerType {
        case emoji
        case sticker
        case mention
        case hashtag
        case location
        case poll
        case question
        case questionResponse
        case generic
        case weather
        case time
        case selfie
    }
    
    struct StickerInteractionData {
        let username: String?
        let userId: String?
        let hashtag: String?
        let location: String?
        let locationCoordinate: CLLocationCoordinate2D?
        let pollData: [String]?
        let questionText: String?
        let weatherSymbol: String?
    }
    
    // ✅ INICIALIZADORES ACTUALIZADOS
    init(image: UIImage, position: CGPoint, type: StickerType, interactionData: StickerInteractionData?) {
        self.id = "\(type.rawValue)_\(Int(position.x))_\(Int(position.y))"
        self.image = image
        self.position = position
        self.type = type
        self.interactionData = interactionData
        self.gifURL = nil
        self.isAnimated = false
    }
    
    // ✅ NUEVO INICIALIZADOR para GIFs
    init(image: UIImage, gifURL: URL, position: CGPoint, type: StickerType, interactionData: StickerInteractionData?) {
        self.id = "\(type.rawValue)_\(Int(position.x))_\(Int(position.y))"
        self.image = image
        self.position = position
        self.type = type
        self.interactionData = interactionData
        self.gifURL = gifURL
        self.isAnimated = true
    }
}

// MARK: - Camera Preview UIViewRepresentable
struct CameraPreviewRepresentable: UIViewRepresentable {
    @Binding var cameraPosition: AVCaptureDevice.Position
    @Binding var flashMode: AVCaptureDevice.FlashMode
    @Binding var isRecording: Bool
    @Binding var zoomLevel: CGFloat
    @Binding var capturePhotoTrigger: Bool
    
    let onImageCaptured: (UIImage) -> Void
    let onVideoCaptured: (URL) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let preview = CameraPreviewView()
        preview.delegate = context.coordinator
        return preview
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updateCameraPosition(cameraPosition)
        uiView.updateFlashMode(flashMode)
        uiView.updateZoom(zoomLevel)
        
        // Handle photo capture trigger
        if capturePhotoTrigger != context.coordinator.lastCaptureState {
            context.coordinator.lastCaptureState = capturePhotoTrigger
            uiView.capturePhoto()
        }
        
        if isRecording && !uiView.isCurrentlyRecording {
            uiView.startRecording()
        } else if !isRecording && uiView.isCurrentlyRecording {
            uiView.stopRecording()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreviewRepresentable
        var lastCaptureState: Bool = false
        
        init(_ parent: CameraPreviewRepresentable) {
            self.parent = parent
        }
    }
}
