import SwiftUI
import PhotosUI
import Kingfisher
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import TOCropViewController
import CoreLocation
import MapKit
import UIKit

// Add Photos import at the top
import Photos

// MARK: - Main Creator View
struct CreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isCreatingStory: Bool
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem? // ✅ NUEVO: Sticker inicial
    let initialMedia: [CreatorMedia]? // ✅ NUEVO: Media inicial (foto/video de fondo)
    let openInStoryMode: Bool // ✅ NUEVO: Abrir directamente en modo historia
    let startInCameraWhenOnlySticker: Bool

    @State private var currentFlow: CreatorFlow = .typeSelection
    @State private var contentType: ContentType = .moment

    init(isCreatingStory: Binding<Bool>, showCreatorView: Binding<Bool>, initialSticker: StickerItem? = nil, initialMedia: [CreatorMedia]? = nil, openInStoryMode: Bool = false, startInCameraWhenOnlySticker: Bool = false) {
        self._isCreatingStory = isCreatingStory
        self._showCreatorView = showCreatorView
        self.initialSticker = initialSticker
        self.initialMedia = initialMedia
        self.openInStoryMode = openInStoryMode
        self.startInCameraWhenOnlySticker = startInCameraWhenOnlySticker

        // ✅ Inicialización de estado sincronizada
        if initialMedia != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
            _selectedMediaItems = State(initialValue: initialMedia ?? [])
        } else if initialSticker != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: startInCameraWhenOnlySticker ? .storyCamera : .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
        } else if openInStoryMode {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyCamera)
        }
    }
    @State private var selectedMediaItems: [CreatorMedia] = []
    @State private var captionText: String = ""
    @State private var taggedUsers: [String] = []
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var responseSticker: StickerItem? = nil

    // 🔗 NUEVO: Variables para contexto de cadena
    @State private var pendingChainId: String? = nil
    @State private var pendingChainTitle: String? = nil
    @State private var pendingChainPosition: Int? = nil

    // ✅ Geometry Effect Namespace
    @Namespace private var animation

    enum CreatorFlow {
        case typeSelection
        case mediaSelection
        case mediaEditing
        case videoEditing
        case captionAndDetails
        case storyCamera
        case storyEditing
    }

    enum ContentType {
        case moment
        case story
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch currentFlow {
            case .typeSelection:
                ContentTypeSelectionView(
                    contentType: $contentType,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
                )
            case .mediaSelection:
                MediaSelectionView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
                )
            case .mediaEditing:
                MediaEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .videoEditing:
                SocialVideoEditorView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .captionAndDetails:
                CaptionAndDetailsView(
                    selectedMediaItems: $selectedMediaItems,
                    captionText: $captionText,
                    taggedUsers: $taggedUsers,
                    selectedLocation: $selectedLocation,
                    locationName: $locationName,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .storyCamera:
                StoryCameraView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .storyEditing:
                StoryEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    initialSticker: responseSticker,
                    initialChainId: pendingChainId,
                    initialChainTitle: pendingChainTitle,
                    initialChainPosition: pendingChainPosition
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: contentType) { _, newType in
            // ✅ SEGURIDAD CRÍTICA: No cambiar el flujo si ya estamos editando (especialmente con Stickers)
            if initialSticker != nil || responseSticker != nil {
                if currentFlow == .storyEditing { return }
            }

            // ✅ EVITAR RESET: Si ya estamos en edición o cámara story, no sobrescribir el flujo
            guard currentFlow == .typeSelection else { return }

            if newType == .story {
                // ✅ FIX: Si hay un sticker, ir al editor en lugar de la cámara
                if initialMedia != nil {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }
                isCreatingStory = true
            } else {
                currentFlow = .mediaSelection
                isCreatingStory = false
            }
        }
        .onAppear {
            setupResponseStickerListener()
            setupContinueChainListener()

            // Si llega solo un sticker de pregunta, abrimos la cámara primero y lo conservamos para el editor.
            if let sticker = initialSticker {
                if responseSticker == nil { responseSticker = sticker }

                contentType = .story
                if initialMedia != nil || !startInCameraWhenOnlySticker {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }

                isCreatingStory = true
            } else if openInStoryMode {
                isCreatingStory = true
                if currentFlow == .typeSelection {
                    contentType = .story
                    currentFlow = .storyCamera
                }
            }
        }
        .onDisappear {
            removeResponseStickerListener()
            removeContinueChainListener()

            // ✅ Limpiar video y audio cuando se cierra CreatorView
            cleanupVideoAndAudio()
        }
    }

    // MARK: - Response Sticker Handling
    private func setupResponseStickerListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil,
            queue: .main
        ) { notification in
            if let sticker = notification.object as? StickerItem {
                addResponseStickerToStory(sticker)
            }
        }
    }

    private func removeResponseStickerListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil
        )
    }

    // MARK: - Continue Chain Handling
    private func setupContinueChainListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ContinueStoryChain"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                continueStoryChain(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
            }
        }

        // 🔗 NUEVO: Listener para configurar tipo de contenido
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetContentType"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let contentTypeString = userInfo["contentType"] as? String {
                if contentTypeString == "story" {
                    contentType = .story
                    currentFlow = .storyCamera  // ✅ MANTENER: Ir a cámara para seleccionar medios
                    isCreatingStory = true
                }
            }
        }

        // 🔗 NUEVO: Listener para guardar contexto de cadena
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetChainContext"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                pendingChainId = chainId
                pendingChainTitle = chainTitle
                pendingChainPosition = chainPosition
            }
        }
    }

    private func removeContinueChainListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("ContinueStoryChain"),
            object: nil
        )

        // 🔗 NUEVO: Limpiar listener de tipo de contenido
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("SetContentType"),
            object: nil
        )
    }

    private func continueStoryChain(chainId: String, chainTitle: String, chainPosition: Int) {
        // Configurar para continuar cadena
        contentType = .story
        currentFlow = .storyCamera
        isCreatingStory = true

        // Pasar datos de cadena al StoryEditingView
        // Esto se manejará en el StoryEditingView cuando se abra
        NotificationCenter.default.post(
            name: NSNotification.Name("SetChainContext"),
            object: nil,
            userInfo: [
                "chainId": chainId,
                "chainTitle": chainTitle,
                "chainPosition": chainPosition
            ]
        )
    }

    private func addResponseStickerToStory(_ sticker: StickerItem) {
        // ✅ GUARDAR EL STICKER EN EL ESTADO ANTES DE ABRIR StoryEditingView
        responseSticker = sticker

        // Ir directamente a la edición de historia con el sticker
        contentType = .story
        currentFlow = .storyEditing
        isCreatingStory = true
    }
    // ✅ FUNCIÓN PARA LIMPIAR VIDEO Y AUDIO
    private func cleanupVideoAndAudio() {
        // ✅ Limpiar los media items seleccionados
        selectedMediaItems.removeAll()

        // ✅ Pausar cualquier audio que esté reproduciéndose
        try? AVAudioSession.sharedInstance().setActive(false)

        // ✅ Notificar limpieza de video
        NotificationCenter.default.post(name: NSNotification.Name("CleanupVideoPlayer"), object: nil)
    }

    // ✅ Helper to create gradient image for sticker-only stories
    private func createDefaultGradientImage() -> UIImage {
        let size = UIScreen.main.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let colors = [
                UIColor(Color(hex: "4158D0") ?? .blue).cgColor,
                UIColor(Color(hex: "C850C0") ?? .purple).cgColor,
                UIColor(Color(hex: "FFCC70") ?? .pink).cgColor
            ]

            let gradient = sectionGradient(colors: colors, size: size)
            gradient.render(in: context.cgContext)
        }
    }

    private func sectionGradient(colors: [CGColor], size: CGSize) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.colors = colors
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
        return layer
    }
}

// MARK: - Media Stack Preview
struct MediaStackPreview: View {
    let items: [CreatorMedia]

    var body: some View {
        ZStack {
            ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .rotationEffect(.degrees(Double(index) * 3))
                    .offset(x: CGFloat(index) * 4, y: CGFloat(index) * 2)
            }
        }
    }
}

