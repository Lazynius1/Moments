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
    @Binding var startInTextMode: Bool
    let initialSticker: StickerItem?

    // 🔗 NUEVO: Parámetros de cadena
    let initialChainId: String?
    let initialChainTitle: String?
    let initialChainPosition: Int?
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDiscardChangesAlert = false
    @State private var storyText = ""
    @State private var textPosition: CGPoint = .zero
    @State private var storyTextColor: Color = .white
    @State private var storyTextAlignment: TextAlignment = .center
    @State private var storyTextBackground: TextBackgroundFill = .none
    @State private var storyTextFontSize: CGFloat = 30
    @State private var selectedStickers: [StickerItem] = []
    @State private var selectedStickerId: String? = nil // ✅ NUEVO: Selección de sticker para paleta
    @State private var activeEditingStickerId: String? = nil // ✅ NUEVO: Edición inline
    @State private var showingEmojiPicker = false // ✅ NUEVO: Selector de emojis expandido
    @State private var activeEditorMode: ActiveEditorMode = .idle
    @State private var showingStickerPicker = false
    @State private var isPublishing = false
    @State private var storyAudience: CaptionAndDetailsView.AudienceSetting = .everyone
    @State private var storyExpirationHours = 24
    @State private var isLoadingUserSettings = true // NUEVO
    @Environment(\.colorScheme) var colorScheme
    @State private var showingAudienceSelector = false
    @State private var selectedTextStyle: TextStyle = .modern
    @State private var selectedTextStroke: TextStroke = .none
    @State private var selectedTextMotion: TextMotion = .none
    @State private var selectedVisualEffect: TextEffect = .none
    @State private var storyGradientStops: [Color] = []
    @State private var storyGradientAngle: Int = 0
    @State private var storySelectedGradientStopIndex: Int = 0
    @State private var storyForcesAllCaps = false
    @State private var textOverlays: [StoryTextOverlayDraft] = []
    @State private var activeTextOverlayId: String?
    @State private var drawingImage: UIImage?
    @State private var editableImageViewRef: EditableImageView?

    // ✅ Filtros e Intensidad
    @State private var filterIntensity: Double = 1.0
    @State private var isApplyingFilter = false
    @State private var showingIntensitySlider = false
    @State private var isEditingSticker = false // ✅ NUEVO
    @State private var editingRevealStickerId: String? = nil
    @State private var stickerPickerDetent: PresentationDetent = .medium


    // ✅ Variables para transformaciones de imagen
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var imageRotation: Angle = .zero
    @State private var selectedBackgroundPresetIndex: Int = 0
    @State private var autoBackgroundPalette: [UIColor] = [
        UIColor(Color(hex: "0B1215")),
        UIColor(Color(hex: "FAF9F6"))
    ]
    @State private var autoBackgroundPaletteMediaId: String?

    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []
    @State private var forceUpdate: Bool = false
    @StateObject private var emojiUsageTracker = EmojiUsageTracker()

    // ✅ Filtros
    @State private var selectedFilter: FilterService.FilterType = .normal
    @State private var filteredImage: UIImage? = nil
    @State private var filterTask: Task<Void, Never>? = nil

    // ✅ PROPIEDADES para navegación
    @State private var showingUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var navigationPath = NavigationPath()
    @Namespace private var profileZoomNamespace



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
    @State private var primaryVideoPresentationSize: CGSize? = nil
    @State private var isVideoPreviewMuted = false
    @State private var showingExpirationInfoOverlay = false


    private var isTextMode: Bool { activeEditorMode == .text }
    private var isDrawingMode: Bool { activeEditorMode == .drawing }
    private var isFilterMode: Bool { activeEditorMode == .filters }
    private var chromeIconColor: Color { StoryEditorChromeColor.icon(colorScheme) }
    private var isCanvasModeActive: Bool { activeEditorMode != .idle }
    private var isEditingReveal: Bool { editingRevealStickerId != nil }
    private var hasAnyTextOverlays: Bool { textOverlays.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var showsStoryExpirationSelector: Bool { !isCreatingChain && !isContinuingChain }
    private var showsGeneratedBackground: Bool {
        storyShouldShowGeneratedBackground(scale: imageScale, offset: imageOffset, rotation: imageRotation)
    }
    private var selectedBackgroundPreset: StoryBackgroundPreset {
        StoryBackgroundPreset.presets[selectedBackgroundPresetIndex]
    }

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
                        .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                        .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)

                    // Drawing overlay preview when text editor is open
                    if let drawing = drawingImage, isTextMode {
                        Image(uiImage: drawing)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: mediaCanvasRect.width, height: mediaCanvasRect.height)
                            .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                            .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)
                            .allowsHitTesting(false)
                    }

                    // Overlays
                    if !isTextMode && !isDrawingMode {
                        StoryOverlaysView(
                            canvasSize: mediaCanvasSize,
                            textOverlays: $textOverlays,
                            isTextEditorPresented: Binding(
                                get: { isTextMode },
                                set: { isPresented in
                                    if isPresented {
                                        activeEditorMode = .text
                                    } else {
                                        finishTextEditing()
                                    }
                                }
                            ),
                            stickers: $selectedStickers,
                            drawingImage: $drawingImage,
                            isEditingSticker: $isEditingSticker,
                            editingRevealId: $editingRevealStickerId,
                            onEditTextOverlay: { overlayId in
                                beginEditingTextOverlay(id: overlayId, canvasSize: mediaCanvasSize)
                            },
                            onNavigateToProfile: { userId in
                                handleProfileNavigation(userId: userId)
                            },
                            onNavigateToLocation: { locationName, coordinate in
                                handleLocationNavigation(locationName: locationName, coordinate: coordinate)
                            },
                             selectedStickerId: $selectedStickerId, // ✅ NUEVO: Enlace bidireccional de selección
                             activeEditingStickerId: $activeEditingStickerId // ✅ NUEVO: Edición inline en Canvas
                        )
                        .id(forceUpdate)
                        .frame(width: mediaCanvasRect.width, height: mediaCanvasRect.height)
                        .position(x: mediaCanvasRect.midX, y: mediaCanvasRect.midY)
                    }

                    Color.clear
                        .frame(width: 0, height: 0)
                        .onChange(of: activeEditorMode) { _, mode in
                            if mode == .idle {
                                commitActiveTextOverlayIfNeeded(canvasSize: mediaCanvasSize)
                            }
                        }
                        .onChange(of: storyText) { _, newText in
                            if !newText.isEmpty {
                                seedStoryTextPosition(canvasSize: mediaCanvasSize)
                            }
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
                                    if isPresented {
                                        activeEditorMode = .text
                                    } else {
                                        finishTextEditing()
                                    }
                                }
                            ),
                            text: $storyText,
                            selectedStyle: $selectedTextStyle,
                            textColor: $storyTextColor,
                            textAlignment: $storyTextAlignment,
                            textBackgroundFill: $storyTextBackground,
                            textFontSize: $storyTextFontSize,
                            textStroke: $selectedTextStroke,
                            textMotion: $selectedTextMotion,
                            visualEffect: $selectedVisualEffect,
                            gradientStops: $storyGradientStops,
                            gradientAngle: $storyGradientAngle,
                            selectedGradientStopIndex: $storySelectedGradientStopIndex,
                            forcesAllCaps: $storyForcesAllCaps,
                            mediaSampleImage: currentStorySampleImage()
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(40)
                    }

                    // Floating Emoji Slider Bar — anchored to bottom above keyboard
                    if let activeId = activeEditingStickerId,
                       let sticker = selectedStickers.first(where: { $0.id == activeId }),
                       sticker.type == .emojiSlider {
                        VStack(spacing: 0) {
                            Spacer()
                            emojiSliderPresetBar()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(.keyboard)
                        .zIndex(3100)
                    }
                }
                .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                .ignoresSafeArea(.keyboard)
                .task(id: selectedMediaItems.first?.id) {
                    await resolveAutoBackgroundPaletteIfNeeded()
                }
            }
            .navigationDestination(for: String.self) { userId in
                UserProfileView(userId: userId)
                    .userProfileZoomDestination(userId: userId, namespace: profileZoomNamespace)
            }
            .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            StoryFontRegistry.registerFontsIfNeeded()
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

            if startInTextMode && selectedMediaItems.isEmpty {
                applyRandomBackgroundPresetIfNeeded()
                beginCreatingTextOverlay(canvasSize: currentMediaCanvasRect().size)
                startInTextMode = false
            } else if selectedMediaItems.isEmpty {
                applyRandomBackgroundPresetIfNeeded()
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
            StickerPickerView(selectedStickers: $selectedStickers, activeEditingStickerId: $activeEditingStickerId, isVideo: selectedMediaItems.first?.type == .video)
                .ignoresSafeArea()
                .onDisappear {
                    activeEditorMode = .idle
                    stickerPickerDetent = .medium
                }
                .presentationDetents([.medium, .large], selection: $stickerPickerDetent)
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(isPresented: $showingEmojiPicker, onSelect: { emoji in
                updateActiveSliderEmoji(emoji)
            })
            .chatPickerSheetPresentation()
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
                } else if showDiscardChangesAlert {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showDiscardChangesAlert = false
                        }

                    discardChangesOverlay
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
    private var storyContentAudience: ContentAudience {
        ContentAudience.fromCaptionAudienceSetting(
            storyAudience,
            hasCustomList: storyAudience == .custom && selectedListId != nil
        )
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
                case .mutuals: return .mutuals
                case .bestFriends: return .bestFriends
                case .custom:
                    return selectedListId != nil ? .customList : .custom
                case .onlyMe: return .onlyMe
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: storyAudience = .everyone
                case .mutuals: storyAudience = .mutuals
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
        case .mutuals:      audienceRaw = ContentAudience.mutuals.rawValue
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
        case .mutuals: return .mutuals
        case .bestFriends: return .bestFriends
        case .custom: return .custom
        case .customList: return .customList
        }
    }

    private func refreshPrimaryVideoAspectRatio() {
        guard let media = selectedMediaItems.first, media.type == .video, let videoURL = media.videoURL else {
            primaryVideoPresentationSize = nil
            return
        }

        Task {
            let asset = AVURLAsset(url: videoURL)
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await videoTrack.load(.naturalSize),
                  let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
                return
            }

            let resolvedSize = StoryViewerScreen.resolvedVideoPresentationSize(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            )

            await MainActor.run {
                if selectedMediaItems.first?.id == media.id {
                    primaryVideoPresentationSize = resolvedSize.width > 0 && resolvedSize.height > 0 ? resolvedSize : nil
                }
            }
        }
    }

    private func resetBaseMediaTransform() {
        imageScale = 1.0
        imageOffset = .zero
        imageRotation = .zero
        selectedBackgroundPresetIndex = 0
    }

    private func applyRandomBackgroundPresetIfNeeded() {
        guard selectedMediaItems.isEmpty else { return }
        selectedBackgroundPresetIndex = Int.random(in: 0..<StoryBackgroundPreset.presets.count)
    }

    @ViewBuilder
    private func backgroundMediaView(canvasSize: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            storyEditorMediaContent(canvasSize: canvasSize)
            canvasAutoSplitNotice()
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func storyEditorMediaContent(canvasSize: CGSize) -> some View {
        if let firstMedia = selectedMediaItems.first {
            if firstMedia.type == .video, let videoURL = firstMedia.videoURL {
                let fallbackMediaSize = CGSize(
                    width: max(firstMedia.image.size.width, 1),
                    height: max(firstMedia.image.size.height, 1)
                )
                let resolvedMediaSize = primaryVideoPresentationSize ?? fallbackMediaSize
                let mediaAspectRatio = resolvedMediaSize.width / max(resolvedMediaSize.height, 1)
                StoryEditableMediaContainer(
                    mediaSize: resolvedMediaSize,
                    scale: $imageScale,
                    offset: $imageOffset,
                    rotation: $imageRotation,
                    canvasSize: canvasSize,
                    paletteIdentity: "\(firstMedia.id)-video-\(Int(mediaAspectRatio * 1000))",
                    paletteSourceImage: firstMedia.image,
                    paletteOverride: currentStoryBackgroundPalette(for: firstMedia),
                    isInteractionEnabled: activeEditorMode == .idle && !isEditingSticker
                ) { baseRect in
                    StoryVideoPlayerView(
                        videoURL: videoURL,
                        videoGravity: StoryMediaLayoutRules.presentationMode(
                            for: mediaAspectRatio,
                            canvasAspectRatio: canvasSize.width / max(canvasSize.height, 1)
                        ).videoGravity,
                        isMuted: isVideoPreviewMuted
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
                    paletteIdentity: firstMedia.id,
                    paletteOverride: currentStoryBackgroundPalette(for: firstMedia),
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
            textOnlyBackgroundView(canvasSize: canvasSize)
        }
    }

    @ViewBuilder
    private func textOnlyBackgroundView(canvasSize: CGSize) -> some View {
        let palette = selectedBackgroundPreset.usesAutoPalette ? autoBackgroundPalette : selectedBackgroundPreset.uiColors
        let resolvedPalette = palette.isEmpty
            ? [UIColor(Color(hex: "0B1215")), UIColor(Color(hex: "FAF9F6"))]
            : palette

        LinearGradient(
            colors: resolvedPalette.map { Color(uiColor: $0) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func canvasAutoSplitNotice() -> some View {
        autoSplitNoticeView()
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func topBarView(topInset: CGFloat) -> some View {
        if activeEditingStickerId != nil {
            ZStack {
                HStack {
                    Color.clear
                        .frame(width: 44, height: 44)

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            activeEditingStickerId = nil
                        }
                        HapticManager.shared.lightImpact()
                    }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(chromeIconColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .momentsChromeGlass(in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                
                if showsStickerPaletteButton {
                    Button(action: cycleSelectedStickerColor) {
                        HStack(spacing: 8) {
                            Image(systemName: "swatchpalette")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 4) {
                                ForEach(Array(stickerPalettePreviewColors().enumerated()), id: \.offset) { entry in
                                    Circle()
                                        .fill(entry.element)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                        .foregroundColor(chromeIconColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.top, topBarTopPadding(topInset: topInset))
        } else {
            ZStack {
                HStack {
                    Button(action: {
                        if isFilterMode {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                activeEditorMode = .idle
                            }
                        } else {
                            showDiscardChangesAlert = true
                        }
                    }) {
                        Image(systemName: isFilterMode ? "chevron.left" : "xmark")
                            .font(.title2)
                            .foregroundColor(chromeIconColor)
                            .padding(12)
                            .momentsChromeGlass(in: Circle())
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
                                .foregroundColor(chromeIconColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .momentsChromeGlass(in: Capsule())
                        }
                    } else {
                        Button(action: { saveToGallery() }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundColor(chromeIconColor)
                                .padding(12)
                                .momentsChromeGlass(in: Circle())
                        }
                    }
                }

                if showsStickerPaletteButton {
                    Button(action: cycleSelectedStickerColor) {
                        HStack(spacing: 8) {
                            Image(systemName: "swatchpalette")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 4) {
                                ForEach(Array(stickerPalettePreviewColors().enumerated()), id: \.offset) { entry in
                                    Circle()
                                        .fill(entry.element)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                        .foregroundColor(chromeIconColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                    }
                } else if showsBackgroundPaletteButton {
                    Button(action: cycleBackgroundPreset) {
                        HStack(spacing: 8) {
                            Image(systemName: "swatchpalette")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 4) {
                                ForEach(Array(backgroundPalettePreviewColors().prefix(3).enumerated()), id: \.offset) { entry in
                                    Circle()
                                        .fill(entry.element)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                        .foregroundColor(chromeIconColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, topBarTopPadding(topInset: topInset))
        }
    }

    private var discardChangesOverlay: some View {
        let primaryTextColor = colorScheme == .dark ? Color.white : Color.black
        let secondaryTextColor = primaryTextColor.opacity(0.72)
        let dividerColor = primaryTextColor.opacity(0.12)

        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(NSLocalizedString("storyEditor.discardDraft.title", comment: "Discard story draft title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("storyEditor.discardDraft.message", comment: "Discard story draft message"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.5)

            MomentRowButton(action: {
                showDiscardChangesAlert = false
                currentFlow = .storyCamera
            }) {
                Text(NSLocalizedString("storyEditor.discardDraft.confirm", comment: "Discard draft"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.5)

            MomentRowButton(action: {
                showDiscardChangesAlert = false
            }) {
                Text(NSLocalizedString("storyEditor.discardDraft.cancel", comment: "Continue editing"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
        }
        .frame(maxWidth: 320)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 24)
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .zIndex(5000)
    }

    @ViewBuilder
    private func sideToolbarView() -> some View {
        if activeEditingStickerId == nil {
            VStack(spacing: 12) {
                EditingToolIcon(icon: "textformat.alt") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        beginCreatingTextOverlay(canvasSize: currentMediaCanvasRect().size)
                    }
                }
                EditingToolIcon(icon: "face.smiling", usesCustomStickerGlyph: true) {
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
                        .foregroundColor(isFilterMode ? .pink : chromeIconColor)
                        .frame(width: 44, height: 44)
                        .momentsChromeGlass(in: Circle())
                        .overlay(Circle().stroke(isFilterMode ? Color.pink : Color.clear, lineWidth: 1))
                }

                if let firstMedia = selectedMediaItems.first, firstMedia.type == .video {
                    Button(action: {
                        isVideoPreviewMuted.toggle()
                    }) {
                        Image(systemName: isVideoPreviewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(chromeIconColor)
                            .frame(width: 44, height: 44)
                            .momentsChromeGlass(in: Circle())
                    }
                }

                if !isContinuingChain {
                    Button(action: {
                        withAnimation(.spring()) { isCreatingChain.toggle() }
                    }) {
                        Image(systemName: "link")
                            .font(.system(size: 20))
                            .foregroundColor(isCreatingChain ? .blue : chromeIconColor)
                            .frame(width: 44, height: 44)
                            .momentsChromeGlass(in: Circle())
                            .overlay(Circle().stroke(isCreatingChain ? Color.blue : Color.clear, lineWidth: 1))
                    }
                }

                if showsStoryExpirationSelector {
                    Button(action: {
                        storyExpirationHours = storyExpirationHours == 24 ? 48 : 24
                    }) {
                        Text(String(format: NSLocalizedString("storyEditor.expiration.option", comment: "Story expiration option"), storyExpirationHours))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(chromeIconColor)
                            .frame(width: 44, height: 44)
                            .momentsChromeGlass(in: Circle())
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                showingExpirationInfoOverlay = true
                            }
                        }
                    )
                    .accessibilityLabel(NSLocalizedString("storyEditor.expiration.selector", comment: "Story expiration selector"))
                    .accessibilityHint(String(format: NSLocalizedString("storyEditor.expiration.optionAccessibility", comment: "Story expiration option accessibility"), storyExpirationHours))
                }
            }
            .padding(.trailing, 16)
        }
    }

    @ViewBuilder
    private func mainControlsOverlay(
        proxy: GeometryProxy,
        mediaCanvasRect: CGRect
    ) -> some View {
        if !isTextMode && !isDrawingMode {
            VStack {
                if !isEditingReveal {
                    topBarView(topInset: proxy.safeAreaInsets.top)
                }

                Group {
                    if activeEditorMode == .idle && !isEditingReveal {
                        HStack {
                            Spacer()
                            sideToolbarView()
                        }
                    }

                    Spacer()

                    // Video playback controls
                    if let firstMedia = selectedMediaItems.first, firstMedia.type == .video, !isEditingReveal {
                        VideoControlsOverlay()
                    }

                    bottomControlsView(
                        bottomInset: proxy.safeAreaInsets.bottom,
                        canvasBottomEdge: mediaCanvasRect.maxY,
                        viewportHeight: proxy.size.height
                    )
                }
                .opacity((isEditingSticker && !isEditingReveal) ? 0 : 1)
                .disabled(isEditingSticker && !isEditingReveal)
            }
            .overlay(alignment: .topTrailing) {
                if showingExpirationInfoOverlay {
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showingExpirationInfoOverlay = false
                                }
                            }

                        storyExpirationInfoOverlay
                            .padding(.top, max(proxy.safeAreaInsets.top, 16) + 84)
                            .padding(.trailing, 68)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private var storyExpirationInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("storyEditor.expiration.info.title", comment: "Story expiration info title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)

            Text(NSLocalizedString("storyEditor.expiration.info.message", comment: "Story expiration info message"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle((colorScheme == .dark ? Color.white : Color.black).opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 260, alignment: .leading)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 20, x: 0, y: 10)
        .onTapGesture {
            // Consume taps inside the card so only outside taps dismiss it.
        }
    }

    @ViewBuilder
    private func bottomPublishingInset() -> some View {
        if activeEditorMode == .idle && activeEditingStickerId == nil {
            if isEditingReveal {
                RevealStickerBottomControlsInset(
                    stickers: $selectedStickers,
                    editingId: $editingRevealStickerId
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
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
                            .momentsChromeGlass(in: Capsule(), interactive: true)
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
                            .momentsChromeGlass(in: Capsule(), interactive: false)
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
                                        AudienceIconView(
                                            audience: storyContentAudience,
                                            size: AudienceIconMetrics.storyCapsule,
                                            colorScheme: colorScheme
                                        )
                                        .frame(width: 22, height: 22)
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
                                .momentsChromeGlass(in: Capsule(), interactive: true)
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
    }


    @ViewBuilder
    private func bottomControlsView(bottomInset: CGFloat, canvasBottomEdge: CGFloat, viewportHeight: CGFloat) -> some View {
        if activeEditingStickerId == nil {
            VStack(spacing: 12) {
                if isFilterMode {
                    // Intensity Slider
                    if selectedFilter != .normal && showingIntensitySlider {
                        VStack(spacing: 4) {
                            Text("\(Int(filterIntensity * 100))%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(chromeIconColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .momentsChromeGlass(in: Capsule())

                            Slider(value: $filterIntensity, in: 0...1.0)
                                .tint(chromeIconColor)
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

            }
            .padding(.horizontal, activeEditorMode == .idle && !isCreatingChain ? 0 : 16)
            .padding(.top, activeEditorMode == .idle && !isCreatingChain ? 0 : max(10, min(26, viewportHeight - canvasBottomEdge - 94)))
            .padding(.bottom, bottomControlsBottomPadding(bottomInset: bottomInset))
        }
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
            .foregroundColor(chromeIconColor.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
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
                .momentsChromeGlass(in: Capsule(), interactive: true)
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
                        case .mutuals:
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
        let palette = resolvedStoryBackgroundPalette(for: baseImage)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            drawStoryMediaBackground(
                in: CGRect(origin: .zero, size: targetSize),
                palette: palette,
                context: context.cgContext
            )
        }
    }

    private func currentTextOnlyBackgroundImage(targetSize: CGSize) -> UIImage {
        let palette = (selectedBackgroundPreset.usesAutoPalette ? autoBackgroundPalette : selectedBackgroundPreset.uiColors)
        let fallbackPalette = [
            UIColor(Color(hex: "0B1215")),
            UIColor(Color(hex: "203A43")),
            UIColor(Color(hex: "FAF9F6"))
        ]
        let resolvedPalette = palette.isEmpty ? fallbackPalette : palette
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            drawStoryMediaBackground(
                in: CGRect(origin: .zero, size: targetSize),
                palette: resolvedPalette,
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

    private func resolvedStoryBackgroundPalette(for image: UIImage) -> [UIColor] {
        if selectedBackgroundPreset.usesAutoPalette {
            return autoBackgroundPalette
        }
        return selectedBackgroundPreset.uiColors
    }

    private func currentStoryBackgroundPalette(for media: ProcessedMedia) -> [UIColor]? {
        if selectedBackgroundPreset.usesAutoPalette {
            return autoBackgroundPalette
        }
        return selectedBackgroundPreset.uiColors
    }

    private var showsBackgroundPaletteButton: Bool {
        !isFilterMode && activeEditorMode == .idle && !isEditingSticker && (selectedMediaItems.isEmpty || showsGeneratedBackground)
    }

    private func cycleBackgroundPreset() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedBackgroundPresetIndex = (selectedBackgroundPresetIndex + 1) % StoryBackgroundPreset.presets.count
        }
    }

    private func backgroundPalettePreviewColors() -> [Color] {
        let palette = selectedBackgroundPreset.usesAutoPalette
            ? autoBackgroundPalette
            : selectedBackgroundPreset.uiColors
        return palette.prefix(3).map { Color(uiColor: $0) }
    }

    @MainActor
    private func resolveAutoBackgroundPaletteIfNeeded() async {
        guard let firstMedia = selectedMediaItems.first else { return }
        guard autoBackgroundPaletteMediaId != firstMedia.id else { return }

        let mediaId = firstMedia.id
        let sourceImage = firstMedia.image
        let palette = await Task.detached(priority: .userInitiated) {
            storyDominantBackgroundColors(from: sourceImage)
        }.value

        guard selectedMediaItems.first?.id == mediaId else { return }
        autoBackgroundPalette = palette
        autoBackgroundPaletteMediaId = mediaId
    }

    private var showsStickerPaletteButton: Bool {
        guard let activeId = activeEditingStickerId,
              let activeSticker = selectedStickers.first(where: { $0.id == activeId }) else { return false }

        switch activeSticker.type {
        case .poll, .question, .quiz, .countdown, .emojiSlider:
            return true
        default:
            return false
        }
    }

    private func cycleSelectedStickerColor() {
        guard let selectedId = activeEditingStickerId ?? selectedStickerId,
              let index = selectedStickers.firstIndex(where: { $0.id == selectedId }) else { return }
        
        let currentVariant = selectedStickers[index].interactionData?.styleVariant ?? 0
        let nextVariant = (currentVariant + 1) % 6
        
        var data = selectedStickers[index].interactionData ?? StickerItem.StickerInteractionData()
        data.styleVariant = nextVariant
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            selectedStickers[index].interactionData = data
        }
        
        HapticManager.shared.lightImpact()
    }

    private func stickerPalettePreviewColors() -> [Color] {
        [Color(hex: "FF5F6D"), Color(hex: "9D4EDD"), Color(hex: "4A00E0")]
    }

    private func updateActiveSliderEmoji(_ emoji: String) {
        guard let activeId = activeEditingStickerId,
              let index = selectedStickers.firstIndex(where: { $0.id == activeId }) else { return }
        var data = selectedStickers[index].interactionData ?? StickerItem.StickerInteractionData()
        data.sliderEmoji = emoji
        emojiUsageTracker.increment(emoji)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            selectedStickers[index].interactionData = data
            forceUpdate.toggle()
        }
        HapticManager.shared.lightImpact()
    }

    @ViewBuilder
    private func emojiSliderPresetBar() -> some View {
        let presetEmojis = resolvedEmojiSliderEmojis()
        let bottomPad: CGFloat = keyboardHeight > 0
            ? keyboardHeight + 96
            : keyWindowSafeAreaInsets().bottom + 72

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(presetEmojis, id: \.self) { emoji in
                        Button(action: { updateActiveSliderEmoji(emoji) }) {
                            Text(emoji)
                                .font(.system(size: 34))
                                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(MomentEmojiScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
            }

            // Divisor
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 30)
                .padding(.horizontal, 4)

            // Botón "más"
            Button(action: {
                showingEmojiPicker = true
                HapticManager.shared.lightImpact()
            }) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(chromeIconColor)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 4, x: 0, y: 2)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(.bottom, bottomPad)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: keyboardHeight)
        .ignoresSafeArea(.keyboard)
    }

    private func resolvedEmojiSliderEmojis() -> [String] {
        emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.emojiSlider, limit: 8)
    }

    private func renderStoryOverlayImage(targetSize: CGSize, screenSize: CGSize) -> UIImage? {
        // Text overlays are persisted as metadata and rendered live in the viewer (not baked into media).
        guard drawingImage != nil else { return nil }

        let scaleFactorX = targetSize.width / max(screenSize.width, 1)
        let scaleFactorY = targetSize.height / max(screenSize.height, 1)
        let editorOuterHorizontalPadding: CGFloat = 24
        let editorInnerHorizontalPadding: CGFloat = 14
        let editorInnerVerticalPadding: CGFloat = 10
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)

            if let drawing = drawingImage {
                drawing.draw(in: rect, blendMode: .normal, alpha: 1.0)
            }

        }
    }

    private func renderStoryWithOverlays() -> UIImage {
        let screenSize = UIScreen.main.bounds.size
        let targetSize = storyRenderTargetSize(for: screenSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let editorCanvasSize = currentMediaCanvasRect().size

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            if let firstMedia = selectedMediaItems.first {
                let baseImage = firstMedia.image
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
                let scaleFactorX = targetSize.width / max(editorCanvasSize.width, 1)
                let scaleFactorY = targetSize.height / max(editorCanvasSize.height, 1)
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
            } else {
                currentTextOnlyBackgroundImage(targetSize: targetSize).draw(in: rect)
            }

            if let overlayImage = renderStoryOverlayImage(targetSize: targetSize, screenSize: editorCanvasSize) {
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
            || hasAnyTextOverlays
            || abs(imageScale - 1) > 0.001
            || abs(imageOffset.width) > 0.5
            || abs(imageOffset.height) > 0.5
            || abs(imageRotation.radians) > 0.001
    }

    private func exportVideoWithCurrentOverlays(
        _ media: ProcessedMedia,
        preRenderedOverlay: UIImage?,
        preRenderedBackground: UIImage?,
        targetSize: CGSize,
        editorCanvasSize: CGSize,
        imageScale: CGFloat,
        imageOffset: CGSize,
        imageRotation: Angle
    ) async throws -> URL {
        guard let sourceURL = media.videoURL else {
            throw NSError(domain: "StoryEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing source video URL"])
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "StoryEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing video track"])
        }

        let duration = try await asset.load(.duration)
        let overlayImage = preRenderedOverlay
        let backgroundImage = preRenderedBackground ?? storyBackgroundImage(
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
        let editorCanvasSize = currentMediaCanvasRect().size
        let scaleFactorX = targetSize.width / max(editorCanvasSize.width, 1)
        let scaleFactorY = targetSize.height / max(editorCanvasSize.height, 1)
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

    private func prepareMediaForStoryUpload(
        from media: ProcessedMedia,
        preRenderedImage: UIImage,
        preRenderedOverlay: UIImage?,
        preRenderedBackground: UIImage?,
        shouldBake: Bool,
        targetSize: CGSize,
        editorCanvasSize: CGSize,
        imageScale: CGFloat,
        imageOffset: CGSize,
        imageRotation: Angle
    ) async throws -> (mediaItem: ProcessedMedia, finalRenderedImage: UIImage) {
        guard shouldBake else {
            return (media, preRenderedImage)
        }

        let exportedVideoURL = try await exportVideoWithCurrentOverlays(
            media,
            preRenderedOverlay: preRenderedOverlay,
            preRenderedBackground: preRenderedBackground,
            targetSize: targetSize,
            editorCanvasSize: editorCanvasSize,
            imageScale: imageScale,
            imageOffset: imageOffset,
            imageRotation: imageRotation
        )
        let finalMedia = media.with(
            videoURL: exportedVideoURL,
            aspectRatio: .nineBySixteen,
            recommendedAspectRatio: .nineBySixteen,
            hasEdits: true,
            thumbnailURL: nil,
            image: preRenderedImage
        )

        return (finalMedia, preRenderedImage)
    }

    private func makeTextOnlyStoryMedia(from image: UIImage) -> ProcessedMedia {
        ProcessedMedia(
            type: .image,
            image: image,
            videoURL: nil,
            aspectRatio: .nineBySixteen,
            recommendedAspectRatio: .nineBySixteen
        )
    }

    // ✅ FUNCIÓN ACTUALIZADA: Publicar historia con soporte para listas
    private func publishStory() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let hasStoryContent = !selectedMediaItems.isEmpty || hasAnyTextOverlays || !selectedStickers.isEmpty || drawingImage != nil
        guard hasStoryContent else { return }


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
        // 1. Capturar todos los estados y renderizados en el Main Actor sincrónicamente antes de cerrar/resetear
        let targetSize = storyRenderTargetSize()
        let editorCanvasSize = currentMediaCanvasRect().size
        let finalRenderedImage = renderStoryWithOverlays()
        let media = selectedMediaItems.first ?? makeTextOnlyStoryMedia(from: finalRenderedImage)
        let preRenderedOverlay = renderStoryOverlayImage(targetSize: targetSize, screenSize: editorCanvasSize)
        let preRenderedBackground = selectedMediaItems.first.map {
            storyBackgroundImage(baseImage: renderPaletteSourceImage(for: $0), targetSize: targetSize)
        } ?? currentTextOnlyBackgroundImage(targetSize: targetSize)
        let shouldBake = selectedMediaItems.first.map(shouldBakeCurrentOverlaysIntoVideo) ?? false

        let capturedImageScale = imageScale
        let capturedImageOffset = imageOffset
        let capturedImageRotation = imageRotation

        let stickerData = selectedStickers
        let drawingData = drawingImage?.pngData()
        let resolvedExpirationHours = (isCreatingChain || isContinuingChain) ? 48 : storyExpirationHours

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
                case .mutuals: return .mutuals
                case .bestFriends: return .bestFriends
                case .custom: return selectedListId != nil ? .customList : .custom
                case .onlyMe: return .onlyMe
                }
            }
        }()

        let contentRect = currentMediaCanvasRect()
        commitActiveTextOverlayIfNeeded(canvasSize: contentRect.size)
        let preparedTextOverlays = textOverlays
            .sorted { $0.layerOrder < $1.layerOrder }
            .compactMap { $0.metadata(in: contentRect) }
        let primaryTextOverlay = preparedTextOverlays.first
        let legacyStoryText = primaryTextOverlay?.text

        // 2. Iniciar preparación instantánea en el servicio con estado .initializing
        guard let uploadingStory = BackgroundStoryUploadService.shared.startPreparingStory(
            mediaItem: media,
            storyText: legacyStoryText,
            textPosition: primaryTextOverlay?.displayPosition(in: contentRect.size),
            selectedTextStyle: primaryTextOverlay.flatMap { StoryEditingView.TextStyle(rawValue: $0.styleRaw) },
            textOverlayMetadata: primaryTextOverlay,
            textOverlays: preparedTextOverlays.isEmpty ? nil : preparedTextOverlays,
            stickerData: stickerData,
            drawingData: drawingData,
            audienceSetting: contentAudience,
            customViewers: customSelectedUsers,
            customListId: selectedListId,
            selectedListName: selectedListName,
            chainId: finalChainId,
            chainPosition: finalChainPosition,
            chainTitle: finalChainTitle,
            allowOthersToContinue: (isCreatingChain || isContinuingChain) ? allowOthersToContinue : nil,
            continuationAudience: (isCreatingChain || isContinuingChain) ? convertContinuationAudience() : nil,
            continuationCustomViewers: (isCreatingChain || isContinuingChain) ? customSelectedUsers : nil,
            continuationCustomListId: (isCreatingChain || isContinuingChain) ? selectedListId : nil,
            continuationCustomListName: (isCreatingChain || isContinuingChain) ? selectedListName : nil,
            expirationHours: resolvedExpirationHours,
            storyVideoMode: media.storyVideoMode
        ) else {
            // Feedback háptico de error
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
            alertMessage = NSLocalizedString("storyEditor.error.publishStart", comment: "Error starting story upload")
            showAlert = true
            return
        }

        // 3. 🔥 CERRAR PANTALLA Y RESETEAR FORMULARIO INSTANTÁNEAMENTE
        self.showCreatorView = false

        // 🎉 Feedback háptico de éxito inicial
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // 🧹 Limpiar formulario para próximo uso
        self.resetStoryForm()

        // 4. Procesar la composición pesada en segundo plano
        Task.detached(priority: .userInitiated) {
            do {
                let preparedUpload = try await self.prepareMediaForStoryUpload(
                    from: media,
                    preRenderedImage: finalRenderedImage,
                    preRenderedOverlay: preRenderedOverlay,
                    preRenderedBackground: preRenderedBackground,
                    shouldBake: shouldBake,
                    targetSize: targetSize,
                    editorCanvasSize: editorCanvasSize,
                    imageScale: capturedImageScale,
                    imageOffset: capturedImageOffset,
                    imageRotation: capturedImageRotation
                )

                await BackgroundStoryUploadService.shared.publishPreparedStoryInBackground(
                    uploadingStory: uploadingStory,
                    preparedMediaItem: preparedUpload.mediaItem,
                    finalRenderedImage: preparedUpload.finalRenderedImage
                )
            } catch {
                await MainActor.run {
                    alertMessage = NSLocalizedString("storyEditor.error.publishStart", comment: "Error starting story upload")
                }
                await BackgroundStoryUploadService.shared.markStoryAsFailed(
                    uploadingStory: uploadingStory,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    // 🧹 AÑADE esta nueva función para limpiar el formulario:
    private func resetStoryForm() {
        storyText = ""
        textPosition = .zero
        storyExpirationHours = 24
        activeTextOverlayId = nil
        textOverlays = []
        selectedStickers = []
        drawingImage = nil
        selectedTextStyle = .modern
        selectedTextMotion = .none
        selectedVisualEffect = .none
        storyGradientStops = []
        storyGradientAngle = 0
        storySelectedGradientStopIndex = 0
        storyForcesAllCaps = false
        storyTextColor = .white
        storyTextAlignment = .center
        storyTextBackground = .none
        storyTextFontSize = 30

    }

    private func seedStoryTextPosition(canvasSize: CGSize) {
        guard !storyText.isEmpty else { return }
        guard StoryTextCanvasPlacement.needsSeed(position: textPosition, canvasSize: canvasSize) else { return }
        textPosition = StoryTextCanvasPlacement.defaultPosition(in: canvasSize)
    }

    private func beginCreatingTextOverlay(canvasSize: CGSize) {
        commitActiveTextOverlayIfNeeded(canvasSize: canvasSize)

        let nextOrder = nextTextLayerOrder()
        let initialPosition = StoryTextCanvasPlacement.defaultPosition(in: canvasSize)
        let newOverlay = StoryTextOverlayDraft(
            text: "",
            position: initialPosition,
            style: selectedTextStyle,
            visualEffect: selectedVisualEffect,
            textColor: storyTextColor,
            textAlignment: storyTextAlignment,
            textBackgroundFill: storyTextBackground,
            fontSize: storyTextFontSize,
            textStroke: selectedTextStroke,
            textMotion: selectedTextMotion,
            forcesAllCaps: storyForcesAllCaps,
            layerOrder: nextOrder,
            gradientStopHexes: StoryTextGradientSettings.encodeStops(storyGradientStops),
            gradientAngle: storyGradientAngle
        )

        textOverlays.append(newOverlay)
        loadEditorBuffer(from: newOverlay)
        activeTextOverlayId = newOverlay.id
        activeEditorMode = .text
    }

    private func beginEditingTextOverlay(id: String, canvasSize: CGSize) {
        commitActiveTextOverlayIfNeeded(canvasSize: canvasSize)
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let frontmostOrder = nextTextLayerOrder()
        textOverlays[index].layerOrder = frontmostOrder
        let overlay = textOverlays[index]
        loadEditorBuffer(from: overlay)
        activeTextOverlayId = id
        activeEditorMode = .text
    }

    private func finishTextEditing() {
        commitActiveTextOverlayIfNeeded(canvasSize: currentMediaCanvasRect().size)
        activeEditorMode = .idle
        activeTextOverlayId = nil
    }

    private func commitActiveTextOverlayIfNeeded(canvasSize: CGSize) {
        guard let activeTextOverlayId else { return }
        let trimmed = storyText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            textOverlays.removeAll { $0.id == activeTextOverlayId }
            return
        }

        let seededPosition: CGPoint
        if StoryTextCanvasPlacement.needsSeed(position: textPosition, canvasSize: canvasSize) {
            seededPosition = StoryTextCanvasPlacement.defaultPosition(in: canvasSize)
        } else {
            seededPosition = textPosition
        }

        let updated = StoryTextOverlayDraft(
            id: activeTextOverlayId,
            text: trimmed,
            position: seededPosition,
            style: selectedTextStyle,
            visualEffect: selectedVisualEffect,
            textColor: storyTextColor,
            textAlignment: storyTextAlignment,
            textBackgroundFill: storyTextBackground,
            fontSize: storyTextFontSize,
            textStroke: selectedTextStroke,
            textMotion: selectedTextMotion,
            forcesAllCaps: storyForcesAllCaps,
            layerOrder: layerOrder(for: activeTextOverlayId),
            gradientStopHexes: StoryTextGradientSettings.encodeStops(storyGradientStops),
            gradientAngle: storyGradientAngle
        )

        if let index = textOverlays.firstIndex(where: { $0.id == activeTextOverlayId }) {
            textOverlays[index] = updated
        } else {
            textOverlays.append(updated)
        }
    }

    private func loadEditorBuffer(from overlay: StoryTextOverlayDraft) {
        storyText = overlay.text
        textPosition = overlay.position
        selectedTextStyle = overlay.style
        selectedVisualEffect = overlay.visualEffect
        storyTextColor = overlay.textColor
        storyTextAlignment = overlay.textAlignment
        storyTextBackground = overlay.textBackgroundFill
        storyTextFontSize = overlay.fontSize
        selectedTextStroke = overlay.textStroke
        selectedTextMotion = overlay.textMotion
        storyForcesAllCaps = overlay.forcesAllCaps
        storyGradientStops = overlay.gradientColors
        storyGradientAngle = overlay.gradientAngle
        storySelectedGradientStopIndex = 0
    }

    private func nextTextLayerOrder() -> Int {
        let maxTextOrder = textOverlays.map(\.layerOrder).max() ?? -1
        let maxStickerOrder = selectedStickers.map { $0.zIndex ?? 0 }.max() ?? -1
        return max(maxTextOrder, maxStickerOrder) + 1
    }

    private func layerOrder(for overlayId: String) -> Int {
        textOverlays.first(where: { $0.id == overlayId })?.layerOrder ?? nextTextLayerOrder()
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
        case .solid:
            return UIColor(storyTextColor)
        case .semiTransparent:
            return UIColor(storyTextColor).withAlphaComponent(0.70)
        case .inverted:
            return StoryTextAttributesBuilder.contrastUIColor(for: storyTextColor) == .black ? .white : .black
        }
    }

    private func resolvedTextBackgroundUIColor() -> UIColor? {
        StoryTextAttributesBuilder.backgroundUIColor(
            fill: storyTextBackground,
            selectedColor: storyTextColor,
            effect: selectedVisualEffect,
            style: selectedTextStyle
        )
    }

    private func currentStorySampleImage() -> UIImage? {
        if let filteredImage {
            return filteredImage
        }
        return selectedMediaItems.first?.image
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

// MARK: - Emoji Frame Preference Key
private struct EmojiFramePreferenceKey: PreferenceKey {
    typealias Value = [String: CGRect]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Premium Emoji Picker Sheet
struct EmojiPickerView: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emojiUsageTracker = EmojiUsageTracker()

    // Skin tone popover state
    @State private var selectedBaseEmoji: String? = nil
    @State private var emojiFrames: [String: CGRect] = [:]
    @State private var pickerGeometryFrame: CGRect = .zero

    // Skin tone modifiers: yellow, light, medium-light, medium, medium-dark, dark
    private let skinTones: [String] = ["", "🏻", "🏼", "🏽", "🏾", "🏿"]
    private let maxRecentCount = 12

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    private var recentEmojis: [String] {
        emojiUsageTracker.recentlyUsed(limit: maxRecentCount)
    }

    static let emojiCategories: [(nameKey: String, emojis: [String])] = {
        let reactionEmojis = ["😍", "🔥", "😂", "🥹", "❤️", "👏", "🙌", "🎉", "🤔", "💯", "✨", "👀", "🚀", "💀", "😭", "🥳", "😎", "🥺", "🥰", "🧁", "🙄", "😴", "😮‍💨", "🫠", "🤐", "🤯", "💔", "🌟", "🎈"]

        var categoryMap: [String: [String]] = [
            "reactions": reactionEmojis,
            "faces": [],
            "nature": [],
            "food": [],
            "activities": [],
            "travel": [],
            "objects": [],
            "symbols": []
        ]

        func getCategoryKey(_ code: Int) -> String? {
            switch code {
            case 0x1F600...0x1F64F: return "faces"
            case 0x1F440...0x1F487, 0x1F90C...0x1F93F, 0x1F970...0x1F97F: return "faces"
            case 0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F353: return "nature"
            case 0x1F354...0x1F37F, 0x1F9C0...0x1F9CF: return "food"
            case 0x1F3A0...0x1F3C4, 0x1F940...0x1F94F: return "activities"
            case 0x1F680...0x1F6C5, 0x1F300...0x1F32F, 0x1F3E0...0x1F3F0: return "travel"
            case 0x1F4A0...0x1F4FF, 0x1F500...0x1F5FF, 0x1F9E0...0x1F9FF, 0x1FA90...0x1FAAF: return "objects"
            case 0x2700...0x27BF, 0x1F490...0x1F49F, 0x2600...0x26FF: return "symbols"
            default: return nil
            }
        }

        for code in 0x2600...0x1FAFF {
            if let key = getCategoryKey(code), let scalar = UnicodeScalar(code) {
                if scalar.properties.isEmojiPresentation {
                    categoryMap[key, default: []].append(String(scalar))
                }
            }
        }

        return [
            ("storyEditor.emojiPicker.reactions", categoryMap["reactions"] ?? reactionEmojis),
            ("storyEditor.emojiPicker.faces", categoryMap["faces"] ?? []),
            ("storyEditor.emojiPicker.nature", categoryMap["nature"] ?? []),
            ("storyEditor.emojiPicker.food", categoryMap["food"] ?? []),
            ("storyEditor.emojiPicker.activities", categoryMap["activities"] ?? []),
            ("storyEditor.emojiPicker.travel", categoryMap["travel"] ?? []),
            ("storyEditor.emojiPicker.objects", categoryMap["objects"] ?? []),
            ("storyEditor.emojiPicker.symbols", categoryMap["symbols"] ?? [])
        ]
    }()

    private func isSkinToneSupported(emoji: String) -> Bool {
        guard let firstScalar = emoji.unicodeScalars.first else { return false }
        let val = firstScalar.value
        switch val {
        case 0x1F442...0x1F44F,
             0x1F450,
             0x1F466...0x1F487,
             0x1F48F...0x1F490,
             0x1F645...0x1F64F,
             0x1F6A3,
             0x1F6B4...0x1F6B6,
             0x1F90C, 0x1F90F,
             0x1F918...0x1F91F,
             0x1F926,
             0x1F930...0x1F93E,
             0x1F977,
             0x1F9B5...0x1F9B6,
             0x1F9C1...0x1F9C2,
             0x1F9D1...0x1F9FF,
             0x270A...0x270D:
            return true
        default:
            return false
        }
    }

    // Compute the popover bubble position anchored above the tapped emoji
    private func popoverOffset(for base: String, in totalSize: CGSize) -> CGPoint {
        guard let frame = emojiFrames[base] else {
            return CGPoint(x: totalSize.width / 2, y: totalSize.height / 2)
        }
        let bubbleWidth: CGFloat = CGFloat(skinTones.count) * 52 + 24
        let bubbleHeight: CGFloat = 72
        let margin: CGFloat = 12

        var x = frame.midX
        // Clamp horizontally so bubble stays inside screen
        x = max(bubbleWidth / 2 + margin, min(totalSize.width - bubbleWidth / 2 - margin, x))

        var y = frame.minY - bubbleHeight / 2 - 12
        // If too close to top, flip below
        if y < 80 {
            y = frame.maxY + bubbleHeight / 2 + 12
        }
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func emojiPickerCell(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: 36))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .background(
                GeometryReader { itemGeo in
                    Color.clear.preference(
                        key: EmojiFramePreferenceKey.self,
                        value: [emoji: itemGeo.frame(in: .named("emojiPickerRoot"))]
                    )
                }
            )
            .onTapGesture {
                if selectedBaseEmoji != nil {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        selectedBaseEmoji = nil
                    }
                } else {
                    onSelect(emoji)
                    isPresented = false
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                if isSkinToneSupported(emoji: emoji) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        selectedBaseEmoji = emoji
                    }
                    HapticManager.shared.mediumImpact()
                } else {
                    onSelect(emoji)
                    isPresented = false
                }
            }
    }

    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                NavigationView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !recentEmojis.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(LocalizedStringKey("chat.giphy.recents"))
                                        .font(.custom("Poppins-Medium", size: 13))
                                        .foregroundColor(secondaryText)
                                        .padding(.horizontal, 16)

                                    LazyVGrid(columns: gridColumns, spacing: 12) {
                                        ForEach(recentEmojis, id: \.self) { emoji in
                                            emojiPickerCell(emoji)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }

                            ForEach(Self.emojiCategories, id: \.nameKey) { category in
                                if !category.emojis.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(NSLocalizedString(category.nameKey, comment: ""))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal)

                                        LazyVGrid(columns: gridColumns, spacing: 12) {
                                            ForEach(category.emojis, id: \.self) { emoji in
                                                emojiPickerCell(emoji)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .scrollContentBackground(.hidden)
                    .navigationTitle(NSLocalizedString("storyEditor.emojiPicker.title", comment: "Emoji Picker Title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(NSLocalizedString("storyEditor.emojiPicker.close", comment: "Close button")) {
                                isPresented = false
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── Skin-tone bubble popover ─────────────────────────────────
                if let base = selectedBaseEmoji {
                    let totalSize = outerGeo.size
                    let anchor = popoverOffset(for: base, in: totalSize)

                    // Scrim — dismiss on tap
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                selectedBaseEmoji = nil
                            }
                        }

                    // Bubble — anchored to emoji
                    SkinToneBubble(
                        base: base,
                        skinTones: skinTones,
                        colorScheme: colorScheme,
                        onSelect: { variant in
                            onSelect(variant)
                            isPresented = false
                            selectedBaseEmoji = nil
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                selectedBaseEmoji = nil
                            }
                        }
                    )
                    .position(x: anchor.x, y: anchor.y)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
                        )
                    )
                    .zIndex(10)
                }
            }
            .coordinateSpace(name: "emojiPickerRoot")
            .onPreferenceChange(EmojiFramePreferenceKey.self) { frames in
                emojiFrames.merge(frames) { $1 }
            }
        }
    }
}

// MARK: - Skin Tone Bubble
private struct SkinToneBubble: View {
    let base: String
    let skinTones: [String]
    let colorScheme: ColorScheme
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    // Slight scale-up on the hovered/selected slot
    @State private var hoveredIndex: Int? = nil

    private let slotSize: CGFloat = 46

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(skinTones.enumerated()), id: \.offset) { index, modifier in
                let variant = base + modifier
                Button(action: { onSelect(variant) }) {
                    Text(variant)
                        .font(.system(size: 30))
                        .frame(width: slotSize, height: slotSize)
                        .scaleEffect(hoveredIndex == index ? 1.18 : 1.0)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in hoveredIndex = index }
                        .onEnded { _ in hoveredIndex = nil }
                )
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: hoveredIndex)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .momentsChromeGlass(in: Capsule(), interactive: true)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
            radius: 24,
            x: 0,
            y: 12
        )
    }
}

// MARK: - Interactive Button Style for Micro-feedback
struct MomentEmojiScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
