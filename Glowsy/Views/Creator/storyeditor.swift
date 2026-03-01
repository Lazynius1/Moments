import UIKit
import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth

// MARK: - Editable Image View
struct EditableImageView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    let filteredImage: UIImage?
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastRotation: Angle = .zero
    
    // ✅ Fix: Use physical screen size to match Viewer and avoid Safe Area interpolation issues
    private let screenSize = UIScreen.main.bounds.size
    
    init(image: UIImage, scale: Binding<CGFloat>, offset: Binding<CGSize>, rotation: Binding<Angle>, filteredImage: UIImage? = nil) {
        self.image = image
        self._scale = scale
        self._offset = offset
        self._rotation = rotation
        self.filteredImage = filteredImage
    }
    
    var displayImage: UIImage {
        filteredImage ?? image
    }
    
    var body: some View {
        ZStack {
            // ✅ Fondo con imagen original blur (usando blur nativo de SwiftUI)
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenSize.width, height: screenSize.height)
                .blur(radius: 20)
                .scaleEffect(1.1) // Ligeramente más grande para evitar bordes
            
            // ✅ Imagen editable en primer plano
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: {
                    let imageRatio = displayImage.size.width / displayImage.size.height
                    let isHorizontal = imageRatio > 1.0
                    return isHorizontal ? .fit : .fill
                }())
                // .scaleEffect(scale)           // COMENTADO: Zoom manual
                // .offset(offset)              // COMENTADO: Movimiento manual
                // .rotationEffect(rotation)    // COMENTADO: Rotación manual
        }
        .frame(width: screenSize.width, height: screenSize.height) // Ensure ZStack fills screen
    }
}