// MARK: - Caption and Details View
struct CaptionAndDetailsView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var captionText: String
    @Binding var taggedUsers: [String]
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    // Total tags across all media
    private var totalTagsCount: Int {
        selectedMediaItems.reduce(0) { $0 + ($1.tags?.count ?? 0) }
    }

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var uploadService = BackgroundMomentUploadService.shared

    @State private var isPublishing = false
    @State private var showingUserSearch = false
    @State private var showingLocationPicker = false
    @State private var showingAudience = false
    @State private var audienceSetting: AudienceSetting = .everyone
    @State private var customViewers: [String] = []
    @State private var customListId: String? = nil

    // Interaction Settings (from AdvancedSettingsView)
    @AppStorage("disableComments") private var disableComments = false
    @AppStorage("hideLikeCounts") private var hideLikeCounts = false
    @AppStorage("allowSharing") private var allowSharing = true

    // Scheduling (New)
    @State private var isSchedulingEnabled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600) // Default to 1 hour from now

    // New variables for custom lists
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []

    @FocusState private var isCaptionFocused: Bool
    @State private var isLaunching = false // 🔥 Control para la animación de lanzamiento
    @State private var isPreviewingMedia = false
    @State private var showingTagSelector = false
    @State private var showingHiddenLayersEditor = false
    @State private var hiddenLayerDrafts: [HiddenLayerDraft] = []
    @State private var currentMediaTagIndex = 0
    @State private var tagSelectorDetent: PresentationDetent = .large
    @State private var hiddenLayersDetent: PresentationDetent = .large

    enum AudienceSetting {
        case everyone
        case mutuals
        case admirers
        case bestFriends
        case custom
        case onlyMe

        var title: String {
            switch self {
            case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone audience type")
            case .mutuals: return NSLocalizedString("audience.type.connections", comment: "Connections audience type")
            case .admirers: return NSLocalizedString("audience.type.connections", comment: "Connections audience type (admirers maps to connections)")
            case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type")
            case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
            case .onlyMe: return NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type")
            }
        }

        var icon: String {
            switch self {
            case .everyone: return "globe"
            case .mutuals: return "person.2.fill"
            case .admirers: return "person.3"
            case .bestFriends: return "star"
            case .custom: return "gearshape"
            case .onlyMe: return "lock.fill"
            }
        }
    }

    // New function to map AudienceSetting to ContentAudience
    func toContentAudience() -> ContentAudience {
        switch audienceSetting {
        case .everyone: return .everyone
        case .mutuals: return .connections
        case .admirers: return .connections
        case .bestFriends: return .bestFriends
        case .custom: return selectedListId != nil ? .customList : .custom
        case .onlyMe: return .onlyMe
        }
    }

    private var canUseHiddenLayers: Bool {
        selectedMediaItems.count == 1 && selectedMediaItems.first?.type == .image
    }
    private var hiddenLayerOptionValue: String? {
        if !canUseHiddenLayers {
            return NSLocalizedString("hiddenLayers.creator.singleImageOnly", value: "Solo en una foto", comment: "Hidden layers unsupported state")
        }

        guard !hiddenLayerDrafts.isEmpty else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("hiddenLayers.count", value: "%d capas", comment: "Hidden layers count"),
            hiddenLayerDrafts.count
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 1. Immersive Background (Mosaic Blur)
                SelectedMediaBlurView(mediaItems: selectedMediaItems)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            currentFlow = .mediaEditing
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(10)
                                .liquidGlass(in: Circle(), interactive: true)
                        }

                        Spacer()

                        Text("creator.newMoment")
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        GlowSharePill(title: "creator.share", isLoading: isPublishing, action: {
                            publishMoment()
                        })
                    }
                    .padding()


                    ScrollView {
                        VStack(spacing: 15) { // Tight spacing to bring options right under

                            // SECTION 1: Caption & Media Preview
                            HStack(alignment: .top, spacing: 30) { // Aumentado spacing de 20 a 30
                                // Media Preview with "Press to Unfold" gesture
                                ZStack {
                                    MediaStackPreview(items: selectedMediaItems)
                                        .frame(width: 100, height: 150)
                                        .contentShape(Rectangle())
                                        .scaleEffect(isPreviewingMedia ? 0.95 : 1.0)
                                        .onLongPressGesture(minimumDuration: 0.2, pressing: { isPressing in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                isPreviewingMedia = isPressing
                                            }
                                        }) {
                                            // Action on complete
                                        }

                                    // Helper hint
                                    if !isPreviewingMedia {
                                        Text("creator.media_preview.hint")
                                            .font(.system(size: 8, weight: .bold)) // Un poco más pequeño y bold para legibilidad
                                            .foregroundColor(.white.opacity(0.7))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(6)
                                            .offset(y: 60) // Bajado de 50 a 60 para que tape menos la imagen
                                            .allowsHitTesting(false)
                                    }
                                }

                                // Caption Input
                                ZStack(alignment: .topLeading) {
                                    if captionText.isEmpty {
                                        Text("creator.caption.placeholder")
                                            .foregroundColor(.white.opacity(0.6))
                                            .padding(.top, 8)
                                    }

                                    TextEditor(text: $captionText)
                                        .scrollContentBackground(.hidden)
                                        .foregroundColor(.white)
                                        .frame(minHeight: 120) // Restored a bit of height
                                        .tint(.white)
                                        .focused($isCaptionFocused)
                                }
                                .padding(.top, 4) // Tight top-only padding
                            }
                            .padding(.horizontal)
                            .padding(.top, 10) // Tighter top spacing from header

                            // SECTION 2: Options List
                            VStack(spacing: 0) {
                                // Tag people
                                MinimalOptionRow(
                                    icon: "person.crop.circle.badge.plus",
                                    title: NSLocalizedString("creator.tagPeople", comment: "Tag people"),
                                    value: totalTagsCount == 0 ? nil : String.localizedStringWithFormat(NSLocalizedString("audience.people.count", comment: ""), totalTagsCount)
                                ) {
                                    if selectedMediaItems.indices.contains(currentMediaTagIndex) {
                                        tagSelectorDetent = preferredTagSelectorDetent(for: selectedMediaItems[currentMediaTagIndex])
                                    } else {
                                        tagSelectorDetent = .large
                                    }
                                    showingTagSelector = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Add location
                                MinimalOptionRow(
                                    icon: "location",
                                    title: NSLocalizedString("creator.addLocation", comment: "Add location"),
                                    value: locationName.isEmpty ? nil : locationName
                                ) {
                                    showingLocationPicker = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                MinimalOptionRow(
                                    icon: "sparkles.rectangle.stack",
                                    title: NSLocalizedString("hiddenLayers.editor.title", value: "Capas ocultas", comment: "Hidden layers editor title"),
                                    value: hiddenLayerOptionValue
                                ) {
                                    if canUseHiddenLayers {
                                        showingHiddenLayersEditor = true
                                    }
                                }
                                .opacity(canUseHiddenLayers ? 1 : 0.45)
                                .disabled(!canUseHiddenLayers)

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Audience
                                MinimalOptionRow(
                                    icon: getAudienceIcon(),
                                    title: NSLocalizedString("audience.title", comment: "Audience title"),
                                    value: getAudienceText()
                                ) {
                                    showingAudience = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Advanced settings removed (moved to quick access)
                            }
                            .padding(.top, 10) // Pull options closer to preview

                            // SECTION 3: Interaction Settings (Quick Access)
                            VStack(spacing: 0) {
                                Text("creator.interactions.title")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 8)

                                MinimalToggleRow(
                                    icon: "bubble.left.and.bubble.right",
                                    title: NSLocalizedString("creator.interactions.disableComments", comment: ""),
                                    isOn: $disableComments
                                )

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                MinimalToggleRow(
                                    icon: "heart.slash",
                                    title: NSLocalizedString("creator.visualization.hideReactions", comment: ""),
                                    isOn: $hideLikeCounts
                                )

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                MinimalToggleRow(
                                    icon: "bookmark",
                                    title: NSLocalizedString("creator.interactions.allowSharing", comment: ""),
                                    isOn: $allowSharing
                                )
                            }
                            .padding(.top, 25)

                            // SECTION 4: Scheduling
                            VStack(spacing: 0) {
                                Text("creator.scheduling.title")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 8)

                                MinimalToggleRow(
                                    icon: "calendar.badge.clock",
                                    title: NSLocalizedString("creator.scheduling.enable", comment: ""),
                                    isOn: $isSchedulingEnabled
                                )

                                if isSchedulingEnabled {
                                    Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                    HStack {
                                        Image(systemName: "clock")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 24)

                                        DatePicker(
                                            NSLocalizedString("creator.scheduling.date", comment: ""),
                                            selection: $scheduledDate,
                                            in: Date()...,
                                            displayedComponents: [.date, .hourAndMinute]
                                        )
                                        .colorScheme(.dark)
                                        .accentColor(.pink)
                                        .labelsHidden()

                                        Spacer()

                                        Text(scheduledDate.formatted())
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 25)
                            .padding(.bottom, 30) // Extra bottom padding for the scroll
                        }
                    }
                }

                    if isPublishing && !isLaunching {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("creator.publishing")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }

                    // 🔥 OVERLAY DE LANZAMIENTO (Cinematic Handoff)
                    if isLaunching {
                        ZStack {
                            Color.black.ignoresSafeArea()

                            VStack(spacing: 24) {
                                Text(NSLocalizedString("creator.uploading.success_fly", comment: "Successfully shared"))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        .transition(.opacity)
                    }

                    // Full Screen Media Preview Overlay
                    if isPreviewingMedia {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(99)

                        TabView {
                            ForEach(selectedMediaItems) { item in
                                Image(uiImage: item.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(20)
                                    .padding()
                                    .shadow(radius: 20)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(height: 500)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .zIndex(100)
                    }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingUserSearch) {
            UserSearchView(selectedUsers: $taggedUsers)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                selectedLocation: $selectedLocation,
                locationName: $locationName
            )
        }
        .sheet(isPresented: $showingAudience) {
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
        .sheet(isPresented: $showingTagSelector) {
            if !selectedMediaItems.isEmpty {
                PhotoTagSelectionView(mediaItem: $selectedMediaItems[currentMediaTagIndex])
                    .presentationDetents([.medium, .large], selection: $tagSelectorDetent)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingHiddenLayersEditor) {
            if let mediaItem = selectedMediaItems.first, canUseHiddenLayers {
                    HiddenLayersEditorView(
                        image: mediaItem.image,
                        postAspectRatio: preferredMomentDisplayAspectRatioValue(for: selectedMediaItems),
                        layers: $hiddenLayerDrafts
                    )
                        .interactiveDismissDisabled()
                        .presentationDetents([.large], selection: $hiddenLayersDetent)
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(.clear)
            }
        }
        .onAppear {
            loadDefaultPostAudience()
            hiddenLayersDetent = .large
        }
        .onChange(of: selectedMediaItems.map(\.id)) { _, _ in
            if !canUseHiddenLayers {
                hiddenLayerDrafts.removeAll()
            }
        }
    }

    // ✅ FUNCIÓN ACTUALIZADA: Publicar momento con soporte para listas
    private func publishMoment() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isPublishing = true

        // Use local properties (managed by @AppStorage)
        let finalDisableComments = disableComments
        let finalHideLikeCounts = hideLikeCounts
        let finalAllowSharing = allowSharing
        let finalScheduledDate = isSchedulingEnabled ? scheduledDate : nil


        let detectedAspectRatio = preferredMomentAspectRatio(for: selectedMediaItems)

        // 🔥 USAR EL SERVICIO DE BACKGROUND UPLOAD
        // Combinar etiquetas espaciales con la lista legacy para notificaciones y búsquedas
        let spatialTaggedUsers = selectedMediaItems.flatMap { $0.tags ?? [] }.map { $0.userId }
        let allTaggedUsers = Array(Set(taggedUsers + spatialTaggedUsers))

        let uploadingMoment = uploadService.uploadMoment(
            content: captionText,
            mediaItems: selectedMediaItems,
            taggedUsers: allTaggedUsers.isEmpty ? nil : allTaggedUsers,
            location: locationName.isEmpty ? nil : locationName,
            locationCoordinate: selectedLocation != nil ? Moment.LocationCoordinate(
                latitude: selectedLocation!.latitude,
                longitude: selectedLocation!.longitude
            ) : nil,  // ✅ NUEVO: Convertir coordenadas a LocationCoordinate
            audienceSetting: audienceSetting,
            customViewers: customSelectedUsers.isEmpty ? nil : customSelectedUsers,
            customListId: selectedListId,
            aspectRatio: detectedAspectRatio,
            disableComments: finalDisableComments,
            hideLikeCounts: finalHideLikeCounts,
            allowSharing: finalAllowSharing,
            scheduledDate: finalScheduledDate,
            hiddenLayers: canUseHiddenLayers ? hiddenLayerDrafts.filter(\.isReadyToPublish) : []
        )

        // 🔥 CERRAR PANTALLA CON ANIMACIÓN CINEMÁTICA
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            self.isLaunching = true
        }

        hapticNotification(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isPublishing = false
            self.showCreatorView = false

            if uploadingMoment != nil {
                // 🧹 Limpiar formulario para próximo uso
                self.resetForm()

                // 📊 Analytics

            } else {
                // ❌ Feedback háptico de error
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)

                // Revertir estado si falló el inicio del servicio
                withAnimation {
                    self.isLaunching = false
                }
            }
        }
    }

    private func preferredTagSelectorDetent(for mediaItem: CreatorMedia) -> PresentationDetent {
        let aspectRatio = mediaItem.image.size.width / max(mediaItem.image.size.height, 1)
        return aspectRatio >= 0.95 ? .medium : .large
    }

    private func preferredMomentAspectRatio(for mediaItems: [CreatorMedia]) -> String {
        guard !mediaItems.isEmpty else { return "1:1" }

        let preferredRatios = mediaItems.map { mediaItem -> CreatorMedia.AspectRatio in
            if let recommended = mediaItem.recommendedAspectRatio {
                return recommended
            }

            if mediaItem.aspectRatio != .square {
                return mediaItem.aspectRatio
            }

            let imageRatio = mediaItem.image.size.width / max(mediaItem.image.size.height, 1)
            return CreatorMedia.AspectRatio.fromRatio(imageRatio)
        }

        let mostVerticalRatio = preferredRatios.min { lhs, rhs in
            lhs.value < rhs.value
        } ?? .square

        return mostVerticalRatio.displayName
    }

    private func preferredMomentDisplayAspectRatioValue(for mediaItems: [CreatorMedia]) -> CGFloat {
        guard !mediaItems.isEmpty else { return 1.0 }

        let preferredRatios = mediaItems.map { mediaItem -> CreatorMedia.AspectRatio in
            if let recommended = mediaItem.recommendedAspectRatio {
                return recommended
            }

            if mediaItem.aspectRatio != .square {
                return mediaItem.aspectRatio
            }

            let imageRatio = mediaItem.image.size.width / max(mediaItem.image.size.height, 1)
            return CreatorMedia.AspectRatio.fromRatio(imageRatio)
        }

        let mostVerticalRatio = preferredRatios.min { lhs, rhs in
            lhs.value < rhs.value
        } ?? .square

        return mostVerticalRatio.value
    }

    // 🧹 NUEVA FUNCIÓN: Limpiar formulario después de publicar
    private func resetForm() {
        captionText = ""
        taggedUsers = []
        locationName = ""
        selectedLocation = nil
        customSelectedUsers = []
        selectedListId = nil
        selectedListName = nil
        audienceSetting = .everyone
        hiddenLayerDrafts = []
    }

    // MediaStackPreview eliminado (reemplazado por imagen grande inline)

    // ✅ FUNCIONES AUXILIARES RESTAURADAS
    private func getAudienceIcon() -> String {
        if audienceSetting == .custom && selectedListId != nil {
            return "list.bullet.rectangle"
        }
        return audienceSetting.icon
    }

    private func getAudienceText() -> String {
        if audienceSetting == .custom {
            if let listName = selectedListName {
                return listName
            } else if !customSelectedUsers.isEmpty {
                return "\(customSelectedUsers.count) personas"
            }
        }
        return audienceSetting.title
    }

    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch audienceSetting {
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
                case .everyone: audienceSetting = .everyone
                case .connections: audienceSetting = .mutuals
                case .bestFriends: audienceSetting = .bestFriends
                case .custom: audienceSetting = .custom
                case .customList: audienceSetting = .custom
                case .onlyMe: audienceSetting = .onlyMe
                }
            }
        )
    }

    private func updateAudienceSetting() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let audienceRaw: String
        switch audienceSetting {
        case .everyone:    audienceRaw = ContentAudience.everyone.rawValue
        case .mutuals:     audienceRaw = ContentAudience.connections.rawValue
        case .admirers:    audienceRaw = ContentAudience.connections.rawValue
        case .bestFriends: audienceRaw = ContentAudience.bestFriends.rawValue
        case .custom:      audienceRaw = (selectedListId != nil) ? ContentAudience.customList.rawValue : ContentAudience.custom.rawValue
        case .onlyMe:      audienceRaw = ContentAudience.onlyMe.rawValue
        }

        var update: [String: Any] = [
            "contentVisibilitySettings.postAudience": audienceRaw
        ]
        if let listId = selectedListId {
            update["contentVisibilitySettings.postCustomListId"] = listId
            update["contentVisibilitySettings.postCustomListName"] = selectedListName ?? ""
        }
        if !customSelectedUsers.isEmpty {
            update["contentVisibilitySettings.postCustomUsers"] = customSelectedUsers
        }

        FirestoreService().db.collection("users").document(userId).updateData(update)
    }

    private func loadDefaultPostAudience() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        FirestoreService().db.collection("users").document(userId).getDocument { document, _ in
            DispatchQueue.main.async {
                guard let data = document?.data(),
                      let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] else { return }

                if let postAudienceRaw = visibilitySettings["postAudience"] as? String,
                   let contentAudience = ContentAudience(rawValue: postAudienceRaw) {
                    switch contentAudience {
                    case .everyone:    self.audienceSetting = .everyone
                    case .connections: self.audienceSetting = .mutuals
                    case .bestFriends: self.audienceSetting = .bestFriends
                    case .custom:
                        self.audienceSetting = .custom
                        self.customSelectedUsers = visibilitySettings["postCustomUsers"] as? [String] ?? []
                    case .customList:
                        self.audienceSetting = .custom
                        self.selectedListId = visibilitySettings["postCustomListId"] as? String
                        self.selectedListName = visibilitySettings["postCustomListName"] as? String
                    case .onlyMe:      self.audienceSetting = .onlyMe
                    }
                }
            }
        }
    }

    private func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    // MARK: - 📍 MINIMAL OPTION ROW (Clean Design)

    struct MinimalOptionRow: View {
        let icon: String
        let title: String
        let value: String?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                MinimalOptionRowContent(icon: icon, title: title, value: value)
            }
            .pressAnimation()
        }
    }

    struct MinimalToggleRow: View {
        let icon: String
        let title: String
        @Binding var isOn: Bool

        var body: some View {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 32)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.pink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    struct MinimalOptionRowContent: View {
        let icon: String
        let title: String
        let value: String?

        var body: some View {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 32)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                if let value = value {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle()) // Full width tap area
        }
    }
}

