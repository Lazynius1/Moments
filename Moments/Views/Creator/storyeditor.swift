import UIKit
import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import CoreLocation
import Photos

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


    private var isTextMode: Bool { activeEditorMode == .text }
    private var isDrawingMode: Bool { activeEditorMode == .drawing }
    private var isFilterMode: Bool { activeEditorMode == .filters }
    private var isCanvasModeActive: Bool { activeEditorMode != .idle }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                let windowInsets = keyWindowSafeAreaInsets()
                let viewportSize = stableViewportSize(for: proxy)
                let mediaCanvasRect = creatorMomentsCaptureRect(
                    in: viewportSize,
                    topInset: windowInsets.top,
                    bottomInset: windowInsets.bottom
                )
                let mediaCanvasSize = mediaCanvasRect.size

                ZStack(alignment: .topLeading) {
                    (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                        .ignoresSafeArea()

                    backgroundMediaView(canvasSize: mediaCanvasSize)
                        .frame(width: mediaCanvasRect.width, height: mediaCanvasRect.height)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)

                    // Drawing overlay preview when text editor is open
                    if let drawing = drawingImage, isTextMode {
                        Image(uiImage: drawing)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: mediaCanvasRect.width, height: mediaCanvasRect.height)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)
                            .allowsHitTesting(false)
                    }

                    // Overlays
                    if !isTextMode && !isDrawingMode {
                        StoryOverlaysView(
                            canvasSize: mediaCanvasSize,
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
                        .frame(width: mediaCanvasRect.width, height: mediaCanvasRect.height)
                        .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)
                    }

                    // Controls
                    mainControlsOverlay(
                        proxy: proxy,
                        mediaCanvasRect: mediaCanvasRect
                    )

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
            resetBaseMediaTransform()

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
                resetBaseMediaTransform()
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
            bottomPublishingInset()
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
            StickerPickerView(selectedStickers: $selectedStickers, isVideo: selectedMediaItems.first?.type == .video)
                .ignoresSafeArea()
                .onDisappear {
                    activeEditorMode = .idle
                }
                .presentationDetents([.medium])
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

    private func resetBaseMediaTransform() {
        imageScale = 1.0
        imageOffset = .zero
        imageRotation = .zero
    }

    @ViewBuilder
    private func backgroundMediaView(canvasSize: CGSize) -> some View {
        if let firstMedia = selectedMediaItems.first {
            if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                let fallbackAspectRatio = firstMedia.image.size.width / max(firstMedia.image.size.height, 1)
                let mediaAspectRatio = primaryVideoAspectRatio ?? fallbackAspectRatio
                let referenceHeight = max(firstMedia.image.size.height, 1)
                let resolvedMediaSize = CGSize(
                    width: mediaAspectRatio * referenceHeight,
                    height: referenceHeight
                )
                StoryEditableMediaContainer(
                    mediaSize: resolvedMediaSize,
                    scale: $imageScale,
                    offset: $imageOffset,
                    rotation: $imageRotation,
                    canvasSize: canvasSize,
                    paletteIdentity: "\(firstMedia.id)-video-\(Int(mediaAspectRatio * 1000))",
                    paletteSourceImage: firstMedia.image,
                    isInteractionEnabled: activeEditorMode == .idle && !isEditingSticker
                ) { baseRect in
                    StoryVideoPlayerView(
                        videoURL: videoURL,
                        videoGravity: StoryMediaLayoutRules.presentationMode(
                            for: mediaAspectRatio,
                            canvasAspectRatio: canvasSize.width / max(canvasSize.height, 1)
                        ).videoGravity
                    )
                    .frame(width: baseRect.width, height: baseRect.height)
                }
                .clipped()
                .ignoresSafeArea()
            } else {
                EditableImageView(
                    image: firstMedia.image,
                    scale: $imageScale,
                    offset: $imageOffset,
                    rotation: $imageRotation,
                    filteredImage: filteredImage,
                    canvasSize: canvasSize,
                    paletteIdentity: "\(firstMedia.id)-\(selectedFilter.rawValue)-\(Int(filterIntensity * 100))-\(filteredImage != nil)",
                    isInteractionEnabled: activeEditorMode == .idle && !isEditingSticker
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .ignoresSafeArea()
                .onChange(of: selectedFilter) { _, _ in
                    applySelectedFilter()
                }
            }
        } else {
            // ✅ Fondo por defecto cuando se comparte un sticker (ej. share to story)
            LinearGradient(
                colors: [
                    Color(hex: "4158D0"),
                    Color(hex: "C850C0"),
                    Color(hex: "FFCC70")
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
    private func mainControlsOverlay(
        proxy: GeometryProxy,
        mediaCanvasRect: CGRect
    ) -> some View {
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

                bottomControlsView(
                    bottomInset: proxy.safeAreaInsets.bottom,
                    canvasBottomEdge: mediaCanvasRect.maxY,
                    viewportHeight: proxy.size.height
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .opacity(isEditingSticker ? 0 : 1)
            .disabled(isEditingSticker)
        }
    }

    @ViewBuilder
    private func bottomPublishingInset() -> some View {
        if activeEditorMode == .idle {
            HStack(spacing: 12) {
                Group {
                    if isCreatingChain && !isCanvasModeActive {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.72))
                                .font(.system(size: 15, weight: .semibold))

                            TextField(NSLocalizedString("storyChains.chainTitlePlaceholder", comment: "Chain title placeholder"), text: $chainTitle)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .tint(colorScheme == .dark ? .white : .black)
                                .focused($isChainTitleFocused)

                            if isChainTitleFocused {
                                Button(action: { isChainTitleFocused = false }) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.72))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .liquidGlass(in: Capsule(), interactive: true)
                    } else if isContinuingChain {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 15, weight: .semibold))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: NSLocalizedString("storyChains.continuing", comment: "Continuing chain"), originalChainTitle))
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(String(format: NSLocalizedString("storyChains.partShort", comment: "Part number"), (chainPosition ?? 0) + 1))
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .opacity(0.72)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .liquidGlass(in: Capsule(), interactive: false)
                    } else if !isContinuingChain {
                        Button(action: {
                            if !isLoadingUserSettings {
                                showingAudienceSelector = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoadingUserSettings {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(colorScheme == .dark ? .white : .black)
                                } else {
                                    Image(systemName: getAudienceIcon())
                                }

                                Text(isLoadingUserSettings ? NSLocalizedString("storyEditor.loadingSettings", comment: "Loading user settings") : getAudienceText())
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .liquidGlass(in: Capsule(), interactive: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                principalActionButton()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isCreatingChain ? chainInputBottomPadding() : 8)
            .animation(.easeOut(duration: 0.24), value: keyboardHeight)
        }
    }


    @ViewBuilder
    private func bottomControlsView(bottomInset: CGFloat, canvasBottomEdge: CGFloat, viewportHeight: CGFloat) -> some View {
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
                            .onChange(of: filterIntensity) { _, _ in
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
                        .onChange(of: selectedFilter) { _, _ in
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

            autoSplitNoticeView()

        }
        .padding(.horizontal, activeEditorMode == .idle && !isCreatingChain ? 0 : 16)
        .padding(.top, activeEditorMode == .idle && !isCreatingChain ? 0 : max(10, min(26, viewportHeight - canvasBottomEdge - 94)))
        .padding(.bottom, bottomControlsBottomPadding(bottomInset: bottomInset))
    }

    @ViewBuilder
    private func autoSplitNoticeView() -> some View {
        if activeEditorMode == .idle,
           let media = selectedMediaItems.first,
           media.storyVideoMode == .autoSplit,
           let duration = media.videoDuration {
            let partCount = max(2, Int(ceil(duration / StoryVideoProcessingService.maxStorySegmentDuration)))

            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12, weight: .semibold))

                Text(String(format: NSLocalizedString("storyVideo.editor.autoSplitNotice", comment: "Auto split publish notice"), partCount))
                    .font(.custom("Poppins-Medium", size: 12))
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .foregroundColor(.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
            .padding(.horizontal, 16)
        }
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
        if activeEditorMode == .idle && !isCreatingChain {
            return 8
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

    private func keyWindowBounds() -> CGRect? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive }
        let scene = activeScene ?? scenes.first
        let keyWindow = scene?.windows.first(where: { $0.isKeyWindow })
        return keyWindow?.bounds
    }

    private func stableViewportSize(for proxy: GeometryProxy) -> CGSize {
        guard let windowBounds = keyWindowBounds() else { return proxy.size }
        return CGSize(
            width: max(proxy.size.width, windowBounds.width),
            height: max(proxy.size.height, windowBounds.height)
        )
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
                Image(systemName: "arrow.right")
                    .foregroundColor(colorScheme == .dark ? Color.black.opacity(0.9) : .white)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 54, height: 48)
                .background(
                    (colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215"))
                        .opacity(isLoadingUserSettings ? 0.55 : 1.0)
                )
                .clipShape(Capsule())
            }
            .disabled(isPublishing || isLoadingUserSettings)
        } else if isCreatingChain {
            // 🔗 BOTÓN DE CONFIGURACIÓN PARA EL AUTOR ORIGINAL
            Button(action: {
                showingChainConfiguration = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 54, height: 48)
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
                .foregroundColor(colorScheme == .dark ? Color.black.opacity(0.9) : .white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    (colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215"))
                        .opacity(isLoadingUserSettings ? 0.55 : 1.0)
                )
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
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
        let targetWidth: CGFloat = 1080
        let targetHeight = targetWidth / max(creatorMomentsCaptureAspectRatio, 0.0001)
        var targetSize = CGSize(width: targetWidth, height: targetHeight)

        if targetSize.height > 3000 { targetSize.height = 3000 }
        if targetSize.height < 1200 { targetSize.height = 1200 }

        return targetSize
    }

    private func storyBackgroundImage(baseImage: UIImage, targetSize: CGSize) -> UIImage {
        let palette = storyDominantBackgroundColors(from: baseImage)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            drawStoryMediaBackground(
                in: CGRect(origin: .zero, size: targetSize),
                palette: palette,
                context: context.cgContext
            )
        }
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

        await writer.finishWriting()
        if writer.status == .completed {
            return outputURL
        } else {
            throw writer.error ?? NSError(domain: "StoryEditor", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unable to finish background video writer"])
        }
    }

    private func mediaRectForStoryCanvas(mediaSize: CGSize, targetSize: CGSize) -> CGRect {
        storyMediaRectForCanvas(mediaSize: mediaSize, canvasSize: targetSize)
    }

    private func transformedStoryMediaRect(
        mediaSize: CGSize,
        targetSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        rotation: Angle
    ) -> CGRect {
        let baseRect = mediaRectForStoryCanvas(mediaSize: mediaSize, targetSize: targetSize)
        let center = CGPoint(x: targetSize.width / 2, y: targetSize.height / 2)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x + offset.width, y: center.y + offset.height)
        transform = transform.rotated(by: rotation.radians)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        return baseRect.applying(transform)
    }

    private func renderPaletteSourceImage(for media: ProcessedMedia) -> UIImage {
        if media.type == .image, selectedFilter != .normal {
            return FilterService.shared.applyFilter(selectedFilter, to: media.image, intensity: filterIntensity)
        }
        return media.image
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
            let paletteImage = storyBackgroundImage(
                baseImage: renderPaletteSourceImage(for: firstMedia),
                targetSize: targetSize
            )
            paletteImage.draw(in: rect)

            let renderImage: UIImage
            if selectedFilter != .normal {
                renderImage = FilterService.shared.applyFilter(selectedFilter, to: baseImage, intensity: filterIntensity)
            } else {
                renderImage = baseImage
            }

            context.cgContext.saveGState()
            let scaleFactorX = targetSize.width / max(screenSize.width, 1)
            let scaleFactorY = targetSize.height / max(screenSize.height, 1)
            let baseRect = mediaRectForStoryCanvas(mediaSize: renderImage.size, targetSize: targetSize)

            context.cgContext.translateBy(
                x: (targetSize.width / 2) + (imageOffset.width * scaleFactorX),
                y: (targetSize.height / 2) + (imageOffset.height * scaleFactorY)
            )
            context.cgContext.rotate(by: imageRotation.radians)
            context.cgContext.scaleBy(x: imageScale, y: imageScale)
            context.cgContext.translateBy(x: -targetSize.width / 2, y: -targetSize.height / 2)

            let imageRect = baseRect
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
        guard media.type == .video, media.storyVideoMode != .autoSplit else { return false }
        return drawingImage != nil
            || !storyText.isEmpty
            || abs(imageScale - 1) > 0.001
            || abs(imageOffset.width) > 0.5
            || abs(imageOffset.height) > 0.5
            || abs(imageRotation.radians) > 0.001
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
        let backgroundImage = storyBackgroundImage(
            baseImage: renderPaletteSourceImage(for: media),
            targetSize: targetSize
        )

        let composition = AVMutableComposition()
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let timescale = Int32(max(30, min(60, Int(frameRate.rounded()))))

        let blurVideoURL = try await createStillImageVideo(
            from: backgroundImage,
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
        let baseRect = storyMediaBaseRect(mediaSize: actualSize, canvasSize: targetSize)
        let scale = baseRect.width / max(actualSize.width, 1)
        let scaledTransform = preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaledRect = CGRect(origin: .zero, size: naturalSize).applying(scaledTransform)
        let translation = CGAffineTransform(
            translationX: baseRect.midX - scaledRect.midX,
            y: baseRect.midY - scaledRect.midY
        )
        let scaleFactorX = targetSize.width / max(UIScreen.main.bounds.width, 1)
        let scaleFactorY = targetSize.height / max(UIScreen.main.bounds.height, 1)
        let userTransform = CGAffineTransform.identity
            .translatedBy(
                x: (targetSize.width / 2) + (imageOffset.width * scaleFactorX),
                y: (targetSize.height / 2) + (imageOffset.height * scaleFactorY)
            )
            .rotated(by: imageRotation.radians)
            .scaledBy(x: imageScale, y: imageScale)
            .translatedBy(x: -targetSize.width / 2, y: -targetSize.height / 2)
        let finalTransform = scaledTransform
            .concatenating(translation)
            .concatenating(userTransform)

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

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            throw NSError(domain: "StoryEditor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Video export failed: \(error.localizedDescription)", NSUnderlyingErrorKey: error])
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
            aspectRatio: .nineBySixteen,
            recommendedAspectRatio: .nineBySixteen,
            hasEdits: true,
            thumbnailURL: nil,
            image: finalRenderedImage
        )

        return (finalMedia, finalRenderedImage)
    }

    // ✅ FUNCIÓN ACTUALIZADA: Publicar historia con soporte para listas
    private func publishStory() {
        guard let userId = Auth.auth().currentUser?.uid,
              !selectedMediaItems.isEmpty else { return }

        // 🔗 VALIDAR LÍMITES DE STORY CHAINS
        Task {
            do {
                if isCreatingChain {
                    // Validar título de nueva cadena
                    try StoryChainLimitsService.shared.validateChainTitle(chainTitle)
                } else if isContinuingChain, let existingChainId = chainId {
                    // Validar que se puede continuar la cadena
                    _ = try await StoryChainLimitsService.shared.canContinueChain(chainId: existingChainId, userId: userId)
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
        var mappedSticker = sticker
        let canvasRect = currentMediaCanvasRect()

        let screenBounds = UIScreen.main.bounds
        let looksLikeScreenPosition =
            sticker.position.x > canvasRect.width ||
            sticker.position.y > canvasRect.height ||
            sticker.position.x > screenBounds.width ||
            sticker.position.y > screenBounds.height

        if looksLikeScreenPosition {
            let relativeX = (sticker.position.x - canvasRect.minX) / max(canvasRect.width, 1)
            let relativeY = (sticker.position.y - canvasRect.minY) / max(canvasRect.height, 1)

            mappedSticker.position = CGPoint(
                x: min(max(relativeX, 0.0), 1.0) * canvasRect.width,
                y: min(max(relativeY, 0.0), 1.0) * canvasRect.height
            )
        }

        if mappedSticker.position == .zero {
            mappedSticker.position = CGPoint(x: canvasRect.width / 2, y: canvasRect.height / 2)
        }

        selectedStickers.append(mappedSticker)

        // Feedback háptico
        HapticManager.shared.mediumImpact()

        // ✅ FORZAR ACTUALIZACIÓN DE LA VISTA
        DispatchQueue.main.async {
            self.forceUpdate.toggle()
        }
    }

    private func currentMediaCanvasRect() -> CGRect {
        let windowInsets = keyWindowSafeAreaInsets()
        let viewport = keyWindowBounds()?.size ?? UIScreen.main.bounds.size
        return creatorMomentsCaptureRect(
            in: viewport,
            topInset: windowInsets.top,
            bottomInset: windowInsets.bottom
        )
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

private func requestPhotoLibraryPermission() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    return status == .authorized || status == .limited
}
