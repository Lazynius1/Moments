import UIKit
import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import PencilKit
import CoreLocation

// MARK: - Editable Image View
struct EditableImageView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    let filteredImage: UIImage?
    let canvasSize: CGSize
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastRotation: Angle = .zero

    init(
        image: UIImage,
        scale: Binding<CGFloat>,
        offset: Binding<CGSize>,
        rotation: Binding<Angle>,
        filteredImage: UIImage? = nil,
        canvasSize: CGSize
    ) {
        self.image = image
        self._scale = scale
        self._offset = offset
        self._rotation = rotation
        self.filteredImage = filteredImage
        self.canvasSize = canvasSize
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
                .frame(width: canvasSize.width, height: canvasSize.height)
                .blur(radius: 20)
                .scaleEffect(1.1) // Ligeramente más grande para evitar bordes
            
            // ✅ Imagen editable en primer plano
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: StoryMediaLayoutRules.presentationMode(for: displayImage.size, canvasSize: canvasSize).swiftUIContentMode)
                // .scaleEffect(scale)           // COMENTADO: Zoom manual
                // .offset(offset)              // COMENTADO: Movimiento manual
                // .rotationEffect(rotation)    // COMENTADO: Rotación manual
        }
        .frame(width: canvasSize.width, height: canvasSize.height) // Ensure ZStack fills screen
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
    @State private var storyTextColor: Color = .white
    @State private var storyTextAlignment: TextAlignment = .center
    @State private var storyTextBackground: TextBackgroundFill = .none
    @State private var storyTextFontSize: CGFloat = 30
    @State private var selectedStickers: [StickerItem] = []
    @State private var activeEditorMode: ActiveEditorMode = .idle
    @State private var showingStickerPicker = false
    @State private var isPublishing = false
    @State private var storyAudience: CaptionAndDetailsView.AudienceSetting = .everyone
    @State private var isLoadingUserSettings = true // NUEVO
    @Environment(\.colorScheme) var colorScheme
    @State private var showingAudienceSelector = false
    @State private var selectedTextStyle: TextStyle = .modern
    @State private var selectedTextEffect: TextEffect = .none
    @State private var drawingImage: UIImage?
    @State private var editableImageViewRef: EditableImageView?
    
    // ✅ Filtros e Intensidad
    @State private var filterIntensity: Double = 1.0
    @State private var isApplyingFilter = false
    @State private var showingIntensitySlider = false
    @State private var isEditingSticker = false // ✅ NUEVO
    
    
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
    @State private var keyboardHeight: CGFloat = 0
    
    // 🔗 NUEVAS VARIABLES para configuración de cadenas
    @State private var allowOthersToContinue = true
    @State private var continuationAudience: ChainContinuationSetting = .everyone
    @State private var showingChainConfiguration = false
    @State private var primaryVideoAspectRatio: CGFloat? = nil

    enum TextStyle: String, CaseIterable {
        case modern
        case classic
        case poster
        case editorial
        case rounded
        case signature
        case marker
        case typewriter
        case handwritten
        case bold
        case neon
        case chalk

        var displayName: String {
            switch self {
            case .modern: return "Modern"
            case .classic: return "Classic"
            case .poster: return "Poster"
            case .editorial: return "Editorial"
            case .rounded: return "Rounded"
            case .signature: return "Signature"
            case .marker: return "Marker"
            case .typewriter: return "Typewriter"
            case .handwritten: return "Handwritten"
            case .bold: return "Bold"
            case .neon: return "Neon"
            case .chalk: return "Chalk"
            }
        }

        static var fontPickerStyles: [TextStyle] {
            [.modern, .classic, .editorial, .rounded, .signature, .typewriter, .handwritten, .bold, .poster]
        }
        
        func font(size: CGFloat) -> Font {
            switch self {
            case .modern: return .system(size: size, weight: .medium)
            case .classic: return .custom("Georgia", size: max(12, size - 1))
            case .poster: return .custom("Futura-CondensedExtraBold", size: size + 5)
            case .editorial: return .custom("Didot", size: size + 1)
            case .rounded: return .custom("ArialRoundedMTBold", size: size)
            case .signature: return .custom("SnellRoundhand", size: size + 6)
            case .marker: return .custom("MarkerFelt-Wide", size: size + 2)
            case .typewriter: return .custom("Courier New", size: max(12, size - 3))
            case .handwritten: return .custom("Noteworthy-Bold", size: size + 2)
            case .bold: return .custom("AvenirNextCondensed-DemiBold", size: size + 4)
            case .neon: return .system(size: size + 2, weight: .black)
            case .chalk: return .custom("ChalkboardSE-Bold", size: size + 1)
            }
        }

        func uiFont(size: CGFloat) -> UIFont {
            switch self {
            case .modern:
                return .systemFont(ofSize: size, weight: .medium)
            case .classic:
                return UIFont(name: "Georgia", size: max(12, size - 1)) ?? .systemFont(ofSize: size)
            case .poster:
                return UIFont(name: "Futura-CondensedExtraBold", size: size + 5) ?? .boldSystemFont(ofSize: size + 5)
            case .editorial:
                return UIFont(name: "Didot", size: size + 1) ?? .systemFont(ofSize: size + 1)
            case .rounded:
                return UIFont(name: "ArialRoundedMTBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
            case .signature:
                return UIFont(name: "SnellRoundhand", size: size + 6) ?? .italicSystemFont(ofSize: size + 4)
            case .marker:
                return UIFont(name: "MarkerFelt-Wide", size: size + 2) ?? .systemFont(ofSize: size + 2, weight: .bold)
            case .typewriter:
                return UIFont(name: "Courier New", size: max(12, size - 3)) ?? .monospacedSystemFont(ofSize: size - 2, weight: .regular)
            case .handwritten:
                return UIFont(name: "Noteworthy-Bold", size: size + 2) ?? .systemFont(ofSize: size + 2, weight: .semibold)
            case .bold:
                return UIFont(name: "AvenirNextCondensed-DemiBold", size: size + 4) ?? .systemFont(ofSize: size + 4, weight: .heavy)
            case .neon:
                return .systemFont(ofSize: size + 2, weight: .black)
            case .chalk:
                return UIFont(name: "ChalkboardSE-Bold", size: size + 1) ?? .systemFont(ofSize: size + 1, weight: .bold)
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .modern: return Color.black.opacity(0.6)
            case .classic: return Color.clear
            case .poster: return Color.clear
            case .editorial: return Color.clear
            case .rounded: return Color.black.opacity(0.22)
            case .signature: return Color.clear
            case .marker: return Color.yellow.opacity(0.18)
            case .neon: return Color.purple.opacity(0.8)
            case .typewriter: return Color.gray.opacity(0.55)
            case .handwritten: return Color.clear
            case .bold: return Color.clear
            case .chalk: return Color.black.opacity(0.18)
            }
        }
    }

    enum TextBackgroundFill: String, CaseIterable {
        case none
        case black
        case white
    }

    enum TextEffect: String, CaseIterable {
        case none
        case glow
        case marker
        case chalk

        var displayName: String {
            switch self {
            case .none: return "None"
            case .glow: return "Glow"
            case .marker: return "Marker"
            case .chalk: return "Chalk"
            }
        }

        var backgroundColor: Color? {
            switch self {
            case .marker:
                return Color.yellow.opacity(0.28)
            case .none, .glow, .chalk:
                return nil
            }
        }

        var uiBackgroundColor: UIColor? {
            switch self {
            case .marker:
                return UIColor.systemYellow.withAlphaComponent(0.28)
            case .none, .glow, .chalk:
                return nil
            }
        }

        func shadow(for textColor: Color) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)? {
            switch self {
            case .glow:
                return (textColor.opacity(0.92), 12, 0, 0)
            case .chalk:
                return (Color.black.opacity(0.62), 1.0, 1.0, 1.0)
            case .none, .marker:
                return nil
            }
        }

        func nsShadow(for textColor: UIColor) -> NSShadow? {
            let shadow = NSShadow()
            switch self {
            case .glow:
                shadow.shadowColor = textColor.withAlphaComponent(0.92)
                shadow.shadowBlurRadius = 12
                shadow.shadowOffset = .zero
                return shadow
            case .chalk:
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.62)
                shadow.shadowBlurRadius = 1
                shadow.shadowOffset = CGSize(width: 1, height: 1)
                return shadow
            case .none, .marker:
                return nil
            }
        }
    }

    enum ActiveEditorMode {
        case idle
        case text
        case drawing
        case filters
    }

    private var isTextMode: Bool { activeEditorMode == .text }
    private var isDrawingMode: Bool { activeEditorMode == .drawing }
    private var isFilterMode: Bool { activeEditorMode == .filters }
    private var isCanvasModeActive: Bool { activeEditorMode != .idle }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                let viewportSize = proxy.size
                let mediaCanvasSize = CGSize(
                    width: viewportSize.width,
                    height: viewportSize.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                )
                let mediaCanvasOffsetY = -proxy.safeAreaInsets.top

                ZStack(alignment: .topLeading) {
                    backgroundMediaView(canvasSize: mediaCanvasSize)
                        .offset(y: mediaCanvasOffsetY)
                    
                    // Drawing overlay preview when text editor is open
                    if let drawing = drawingImage, isTextMode {
                        Image(uiImage: drawing)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: mediaCanvasSize.width, height: mediaCanvasSize.height)
                            .offset(y: mediaCanvasOffsetY)
                            .allowsHitTesting(false)
                    }
                    
                    // Overlays
                    if !isTextMode && !isDrawingMode {
                        StoryOverlaysView(
                            text: $storyText,
                            textPosition: $textPosition,
                            textStyle: $selectedTextStyle,
                            textEffect: $selectedTextEffect,
                            textColor: $storyTextColor,
                            textAlignment: $storyTextAlignment,
                            textBackgroundFill: $storyTextBackground,
                            textFontSize: $storyTextFontSize,
                            isTextEditorPresented: Binding(
                                get: { isTextMode },
                                set: { isPresented in
                                    activeEditorMode = isPresented ? .text : .idle
                                }
                            ),
                            stickers: $selectedStickers,
                            drawingImage: $drawingImage,
                            isEditingSticker: $isEditingSticker,
                            onNavigateToProfile: { userId in
                                handleProfileNavigation(userId: userId)
                            },
                            onNavigateToLocation: { locationName, coordinate in
                                handleLocationNavigation(locationName: locationName, coordinate: coordinate)
                            }
                        )
                        .id(forceUpdate)
                        .ignoresSafeArea()
                    }

                    // Controls
                    if !isTextMode && !isDrawingMode {
                        VStack {
                            topBarView(topInset: proxy.safeAreaInsets.top)

                            if activeEditorMode == .idle {
                                HStack {
                                    Spacer()
                                    sideToolbarView()
                                }
                            }
                            
                            Spacer()
                            
                            // Video playback controls
                            if let firstMedia = selectedMediaItems.first, firstMedia.type == .video {
                                VideoControlsOverlay()
                            }
                            
                            bottomControlsView(bottomInset: proxy.safeAreaInsets.bottom)
                        }
                        .opacity(isEditingSticker ? 0 : 1)
                        .disabled(isEditingSticker)
                    }

                    if isDrawingMode {
                        StoryDrawingEditorOverlay(
                            isPresented: Binding(
                                get: { isDrawingMode },
                                set: { isPresented in
                                    activeEditorMode = isPresented ? .drawing : .idle
                                }
                            ),
                            drawingImage: $drawingImage
                        )
                        .zIndex(45)
                    }

                    if isTextMode {
                        StoryTextEditor(
                            isPresented: Binding(
                                get: { isTextMode },
                                set: { isPresented in
                                    activeEditorMode = isPresented ? .text : .idle
                                }
                            ),
                            text: $storyText,
                            selectedStyle: $selectedTextStyle,
                            selectedEffect: $selectedTextEffect,
                            textColor: $storyTextColor,
                            textAlignment: $storyTextAlignment,
                            textBackgroundFill: $storyTextBackground,
                            textFontSize: $storyTextFontSize
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(40)
                    }
                }
                .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                .ignoresSafeArea(.keyboard)
            }
            .navigationDestination(for: String.self) { userId in
                UserProfileView(userId: userId)
            }
            .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadUserDefaultAudienceSettings()
            setupStickerListener()
            setupChainContextListener()
            refreshPrimaryVideoAspectRatio()
            
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
            .onChange(of: selectedMediaItems.first?.id) { _, _ in
                refreshPrimaryVideoAspectRatio()
            }
            .onDisappear {
                removeStickerListener()
                removeChainContextListener()
            }
        }
        .ignoresSafeArea(.keyboard)
        // ✅ Input inferior para título de cadena
        .safeAreaInset(edge: .bottom) {
            if isCreatingChain && !isCanvasModeActive {
                VStack(spacing: 6) {
                    if activeEditorMode == .idle {
                        HStack {
                            Spacer()
                            principalActionButton()
                        }
                        .padding(.horizontal, 16)
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.72))
                                .font(.system(size: 15, weight: .semibold))

                            TextField(NSLocalizedString("storyChains.chainTitlePlaceholder", comment: "Chain title placeholder"), text: $chainTitle)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .tint(colorScheme == .dark ? .white : .black)
                                .focused($isChainTitleFocused)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .liquidGlass(in: Capsule(), interactive: true)

                        Button(action: { isChainTitleFocused = false }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(10)
                                .background((colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.2 : 0.28))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, activeEditorMode == .idle ? 8 : 12)
                    .padding(.bottom, 12)
                    .background(
                        Color.clear
                            .liquidGlass(in: Rectangle())
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
                .padding(.top, 8)
                .padding(.bottom, chainInputBottomPadding())
                .animation(.easeOut(duration: 0.24), value: keyboardHeight)
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                chainTitleSummary: isContinuingChain ? originalChainTitle : chainTitle,
                isContinuing: isContinuingChain,
                onConfirm: {
                    // 🔗 PUBLICAR SOLO SI SE CONFIRMA EN EL SHEET
                    publishStory()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: selectedLocationName,
                coordinate: selectedCoordinate,
                isPresented: $showingLocationMap
            )
        }
        .sheet(isPresented: $showingStickerPicker) {
            StickerPickerView(selectedStickers: $selectedStickers)
                .ignoresSafeArea()
                .onDisappear {
                    activeEditorMode = .idle
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - endFrame.minY)
            let safeBottom = keyWindowSafeAreaInsets().bottom
            keyboardHeight = max(0, overlap - safeBottom)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
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

    private func refreshPrimaryVideoAspectRatio() {
        guard let media = selectedMediaItems.first, media.type == .video, let videoURL = media.videoURL else {
            primaryVideoAspectRatio = nil
            return
        }

        Task {
            let asset = AVURLAsset(url: videoURL)
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await videoTrack.load(.naturalSize),
                  let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
                return
            }

            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let resolvedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
            let aspectRatio = resolvedSize.width / max(resolvedSize.height, 1)

            await MainActor.run {
                if selectedMediaItems.first?.id == media.id {
                    primaryVideoAspectRatio = aspectRatio.isFinite ? aspectRatio : nil
                }
            }
        }
    }
    
    @ViewBuilder
    private func backgroundMediaView(canvasSize: CGSize) -> some View {
        if let firstMedia = selectedMediaItems.first {
            if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                let fallbackAspectRatio = firstMedia.image.size.width / max(firstMedia.image.size.height, 1)
                let mediaAspectRatio = primaryVideoAspectRatio ?? fallbackAspectRatio
                let presentationMode = StoryMediaLayoutRules.presentationMode(
                    for: mediaAspectRatio,
                    canvasAspectRatio: canvasSize.width / max(canvasSize.height, 1)
                )
                ZStack {
                    StoryVideoPlayerView(videoURL: videoURL, videoGravity: .resizeAspectFill)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .blur(radius: 20)
                        .scaleEffect(1.1)
                        .clipped()
                        .ignoresSafeArea()
                    
                    StoryVideoPlayerView(
                        videoURL: videoURL,
                        videoGravity: presentationMode.videoGravity
                    )
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .clipped()
                        .ignoresSafeArea()
                }
            } else {
                EditableImageView(
                    image: firstMedia.image,
                    scale: $imageScale,
                    offset: $imageOffset,
                    rotation: $imageRotation,
                    filteredImage: filteredImage,
                    canvasSize: canvasSize
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
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
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private func topBarView(topInset: CGFloat) -> some View {
        HStack {
            Button(action: {
                if isFilterMode {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        activeEditorMode = .idle
                    }
                } else {
                    currentFlow = .storyCamera
                }
            }) {
                Image(systemName: isFilterMode ? "chevron.left" : "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .liquidGlass(in: Circle())
            }
            Spacer()
            if isFilterMode {
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        activeEditorMode = .idle
                    }
                }) {
                    Text("creator.done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .liquidGlass(in: Capsule())
                }
            } else {
                Button(action: { saveToGallery() }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .liquidGlass(in: Circle())
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, topBarTopPadding(topInset: topInset))
    }
    
    @ViewBuilder
    private func sideToolbarView() -> some View {
        VStack(spacing: 12) {
            EditingToolIcon(icon: "textformat.alt") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    activeEditorMode = .text
                }
            }
            EditingToolIcon(icon: "face.smiling") {
                activeEditorMode = .idle
                showingStickerPicker = true
            }
            EditingToolIcon(icon: "scribble") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    activeEditorMode = .drawing
                }
            }
            
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    activeEditorMode = isFilterMode ? .idle : .filters
                    showingIntensitySlider = selectedFilter != .normal
                }
            }) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 20))
                    .foregroundColor(isFilterMode ? .pink : .white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle())
                    .overlay(Circle().stroke(isFilterMode ? Color.pink : Color.clear, lineWidth: 1))
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
    private func bottomControlsView(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            if isFilterMode {
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

                if selectedMediaItems.first?.type == .image {
                    FilterSelectorView(
                        selectedFilter: $selectedFilter,
                        filters: FilterService.FilterType.allCases,
                        baseImage: selectedMediaItems.first?.image
                    )
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
            
            if activeEditorMode == .idle && !isCreatingChain {
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
        }
        .padding(.horizontal)
        .padding(.bottom, bottomControlsBottomPadding(bottomInset: bottomInset))
    }

    private func bottomControlsBottomPadding(bottomInset: CGFloat) -> CGFloat {
        let resolvedBottomInset = effectiveBottomInset(bottomInset)
        if isFilterMode {
            return max(52, resolvedBottomInset + 30)
        }
        if isCreatingChain {
            // The safeAreaInset already lifts content with the chain input
            // (and with keyboard). Keep only a tiny local gap here.
            return 6
        }
        return max(90, resolvedBottomInset + 54)
    }

    private func topBarTopPadding(topInset: CGFloat) -> CGFloat {
        let resolvedTopInset = effectiveTopInset(topInset)
        // Ensure the top controls sit safely below the notch/dynamic island.
        // Previously this subtracted resolvedTopInset excessively, pushing it too high.
        return max(16, 76 - resolvedTopInset)
    }

    private func effectiveTopInset(_ topInset: CGFloat) -> CGFloat {
        if topInset > 0 { return topInset }
        return keyWindowSafeAreaInsets().top
    }

    private func effectiveBottomInset(_ bottomInset: CGFloat) -> CGFloat {
        if bottomInset > 0 { return bottomInset }
        return keyWindowSafeAreaInsets().bottom
    }

    private func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive }
        let scene = activeScene ?? scenes.first
        let keyWindow = scene?.windows.first(where: { $0.isKeyWindow })
        return keyWindow?.safeAreaInsets ?? .zero
    }

    private func chainInputBottomPadding() -> CGFloat {
        if keyboardHeight > 0 {
            // Let the bar overlap the rounded top edge of the keyboard slightly
            // so it doesn't leave a visible gap when the keyboard is shown.
            return max(0, keyboardHeight - 10)
        }
        return 0
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
                .opacity(isLoadingUserSettings ? 0.5 : 1.0)
                .liquidGlass(in: Capsule(), interactive: true)
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
            .disabled(isPublishing || isLoadingUserSettings || isEditingSticker)
            .opacity(isEditingSticker ? 0 : 1)
        }
    }
    
    // ✅ Filtros: Aplicación asíncrona optimizada (Cancela tareas previas para evitar lag)
    private func applySelectedFilter() {
        guard let firstMedia = selectedMediaItems.first, firstMedia.type == .image else {
            filteredImage = nil
            isApplyingFilter = false
            return
        }
        
        if selectedFilter == .normal {
            filteredImage = nil
            isApplyingFilter = false
            return
        }
        
        isApplyingFilter = true
        
        // Cancelar la tarea anterior si existe para evitar acumulación de procesamiento
        filterTask?.cancel()

        let selectedFilter = self.selectedFilter
        let filterIntensity = self.filterIntensity
        let optimizedImage = firstMedia.image

        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 45_000_000)

            if Task.isCancelled { return }

            let processed = FilterService.shared.applyFilter(selectedFilter, to: optimizedImage, intensity: filterIntensity)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.filteredImage = processed
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

    private func storyRenderTargetSize(for screenSize: CGSize = UIScreen.main.bounds.size) -> CGSize {
        let safeScreenWidth = max(screenSize.width, 1)
        let safeScreenHeight = max(screenSize.height, 1)
        let screenAspectRatio = safeScreenWidth / safeScreenHeight
        
        let targetWidth: CGFloat = 1080
        let targetHeight = targetWidth / max(screenAspectRatio, 0.0001)
        var targetSize = CGSize(width: targetWidth, height: targetHeight)
        
        if targetSize.height > 3000 { targetSize.height = 3000 }
        if targetSize.height < 1200 { targetSize.height = 1200 }
        
        return targetSize
    }

    private func storyBackgroundBlurImage(baseImage: UIImage, targetSize: CGSize) -> UIImage {
        let blurRadius: CGFloat = 20
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let smallSize = CGSize(width: 200, height: 200 * (targetSize.height / max(targetSize.width, 1)))
        let smallRect = CGRect(origin: .zero, size: smallSize)
        
        let smallRenderer = UIGraphicsImageRenderer(size: smallSize)
        let smallImage = smallRenderer.image { _ in
            baseImage.draw(in: smallRect)
        }
        
        guard let ciImage = CIImage(image: smallImage),
              let clampFilter = CIFilter(name: "CIAffineClamp"),
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return baseImage
        }
        
        clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(clampFilter.outputImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = blurFilter.outputImage?.cropped(to: ciImage.extent),
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return baseImage
        }
        
        return UIImage(cgImage: cgImage)
    }

    private func makePixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: size))
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()

        return pixelBuffer
    }

    private func createStillImageVideo(
        from image: UIImage,
        targetSize: CGSize,
        duration: CMTime,
        frameRate: Int32
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_blur_bg_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw NSError(domain: "StoryEditor", code: 8, userInfo: [NSLocalizedDescriptionKey: "Unable to create background video writer"])
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height)
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(targetSize.width),
                kCVPixelBufferHeightKey as String: Int(targetSize.height)
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "StoryEditor", code: 9, userInfo: [NSLocalizedDescriptionKey: "Unable to add background writer input"])
        }
        writer.add(writerInput)

        guard let pixelBuffer = makePixelBuffer(from: image, size: targetSize) else {
            throw NSError(domain: "StoryEditor", code: 10, userInfo: [NSLocalizedDescriptionKey: "Unable to create background pixel buffer"])
        }

        let totalFrames = max(1, Int(ceil(CMTimeGetSeconds(duration) * Double(frameRate))))
        let frameDuration = CMTime(value: 1, timescale: frameRate)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()

        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: writer.error ?? NSError(domain: "StoryEditor", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unable to finish background video writer"]))
                }
            }
        }
    }

    private func mediaRectForStoryCanvas(mediaSize: CGSize, targetSize: CGSize) -> CGRect {
        let imageRatio = mediaSize.width / max(mediaSize.height, 1)
        let targetRatio = targetSize.width / max(targetSize.height, 1)
        let useFit = StoryMediaLayoutRules.presentationMode(for: imageRatio, canvasAspectRatio: targetRatio) == .fitWithBlur
        let mediaIsWider = imageRatio > targetRatio
        
        let finalWidth: CGFloat
        let finalHeight: CGFloat
        
        if useFit {
            if mediaIsWider {
                finalWidth = targetSize.width
                finalHeight = targetSize.width / max(imageRatio, 0.0001)
            } else {
                finalHeight = targetSize.height
                finalWidth = targetSize.height * imageRatio
            }
        } else {
            if mediaIsWider {
                finalHeight = targetSize.height
                finalWidth = targetSize.height * imageRatio
            } else {
                finalWidth = targetSize.width
                finalHeight = targetSize.width / max(imageRatio, 0.0001)
            }
        }
        
        return CGRect(
            x: (targetSize.width - finalWidth) / 2,
            y: (targetSize.height - finalHeight) / 2,
            width: finalWidth,
            height: finalHeight
        )
    }

    private func renderStoryOverlayImage(targetSize: CGSize, screenSize: CGSize) -> UIImage? {
        guard drawingImage != nil || !storyText.isEmpty else { return nil }
        
        let scaleFactorX = targetSize.width / max(screenSize.width, 1)
        let scaleFactorY = targetSize.height / max(screenSize.height, 1)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)
            
            if let drawing = drawingImage {
                drawing.draw(in: rect, blendMode: .normal, alpha: 1.0)
            }
            
            if !storyText.isEmpty {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = nsTextAlignment(from: storyTextAlignment)
                
                let scaledFontSize = storyTextFontSize * max(scaleFactorX, scaleFactorY)
                let font = selectedTextStyle.uiFont(size: scaledFontSize)
                
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(storyTextColor),
                    .paragraphStyle: paragraphStyle
                ]
                
                if let shadow = selectedTextEffect.nsShadow(for: UIColor(storyTextColor)) {
                    attributes[.shadow] = shadow
                }
                
                let attributedText = NSAttributedString(string: storyText, attributes: attributes)
                let maxTextWidth = rect.width * 0.82
                let measuredSize = attributedText.boundingRect(
                    with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).integral.size
                let drawTextWidth = min(maxTextWidth, max(1, measuredSize.width))
                let textRect = CGRect(
                    x: (textPosition.x * scaleFactorX) - drawTextWidth / 2,
                    y: (textPosition.y * scaleFactorY) - measuredSize.height / 2,
                    width: drawTextWidth,
                    height: measuredSize.height
                )
                
                let scaleFactor = max(scaleFactorX, scaleFactorY)
                if let backgroundUIColor = resolvedTextBackgroundUIColor() {
                    backgroundUIColor.setFill()
                    let backgroundRect = textRect.insetBy(dx: -16 * scaleFactor, dy: -8 * scaleFactor)
                    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8 * scaleFactor).fill()
                }
                
                attributedText.draw(in: textRect)
            }
        }
    }

    private func renderStoryWithOverlays() -> UIImage {
        guard let firstMedia = selectedMediaItems.first else {
            return UIImage()
        }
        
        let baseImage = firstMedia.image
        let screenSize = UIScreen.main.bounds.size
        let targetSize = storyRenderTargetSize(for: screenSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            let blurImage = storyBackgroundBlurImage(baseImage: baseImage, targetSize: targetSize)
            let overscale: CGFloat = 1.05
            let overscaleRect = CGRect(
                x: -(targetSize.width * (overscale - 1) / 2),
                y: -(targetSize.height * (overscale - 1) / 2),
                width: targetSize.width * overscale,
                height: targetSize.height * overscale
            )
            blurImage.draw(in: overscaleRect)
            
            let renderImage: UIImage
            if selectedFilter != .normal {
                renderImage = FilterService.shared.applyFilter(selectedFilter, to: baseImage, intensity: filterIntensity)
            } else {
                renderImage = baseImage
            }
            
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            
            if firstMedia.type != .video {
                let scaleFactorX = targetSize.width / max(screenSize.width, 1)
                let scaleFactorY = targetSize.height / max(screenSize.height, 1)
                context.cgContext.rotate(by: imageRotation.radians)
                context.cgContext.scaleBy(x: imageScale, y: imageScale)
                context.cgContext.translateBy(
                    x: imageOffset.width * scaleFactorX,
                    y: imageOffset.height * scaleFactorY
                )
            }
            
            let imageRect = mediaRectForStoryCanvas(mediaSize: renderImage.size, targetSize: targetSize)
                .offsetBy(dx: -targetSize.width / 2, dy: -targetSize.height / 2)
            renderImage.draw(in: imageRect)
            context.cgContext.restoreGState()
            
            if let overlayImage = renderStoryOverlayImage(targetSize: targetSize, screenSize: screenSize) {
                overlayImage.draw(in: rect)
            }
            
            // 5. Stickers overlay
            // ✅ FIX: No renderizar NINGÚN sticker en la imagen de fondo
            // Los stickers se añaden como metadatos interactivos y se renderizan en el visor
            // Si los dibujamos aquí, aparecerán dobles (uno estático y uno interactivo)
            /*
            for sticker in selectedStickers {
                // interactive stickers (mentions, etc.) are handled by metadata, not drawn on the static image
                if sticker.type == .mention || sticker.type == .poll || sticker.type == .question ||
                   sticker.type == .location || sticker.type == .hashtag || sticker.type == .weather ||
                   sticker.type == .link || sticker.type == .countdown {
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

    private func shouldBakeCurrentOverlaysIntoVideo(_ media: ProcessedMedia) -> Bool {
        guard media.type == .video else { return false }
        return drawingImage != nil || !storyText.isEmpty
    }

    private func exportVideoWithCurrentOverlays(_ media: ProcessedMedia) async throws -> URL {
        guard let sourceURL = media.videoURL else {
            throw NSError(domain: "StoryEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing source video URL"])
        }
        
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "StoryEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing video track"])
        }
        
        let duration = try await asset.load(.duration)
        let targetSize = storyRenderTargetSize()
        let overlayImage = renderStoryOverlayImage(targetSize: targetSize, screenSize: UIScreen.main.bounds.size)
        let blurImage = storyBackgroundBlurImage(baseImage: media.image, targetSize: targetSize)
        
        let composition = AVMutableComposition()
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let timescale = Int32(max(30, min(60, Int(frameRate.rounded()))))

        let blurVideoURL = try await createStillImageVideo(
            from: blurImage,
            targetSize: targetSize,
            duration: duration,
            frameRate: timescale
        )
        let blurAsset = AVURLAsset(url: blurVideoURL)
        guard let blurTrack = try await blurAsset.loadTracks(withMediaType: .video).first,
              let compositionBackgroundTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw NSError(domain: "StoryEditor", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unable to create background composition track"])
        }

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "StoryEditor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create composition track"])
        }
        
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionBackgroundTrack.insertTimeRange(timeRange, of: blurTrack, at: .zero)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let actualSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let useFit = StoryMediaLayoutRules.presentationMode(for: actualSize, canvasSize: targetSize) == .fitWithBlur
        let scale = useFit
            ? min(targetSize.width / max(actualSize.width, 1), targetSize.height / max(actualSize.height, 1))
            : max(targetSize.width / max(actualSize.width, 1), targetSize.height / max(actualSize.height, 1))
        
        let scaledTransform = preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaledRect = CGRect(origin: .zero, size: naturalSize).applying(scaledTransform)
        let translation = CGAffineTransform(
            translationX: (targetSize.width - scaledRect.width) / 2 - scaledRect.minX,
            y: (targetSize.height - scaledRect.height) / 2 - scaledRect.minY
        )
        let finalTransform = scaledTransform.concatenating(translation)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        
        let backgroundInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionBackgroundTrack)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction, backgroundInstruction]
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: timescale)
        videoComposition.instructions = [instruction]
        
        let renderFrame = CGRect(origin: .zero, size: targetSize)
        let parentLayer = CALayer()
        parentLayer.frame = renderFrame
        let videoLayer = CALayer()
        videoLayer.frame = renderFrame
        
        parentLayer.addSublayer(videoLayer)
        
        if let overlayImage {
            let overlayLayer = CALayer()
            overlayLayer.frame = renderFrame
            overlayLayer.contents = overlayImage.cgImage
            overlayLayer.contentsGravity = .resize
            parentLayer.addSublayer(overlayLayer)
        }
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_overlay_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "StoryEditor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw exportSession.error ?? NSError(domain: "StoryEditor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Video export failed"])
        case .cancelled:
            throw NSError(domain: "StoryEditor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Video export cancelled"])
        default:
            throw NSError(domain: "StoryEditor", code: 7, userInfo: [NSLocalizedDescriptionKey: "Video export did not finish"])
        }
    }

    private func prepareMediaForStoryUpload(from media: ProcessedMedia) async throws -> (mediaItem: ProcessedMedia, finalRenderedImage: UIImage) {
        let finalRenderedImage = renderStoryWithOverlays()
        
        guard shouldBakeCurrentOverlaysIntoVideo(media) else {
            return (media, finalRenderedImage)
        }
        
        let exportedVideoURL = try await exportVideoWithCurrentOverlays(media)
        let finalMedia = media.with(
            videoURL: exportedVideoURL,
            hasEdits: true,
            image: finalRenderedImage
        )
        
        return (finalMedia, finalRenderedImage)
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
        guard let media = selectedMediaItems.first else { return }
        
        Task {
            do {
                let preparedUpload = try await prepareMediaForStoryUpload(from: media)
                await MainActor.run {
                    publishPreparedStory(
                        media: preparedUpload.mediaItem,
                        finalRenderedImage: preparedUpload.finalRenderedImage
                    )
                }
            } catch {
                await MainActor.run {
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.error)
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func publishPreparedStory(media: ProcessedMedia, finalRenderedImage: UIImage) {
        let stickerData = selectedStickers
        let drawingData = drawingImage?.pngData()
        
        var finalChainId: String? = nil
        var finalChainPosition: Int? = nil
        var finalChainTitle: String? = nil
        
        if isCreatingChain && !chainTitle.isEmpty {
            finalChainId = UUID().uuidString
            finalChainPosition = 1
            finalChainTitle = chainTitle
        } else if isContinuingChain, let existingChainId = chainId {
            finalChainId = existingChainId
            finalChainPosition = (chainPosition ?? 0) + 1
            finalChainTitle = originalChainTitle
        }
        
        let contentAudience: ContentAudience = {
            if isCreatingChain || isContinuingChain {
                return .everyone
            } else {
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
        selectedTextEffect = .none
        storyTextColor = .white
        storyTextAlignment = .center
        storyTextBackground = .none
        storyTextFontSize = 30
        
    }

    private func nsTextAlignment(from alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading:
            return .left
        case .trailing:
            return .right
        default:
            return .center
        }
    }

    private func textBackgroundUIColor() -> UIColor? {
        switch storyTextBackground {
        case .none:
            return nil
        case .black:
            return UIColor.black.withAlphaComponent(0.58)
        case .white:
            return UIColor.white.withAlphaComponent(0.90)
        }
    }

    private func resolvedTextBackgroundUIColor() -> UIColor? {
        if let explicitBackground = textBackgroundUIColor() {
            return explicitBackground
        }
        return selectedTextEffect.uiBackgroundColor
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
        case .link:
            return interactionData.linkURL ?? ""
        case .countdown:
            return interactionData.countdownTitle ?? ""
        case .emojiSlider:
            return interactionData.sliderPrompt ?? ""
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
        playerView.update(with: videoURL, gravity: videoGravity)
        return playerView
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.update(with: videoURL, gravity: videoGravity)
    }
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentURL: URL?
    private var currentGravity: AVLayerVideoGravity?
    
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
    
    func update(with url: URL, gravity: AVLayerVideoGravity = .resizeAspect) {
        if currentURL != url || player == nil || playerLayer == nil {
            configurePlayer(with: url, gravity: gravity)
            return
        }

        if currentGravity != gravity {
            currentGravity = gravity
            playerLayer?.videoGravity = gravity
        }
    }

    private func configurePlayer(with url: URL, gravity: AVLayerVideoGravity) {
        player?.pause()
        playerLayer?.removeFromSuperlayer()

        currentURL = url
        currentGravity = gravity
        player = AVPlayer(url: url)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        layer.frame = bounds
        self.playerLayer = layer
        self.layer.addSublayer(layer)

        player?.play()

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
    var interactionData: StickerInteractionData?
    
    enum StickerType: String, Codable {
        case emoji
        case sticker
        case mention
        case hashtag
        case location
        case poll
        case question
        case link
        case countdown
        case emojiSlider
        case questionResponse
        case generic
        case weather
        case time
        case selfie
        case shareMoment
        case quiz
        case frame
        case reveal
    }
    
    struct StickerInteractionData {
        var username: String?
        var userId: String?
        var hashtag: String?
        var location: String?
        var locationCoordinate: CLLocationCoordinate2D?
        var pollData: [String]?
        var questionText: String?
        var weatherSymbol: String?
        var linkURL: String?
        var linkTitle: String?
        var countdownTitle: String?
        var countdownTargetAtMs: Double?
        var sliderEmoji: String?
        var sliderPrompt: String?
        var caption: String?
        var profileImagePath: String?
        var momentId: String?
        var mediaCount: Int?
        
        // Quiz Data
        var quizQuestion: String?
        var quizOptions: [String]?
        var quizCorrectIndex: Int?
        
        // Reveal Data
        var revealType: String? // "scratch" por defecto
        
        // Polaroid Frame Data
        var frameStyle: String?

        // ✅ Inicializador
        init(
            username: String? = nil,
            userId: String? = nil,
            hashtag: String? = nil,
            location: String? = nil,
            locationCoordinate: CLLocationCoordinate2D? = nil,
            pollData: [String]? = nil,
            questionText: String? = nil,
            weatherSymbol: String? = nil,
            linkURL: String? = nil,
            linkTitle: String? = nil,
            countdownTitle: String? = nil,
            countdownTargetAtMs: Double? = nil,
            sliderEmoji: String? = nil,
            sliderPrompt: String? = nil,
            caption: String? = nil,
            profileImagePath: String? = nil,
            momentId: String? = nil,
            mediaCount: Int? = nil,
            quizQuestion: String? = nil,
            quizOptions: [String]? = nil,
            quizCorrectIndex: Int? = nil,
            revealType: String? = nil,
            frameStyle: String? = nil
        ) {
            self.username = username
            self.userId = userId
            self.hashtag = hashtag
            self.location = location
            self.locationCoordinate = locationCoordinate
            self.pollData = pollData
            self.questionText = questionText
            self.weatherSymbol = weatherSymbol
            self.linkURL = linkURL
            self.linkTitle = linkTitle
            self.countdownTitle = countdownTitle
            self.countdownTargetAtMs = countdownTargetAtMs
            self.sliderEmoji = sliderEmoji
            self.sliderPrompt = sliderPrompt
            self.caption = caption
            self.profileImagePath = profileImagePath
            self.momentId = momentId
            self.mediaCount = mediaCount
            self.quizQuestion = quizQuestion
            self.quizOptions = quizOptions
            self.quizCorrectIndex = quizCorrectIndex
            self.revealType = revealType
            self.frameStyle = frameStyle
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



private enum StoryDrawingBrush {
    case pen
    case arrow
    case glow
    case marker
    case eraser
}

private struct StoryDrawingEditorOverlay: View {
    @Binding var isPresented: Bool
    @Binding var drawingImage: UIImage?

    @State private var baseDrawing: UIImage?
    @State private var liveGlowImage: UIImage?
    @State private var brush: StoryDrawingBrush = .pen
    @State private var brushWidth: CGFloat = 7
    @State private var color: UIColor = .white

    @State private var clearToken = 0
    @State private var undoToken = 0
    @State private var redoToken = 0
    @State private var exportToken = 0

    init(isPresented: Binding<Bool>, drawingImage: Binding<UIImage?>) {
        self._isPresented = isPresented
        self._drawingImage = drawingImage
        self._baseDrawing = State(initialValue: drawingImage.wrappedValue)
    }

    var body: some View {
        ZStack {
            if let baseDrawing {
                Image(uiImage: baseDrawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .allowsHitTesting(false)
            }

            StoryDrawingCanvasView(
                brush: $brush,
                color: $color,
                brushWidth: $brushWidth,
                clearToken: $clearToken,
                undoToken: $undoToken,
                redoToken: $redoToken,
                exportToken: $exportToken,
                onExport: { strokesImage, hasStrokes in
                    if hasStrokes {
                        if let base = baseDrawing {
                            drawingImage = merge(base: base, overlay: strokesImage)
                        } else {
                            drawingImage = strokesImage
                        }
                    } else {
                        drawingImage = baseDrawing
                    }
                    isPresented = false
                },
                onLiveGlowPreview: { image in
                    liveGlowImage = image
                }
            )
            .ignoresSafeArea()

            if let liveGlowImage {
                Image(uiImage: liveGlowImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack(spacing: 10) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .liquidGlass(in: Circle())
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 12) {
                        brushButton(icon: "pencil", brushType: .pen)
                        brushButton(icon: "arrow.up.right", brushType: .arrow)
                        brushButton(icon: "highlighter", brushType: .marker)
                        brushButton(icon: "sparkles", brushType: .glow)
                        brushButton(icon: "eraser", brushType: .eraser)
                    }

                    Spacer(minLength: 6)

                    Button(action: {
                        exportToken += 1
                    }) {
                        Text("creator.done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Eyedropper / Custom Color Picker
                        ZStack {
                            Circle()
                                .fill(Color(color))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                )
                            
                            Image(systemName: "eyedropper")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(color == .white ? .black : .white)
                            
                            ColorPicker("", selection: Binding(
                                get: { Color(color) },
                                set: { newColor in
                                    let uiColor = UIColor(newColor)
                                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                    // Force color into standard RGBA space so CoreGraphics (.cgColor) shadowing works.
                                    if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                                        color = UIColor(red: r, green: g, blue: b, alpha: a)
                                    } else {
                                        color = UIColor(cgColor: uiColor.cgColor)
                                    }
                                }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40, height: 40)
                            .scaleEffect(2.2)
                            .contentShape(Rectangle())
                            .opacity(0.011)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                        
                        Divider()
                            .frame(height: 24)
                            .background(Color.white.opacity(0.3))
                            .padding(.horizontal, 2)

                        ForEach(drawingPalette, id: \.self) { paletteColor in
                            Button(action: { color = paletteColor }) {
                                Circle()
                                    .fill(Color(paletteColor))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(color == paletteColor ? 0.95 : 0.26), lineWidth: color == paletteColor ? 2.5 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
            }

            HStack {
                Spacer()
                VStack(spacing: 10) {
                    sideToolButton(icon: "arrow.uturn.backward") {
                        undoToken += 1
                    }

                    sideToolButton(icon: "arrow.uturn.forward") {
                        redoToken += 1
                    }

                    StoryVerticalBrushSlider(
                        value: $brushWidth,
                        range: 2...26
                    )
                }
                .padding(.trailing, 16)
                .padding(.bottom, 116)
            }
            .padding(.top, 148)
        }
        .ignoresSafeArea()
    }

    private var drawingPalette: [UIColor] {
        [
            .white, .black, .darkGray, .lightGray,
            .systemRed, .systemOrange, .systemYellow, .systemGreen,
            .systemCyan, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .brown
        ]
    }

    private func merge(base: UIImage, overlay: UIImage) -> UIImage {
        let size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            overlay.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @ViewBuilder
    private func brushButton(icon: String, brushType: StoryDrawingBrush) -> some View {
        let isSelected = brush == brushType
        Button(action: { brush = brushType }) {
            Image(systemName: icon)
                .font(.system(size: isSelected ? 20 : 18, weight: .semibold))
                .foregroundColor(.white.opacity(isSelected ? 1 : 0.58))
                .frame(width: 30, height: 30)
                .scaleEffect(isSelected ? 1.08 : 1)
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sideToolButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

}

private struct StoryVerticalBrushSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbSize: CGFloat = 34
            let normalized = normalizedValue
            let thumbTravel = max(0, trackHeight - thumbSize)
            let thumbY = (1 - normalized) * thumbTravel

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 6, height: max(thumbSize * 0.7, trackHeight * normalized))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .offset(y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 0), trackHeight)
                        let normalized = 1 - (clampedY / max(trackHeight, 1))
                        value = range.lowerBound + ((range.upperBound - range.lowerBound) * normalized)
                    }
            )
        }
        .frame(width: 34, height: 208)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
    }

    private var normalizedValue: CGFloat {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        return min(max((value - range.lowerBound) / distance, 0), 1)
    }
}

private struct StoryDrawingCanvasView: UIViewRepresentable {
    @Binding var brush: StoryDrawingBrush
    @Binding var color: UIColor
    @Binding var brushWidth: CGFloat

    @Binding var clearToken: Int
    @Binding var undoToken: Int
    @Binding var redoToken: Int
    @Binding var exportToken: Int

    let onExport: (UIImage, Bool) -> Void
    let onLiveGlowPreview: (UIImage?) -> Void

    fileprivate struct StrokeMetadata {
        let brush: StoryDrawingBrush
        let color: UIColor
        let width: CGFloat
    }

    private enum GlowConfig {
        // Instagram-like neon: nearly-invisible PK stroke + intense colored glow via CGContext shadow.
        static let coreWidthMultiplier: CGFloat = 0.3

        // Shadow pass 1: tight, intense inner glow
        static let innerShadowBlur: CGFloat = 3
        static let innerShadowAlpha: CGFloat = 1.0
        static let innerStrokeWidthMultiplier: CGFloat = 0.9

        // Shadow pass 2: medium spread
        static let midShadowBlur: CGFloat = 8
        static let midShadowAlpha: CGFloat = 0.9
        static let midStrokeWidthMultiplier: CGFloat = 0.8

        // Shadow pass 3: wide ambient glow
        static let outerShadowBlur: CGFloat = 18
        static let outerShadowAlpha: CGFloat = 0.4
        static let outerStrokeWidthMultiplier: CGFloat = 0.6
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInset = .zero
        canvas.contentSize = UIScreen.main.bounds.size
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.currentBrush = brush
        context.coordinator.currentColor = color
        context.coordinator.currentWidth = brushWidth
        uiView.tool = currentTool()

        if clearToken != context.coordinator.lastClearToken {
            context.coordinator.lastClearToken = clearToken
            context.coordinator.strokeMetadata = []
            uiView.drawing = PKDrawing()
        }

        if undoToken != context.coordinator.lastUndoToken {
            context.coordinator.lastUndoToken = undoToken
            uiView.undoManager?.undo()
        }

        if redoToken != context.coordinator.lastRedoToken {
            context.coordinator.lastRedoToken = redoToken
            uiView.undoManager?.redo()
        }

        if exportToken != context.coordinator.lastExportToken {
            context.coordinator.lastExportToken = exportToken
            let hasStrokes = !uiView.drawing.strokes.isEmpty
            let exported = renderExportedImage(
                from: uiView.drawing,
                bounds: uiView.bounds,
                scale: UIScreen.main.scale,
                strokeMetadata: context.coordinator.strokeMetadata
            )
            onExport(exported, hasStrokes)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLiveGlowPreview: onLiveGlowPreview)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let onLiveGlowPreview: (UIImage?) -> Void

        var lastClearToken = 0
        var lastUndoToken = 0
        var lastRedoToken = 0
        var lastExportToken = 0
        var currentBrush: StoryDrawingBrush = .pen
        var currentColor: UIColor = .white
        var currentWidth: CGFloat = 7
        fileprivate var strokeMetadata: [StrokeMetadata] = []

        private var glowPreviewWorkItem: DispatchWorkItem?

        init(onLiveGlowPreview: @escaping (UIImage?) -> Void) {
            self.onLiveGlowPreview = onLiveGlowPreview
            super.init()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokeCount = canvasView.drawing.strokes.count

            if strokeCount > strokeMetadata.count {
                let newMetadata = StrokeMetadata(
                    brush: currentBrush,
                    color: currentColor,
                    width: currentWidth
                )
                strokeMetadata.append(contentsOf: Array(repeating: newMetadata, count: strokeCount - strokeMetadata.count))
            } else if strokeCount < strokeMetadata.count {
                strokeMetadata = Array(strokeMetadata.prefix(strokeCount))
            }

            // WYSIWYG glow preview (debounced).
            glowPreviewWorkItem?.cancel()
            let shouldRenderGlow = strokeMetadata.contains(where: { $0.brush == .glow })
            let drawingSnapshot = canvasView.drawing
            let boundsSnapshot = canvasView.bounds
            let metadataSnapshot = strokeMetadata

            let workItem = DispatchWorkItem { [onLiveGlowPreview] in
                guard shouldRenderGlow else {
                    onLiveGlowPreview(nil)
                    return
                }

                let preview = StoryDrawingCanvasView.renderBlurredGlowImage(
                    from: drawingSnapshot,
                    bounds: boundsSnapshot,
                    strokeMetadata: metadataSnapshot,
                    scale: UIScreen.main.scale
                )
                onLiveGlowPreview(preview)
            }

            glowPreviewWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
        }
    }

    private func currentTool() -> PKTool {
        switch brush {
        case .pen:
            return PKInkingTool(.pen, color: color, width: brushWidth)
        case .arrow:
            return PKInkingTool(.pen, color: color, width: max(3, brushWidth))
        case .glow:
            // Nearly invisible on PK canvas – the glow overlay provides all visual feedback.
            return PKInkingTool(
                .pen,
                color: color.withAlphaComponent(0.08),
                width: max(2, brushWidth * GlowConfig.coreWidthMultiplier)
            )
        case .marker:
            return PKInkingTool(.marker, color: color.withAlphaComponent(0.40), width: max(10, brushWidth * 2.4))
        case .eraser:
            return PKEraserTool(.bitmap)
        }
    }

    private func renderExportedImage(
        from drawing: PKDrawing,
        bounds: CGRect,
        scale: CGFloat,
        strokeMetadata: [StrokeMetadata]
    ) -> UIImage {
        let hasGlowStrokes = strokeMetadata.contains(where: { $0.brush == .glow })
        let hasArrowStrokes = strokeMetadata.contains(where: { $0.brush == .arrow })

        // Build a "clean" drawing without glow strokes so they don't appear as ghost lines.
        let cleanDrawing: PKDrawing
        if hasGlowStrokes {
            let nonGlowStrokes = drawing.strokes.enumerated().compactMap { (index, stroke) -> PKStroke? in
                guard index < strokeMetadata.count else { return stroke }
                return strokeMetadata[index].brush == .glow ? nil : stroke
            }
            var rebuilt = PKDrawing()
            rebuilt.strokes = nonGlowStrokes
            cleanDrawing = rebuilt
        } else {
            cleanDrawing = drawing
        }

        let baseImage = cleanDrawing.image(from: bounds, scale: scale)

        guard hasGlowStrokes || hasArrowStrokes else {
            return baseImage
        }

        let glowImage: UIImage? = hasGlowStrokes
            ? Self.renderBlurredGlowImage(from: drawing, bounds: bounds, strokeMetadata: strokeMetadata, scale: scale)
            : nil

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { ctx in
            // Glow image first (it includes its own white core)
            if let glowImage {
                glowImage.draw(in: CGRect(origin: .zero, size: bounds.size))
            }

            // Non-glow strokes on top
            baseImage.draw(in: CGRect(origin: .zero, size: bounds.size))

            for (index, stroke) in drawing.strokes.enumerated() {
                guard index < strokeMetadata.count else { continue }
                let metadata = strokeMetadata[index]
                guard metadata.brush == .arrow else { continue }
                drawArrowHead(for: stroke, metadata: metadata)
            }
        }
    }

    private static func renderBlurredGlowImage(
        from drawing: PKDrawing,
        bounds: CGRect,
        strokeMetadata: [StrokeMetadata],
        scale: CGFloat
    ) -> UIImage? {
        let glowStrokes = drawing.strokes.enumerated().compactMap { (index, stroke) -> (index: Int, stroke: PKStroke)? in
            guard index < strokeMetadata.count else { return nil }
            return strokeMetadata[index].brush == .glow ? (index: index, stroke: stroke) : nil
        }

        guard !glowStrokes.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext

            for glow in glowStrokes {
                let metadata = strokeMetadata[glow.index]
                let bezier = strokeToBezierPath(stroke: glow.stroke)
                guard !bezier.cgPath.isEmpty else { continue }

                let glowColor = metadata.color
                let w = metadata.width

                // Scale the glow extent with the brush size so fat strokes
                // get a proportionally bigger, more dramatic outer halo.
                let outerBlur = max(14, w * 3.0)   // wide ambient spill
                let midBlur   = max(6,  w * 1.2)   // medium intensity halo
                let coreBlur  = max(3,  w * 0.6)   // tight colored edge around white

                // -- Pass 1: Wide ambient glow (soft light spill) --
                ctx.saveGState()
                ctx.setBlendMode(.plusLighter)
                ctx.setShadow(offset: .zero, blur: outerBlur, color: glowColor.withAlphaComponent(0.45).cgColor)
                ctx.setStrokeColor(UIColor.clear.cgColor)
                ctx.setLineWidth(w)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(bezier.cgPath)
                ctx.strokePath()
                ctx.restoreGState()

                // -- Pass 2: Medium glow (tighter, more intense) --
                ctx.saveGState()
                ctx.setBlendMode(.plusLighter)
                ctx.setShadow(offset: .zero, blur: midBlur, color: glowColor.withAlphaComponent(0.65).cgColor)
                ctx.setStrokeColor(UIColor.clear.cgColor)
                ctx.setLineWidth(w)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(bezier.cgPath)
                ctx.strokePath()
                ctx.restoreGState()

                // -- Pass 3: White core with colored shadow --
                ctx.saveGState()
                ctx.setBlendMode(.normal)
                ctx.setShadow(offset: .zero, blur: coreBlur, color: glowColor.cgColor)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(w)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(bezier.cgPath)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    private static func strokeToBezierPath(stroke: PKStroke) -> UIBezierPath {
        let pts = stroke.path
        guard !pts.isEmpty else { return UIBezierPath() }

        let bezier = UIBezierPath()
        bezier.move(to: pts[0].location)

        if pts.count > 1 {
            for i in 1..<pts.count {
                let mid = CGPoint(
                    x: (pts[i - 1].location.x + pts[i].location.x) / 2,
                    y: (pts[i - 1].location.y + pts[i].location.y) / 2
                )
                bezier.addQuadCurve(to: mid, controlPoint: pts[i - 1].location)
            }
            bezier.addLine(to: pts[pts.count - 1].location)
        }

        bezier.lineCapStyle = .round
        bezier.lineJoinStyle = .round
        return bezier
    }

    private func drawArrowHead(for stroke: PKStroke, metadata: StrokeMetadata) {
        let path = stroke.path
        guard path.count >= 2 else { return }

        let endIndex = path.index(before: path.endIndex)
        let previousIndex = path.index(before: endIndex)
        let endPoint = path[endIndex].location
        let previousPoint = path[previousIndex].location

        let dx = endPoint.x - previousPoint.x
        let dy = endPoint.y - previousPoint.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(12, metadata.width * 3.2)
        let spread: CGFloat = .pi / 7

        let left = CGPoint(
            x: endPoint.x - headLength * cos(angle - spread),
            y: endPoint.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: endPoint.x - headLength * cos(angle + spread),
            y: endPoint.y - headLength * sin(angle + spread)
        )

        let arrowPath = UIBezierPath()
        arrowPath.move(to: left)
        arrowPath.addLine(to: endPoint)
        arrowPath.addLine(to: right)
        arrowPath.lineWidth = max(3, metadata.width * 0.9)
        arrowPath.lineCapStyle = .round
        arrowPath.lineJoinStyle = .round

        metadata.color.setStroke()
        arrowPath.stroke()
    }
}

// MARK: - Filter Selector View
struct FilterSelectorView: View {
    @Binding var selectedFilter: FilterService.FilterType
    let filters: [FilterService.FilterType]
    let baseImage: UIImage?
    
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filters, id: \.self) { filterType in
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