extension CreatorMedia.AspectRatio {
    // ✅ NUEVO: Inicializar desde string guardado en Firestore
    init(from string: String?) {
        switch string {
        case "1:1": self = .square
        case "4:5": self = .portrait
        case "16:9": self = .landscape
        case "9:16": self = .nineBySixteen
        default: self = .square // Default fallback
        }
    }

    // ✅ NOTA: La función fromRatio está definida dentro del enum AspectRatio (línea 78)
    // para usar la lógica mejorada de detección con tolerancia y rangos más precisos
}

// MARK: - Story Camera View
struct StoryCameraView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    @State private var showingGallery = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var isRecording = false
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastZoomLevel: CGFloat = 1.0
    @State private var capturePhotoTrigger = false
    @State private var lastGalleryImage: UIImage?
    @StateObject private var orientationManager = OrientationManager.shared

    private var deviceOrientation: UIDeviceOrientation {
        orientationManager.orientation
    }

    private var rotationAngle: Double {
        switch deviceOrientation {
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        case .portraitUpsideDown: return 180
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let captureRect = creatorMomentsCaptureRect(in: proxy.size, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                // Camera preview
                CameraPreviewRepresentable(
                    cameraPosition: $cameraPosition,
                    flashMode: $flashMode,
                    isRecording: $isRecording,
                    zoomLevel: $zoomLevel,
                    capturePhotoTrigger: $capturePhotoTrigger,
                    deviceOrientation: deviceOrientation,
                    onImageCaptured: { image in
                        handleCapturedImage(image)
                    },
                    onVideoCaptured: { videoURL in
                        handleCapturedVideo(videoURL)
                    }
                )
                .frame(width: captureRect.width, height: captureRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .position(x: captureRect.midX, y: captureRect.midY)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = lastZoomLevel * value
                            zoomLevel = min(max(newZoom, 1.0), 5.0)
                        }
                        .onEnded { value in
                            lastZoomLevel = zoomLevel
                        }
                )


                // Top controls
                VStack {
                    HStack {
                        Button(action: {
                            showCreatorView = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: Circle(), interactive: true)
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.spring(), value: rotationAngle)

                        Spacer()

                        // Flash button
                        Button(action: {
                            toggleFlash()
                        }) {
                            Image(systemName: flashIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: Circle(), interactive: true)
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.spring(), value: rotationAngle)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Bottom controls
                ZStack {
                    VStack(spacing: 12) {
                        ZStack {
                            if isRecording {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                        .scaleEffect(1.0)
                                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecording)

                                    Text(formatTime(recordingDuration))
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(20)
                            }
                        }
                        .frame(height: 36)

                        HStack(alignment: .bottom, spacing: 40) {
                            // Gallery button with last image preview
                            Button(action: {
                                showingGallery = true
                            }) {
                                if let lastImage = lastGalleryImage {
                                    Image(uiImage: lastImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                        )
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.14))
                                        Image(systemName: "photo.stack")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                }
                            }
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.spring(), value: rotationAngle)

                            // Capture button
                            CaptureButton(
                                isRecording: $isRecording,
                                onTap: {
                                    takePhoto()
                                },
                                onLongPressStart: { startRecording() },
                                onLongPressEnd: { stopRecording() }
                            )

                            // Switch camera button
                            Button(action: {
                                switchCamera()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            }
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.spring(), value: rotationAngle)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                }
                .frame(width: captureRect.width, height: captureRect.height, alignment: .bottom)
                .position(x: captureRect.midX, y: captureRect.midY)
            }
        }
        .sheet(isPresented: $showingGallery) {
            StoryGalleryPicker { media in
                selectedMediaItems = [media]
                currentFlow = .storyEditing
            }
        }

        .onAppear {
            setupAudioSession()
            loadLastGalleryImage()
            orientationManager.startTracking()
        }
        .onDisappear {
            stopRecording()
            orientationManager.stopTracking()
        }
    }

    private var flashIcon: String {
        switch flashMode {
        case .off: return "bolt.slash"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a"
        @unknown default: return "bolt.slash"
        }
    }

    private func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }

    private func switchCamera() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = cameraPosition == .back ? .front : .back
            // Reset zoom when switching cameras
            zoomLevel = 1.0
            lastZoomLevel = 1.0
        }
    }

    private func takePhoto() {
        capturePhotoTrigger.toggle()
    }

    private func startRecording() {
        isRecording = true
        recordingDuration = 0
        startRecordingTimer()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
            if recordingDuration >= 60 { // Max 60 seconds
                stopRecording()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [])
            try session.setActive(true)
        } catch {
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        let detectedRatio = CreatorMedia.AspectRatio.fromRatio(image.size.width / image.size.height)
        let processedMedia = CreatorMedia(
            id: UUID().uuidString,
            image: image,
            videoURL: nil,
            type: .image,
            aspectRatio: detectedRatio,
            recommendedAspectRatio: detectedRatio
        )
        selectedMediaItems = [processedMedia]
        currentFlow = .storyEditing
    }

    private func handleCapturedVideo(_ videoURL: URL) {
        // Generate thumbnail from video
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        Task {
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)

                let detectedRatio = CreatorMedia.AspectRatio.fromRatio(thumbnail.size.width / thumbnail.size.height)

                await MainActor.run {
                    let processedMedia = CreatorMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedRatio,
                        recommendedAspectRatio: detectedRatio
                    )
                    selectedMediaItems = [processedMedia]
                    currentFlow = .storyEditing
                }
            } catch {
            }
        }
    }

    private func loadLastGalleryImage() {
        // ✅ Cargar la última imagen de la galería en background
        Task {
            do {
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.fetchLimit = 1

                let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

                if let lastAsset = fetchResult.firstObject {
                    let manager = PHImageManager.default()
                    let options = PHImageRequestOptions()
                    options.deliveryMode = .fastFormat
                    options.isSynchronous = false

                    manager.requestImage(
                        for: lastAsset,
                        targetSize: CGSize(width: 120, height: 120),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        DispatchQueue.main.async {
                            self.lastGalleryImage = image
                        }
                    }
                }
            } catch {
            }
        }
    }
}