// MARK: - Story Editing View with Video Preview
struct StoryEditingView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem?
    
    // 🔗 NUEVO: Parámetros de cadena
    let initialChainId: String?
    let initialChainTitle: String?
    let initialChainPosition: Int?
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
    @Environment(\.colorScheme) var colorScheme
    @State private var showingAudienceSelector = false
    @State private var selectedTextStyle: TextStyle = .modern
    @State private var drawingImage: UIImage?
    @State private var editableImageViewRef: EditableImageView?
    
    // ✅ Filtros e Intensidad
    @State private var filterIntensity: Double = 1.0
    @State private var isApplyingFilter = false
    @State private var showingIntensitySlider = false
    @State private var showingFilterToolbar = false
    
    
    // ✅ Variables para transformaciones de imagen
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var imageRotation: Angle = .zero
    
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []
    @State private var forceUpdate: Bool = false
    
    // ✅ Filtros
    @State private var selectedFilter: FilterService.FilterType = .normal
    @State private var filteredImage: UIImage? = nil
    @State private var filterTask: Task<Void, Never>? = nil
    
    // ✅ PROPIEDADES para navegación
    @State private var showingUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var navigationPath = NavigationPath()
    

    
    @State private var showingLocationMap = false
    @State private var selectedLocationName = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    // 🔗 NUEVAS VARIABLES para Story Chains
    @State private var isCreatingChain = false
    @State private var chainTitle = ""
    @State private var chainId: String? = nil
    @State private var chainPosition: Int? = nil
    @State private var isContinuingChain = false
    @State private var originalChainTitle = ""
    @FocusState private var isChainTitleFocused: Bool
    
    // 🔗 NUEVAS VARIABLES para configuración de cadenas
    @State private var allowOthersToContinue = true
    @State private var continuationAudience: ChainContinuationSetting = .everyone
    @State private var showingChainConfiguration = false

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
                backgroundMediaView()
                
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
                    onNavigateToLocation: { locationName, coordinate in
                        handleLocationNavigation(locationName: locationName, coordinate: coordinate)
                    }
                )
                .id(forceUpdate)
                .ignoresSafeArea()

                // Controls
                VStack {
                    topBarView()
                    
                    HStack {
                        Spacer()
                        sideToolbarView()
                    }
                    
                    Spacer()
                    
                    // Video playback controls
                    if let firstMedia = selectedMediaItems.first, firstMedia.type == .video {
                        VideoControlsOverlay()
                    }
                    
                    bottomControlsView()
                }
            }
            .navigationDestination(for: String.self) { userId in
                UserProfileView(userId: userId)
            }
        .onAppear {
            loadUserDefaultAudienceSettings()
            setupStickerListener()
            setupChainContextListener()
            
            // ✅ AGREGAR STICKER INICIAL SI EXISTE
            if let initialSticker = initialSticker {
                selectedStickers.append(initialSticker)
            }
            
            // 🔗 NUEVO: Configurar contexto de cadena si se pasan parámetros
            if let chainId = initialChainId,
               let chainTitle = initialChainTitle,
               let chainPosition = initialChainPosition {
                setChainContext(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
            }
            
            // Inicializar filtro si es necesario
            if filteredImage == nil && selectedFilter != .normal {
                applySelectedFilter()
            }
        }
            .onDisappear {
                removeStickerListener()
                removeChainContextListener()
            }
        }
        // ✅ Input inferior para título de cadena
        .safeAreaInset(edge: .bottom) {
            if isCreatingChain {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundColor(.blue)
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                    
                    TextField(NSLocalizedString("storyChains.chainTitlePlaceholder", comment: "Chain title placeholder"), text: $chainTitle)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($isChainTitleFocused)
                    
                    Button(action: { isChainTitleFocused = false }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .liquidGlass(in: Rectangle())
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
            .presentationBackground(.clear)
        }
        // 🔗 NUEVO: Sheet de configuración de cadenas
        .sheet(isPresented: $showingChainConfiguration) {
            ChainConfigurationView(
                allowOthersToContinue: $allowOthersToContinue,
                continuationAudience: $continuationAudience,
                selectedListId: $selectedListId,
                selectedListName: $selectedListName,
                customSelectedUsers: $customSelectedUsers,
                isContinuing: isContinuingChain,
                onConfirm: {
                    // 🔗 PUBLICAR SOLO SI SE CONFIRMA EN EL SHEET
                    publishStory()
                }
            )
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
                        
                        Text("storyEditor.sharing")
                            .foregroundColor(.white)
                    }
                }
            }
        )
        .alert(alertMessage, isPresented: $showAlert) {
            Button(NSLocalizedString("storyEditor.ok", comment: "OK")) { }
        }
        .onDisappear {
            // ✅ Limpiar video y audio cuando se cierra la vista
            cleanupVideoAndAudio()
        }
    }
    
    // ✅ FUNCIÓN PARA LIMPIAR VIDEO Y AUDIO
    private func cleanupVideoAndAudio() {
        // ✅ Pausar y limpiar el reproductor de video
        if let videoURL = selectedMediaItems.first?.videoURL {
            // ✅ Notificar al PlayerUIView que debe limpiar el video
            NotificationCenter.default.post(
                name: NSNotification.Name("CleanupVideoPlayer"),
                object: videoURL
            )
        }
        
        // ✅ Limpiar los media items seleccionados
        selectedMediaItems.removeAll()
        
        // ✅ Pausar cualquier audio que esté reproduciéndose
        try? AVAudioSession.sharedInstance().setActive(false)
        
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
                let count = customSelectedUsers.count
                if count == 1 {
                    return String(format: NSLocalizedString("storyEditor.customAudience.single", comment: "1 person"), count)
                } else {
                    return String(format: NSLocalizedString("storyEditor.customAudience.multiple", comment: "%d people"), count)
                }
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
                case .onlyMe: return .onlyMe
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: storyAudience = .everyone
                case .connections: storyAudience = .mutuals
                case .bestFriends: storyAudience = .bestFriends
                case .custom: storyAudience = .custom
                case .customList: storyAudience = .custom
                case .onlyMe: storyAudience = .onlyMe
                }
            }
        )
    }
    
    private func updateAudienceSetting() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Convertir AudienceSetting → rawValue de ContentAudience para guardar
        let audienceRaw: String
        switch storyAudience {
        case .everyone:     audienceRaw = ContentAudience.everyone.rawValue
        case .mutuals:      audienceRaw = ContentAudience.connections.rawValue
        case .admirers:     audienceRaw = ContentAudience.connections.rawValue
        case .bestFriends:  audienceRaw = ContentAudience.bestFriends.rawValue
        case .custom:       audienceRaw = (selectedListId != nil) ? ContentAudience.customList.rawValue : ContentAudience.custom.rawValue
        case .onlyMe:       audienceRaw = ContentAudience.onlyMe.rawValue
        }

        var update: [String: Any] = [
            "contentVisibilitySettings.storyAudience": audienceRaw
        ]
        if let listId = selectedListId {
            update["contentVisibilitySettings.storyCustomListId"] = listId
            update["contentVisibilitySettings.storyCustomListName"] = selectedListName ?? ""
        }
        if !customSelectedUsers.isEmpty {
            update["contentVisibilitySettings.storyCustomUsers"] = customSelectedUsers
        }

        FirestoreService().db.collection("users").document(userId).updateData(update)
    }
    
    // 🔗 NUEVA FUNCIÓN: Convertir audiencia de continuación a ContentAudience
    private func convertContinuationAudience() -> ContentAudience {
        switch continuationAudience {
        case .everyone: return .everyone
        case .connections: return .connections
        case .bestFriends: return .bestFriends
        case .custom: return .custom
        case .customList: return .customList
        }
    }
    
    @ViewBuilder
    private func backgroundMediaView() -> some View {
        if let firstMedia = selectedMediaItems.first {
            if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                let isHorizontalVideo = firstMedia.image.size.width > firstMedia.image.size.height
                ZStack {
                    StoryVideoPlayerView(videoURL: videoURL, videoGravity: .resizeAspectFill)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .blur(radius: 20)
                        .scaleEffect(1.1)
                        .clipped()
                        .ignoresSafeArea()
                    
                    StoryVideoPlayerView(
                        videoURL: videoURL,
                        videoGravity: isHorizontalVideo ? .resizeAspect : .resizeAspectFill
                    )
                        .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.height)
                        .clipped()
                        .ignoresSafeArea()
                }
            } else {
                EditableImageView(
                    image: firstMedia.image,
                    scale: $imageScale,
                    offset: $imageOffset,
                    rotation: $imageRotation,
                    filteredImage: filteredImage
                )
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea()
                .onChange(of: selectedFilter) { _ in
                    applySelectedFilter()
                }
            }
        } else {
            // ✅ Fondo por defecto cuando se comparte un sticker (ej. share to story)
            LinearGradient(
                colors: [
                    Color(hex: "4158D0") ?? .blue,
                    Color(hex: "C850C0") ?? .purple,
                    Color(hex: "FFCC70") ?? .pink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private func topBarView() -> some View {
        HStack {
            Button(action: {
                currentFlow = .storyCamera
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .liquidGlass(in: Circle())
            }
            Spacer()
            Button(action: { saveToGallery() }) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .liquidGlass(in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 40)
    }
    
    @ViewBuilder
    private func sideToolbarView() -> some View {
        VStack(spacing: 12) {
            EditingToolIcon(icon: "textformat.alt") { showingTextEditor = true }
            EditingToolIcon(icon: "face.smiling") { showingStickerPicker = true }
            EditingToolIcon(icon: "scribble") { showingDrawing = true }
            
            Button(action: {
                withAnimation(.spring()) { showingFilterToolbar.toggle() }
            }) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 20))
                    .foregroundColor(showingFilterToolbar ? .pink : .white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle())
                    .overlay(Circle().stroke(showingFilterToolbar ? Color.pink : Color.clear, lineWidth: 1))
            }
            
            if !isContinuingChain {
                Button(action: {
                    withAnimation(.spring()) { isCreatingChain.toggle() }
                }) {
                    Image(systemName: "link")
                        .font(.system(size: 20))
                        .foregroundColor(isCreatingChain ? .blue : .white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                        .overlay(Circle().stroke(isCreatingChain ? Color.blue : Color.clear, lineWidth: 1))
                }
            }
        }
        .padding(.trailing, 16)
    }
    
    @ViewBuilder
    private func bottomControlsView() -> some View {
        VStack(spacing: 12) {
            if showingFilterToolbar {
                // Intensity Slider
                if selectedFilter != .normal && showingIntensitySlider {
                    VStack(spacing: 4) {
                        Text("\(Int(filterIntensity * 100))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .liquidGlass(in: Capsule())
                        
                        Slider(value: $filterIntensity, in: 0...1.0)
                            .accentColor(.white)
                            .padding(.horizontal, 40)
                            .onChange(of: filterIntensity) { _ in
                                applySelectedFilter()
                            }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Swipeable Filter Selector
                if selectedMediaItems.first?.type == .image {
                    FilterSelectorView(selectedFilter: $selectedFilter, baseImage: selectedMediaItems.first?.image)
                        .onChange(of: selectedFilter) { _ in
                            if selectedFilter != .normal {
                                withAnimation(.spring()) {
                                    showingIntensitySlider = true
                                }
                            } else {
                                withAnimation(.spring()) {
                                    showingIntensitySlider = false
                                }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // 🔗 Texto informativo de continuando cadena
            if isContinuingChain {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                    
                    Text("Continuando cadena: \(originalChainTitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
            
            HStack {
                // Story settings
                if !isCreatingChain && !isContinuingChain {
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
                            
                            Text(isLoadingUserSettings ? NSLocalizedString("storyEditor.loadingSettings", comment: "Loading user settings") : getAudienceText())
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .liquidGlass(in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            
                Spacer()
                
                // Botón de acción principal
                principalActionButton()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, isCreatingChain ? 115 : 35)
    }
    
    @ViewBuilder
    private func principalActionButton() -> some View {
        if isContinuingChain {
            // 🔗 BOTÓN DIRECTO PARA COLABORADORES (Sin configuración)
            Button(action: {
                publishStory()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    
                    Text(NSLocalizedString("storyChains.shareChain", comment: "Share Chain"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        // Fondo glassmorphism con gradiente premium
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(Capsule())
                        
                        // Efecto glassmorphism
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .disabled(isPublishing || isLoadingUserSettings)
        } else if isCreatingChain {
            // 🔗 BOTÓN DE CONFIGURACIÓN PARA EL AUTOR ORIGINAL
            Button(action: {
                showingChainConfiguration = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("Configuración")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(isLoadingUserSettings ? 0.5 : 1.0)
                )
                .clipShape(Capsule())
            }
            .disabled(isPublishing || isLoadingUserSettings)
        } else {
            // 🎬 BOTÓN DE PUBLICAR HISTORIA NORMAL
            Button(action: {
                publishStory()
            }) {
                HStack(spacing: 8) {
                    Text("storyEditor.share")
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
    }
    
    // ✅ Filtros: Aplicación asíncrona optimizada (Cancela tareas previas para evitar lag)
    private func applySelectedFilter() {
        guard let firstMedia = selectedMediaItems.first, firstMedia.type == .image else {
            filteredImage = nil
            return
        }
        
        if selectedFilter == .normal {
            filteredImage = nil
            return
        }
        
        isApplyingFilter = true
        
        // Cancelar la tarea anterior si existe para evitar acumulación de procesamiento
        filterTask?.cancel()
        
        // Crear nueva tarea
        filterTask = Task.detached(priority: .userInitiated) {
            // Pequeño retardo opcional si el slider se mueve demasiado rápido (debouncing)
            // try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            
            if Task.isCancelled { return }
            
            let optimizedImage = firstMedia.image
            let filtered = FilterService.shared.applyFilter(selectedFilter, to: optimizedImage, intensity: filterIntensity)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.filteredImage = filtered
                self.isApplyingFilter = false
            }
        }
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
                            self.storyAudience = .onlyMe
                        }
                    }
                }
                self.isLoadingUserSettings = false
            }
        }
    }
    
    private func handleProfileNavigation(userId: String) {
        
        if let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId {
            return
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        navigationPath.append(userId)
    }
    
    private func handleLocationNavigation(locationName: String, coordinate: CLLocationCoordinate2D?) {
        
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
        
        alertMessage = NSLocalizedString("storyEditor.savedToGallery", comment: "Story saved to gallery")
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
        guard let firstMedia = selectedMediaItems.first else {
            return UIImage()
        }
        
        let baseImage: UIImage = firstMedia.image
        
        // ✅ RESOLUCIÓN COMPLETAMENTE DINÁMICA: Mantener el aspect ratio original siempre
        // Bloqueamos el ancho a 1080 (HD) y calculamos la altura según el contenido
        let baseWidth = baseImage.size.width
        let baseHeight = baseImage.size.height
        let contentAspectRatio = baseWidth / baseHeight
        
        // Calculamos el alto objetivo manteniendo el ratio (HD)
        let targetHeight = 1080 / contentAspectRatio
        var targetSize = CGSize(width: 1080, height: targetHeight)
        
        // Sanity check: Si por alguna razón el ratio es absurdo, limitamos para evitar accidentes
        if targetHeight > 3000 { targetSize.height = 3000 }
        if targetHeight < 500 { targetSize.height = 500 }
        
        let screenSize = UIScreen.main.bounds.size
        
        // scaling factors
        let scaleFactorX = targetSize.width / screenSize.width
        let scaleFactorY = targetSize.height / screenSize.height
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            
            // 1. Optimized background blur
            // We downscale the image significantly before blurring to save memory and CPU
            let blurRadius: CGFloat = 20
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            
            // scale down for blur (much faster and less memory)
            let smallSize = CGSize(width: 200, height: 200 * (targetSize.height / targetSize.width))
            let smallRect = CGRect(origin: .zero, size: smallSize)
            
            let smallRenderer = UIGraphicsImageRenderer(size: smallSize)
            let smallImage = smallRenderer.image { _ in
                baseImage.draw(in: smallRect)
            }
            
            let ciImage = CIImage(image: smallImage)
            if let ciImage = ciImage,
               let clampFilter = CIFilter(name: "CIAffineClamp"),
               let blurFilter = CIFilter(name: "CIGaussianBlur") {
                
                // 1. Extend edges to infinity to avoid sampling transparency at borders
                clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
                let clampedImage = clampFilter.outputImage
                
                // 2. Apply blur
                blurFilter.setValue(clampedImage, forKey: kCIInputImageKey)
                blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
                
                // 3. Crop back to original small size and render
                if let outputImage = blurFilter.outputImage?.cropped(to: ciImage.extent),
                   let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) {
                    let blurImage = UIImage(cgImage: cgImage)
                    
                    // 4. Draw slightly larger than canvas (overscale) to guarantee no gaps
                    let overscale: CGFloat = 1.05
                    let overscaleRect = CGRect(
                        x: -(targetSize.width * (overscale - 1) / 2),
                        y: -(targetSize.height * (overscale - 1) / 2),
                        width: targetSize.width * overscale,
                        height: targetSize.height * overscale
                    )
                    blurImage.draw(in: overscaleRect)
                }
            } else {
                // Fallback: solid color or just the image
                UIColor.black.setFill()
                UIRectFill(rect)
            }
            
            // Apply selected filter if any
            let renderImage: UIImage
            if selectedFilter != .normal {
                renderImage = FilterService.shared.applyFilter(selectedFilter, to: baseImage, intensity: filterIntensity)
            } else {
                renderImage = baseImage
            }
            
            // 2. Main content rendering
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            
            if firstMedia.type != .video {
                // images use full transformations
                context.cgContext.rotate(by: imageRotation.radians)
                context.cgContext.scaleBy(x: imageScale, y: imageScale)
                
                let offsetX = imageOffset.width * scaleFactorX
                let offsetY = imageOffset.height * scaleFactorY
                context.cgContext.translateBy(x: offsetX, y: offsetY)
            }
            
            // Draw image scaled to fit/fill
            let imageRatio = renderImage.size.width / renderImage.size.height
            let targetRatio = targetSize.width / targetSize.height
            
            let finalWidth: CGFloat
            let finalHeight: CGFloat
            
            if imageRatio > targetRatio {
                // Horizontal image
                finalWidth = targetSize.width
                finalHeight = targetSize.width / imageRatio
            } else {
                // Vertical image
                finalHeight = targetSize.height
                finalWidth = targetSize.height * imageRatio
            }
            
            let imageRect = CGRect(
                x: -finalWidth / 2,
                y: -finalHeight / 2,
                width: finalWidth,
                height: finalHeight
            )
            renderImage.draw(in: imageRect)
            
            context.cgContext.restoreGState()
            
            // 3. Drawing overlay
            if let drawing = drawingImage {
                drawing.draw(in: rect, blendMode: .normal, alpha: 1.0)
            }
            
            // 4. Text overlay
            if !storyText.isEmpty {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let baseFontSize: CGFloat = 28
                let scaledFontSize = baseFontSize * max(scaleFactorX, scaleFactorY)
                
                let font: UIFont
                switch selectedTextStyle {
                case .modern: font = UIFont.systemFont(ofSize: scaledFontSize, weight: .medium)
                case .classic: font = UIFont(name: "Georgia", size: scaledFontSize - 2) ?? .systemFont(ofSize: scaledFontSize)
                case .neon: font = UIFont.systemFont(ofSize: scaledFontSize + 2, weight: .black)
                case .typewriter: font = UIFont(name: "Courier New", size: scaledFontSize - 4) ?? .systemFont(ofSize: scaledFontSize)
                case .bold: font = UIFont.systemFont(ofSize: scaledFontSize + 4, weight: .heavy)
                }
                
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
                case .modern, .neon, .typewriter:
                    let bgColor: UIColor = {
                        switch selectedTextStyle {
                        case .modern: return .black.withAlphaComponent(0.6)
                        case .neon: return .purple.withAlphaComponent(0.8)
                        case .typewriter: return .gray.withAlphaComponent(0.7)
                        default: return .clear
                        }
                    }()
                    bgColor.setFill()
                    let backgroundRect = textRect.insetBy(dx: -16 * scaleFactor, dy: -8 * scaleFactor)
                    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8 * scaleFactor).fill()
                default: break
                }
                
                storyText.draw(in: textRect, withAttributes: attributes)
            }
            
            // 5. Stickers overlay
            // ✅ FIX: No renderizar NINGÚN sticker en la imagen de fondo
            // Los stickers se añaden como metadatos interactivos y se renderizan en el visor
            // Si los dibujamos aquí, aparecerán dobles (uno estático y uno interactivo)
            /*
            for sticker in selectedStickers {
                // interactive stickers (mentions, etc.) are handled by metadata, not drawn on the static image
                if sticker.type == .mention || sticker.type == .poll || sticker.type == .question || 
                   sticker.type == .location || sticker.type == .hashtag || sticker.type == .weather {
                    continue
                }
                
                context.cgContext.saveGState()
                
                let scaledPosition = CGPoint(
                    x: sticker.position.x * scaleFactorX,
                    y: sticker.position.y * scaleFactorY
                )
                
                let stickerOriginalSize = sticker.image.size
                let scaledWidth: CGFloat
                let scaledHeight: CGFloat
                let stickerScale = sticker.scale
                
                if sticker.type == .questionResponse {
                    let commonScale = max(scaleFactorX, scaleFactorY) * stickerScale
                    scaledWidth = stickerOriginalSize.width * commonScale
                    scaledHeight = stickerOriginalSize.height * commonScale
                } else {
                    let baseSize = 100 * max(scaleFactorX, scaleFactorY) * stickerScale
                    scaledWidth = baseSize
                    scaledHeight = baseSize
                }
                
                context.cgContext.translateBy(x: scaledPosition.x, y: scaledPosition.y)
                context.cgContext.rotate(by: sticker.rotation.radians)
                
                let stickerRect = CGRect(
                    x: -scaledWidth / 2,
                    y: -scaledHeight / 2,
                    width: scaledWidth,
                    height: scaledHeight
                )
                
                sticker.image.draw(in: stickerRect)
                
                context.cgContext.restoreGState()
            }
            */
            
        }
    }
    
    // ✅ FUNCIÓN ACTUALIZADA: Publicar historia con soporte para listas
    private func publishStory() {
        guard let userId = Auth.auth().currentUser?.uid,
              let media = selectedMediaItems.first else { return }
        
        // 🔗 VALIDAR LÍMITES DE STORY CHAINS
        Task {
            do {
                if isCreatingChain {
                    // Validar título de nueva cadena
                    try StoryChainLimitsService.shared.validateChainTitle(chainTitle)
                } else if isContinuingChain, let existingChainId = chainId {
                    // Validar que se puede continuar la cadena
                    try await StoryChainLimitsService.shared.canContinueChain(chainId: existingChainId, userId: userId)
                }
                
                // Continuar con la publicación
                await MainActor.run {
                    publishStoryAfterValidation()
                }
            } catch {
                await MainActor.run {
                    handleChainLimitError(error)
                }
            }
        }
    }
    
    private func publishStoryAfterValidation() {
        guard let userId = Auth.auth().currentUser?.uid,
              let media = selectedMediaItems.first else { return }
        
        // 🔥 RENDERIZAR IMAGEN FINAL CON OVERLAYS
        let finalRenderedImage = renderStoryWithOverlays()
        
        // 🔥 PREPARAR DATOS DE STICKERS - PASAR StickerItem DIRECTAMENTE
        let stickerData = selectedStickers
        
        // 🔥 PREPARAR DRAWING DATA
        let drawingData = drawingImage?.pngData()
        
        // 🔗 MANEJAR STORY CHAINS
        var finalChainId: String? = nil
        var finalChainPosition: Int? = nil
        var finalChainTitle: String? = nil
        
        if isCreatingChain && !chainTitle.isEmpty {
            // Crear nueva cadena
            finalChainId = UUID().uuidString
            finalChainPosition = 1
            finalChainTitle = chainTitle
        } else if isContinuingChain, let existingChainId = chainId {
            // Continuar cadena existente
            finalChainId = existingChainId
            finalChainPosition = (chainPosition ?? 0) + 1
            finalChainTitle = originalChainTitle
        }
        
        // 🔥 CONVERTIR storyAudience (CaptionAndDetailsView.AudienceSetting) a ContentAudience
        // 🔗 STORY CHAINS: Las cadenas siempre son visibles para todos, pero la audiencia determina quién puede continuar
        let contentAudience: ContentAudience = {
            if isCreatingChain || isContinuingChain {
                // Para cadenas, siempre "everyone" para visibilidad
                return .everyone
            } else {
                // Para historias normales, usar la audiencia seleccionada
                switch storyAudience {
                case .everyone: return .everyone
                case .mutuals: return .connections
                case .admirers: return .connections
                case .bestFriends: return .bestFriends
                case .custom: return selectedListId != nil ? .customList : .custom
                case .onlyMe: return .onlyMe
                }
            }
        }()
        
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
            finalRenderedImage: finalRenderedImage,
            chainId: finalChainId, // 🔗 AÑADIDO: Pasar ID de la cadena
            chainPosition: finalChainPosition, // 🔗 AÑADIDO: Pasar posición en la cadena
            chainTitle: finalChainTitle, // 🔗 AÑADIDO: Pasar título de la cadena
            allowOthersToContinue: (isCreatingChain || isContinuingChain) ? allowOthersToContinue : nil, // 🔗 AÑADIDO: Configuración de continuación
            continuationAudience: (isCreatingChain || isContinuingChain) ? convertContinuationAudience() : nil, // 🔗 AÑADIDO: Audiencia de continuación
            continuationCustomViewers: (isCreatingChain || isContinuingChain) ? customSelectedUsers : nil, // 🔗 AÑADIDO: Usuarios específicos de continuación
            continuationCustomListId: (isCreatingChain || isContinuingChain) ? selectedListId : nil, // 🔗 AÑADIDO: Lista específica de continuación
            continuationCustomListName: (isCreatingChain || isContinuingChain) ? selectedListName : nil // 🔗 AÑADIDO: Nombre de lista de continuación
        )
        
        if success {
            // 🔥 CERRAR PANTALLA INMEDIATAMENTE
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCreatorView = false
                
                
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
            
            // Feedback háptico de error
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
            
            // Mostrar error
            alertMessage = NSLocalizedString("storyEditor.error.publishStart", comment: "Error starting story upload")
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
        
    }
    
    // 🔗 MANEJAR ERRORES DE LÍMITES DE STORY CHAINS
    private func handleChainLimitError(_ error: Error) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
        
        if let chainError = error as? StoryChainLimitError {
            alertMessage = chainError.localizedDescription
        } else {
            alertMessage = String(format: NSLocalizedString("storyChains.error.validation", comment: "Error validating chain"), error.localizedDescription)
        }
        
        showAlert = true
        
        // Limpiar estado de cadena si hay error
        if isContinuingChain {
            isContinuingChain = false
            chainId = nil
            chainPosition = nil
            originalChainTitle = ""
        }
    }
    
    // ✅ ENVIAR NOTIFICACIONES DE MENCIONES DESPUÉS DE PUBLICAR HISTORIA
    private func sendMentionNotificationsAfterPublish(stickerData: [StickerItem]) {
        // ✅ Filtrar solo stickers de menciones
        let mentionStickers = stickerData.filter { $0.type == .mention }
        
        if !mentionStickers.isEmpty {
            
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
        case .shareMoment: // ✅ CORREGIDO: Usar shareMoment en lugar de moment
            if let momentId = interactionData.momentId, let mediaCount = interactionData.mediaCount {
                return "Moment ID: \(momentId), Media Count: \(mediaCount)"
            }
            return ""
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
    
    // MARK: - Chain Context Handling
    private func setupChainContextListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetChainContext"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                setChainContext(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
            }
        }
    }
    
    private func removeChainContextListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("SetChainContext"),
            object: nil
        )
    }
    
    private func setChainContext(chainId: String, chainTitle: String, chainPosition: Int) {
        // Configurar variables de cadena
        self.chainId = chainId
        self.chainTitle = chainTitle
        self.chainPosition = chainPosition
        self.isContinuingChain = true
        self.originalChainTitle = chainTitle
        
        // Mantener audiencia seleccionada por el usuario (no forzar)
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

// MARK: - Image Optimization Extensions
extension StoryEditingView {
    
    // ✅ FUNCIÓN: Optimizar imagen para historias
    private func optimizeImageForStory(_ image: UIImage) -> UIImage {
        // Normalizamos orientación siempre
        let normalizedImage = image.normalized()
        
        // Capped dimension for memory - Stories are typically 1080x1920
        // Using 1440 for high quality but much less memory than camera resolution
        let maxDimension: CGFloat = 1440
        
        if normalizedImage.size.width > maxDimension || normalizedImage.size.height > maxDimension {
            return calculateOptimalSize(for: normalizedImage, maxDimension: maxDimension)
        }
        
        return normalizedImage
    }
    
    // ✅ FUNCIÓN: Calcular tamaño óptimo para redimensionar
    private func calculateOptimalSize(for image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let widthRatio = maxDimension / originalSize.width
        let heightRatio = maxDimension / originalSize.height
        let scale = min(widthRatio, heightRatio)
        
        let newWidth = originalSize.width * scale
        let newHeight = originalSize.height * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // ✅ Normalizar orientación después del redimensionamiento
        return resizedImage.normalized()
    }
}

// MARK: - Video Player View
struct StoryVideoPlayerView: UIViewRepresentable {
    let videoURL: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspect // ✅ Default gravity
    
    func makeUIView(context: Context) -> PlayerUIView {
        let playerView = PlayerUIView()
        playerView.configure(with: videoURL, gravity: videoGravity) // ✅ Pass gravity
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
        backgroundColor = .clear // ✅ Transparent background for blur effect
        
        // ✅ Escuchar notificación para limpiar el video
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CleanupVideoPlayer"),
            object: nil,
            queue: .main
        ) { _ in
            self.cleanupPlayer()
        }
    }
    
    func configure(with url: URL, gravity: AVLayerVideoGravity = .resizeAspect) {
        player = AVPlayer(url: url)
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = gravity // ✅ Use passed gravity
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
    

    
    // ✅ FUNCIÓN PARA LIMPIAR EL REPRODUCTOR
    func cleanupPlayer() {
        // ✅ Pausar el video
        player?.pause()
        
        // ✅ Remover el player layer
        playerLayer?.removeFromSuperlayer()
        
        // ✅ Limpiar referencias
        player = nil
        playerLayer = nil
        
        // ✅ Remover observadores
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        cleanupPlayer()
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
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
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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

struct StickerItem: Identifiable {
    let id: String // ID estable basado en posición y tipo
    let image: UIImage  // Para fallback y rendering final
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero
    
    // ✅ NUEVAS PROPIEDADES para GIFs animados y Videos
    let gifURL: URL?  // URL del GIF para mostrar animado
    let videoURL: URL? // URL del Video para mostrar en loop
    let isAnimated: Bool  // Flag para saber si es GIF o Vídeo Animado
    
    let type: StickerType
    let interactionData: StickerInteractionData?
    
    enum StickerType: String, Codable {
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
        case shareMoment // ✅ NUEVO: Para identificar stickers de compartir momento
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
        let caption: String? // ✅ NUEVO: Para mostrar el pie de foto en compartidos
        let profileImagePath: String? // ✅ NUEVO: Para reconstruir el header en el visor
        let momentId: String? // ✅ NUEVO: Para navegación al detalle
        let mediaCount: Int? // ✅ NUEVO: Para indicador de galería

        // ✅ Inicializador con valores por defecto para evitar errores de compilación masivos
        init(
            username: String? = nil,
            userId: String? = nil,
            hashtag: String? = nil,
            location: String? = nil,
            locationCoordinate: CLLocationCoordinate2D? = nil,
            pollData: [String]? = nil,
            questionText: String? = nil,
            weatherSymbol: String? = nil,
            caption: String? = nil,
            profileImagePath: String? = nil,
            momentId: String? = nil,
            mediaCount: Int? = nil
        ) {
            self.username = username
            self.userId = userId
            self.hashtag = hashtag
            self.location = location
            self.locationCoordinate = locationCoordinate
            self.pollData = pollData
            self.questionText = questionText
            self.weatherSymbol = weatherSymbol
            self.caption = caption
            self.profileImagePath = profileImagePath
            self.momentId = momentId
            self.mediaCount = mediaCount
        }
    }
    
    // ✅ INICIALIZADORES ACTUALIZADOS
    init(image: UIImage, position: CGPoint, type: StickerType, interactionData: StickerInteractionData?, videoURL: URL? = nil, gifURL: URL? = nil) {
        self.id = "\(type)_\(position.x)_\(position.y)"
        self.image = image
        self.position = position
        self.type = type
        self.gifURL = gifURL
        self.videoURL = videoURL
        self.isAnimated = videoURL != nil || gifURL != nil
        self.interactionData = interactionData
    }
    
    // ✅ NUEVO INICIALIZADOR para compatibilidad con GIFs
    init(image: UIImage, gifURL: URL, position: CGPoint, type: StickerType, interactionData: StickerInteractionData?) {
        self.id = "\(type)_\(position.x)_\(position.y)"
        self.image = image
        self.position = position
        self.type = type
        self.gifURL = gifURL
        self.videoURL = nil
        self.isAnimated = true
        self.interactionData = interactionData
    }
    
    init(id: String, image: UIImage, position: CGPoint, scale: CGFloat, rotation: Angle, gifURL: URL?, videoURL: URL? = nil, isAnimated: Bool, type: StickerType, interactionData: StickerInteractionData?) {
        self.id = id
        self.image = image
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.gifURL = gifURL
        self.videoURL = videoURL
        self.isAnimated = isAnimated
        self.type = type
        self.interactionData = interactionData
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
// MARK: - Filter Selector View
struct FilterSelectorView: View {
    @Binding var selectedFilter: FilterService.FilterType
    let baseImage: UIImage?
    
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FilterService.FilterType.allCases, id: \.self) { filterType in
                        FilterItemView(
                            type: filterType,
                            isSelected: selectedFilter == filterType,
                            baseImage: baseImage
                        ) {
                            withAnimation(.spring()) {
                                selectedFilter = filterType
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Text(selectedFilter.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlass(in: Capsule())
        }
        .padding(.bottom, 8)
    }
}

struct FilterItemView: View {
    let type: FilterService.FilterType
    let isSelected: Bool
    let baseImage: UIImage?
    let action: () -> Void
    
    @State private var previewImage: UIImage? = nil
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    }
                }
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: isSelected ? 4 : 0)
                
                Text(type.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            }
        }
        .onAppear {
            generatePreview()
        }
    }
    
    private func generatePreview() {
        guard let base = baseImage else { return }
        
        // Generate a very small thumbnail for the carousel to save memory
        let size = CGSize(width: 60, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }
        
        Task.detached(priority: .background) {
            let filtered = FilterService.shared.applyFilterToThumbnail(type, to: thumb)
            await MainActor.run {
                self.previewImage = filtered
            }
        }
    }
}
