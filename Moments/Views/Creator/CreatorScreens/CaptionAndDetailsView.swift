import SwiftUI
import CoreLocation
import FirebaseAuth

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

    // Total tags: foto + menciones en leyenda (@usuario)
    private var totalTagsCount: Int {
        let spatial = selectedMediaItems.reduce(0) { $0 + ($1.tags?.count ?? 0) }
        return spatial + taggedUsers.count
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
    @State private var activeCaptionMention: MentionDraftToken?

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
            case .everyone: return "AudienceEveryoneIcon"
            case .mutuals: return "AudienceMutualsIcon"
            case .admirers: return "AudienceMutualsIcon"
            case .bestFriends: return "AudienceBestFriendsIcon"
            case .custom: return "AudienceCustomIcon"
            case .onlyMe: return "AudienceOnlyMeIcon"
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
                                .momentsChromeGlass(in: Circle(), interactive: true)
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
                                    audience: captionContentAudience,
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

                if let mention = activeCaptionMention {
                    CommentMentionSearchOverlay(
                        query: mention.query,
                        showsSearchField: false,
                        onSelect: { user in
                            insertCaptionMention(user)
                        },
                        onCancel: {
                            activeCaptionMention = nil
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(200)
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
        .onChange(of: captionText) { _, newValue in
            activeCaptionMention = MentionParsing.detectActiveToken(in: newValue)
        }
    }

    private func insertCaptionMention(_ user: AppUser) {
        guard let token = activeCaptionMention else { return }

        let replacement = "@\(user.username) "
        captionText.replaceSubrange(token.fullRange, with: replacement)

        if !taggedUsers.contains(user.id) {
            taggedUsers.append(user.id)
        }

        activeCaptionMention = nil
        HapticManager.shared.selection()
    }

    private func publishMoment() {
        guard Auth.auth().currentUser?.uid != nil else { return }

        isPublishing = true

        let finalDisableComments = disableComments
        let finalHideLikeCounts = hideLikeCounts
        let finalAllowSharing = allowSharing
        let finalScheduledDate = isSchedulingEnabled ? scheduledDate : nil
        let detectedAspectRatio = preferredMomentAspectRatio(for: selectedMediaItems)
        let spatialTaggedUsers = selectedMediaItems.flatMap { $0.tags ?? [] }.map(\.userId)
        let captionSnapshot = captionText
        let mediaSnapshot = selectedMediaItems
        let audienceSnapshot = audienceSetting
        let customViewersSnapshot = customSelectedUsers.isEmpty ? nil : customSelectedUsers
        let listIdSnapshot = selectedListId
        let locationSnapshot = locationName.isEmpty ? nil : locationName
        let coordinateSnapshot = selectedLocation.map {
            Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let hiddenLayersSnapshot = canUseHiddenLayers ? hiddenLayerDrafts.filter(\.isReadyToPublish) : []
        let manualTaggedSnapshot = taggedUsers

        Task {
            let captionMentionIds = await MomentMentionResolver.resolveUserIds(from: captionSnapshot)
            let allTaggedUsers = Array(Set(manualTaggedSnapshot + spatialTaggedUsers))

            await MainActor.run {
                let uploadingMoment = uploadService.uploadMoment(
                    content: captionSnapshot,
                    mediaItems: mediaSnapshot,
                    taggedUsers: allTaggedUsers.isEmpty ? nil : allTaggedUsers,
                    mentionedUsers: captionMentionIds.isEmpty ? nil : captionMentionIds,
                    location: locationSnapshot,
                    locationCoordinate: coordinateSnapshot,
                    audienceSetting: audienceSnapshot,
                    customViewers: customViewersSnapshot,
                    customListId: listIdSnapshot,
                    aspectRatio: detectedAspectRatio,
                    disableComments: finalDisableComments,
                    hideLikeCounts: finalHideLikeCounts,
                    allowSharing: finalAllowSharing,
                    scheduledDate: finalScheduledDate,
                    hiddenLayers: hiddenLayersSnapshot
                )

                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    isLaunching = true
                }
                HapticManager.shared.notification(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isPublishing = false

                    if uploadingMoment != nil {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ReturnToFeedAfterMomentPublish"),
                            object: nil
                        )
                        showCreatorView = false
                        resetForm()
                    } else {
                        HapticManager.shared.notification(.error)
                        withAnimation {
                            isLaunching = false
                        }
                    }
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
        activeCaptionMention = nil
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
    private var captionContentAudience: ContentAudience {
        ContentAudience.fromCaptionAudienceSetting(
            audienceSetting,
            hasCustomList: audienceSetting == .custom && selectedListId != nil
        )
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
    // MARK: - 📍 MINIMAL OPTION ROW (Clean Design)

    struct MinimalOptionRow: View {
        var icon: String? = nil
        var audience: ContentAudience? = nil
        let title: String
        let value: String?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                MinimalOptionRowContent(
                    icon: icon,
                    audience: audience,
                    title: title,
                    value: value
                )
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
        var icon: String? = nil
        var audience: ContentAudience? = nil
        let title: String
        let value: String?

        var body: some View {
            HStack(spacing: 16) {
                Group {
                    if let audience {
                        AudienceIconView(
                            audience: audience,
                            size: AudienceIconMetrics.creatorRow,
                            tintColor: .white
                        )
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
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