private struct MomentsStoryGuideOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let guideRect = creatorMomentsAspectRect(aspectRatio: creatorMomentsCaptureAspectRatio, in: CGRect(origin: .zero, size: proxy.size))
            let topMaskHeight = max(guideRect.minY, 0)
            let bottomMaskHeight = max(proxy.size.height - guideRect.maxY, 0)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: topMaskHeight)

                Color.clear
                    .frame(height: guideRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )

                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: bottomMaskHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - StoryOverlaysView FINAL - Sin cuadrado X, con navegación funcional
struct StoryOverlaysView: View {
    @Binding var text: String
    @Binding var textPosition: CGPoint
    @Binding var textStyle: StoryEditingView.TextStyle
    @Binding var textEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @Binding var isTextEditorPresented: Bool
    @Binding var stickers: [StickerItem]
    @Binding var drawingImage: UIImage?
    @Binding var isEditingSticker: Bool // ✅ NUEVO: Para ocultar la UI del padre

    let onNavigateToProfile: (String) -> Void
    let onNavigateToLocation: (String, CLLocationCoordinate2D?) -> Void

    @State private var selectedStickerId: String?
    @State private var isEditingText = false
    @State private var isDraggingItem = false
    @State private var showTrashZone = false
    @State private var isOverTrash = false
    @State private var pinchStartTextFontSize: CGFloat?
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar el texto

    // 📸 NUEVO: Estado para editar el pie de foto de la Polaroid
    @State private var editingPolaroidId: String? = nil
    @State private var polaroidCaptionBuffer: String = ""
    @State private var originalStickerTransform: (pos: CGPoint, scale: CGFloat, rot: Angle)? = nil
    @State private var keyboardHeight: CGFloat = 0

    // ✨ NUEVO: Estado para editar el diseño del Reveal
    @State private var editingRevealId: String? = nil

    var body: some View {
        ZStack {
            // Drawing overlay
            if let drawing = drawingImage {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil && !text.isEmpty ? 1.0 :
                                 isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil && text.isEmpty ? 0.8 : 1.0)
                    .allowsHitTesting(true)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !text.isEmpty { return }

                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }

                                let trashY = UIScreen.main.bounds.height - 150
                                isOverTrash = value.location.y > trashY
                            }
                            .onEnded { value in
                                if !text.isEmpty { return }

                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false

                                    if isOverTrash {
                                        drawingImage = nil
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .onTapGesture {
                        // Deseleccionar al tocar el fondo
                        selectedStickerId = nil
                    }
            }

            // Text overlay
            if !text.isEmpty && !isTextEditorPresented {
                Text(text)
                    .font(textStyle.font(size: textFontSize))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(nil)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        Group {
                            if let backgroundColor = effectiveTextBackgroundColor {
                                backgroundColor
                            }
                        }
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: effectiveTextBackgroundColor == nil ? 0 : 10, style: .continuous)
                    )
                    .padding(.horizontal, 24)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .modifier(TextEffectModifier(effect: textEffect, textColor: textColor))
                    .contentShape(Rectangle()) // ✅ Área táctil limitada al texto
                    .gesture(
                        DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Estabilidad absoluta en el canvas
                            .onChanged { value in
                                if dragOffset == .zero {
                                    dragOffset = CGSize(
                                        width: value.startLocation.x - textPosition.x,
                                        height: value.startLocation.y - textPosition.y
                                    )
                                }

                                let newPos = CGPoint(
                                    x: value.location.x - dragOffset.width,
                                    y: value.location.y - dragOffset.height
                                )

                                textPosition = newPos

                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }

                                let trashY = UIScreen.main.bounds.height - 150
                                isOverTrash = newPos.y > trashY
                            }
                            .onEnded { value in
                                dragOffset = .zero
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false

                                    if isOverTrash {
                                        text = ""
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let baseFontSize = pinchStartTextFontSize ?? textFontSize
                                if pinchStartTextFontSize == nil {
                                    pinchStartTextFontSize = textFontSize
                                }
                                textFontSize = min(max(baseFontSize * value, 20), 56)
                            }
                            .onEnded { _ in
                                pinchStartTextFontSize = nil
                            }
                    )
                    .onTapGesture {
                        selectedStickerId = nil
                        isEditingText = true
                        isTextEditorPresented = true
                    }
                    .position(textPosition) // ✅ Posicionar al final
                    .animation(.easeInOut(duration: 0.2), value: isDraggingItem)
            }

            // ✅ STICKERS COMPLETAMENTE LIBRES - Sin interfaz de selección
            ForEach(stickers.indices, id: \.self) { index in
                // Ocultar stickers de tipo REVEAL del canvas (se muestran como badge arriba)
                if stickers[index].type != .reveal {
                    StickerOverlayView(
                        sticker: $stickers[index],
                        isSelected: selectedStickerId == stickers[index].id,
                        isDragging: isDraggingItem && selectedStickerId == stickers[index].id,
                        isContentEditing: editingPolaroidId == stickers[index].id,
                        onUpdate: { updatedSticker in
                            stickers[index] = updatedSticker
                        },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                stickers.remove(at: index)
                                selectedStickerId = nil
                            }
                        },
                        onDragChanged: { position in
                            if !isDraggingItem {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = true
                                    showTrashZone = true
                                    selectedStickerId = stickers[index].id
                                }
                            }

                            let trashY = UIScreen.main.bounds.height - 150
                            isOverTrash = position.y > trashY
                        },
                        onDragEnded: { position in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDraggingItem = false
                                showTrashZone = false

                                if isOverTrash {
                                    stickers.remove(at: index)
                                }
                                isOverTrash = false
                            }
                        },
                        onStickerTapped: { tappedSticker in
                            handleStickerTap(tappedSticker)
                            selectedStickerId = tappedSticker.id
                        }
                    )
                    .zIndex(editingPolaroidId == stickers[index].id ? 2000 : (selectedStickerId == stickers[index].id ? 500 : 1))
                }
            }

            // ✅ REVEAL STATUS BADGE (Top)
            if stickers.contains(where: { $0.type == .reveal }) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magicmouse.fill")
                                .font(.system(size: 12))
                            Text(NSLocalizedString("storyEditor.reveal.active", comment: "Reveal effect active status"))
                                .font(.custom("Poppins-Medium", size: 11))

                            Button {
                                withAnimation(.spring()) {
                                    stickers.removeAll(where: { $0.type == .reveal })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                        .onTapGesture {
                            if let revealSticker = stickers.first(where: { $0.type == .reveal }) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    editingRevealId = revealSticker.id
                                }
                                HapticManager.shared.mediumImpact()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 100) // Debajo de los controles superiores
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }


            // Zona de papelera
            if showTrashZone {
                VStack {
                    Spacer()

                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.4),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 200)
                        .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isOverTrash ? Color.red.opacity(0.2) : Color.black.opacity(0.3))
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(isOverTrash ? 1.1 : 1.0)

                                Image(systemName: isOverTrash ? "trash.circle.fill" : "trash.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(isOverTrash ? .red : .white)
                                    .scaleEffect(isOverTrash ? 1.1 : 1.0)
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOverTrash)

                            Text(isOverTrash ? "Soltar para eliminar" : "Arrastra aquí para eliminar")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .opacity(isOverTrash ? 1.0 : 0.8)
                                .animation(.easeInOut(duration: 0.2), value: isOverTrash)
                        }
                        .padding(.bottom, 50)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 📸 FONDO OSCURO DE EDICIÓN (Dentro del ZStack para controlar el zIndex)
            if editingPolaroidId != nil {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .zIndex(1500) // Entre los stickers normales y el "Hero"
                    .onTapGesture {
                        savePolaroidCaption()
                    }
                    .transition(.opacity)

                // INPUT DE TEXTO (Encima de todo)
                VStack {
                    Spacer()
                    TextField(NSLocalizedString("storyEditor.polaroid.addNote", comment: "Prompt to add a note to a polaroid"), text: $polaroidCaptionBuffer)
                        .font(.custom("MarkerFelt-Wide", size: 24)) // Un pelín más pequeña
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12) // Mucho más fino
                        .padding(.horizontal, 25)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .padding(.horizontal, 40)
                        .submitLabel(.done)
                        .onSubmit {
                            savePolaroidCaption()
                        }
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 80 : 160)
                }
                .zIndex(2500)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: keyboardHeight)
                .onChange(of: polaroidCaptionBuffer) { _, newValue in
                    // ✅ ACTUALIZACIÓN EN TIEMPO REAL
                    if let editingId = editingPolaroidId,
                       let index = stickers.firstIndex(where: { $0.id == editingId }) {
                        var interaction = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
                        interaction.caption = newValue
                        stickers[index].interactionData = interaction
                    }
                }
            }

            // ✨ REVEAL EDITOR OVERLAY
            if editingRevealId != nil {
                RevealStickerEditorView(
                    stickers: $stickers,
                    editingId: $editingRevealId
                )
                .zIndex(3000)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: editingPolaroidId) { _, newValue in
            // ✅ AVISAR AL PADRE PARA OCULTAR LA UI
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingRevealId != nil
            }
        }
        .onChange(of: editingRevealId) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingPolaroidId != nil
            }
        }
        .coordinateSpace(name: "storyCanvas")
        .onTapGesture {
            // Deseleccionar al tocar el fondo
            selectedStickerId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - endFrame.minY)
            keyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }

    }

    private var effectiveTextBackgroundColor: Color? {
        switch textBackgroundFill {
        case .none:
            return textEffect.backgroundColor
        case .black:
            return Color.black.opacity(0.58)
        case .white:
            return Color.white.opacity(0.90)
        }
    }

    private func handleStickerTap(_ sticker: StickerItem) {
        switch sticker.type {
        case .mention:
            if let username = sticker.interactionData?.username {
                findUserIdByUsername(username) { userId in
                    if let userId = userId {
                        DispatchQueue.main.async {
                            onNavigateToProfile(userId)
                        }
                    }
                }
            }

        case .hashtag:
            if let hashtag = sticker.interactionData?.hashtag {
                // Handle hashtag tap
            }

        case .location:
            if let interactionData = sticker.interactionData,
               let location = interactionData.location {
                onNavigateToLocation(location, interactionData.locationCoordinate)
            }

        case .poll:
            // Handle poll tap
            break

        case .question:
            // Handle question tap
            break

        case .questionResponse:
            // Handle question response tap
            break

        case .frame:
            // 📸 EFECTO ENFOQUE: Guardar posición y centrar para editar
            if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
                let original = stickers[index]
                originalStickerTransform = (original.position, original.scale, original.rotation)

                editingPolaroidId = sticker.id
                polaroidCaptionBuffer = sticker.interactionData?.caption ?? ""

                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    // Mover al centro (un poco arriba por el teclado) y ampliar
                    stickers[index].position = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 3)
                    stickers[index].scale = 1.4
                    stickers[index].rotation = .zero
                }

                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }

        default:
            break
        }
    }


    private func savePolaroidCaption() {
        guard let editingId = editingPolaroidId else { return }

        if let index = stickers.firstIndex(where: { $0.id == editingId }) {
            // Actualizar el caption en los datos de interacción
            var interactionData = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
            interactionData.caption = polaroidCaptionBuffer
            stickers[index].interactionData = interactionData

            // 🚀 VOLVER A LA POSICIÓN ORIGINAL CON ANIMACIÓN
            if let original = originalStickerTransform {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    stickers[index].position = original.pos
                    stickers[index].scale = original.scale
                    stickers[index].rotation = original.rot
                }
            }
        }

        withAnimation(.easeOut(duration: 0.25)) {
            editingPolaroidId = nil
            polaroidCaptionBuffer = ""
            originalStickerTransform = nil
        }

        // Ocultar teclado
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func findUserIdByUsername(_ username: String, completion: @escaping (String?) -> Void) {
        let firestoreService = FirestoreService()
        firestoreService.searchUsers(query: username, limit: 10) { result in
            switch result {
            case .success(let users):
                if let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    completion(user.id)
                } else {
                    completion(nil)
                }
            case .failure(let error):
                completion(nil)
            }
        }
    }


    // ✅ FUNCIONES AUXILIARES: Mostrar toasts informativos
    private func showUserNotFoundToast(username: String) {
        // Implementar toast: "Usuario @username no encontrado"
    }

    private func showHashtagToast(hashtag: String) {
        // Implementar toast: "Ver publicaciones con #hashtag"
    }

    private func showLocationToast(location: String) {
        // Implementar toast: "Ver ubicación: location"
    }

    private func showPollToast() {
        // Implementar toast: "Toca para votar en la encuesta"
    }

    private func showQuestionToast() {
        // Implementar toast: "Toca para responder la pregunta"
    }

    private func showQuestionResponseToast() {
        // Implementar toast: "Respuesta anónima compartida"
    }
}


// Vista mejorada para cada sticker individual
struct StickerOverlayView: View {
    @Binding var sticker: StickerItem // ✅ USAR BINDING PARA ACTUALIZACIÓN DIRECTA
    let isSelected: Bool
    let isDragging: Bool
    let isContentEditing: Bool
    let onUpdate: (StickerItem) -> Void
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onStickerTapped: (StickerItem) -> Void

    @State private var currentPosition: CGPoint
    @State private var scale: CGFloat
    @State private var rotation: Angle
    @State private var showInteractionFeedback = false
    @State private var selfieCaptureTrigger = false
    @State private var selfieSwitchCameraTrigger = false
    @State private var lastSelfieSwitchAt: Date = .distantPast
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar
    @State private var contentDragStartOffset: CGSize?
    @State private var contentPinchStartScale: CGFloat?

    init(sticker: Binding<StickerItem>, isSelected: Bool, isDragging: Bool,
         isContentEditing: Bool,
         onUpdate: @escaping (StickerItem) -> Void,
         onDelete: @escaping () -> Void,
         onDragChanged: @escaping (CGPoint) -> Void,
         onDragEnded: @escaping (CGPoint) -> Void,
         onStickerTapped: @escaping (StickerItem) -> Void) {
        self._sticker = sticker
        self.isSelected = isSelected
        self.isDragging = isDragging
        self.isContentEditing = isContentEditing
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onStickerTapped = onStickerTapped
        _currentPosition = State(initialValue: sticker.wrappedValue.position)
        _scale = State(initialValue: sticker.wrappedValue.scale)
        _rotation = State(initialValue: sticker.wrappedValue.rotation)
    }

    private var stickerSize: CGSize {
        switch sticker.type {
        case .frame: return CGSize(width: 200, height: 240)
        case .quiz, .poll, .question: return CGSize(width: 300, height: 320)
        case .weather: return CGSize(width: 140, height: 50)
        case .time: return CGSize(width: 180, height: 80)
        default: return sticker.image.size
        }
    }

    private var minimumStickerScale: CGFloat {
        switch sticker.type {
        case .poll, .question, .quiz:
            return 0.42
        case .time, .weather, .location, .mention, .hashtag, .link, .countdown, .emojiSlider:
            return 0.35
        case .frame, .selfie:
            return 0.3
        default:
            return 0.28
        }
    }

    private var maximumStickerScale: CGFloat {
        let maxDimension: CGFloat = 2048
        let maxScaleWidth = maxDimension / max(stickerSize.width, 1)
        let maxScaleHeight = maxDimension / max(stickerSize.height, 1)
        let safeMaxScale = min(maxScaleWidth, maxScaleHeight)
        return min(4.5, safeMaxScale)
    }

    var body: some View {
        ZStack {
            // ... (resto del contenido del ZStack sin cambios hasta la línea 7405)
            // ✅ SOLUCIÓN DEFINITIVA: Renderizado idéntico al Viewer
            if sticker.isAnimated {
                if let videoURL = sticker.videoURL {
                    // ✅ VIDEO STICKER (Loop)
                    ZStack(alignment: .top) {
                        StoryVideoPlayerView(videoURL: videoURL, videoGravity: .resizeAspectFill)
                            .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                            .allowsHitTesting(false)

                        // Header Overlay (Username)
                        if let interactionData = sticker.interactionData, let username = interactionData.username {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))

                                Text(username)
                                    .font(.custom("Poppins-Bold", size: 10))
                                    .foregroundColor(.white)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .mask(
                                        LinearGradient(
                                            colors: [.black, .black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                        }

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                else if let gifURL = sticker.gifURL {
                    AnimatedStickerView(
                        sticker: sticker,
                        size: CGSize(width: sticker.image.size.width, height: sticker.image.size.height)
                    )
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .allowsHitTesting(false)
                }
            } else if isLiveSelfieSticker {
                ZStack {
                    SelfieStickerLiveCameraView(
                        captureTrigger: $selfieCaptureTrigger,
                        switchCameraTrigger: $selfieSwitchCameraTrigger
                    ) { capturedImage in
                        let targetSize = max(sticker.image.size.width, 100)
                        let stickerImage = makeCapturedSelfieStickerImage(from: capturedImage, size: targetSize)
                        let capturedSticker = StickerItem(
                            id: sticker.id,
                            image: stickerImage,
                            position: currentPosition,
                            scale: scale,
                            rotation: rotation,
                            gifURL: nil,
                            videoURL: nil,
                            isAnimated: false,
                            type: .selfie,
                            interactionData: nil
                        )
                        sticker = capturedSticker
                        onUpdate(capturedSticker)
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                    .clipShape(Circle())

                    Circle()
                        .stroke(Color.black.opacity(0.04), lineWidth: max(0.5, sticker.image.size.width * 0.005))
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                .padding(8)
                        }
                    }
                }
                .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                .allowsHitTesting(false)
            } else if sticker.type == .poll, let pollData = sticker.interactionData?.pollData {
                // POLL INTERACTIVO
                InteractivePollSticker(
                    pollData: pollData,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    selectedOption: .constant(nil),
                    hasVoted: .constant(false),
                    voteCounts: .constant([:]),
                    totalVotes: .constant(0),
                    onVote: { _ in }
                )
                .frame(width: 300, height: 172)
                .allowsHitTesting(false)
            } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
                // QUESTION INTERACTIVO
                InteractiveQuestionSticker(
                    questionText: questionText,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .frame(width: 300, height: 132)
                .allowsHitTesting(false)
            } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
                // LOCATION INTERACTIVO
                InteractiveLocationSticker(
                    locationName: locationName,
                    coordinate: sticker.interactionData?.locationCoordinate,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
                // HASHTAG INTERACTIVO
                InteractiveHashtagSticker(
                    hashtag: hashtag,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .mention, let username = sticker.interactionData?.username {
                // MENTION INTERACTIVO
                InteractiveMentionSticker(
                    username: username,
                    onTap: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .countdown,
                      let countdownTitle = sticker.interactionData?.countdownTitle,
                      let targetAtMs = sticker.interactionData?.countdownTargetAtMs {
                StickerCountdownCardView(title: countdownTitle, targetAtMs: targetAtMs)
                    .allowsHitTesting(false)
            } else if sticker.type == .emojiSlider,
                      let sliderPrompt = sticker.interactionData?.sliderPrompt,
                      let sliderEmoji = sticker.interactionData?.sliderEmoji {
                StickerEmojiSliderCardView(
                    prompt: sliderPrompt,
                    emoji: sliderEmoji,
                    value: 0.5
                )
                .frame(width: emojiSliderRenderingSize(prompt: sliderPrompt).width, height: emojiSliderRenderingSize(prompt: sliderPrompt).height)
                .allowsHitTesting(false)
            } else if sticker.type == .shareMoment {
                // ✅ SHARE MOMENT: Renderizado dinámico de overlays (Header + Caption)
                ZStack(alignment: .top) {
                    // 1. Imagen base (Captura limpia del marco glass + media)
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)

                    // 2. Video Overlay (si existe)
                    if let videoURL = sticker.videoURL {
                        StickerVideoPlayer(url: videoURL)
                           .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                           .allowsHitTesting(false)
                    }

                    // 3. Dynamic Overlays (Mismo diseño que en el Viewer)
                    ZStack(alignment: .top) {
                        Color.clear // Contenedor

                        // Header (Username + Profile)
                        HStack(spacing: 10) {
                            if let interactionData = sticker.interactionData,
                               let userId = interactionData.userId {
                                AsyncProfileImageView(userId: userId)
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 34, height: 34)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text(sticker.interactionData?.username ?? "User")
                                    .font(.custom("Poppins-Bold", size: 13))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.black, .black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }

                        // Gallery Indicator (Top Right)
                        if (sticker.interactionData?.mediaCount ?? 0) > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .padding(12)
                                        .padding(.top, 42) // Below header text
                                }
                                Spacer()
                            }
                        }
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .allowsHitTesting(false)

            } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {

                // WEATHER ANIMADO
                AnimatedWeatherSticker(
                    weatherSymbol: weatherSymbol,
                    temperature: sticker.interactionData?.questionText ?? "🌤️"
                )
                .frame(width: 140, height: 50)
                .allowsHitTesting(false)
            } else if sticker.type == .time {
                StickerTimeCardView(
                    timeText: sticker.interactionData?.questionText ?? Date.now.formatted(date: .omitted, time: .shortened),
                    dateText: sticker.interactionData?.caption ?? Date.now.formatted(date: .numeric, time: .omitted)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .frame {
                InteractiveFrameSticker(
                    image: sticker.image,
                    caption: sticker.interactionData?.caption,
                    contentScale: sticker.interactionData?.contentScale ?? 1.0,
                    contentOffset: CGSize(
                        width: sticker.interactionData?.contentOffsetX ?? 0,
                        height: sticker.interactionData?.contentOffsetY ?? 0
                    ),
                    isEditing: true
                )
                .frame(width: 200, height: 240)
                .allowsHitTesting(false)
            } else if sticker.type == .quiz,
                      let question = sticker.interactionData?.quizQuestion,
                      let options = sticker.interactionData?.quizOptions {
                InteractiveQuizSticker(
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    question: question,
                    options: options,
                    correctIndex: sticker.interactionData?.quizCorrectIndex ?? 0,
                    isEditing: true
                )
                .frame(width: 300)
                .allowsHitTesting(false)
            } else if sticker.type == .audio {
                InteractiveAudioStickerView(
                    audioURL: sticker.interactionData?.audioURL ?? "",
                    duration: sticker.interactionData?.audioDuration ?? 15.0
                )
                .allowsHitTesting(false)
            } else {
                // STICKER ESTÁTICO / IMAGEN (Emoji, Generic, etc.)
                // ✅ FIX: Usar tamaño natural de la imagen
                if sticker.type == .selfie {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                } else {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit) // Asegurar aspecto correcto
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .allowsHitTesting(false)
                }
            }
        }
        .rotationEffect(rotation)
        .scaleEffect(isDragging ? 0.9 : (showInteractionFeedback ? 1.05 : 1.0))
        .scaleEffect(scale)
        .opacity(isDragging ? 0.8 : 1.0)
        .frame(width: stickerSize.width, height: stickerSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            handleStickerTap()
        }
        // ✅ SINCRONIZAR CON EL PADRE PARA EL "VUELO HERO"
        .onChange(of: sticker.position) { _, newPos in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPosition = newPos
            }
        }
        .onChange(of: sticker.scale) { _, newScale in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
            }
        }
        .onChange(of: sticker.rotation) { _, newRot in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                rotation = newRot
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard isLiveSelfieSticker else { return }
                    lastSelfieSwitchAt = Date()
                    selfieSwitchCameraTrigger.toggle()
                    let feedback = UIImpactFeedbackGenerator(style: .rigid)
                    feedback.impactOccurred()
                }
        )
        .gesture(
            DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Usar el canvas global para estabilidad absoluta
                .onChanged { value in
                    if isContentEditing, sticker.type == .frame {
                        let baseOffset = contentDragStartOffset ?? frameContentOffset
                        if contentDragStartOffset == nil {
                            contentDragStartOffset = baseOffset
                        }

                        let stickerScale = max(scale, 0.0001)
                        let proposedOffset = CGSize(
                            width: baseOffset.width + (value.translation.width / stickerScale),
                            height: baseOffset.height + (value.translation.height / stickerScale)
                        )

                        updateFrameContentOffset(proposedOffset)
                        return
                    }

                    if dragOffset == .zero {
                        // Calcular la distancia desde el centro del sticker hasta donde pusimos el dedo
                        dragOffset = CGSize(
                            width: value.startLocation.x - currentPosition.x,
                            height: value.startLocation.y - currentPosition.y
                        )
                    }

                    let newPos = CGPoint(
                        x: value.location.x - dragOffset.width,
                        y: value.location.y - dragOffset.height
                    )

                    currentPosition = newPos
                    onDragChanged(newPos)
                    sticker.position = newPos
                }
                .onEnded { _ in
                    if isContentEditing, sticker.type == .frame {
                        contentDragStartOffset = nil
                        return
                    }

                    dragOffset = .zero // Resetear para el próximo arrastre
                    onDragEnded(currentPosition)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if isContentEditing, sticker.type == .frame {
                        let baseScale = contentPinchStartScale ?? max(sticker.interactionData?.contentScale ?? 1.0, 1.0)
                        if contentPinchStartScale == nil {
                            contentPinchStartScale = baseScale
                        }

                        updateFrameContentScale(baseScale * value)
                        return
                    }

                    let newScale = sticker.scale * value
                    scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
                }
                .onEnded { _ in
                    if isContentEditing, sticker.type == .frame {
                        contentPinchStartScale = nil
                        return
                    }

                    sticker.scale = scale
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { value in
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    rotation = sticker.rotation + value
                }
                .onEnded { value in
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    sticker.rotation = rotation
                }
        )
        .position(currentPosition) // ✅ Posicionar en el lienzo global al final
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showInteractionFeedback)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rotation)
    }

    private func handleStickerTap() {
        if isLiveSelfieSticker {
            // Evita capturar justo después de long-press para cambiar cámara.
            if Date().timeIntervalSince(lastSelfieSwitchAt) < 0.35 { return }
            selfieCaptureTrigger.toggle()
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return
        }

        // ✅ Feedback visual MUY sutil
        withAnimation(.spring(response: 0.15, dampingFraction: 0.9)) {
            showInteractionFeedback = true
        }

        // ✅ Feedback háptico ligero
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // ✅ Llamar al handler
        onStickerTapped(sticker)

        // Reset feedback visual rápido
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.15)) {
                showInteractionFeedback = false
            }
        }
    }

    private var isLiveSelfieSticker: Bool {
        sticker.type == .selfie && sticker.interactionData?.caption == "selfie_live"
    }

    private var frameContentOffset: CGSize {
        CGSize(
            width: sticker.interactionData?.contentOffsetX ?? 0,
            height: sticker.interactionData?.contentOffsetY ?? 0
        )
    }

    private func updateFrameContentOffset(_ proposedOffset: CGSize) {
        let clamped = clampedFrameContentOffset(
            proposedOffset,
            imageSize: sticker.image.size,
            contentScale: sticker.interactionData?.contentScale ?? 1.0
        )

        var interaction = sticker.interactionData ?? StickerItem.StickerInteractionData()
        interaction.contentOffsetX = clamped.width
        interaction.contentOffsetY = clamped.height
        sticker.interactionData = interaction
    }

    private func updateFrameContentScale(_ proposedScale: CGFloat) {
        let clampedScale = min(max(proposedScale, 1.0), 4.0)
        var interaction = sticker.interactionData ?? StickerItem.StickerInteractionData()
        interaction.contentScale = clampedScale

        let currentOffset = CGSize(
            width: interaction.contentOffsetX ?? 0,
            height: interaction.contentOffsetY ?? 0
        )
        let clampedOffset = clampedFrameContentOffset(
            currentOffset,
            imageSize: sticker.image.size,
            contentScale: clampedScale
        )
        interaction.contentOffsetX = clampedOffset.width
        interaction.contentOffsetY = clampedOffset.height
        sticker.interactionData = interaction
    }

    private func clampedFrameContentOffset(_ offset: CGSize, imageSize: CGSize, contentScale: CGFloat) -> CGSize {
        let viewportSize = CGSize(width: 180, height: 180)
        let imageRatio = imageSize.width / max(imageSize.height, 0.0001)
        let viewportRatio = viewportSize.width / max(viewportSize.height, 0.0001)

        let baseSize: CGSize
        if imageRatio > viewportRatio {
            let height = viewportSize.height
            baseSize = CGSize(width: height * imageRatio, height: height)
        } else {
            let width = viewportSize.width
            baseSize = CGSize(width: width, height: width / max(imageRatio, 0.0001))
        }

        let safeScale = max(contentScale, 1.0)
        let drawSize = CGSize(width: baseSize.width * safeScale, height: baseSize.height * safeScale)
        let maxOffsetX = max(0, (drawSize.width - viewportSize.width) / 2)
        let maxOffsetY = max(0, (drawSize.height - viewportSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func makeCapturedSelfieStickerImage(from originalImage: UIImage, size: CGFloat) -> UIImage {
        let selfieImage = downscaleSelfieImageIfNeeded(originalImage)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: rect)

            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            UIColor.white.setFill()
            circlePath.fill()
            context.cgContext.restoreGState()

            let imageRect = rect.insetBy(dx: size * 0.012, dy: size * 0.012)
            let imageCirclePath = UIBezierPath(ovalIn: imageRect)
            context.cgContext.saveGState()
            imageCirclePath.addClip()

            let aspectRatio = selfieImage.size.width / max(selfieImage.size.height, 1)
            let drawRect: CGRect
            if aspectRatio > 1 {
                let drawHeight = imageRect.height
                let drawWidth = drawHeight * aspectRatio
                let drawX = imageRect.midX - drawWidth / 2
                drawRect = CGRect(x: drawX, y: imageRect.minY, width: drawWidth, height: drawHeight)
            } else {
                let drawWidth = imageRect.width
                let drawHeight = drawWidth / max(aspectRatio, 0.0001)
                let drawY = imageRect.midY - drawHeight / 2
                drawRect = CGRect(x: imageRect.minX, y: drawY, width: drawWidth, height: drawHeight)
            }

            selfieImage.draw(in: drawRect)
            context.cgContext.restoreGState()

            UIColor.black.withAlphaComponent(0.04).setStroke()
            circlePath.lineWidth = max(0.5, size * 0.005)
            circlePath.stroke()
        }
    }

    private func downscaleSelfieImageIfNeeded(_ image: UIImage, maxDimension: CGFloat = 900) -> UIImage {
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image
        }

        let aspectRatio = image.size.width / max(image.size.height, 1)
        let newSize: CGSize
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct SelfieStickerLiveCameraView: UIViewRepresentable {
    @Binding var captureTrigger: Bool
    @Binding var switchCameraTrigger: Bool
    let onPhotoCaptured: (UIImage) -> Void

    func makeUIView(context: Context) -> SelfieStickerCameraPreviewView {
        let view = SelfieStickerCameraPreviewView()
        view.onPhotoCaptured = onPhotoCaptured
        return view
    }

    func updateUIView(_ uiView: SelfieStickerCameraPreviewView, context: Context) {
        if captureTrigger != context.coordinator.lastCaptureState {
            context.coordinator.lastCaptureState = captureTrigger
            uiView.capturePhoto()
        }
        if switchCameraTrigger != context.coordinator.lastSwitchCameraState {
            context.coordinator.lastSwitchCameraState = switchCameraTrigger
            uiView.toggleCamera()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCaptureState = false
        var lastSwitchCameraState = false
    }
}

final class SelfieStickerCameraPreviewView: UIView, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "moments.selfieSticker.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var captureEventInteraction: AVCaptureEventInteraction?

    var onPhotoCaptured: ((UIImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    deinit {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    private func configureHardwareCaptureInteraction() {
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.capturePhoto()
        }
        addInteraction(interaction)
        captureEventInteraction = interaction
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = (self.currentCameraPosition == .front)
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleCamera() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .front ? .back : .front
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            if let existing = self.currentInput {
                self.session.removeInput(existing)
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.currentCameraPosition = newPosition
            } else if let oldInput = self.currentInput, self.session.canAddInput(oldInput) {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.applyPreviewConnectionConfiguration()
            }
        }
    }

    private func configureCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupSession()
                }
            }
        default:
            break
        }
    }

    private func setupSession() {
        sessionQueue.async {
            guard !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.currentInput = input

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = false
            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self.bounds
                self.layer.insertSublayer(previewLayer, at: 0)
                self.previewLayer = previewLayer
                self.applyPreviewConnectionConfiguration()
            }

            self.session.startRunning()
        }
    }

    private func applyPreviewConnectionConfiguration() {
        guard let previewConnection = previewLayer?.connection else { return }
        if previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = .portrait
        }
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = (currentCameraPosition == .front)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let normalized = image.creatorNormalizedUp()
        DispatchQueue.main.async {
            self.onPhotoCaptured?(normalized)
        }
    }
}

// MARK: - Interfaz de selección moderna y elegante
struct ModernSelectionInterface: View {
    let size: CGSize
    let scale: CGFloat
    @Binding var isScaling: Bool
    @Binding var isRotating: Bool
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Angle) -> Void
    let onDelete: () -> Void

    @State private var initialScale: CGFloat = 1.0
    @State private var initialRotation: Angle = .zero
    @State private var showDeleteButton = false

    var body: some View {
        ZStack {
            // ✅ BORDE ELEGANTE - Solo líneas en las esquinas
            CornerBorders(size: size)

            // ✅ CONTROLES EN LAS ESQUINAS
            VStack {
                HStack {
                    // Botón eliminar (esquina superior izquierda)
                    DeleteButton(onDelete: onDelete)

                    Spacer()

                    // Control de rotación (esquina superior derecha)
                    RotationControl(
                        scale: scale,
                        isRotating: $isRotating,
                        onRotationChanged: { newRotation in
                            onRotationChanged(newRotation)
                        }
                    )
                }

                Spacer()

                HStack {
                    Spacer()

                    // Control de escala (esquina inferior derecha)
                    ScaleControl(
                        scale: scale,
                        isScaling: $isScaling,
                        onScaleChanged: { newScale in
                            onScaleChanged(newScale)
                        }
                    )
                }
            }
            .frame(width: size.width + 40, height: size.height + 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDeleteButton = true
            }
        }
    }
}

// MARK: - Bordes de esquina elegantes
struct CornerBorders: View {
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerBorder()
                    .rotationEffect(.degrees(Double(index * 90)))
            }
        }
        .frame(width: size.width + 20, height: size.height + 20)
    }
}

struct CornerBorder: View {
    var body: some View {
        VStack {
            HStack {
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: 12)
                    Spacer()
                }
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 12, height: 2)
                    Spacer()
                }
            }
            Spacer()
        }
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Botón de eliminar moderno
struct DeleteButton: View {
    let onDelete: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onDelete()
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .offset(x: -10, y: -10)
    }
}

// MARK: - Control de rotación
struct RotationControl: View {
    let scale: CGFloat
    @Binding var isRotating: Bool
    let onRotationChanged: (Angle) -> Void

    @State private var lastRotation: Angle = .zero
    @State private var currentRotation: Angle = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(isRotating ? .degrees(180) : .degrees(0))
                .animation(.easeInOut(duration: 0.3), value: isRotating)
        }
        .offset(x: 10, y: -10)
        .gesture(
            RotationGesture()
                .onChanged { value in
                    if !isRotating {
                        isRotating = true
                        lastRotation = currentRotation
                    }
                    currentRotation = lastRotation + value
                    onRotationChanged(currentRotation)
                }
                .onEnded { value in
                    isRotating = false
                    lastRotation = currentRotation
                }
        )
    }
}

// MARK: - Control de escala
struct ScaleControl: View {
    let scale: CGFloat
    @Binding var isScaling: Bool
    let onScaleChanged: (CGFloat) -> Void

    @State private var lastScale: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(isScaling ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isScaling)
        }
        .offset(x: 10, y: 10)
        .onAppear {
            lastScale = scale
            currentScale = scale
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if !isScaling {
                        isScaling = true
                    }
                    let newScale = lastScale * value
                    currentScale = min(max(newScale, 0.3), 4.0)
                    onScaleChanged(currentScale)
                }
                .onEnded { value in
                    isScaling = false
                    lastScale = currentScale
                }
        )
    }
}



// MARK: - Additional Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview Provider

struct CreatorView_Previews: PreviewProvider {
    static var previews: some View {
        CreatorView(
            isCreatingStory: .constant(false),
            showCreatorView: .constant(true),
            initialSticker: nil
        )
    }
}

// MARK: - 🎨 COMPONENTES PREMIUM COMPARTIDOS (The Cinematic Handoff)

// GlowSharePill moved to CreatorSharedModels.swift

// MARK: - ✨ REVEAL STICKER EDITOR

struct RevealStickerEditorView: View {
    @Binding var stickers: [StickerItem]
    @Binding var editingId: String?

    @State private var selectedTab: EditorTab = .presets
    @State private var selectedPresetId: String = "classic"
    @State private var tabTransientOffset: CGFloat = 0

    // Custom state
    @State private var customType: String = "solid"
    @State private var customPattern: String = "dots"
    @State private var customPrimary: Color = .black
    @State private var customSecondary: Color = .black

    enum EditorTab: CaseIterable, Hashable {
        case presets
        case custom
    }

    private var currentStickerIndex: Int? {
        stickers.firstIndex(where: { $0.id == editingId })
    }

    var body: some View {
        ZStack {
            // 1. Preview Background (Full Screen)
            if let index = currentStickerIndex {
                RevealSurfaceView(
                    type: stickers[index].interactionData?.revealType,
                    pattern: stickers[index].interactionData?.revealPattern,
                    primaryColor: stickers[index].interactionData?.revealPrimaryColor,
                    secondaryColor: stickers[index].interactionData?.revealSecondaryColor
                )
                .ignoresSafeArea()
            }

            // 2. Editor UI
            VStack(spacing: 0) {
                headerView

                Spacer()

                VStack(spacing: 24) {
                    tabSelector

                    if selectedTab == .presets {
                        presetsGrid
                    } else {
                        customControls
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 65) // Ajustado a 65 según preferencia
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6), .black.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            loadCurrentState()
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: { editingId = nil }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .liquidGlass(in: Circle())
            }

            Spacer()

            Text(NSLocalizedString("revealEditor.title", comment: "Customize Reveal"))
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(.white)
                .shadow(radius: 4)

            Spacer()

            Button(action: { editingId = nil }) {
                Text(NSLocalizedString("common.done", comment: "Done"))
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .liquidGlass(in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var tabSelector: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.clear)
                    .liquidGlass(in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: tabSegmentWidth(for: proxy.size.width), height: 34)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.24), radius: 7, x: 0, y: 2)
                    .offset(x: tabPillOffset(for: proxy.size.width))

                HStack(spacing: 0) {
                    ForEach(Array(EditorTab.allCases.enumerated()), id: \.element) { index, tab in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: tab))
                                .font(.system(size: 13, weight: .semibold))

                            Text(title(for: tab))
                                .font(.custom("Poppins-Medium", size: 13))
                        }
                        .foregroundColor(tabLabelColor(for: index, width: proxy.size.width))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 3)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: tabVisualIndex(for: proxy.size.width))

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    tabTransientOffset = constrainedTabTranslation(value.translation.width, width: proxy.size.width)
                                }
                            }
                            .onEnded { value in
                                settleTabSelection(
                                    translation: value.translation.width,
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            }
                    )
            }
        }
        .frame(height: 42)
    }

    private var presetsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(revealPresets) { preset in
                    Button(action: { applyPreset(preset) }) {
                        VStack(spacing: 8) {
                            RevealSurfaceView(
                                type: preset.type,
                                pattern: preset.pattern,
                                primaryColor: preset.primary,
                                secondaryColor: preset.secondary
                            )
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedPresetId == preset.id ? Color.white : Color.white.opacity(0.2), lineWidth: 2)
                            )

                            Text(NSLocalizedString("revealEditor.preset.\(preset.id)", comment: ""))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 160)
    }

    private var customControls: some View {
        VStack(spacing: 20) {
            // Pattern Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["none", "dots", "noise", "static", "scanlines", "grid", "lines", "waves", "matrix", "holographic"], id: \.self) { p in
                        Button(action: { updateCustomPattern(p) }) {
                            Text(NSLocalizedString("revealEditor.pattern.\(p)", comment: ""))
                                .font(.custom("Poppins-Medium", size: 13))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(customPattern == p ? Color.white : Color.white.opacity(0.1))
                                .foregroundColor(customPattern == p ? .black : .white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    ColorPicker(selection: $customPrimary, supportsOpacity: false) {
                        Circle()
                            .fill(customPrimary)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .labelsHidden()

                    Text(NSLocalizedString("revealEditor.color1", comment: ""))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .onChange(of: customPrimary) { updateCustomColors() }

                // Color 2 (Optional)
                if customType == "gradient" {
                    VStack(spacing: 4) {
                        ColorPicker(selection: $customSecondary, supportsOpacity: false) {
                            Circle()
                                .fill(customSecondary)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                        .labelsHidden()

                        Text(NSLocalizedString("revealEditor.color2", comment: ""))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .onChange(of: customSecondary) { updateCustomColors() }
                }

                Button(action: toggleType) {
                    Image(systemName: customType == "solid" ? "plus" : "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }

    private var currentTabIndex: Int {
        EditorTab.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private func title(for tab: EditorTab) -> String {
        switch tab {
        case .presets:
            return NSLocalizedString("revealEditor.tab.presets", comment: "Presets")
        case .custom:
            return NSLocalizedString("revealEditor.tab.custom", comment: "Custom")
        }
    }

    private func icon(for tab: EditorTab) -> String {
        switch tab {
        case .presets:
            return "sparkles"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    private func tabSegmentWidth(for totalWidth: CGFloat) -> CGFloat {
        let innerWidth = totalWidth - 6
        return innerWidth / CGFloat(EditorTab.allCases.count)
    }

    private func tabBaseOffset(for totalWidth: CGFloat) -> CGFloat {
        let segmentWidth = tabSegmentWidth(for: totalWidth)
        let start = -((CGFloat(EditorTab.allCases.count - 1) * segmentWidth) / 2)
        return start + (CGFloat(currentTabIndex) * segmentWidth)
    }

    private func tabPillOffset(for totalWidth: CGFloat) -> CGFloat {
        tabBaseOffset(for: totalWidth) + tabTransientOffset
    }

    private func tabVisualIndex(for totalWidth: CGFloat) -> Int {
        let width = tabSegmentWidth(for: totalWidth)
        let start = -((CGFloat(EditorTab.allCases.count - 1) * width) / 2)
        let raw = ((tabPillOffset(for: totalWidth) - start) / width).rounded()
        return min(max(Int(raw), 0), EditorTab.allCases.count - 1)
    }

    private func tabLabelColor(for index: Int, width: CGFloat) -> Color {
        tabVisualIndex(for: width) == index ? .white.opacity(0.96) : .white.opacity(0.58)
    }

    private func constrainedTabTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let segment = tabSegmentWidth(for: width)
        let minOffset = -((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let maxOffset = ((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let proposed = tabBaseOffset(for: width) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - tabBaseOffset(for: width)
    }

    private func settleTabSelection(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let segment = tabSegmentWidth(for: width)
        let proposedOffset = tabBaseOffset(for: width) + translation
        let start = -((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let fractionalIndex = (proposedOffset - start) / segment
        let threshold = min(segment * 0.28, 36)

        let targetIndex: Int
        if abs(translation) > threshold && abs(translation) < segment * 0.5 {
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentTabIndex + direction, 0), EditorTab.allCases.count - 1)
        } else if abs(translation) < 5 {
            targetIndex = min(max(Int(locationX / segment), 0), EditorTab.allCases.count - 1)
        } else {
            targetIndex = min(max(Int(fractionalIndex.rounded()), 0), EditorTab.allCases.count - 1)
        }

        let targetTab = EditorTab.allCases[targetIndex]
        if targetTab != selectedTab {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedTab = targetTab
            tabTransientOffset = 0
        }
    }


    // MARK: - Logic

    private func loadCurrentState() {
        guard let index = currentStickerIndex else { return }
        let data = stickers[index].interactionData

        customType = data?.revealType ?? "solid"
        customPattern = data?.revealPattern ?? "dots"
        customPrimary = Color(hex: data?.revealPrimaryColor ?? "#000000") ?? .black
        customSecondary = Color(hex: data?.revealSecondaryColor ?? "#000000") ?? .black

        // Try to match preset
        if let preset = revealPresets.first(where: {
            $0.type == customType &&
            $0.pattern == customPattern &&
            $0.primary.lowercased() == data?.revealPrimaryColor?.lowercased()
        }) {
            selectedPresetId = preset.id
            selectedTab = .presets
            tabTransientOffset = 0
        } else {
            selectedTab = .custom
            tabTransientOffset = 0
        }
    }

    private func applyPreset(_ preset: RevealPreset) {
        selectedPresetId = preset.id
        updateSticker(type: preset.type, pattern: preset.pattern, primary: preset.primary, secondary: preset.secondary)
        HapticManager.shared.lightImpact()
    }

    private func updateCustomPattern(_ p: String) {
        customPattern = p
        updateSticker(type: customType, pattern: p, primary: customPrimary.toHex() ?? "#000000", secondary: customSecondary.toHex() ?? "#000000")
    }

    private func updateCustomColors() {
        updateSticker(type: customType, pattern: customPattern, primary: customPrimary.toHex() ?? "#000000", secondary: customSecondary.toHex() ?? "#000000")
    }

    private func toggleType() {
        withAnimation {
            customType = customType == "solid" ? "gradient" : "solid"
        }
        updateCustomColors()
    }

    private func updateSticker(type: String, pattern: String, primary: String, secondary: String) {
        guard let index = currentStickerIndex else { return }
        var data = stickers[index].interactionData ?? StickerItem.StickerInteractionData()

        data.revealType = type
        data.revealPattern = pattern
        data.revealPrimaryColor = primary
        data.revealSecondaryColor = secondary

        stickers[index].interactionData = data
    }
}

struct RevealPreset: Identifiable {
    let id: String
    let name: String
    let type: String
    let pattern: String
    let primary: String
    let secondary: String
}

let revealPresets: [RevealPreset] = [
    RevealPreset(id: "classic", name: "Classic", type: "solid", pattern: "dots", primary: "#000000", secondary: "#000000"),
    RevealPreset(id: "midnight", name: "Midnight", type: "solid", pattern: "grid", primary: "#0B1215", secondary: "#0B1215"),
    RevealPreset(id: "golden", name: "Golden", type: "gradient", pattern: "noise", primary: "#BF953F", secondary: "#8E6E2D"),
    RevealPreset(id: "neon", name: "Neon Glow", type: "gradient", pattern: "lines", primary: "#430089", secondary: "#82009F"),
    RevealPreset(id: "silver", name: "Silver", type: "gradient", pattern: "dots", primary: "#C0C0C0", secondary: "#708090"),
    RevealPreset(id: "retro", name: "Old TV", type: "solid", pattern: "static", primary: "#FFFFFF", secondary: "#FFFFFF"),
    RevealPreset(id: "matrix", name: "Matrix", type: "solid", pattern: "matrix", primary: "#000000", secondary: "#000000"),
    RevealPreset(id: "blueprint", name: "Blueprint", type: "solid", pattern: "grid", primary: "#003366", secondary: "#003366"),
    RevealPreset(id: "magic", name: "Magic", type: "solid", pattern: "holographic", primary: "#C8C8C8", secondary: "#C8C8C8")
]

fileprivate func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(type)
}
