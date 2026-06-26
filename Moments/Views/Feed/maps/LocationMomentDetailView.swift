import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation

// MARK: - ✅ Vista detallada para momentos de ubicación con diseño moderno
struct LocationMomentDetailView: View {
    @State private var moments: [Moment]
    let initialIndex: Int
    let locationName: String
    @Binding var momentAvailability: [String: Bool]
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var firestoreService = FirestoreService.shared
    @State private var currentIndex: Int
    @State private var selectedMoment: Moment?
    @State private var trackedMomentViewIds: Set<String> = []

    // ✅ NUEVOS: Estados para drag transition
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var backgroundOpacity: Double = 1.0
    @State private var contentMinY: CGFloat = .greatestFiniteMagnitude
    @State private var initialContentMinY: CGFloat = .greatestFiniteMagnitude

    // ✅ Estados para interacciones (ModernPostCardView gestiona save/comments internamente)

    // ✅ NUEVOS: Estados para menú contextual
    @State private var showContextMenu = false
    @State private var contextMenuMoment: Moment?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId: String = ""
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag = false
    @State private var feedViewModel = FeedViewModel()
    @State private var locationDisplayTitle: String = ""
    @State private var peekImageURL: String?
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    @Namespace private var profileZoomNamespace
    @State private var showUserProfile = false
    @State private var selectedUserId = ""

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var chromeBlurProgress: CGFloat {
        ProfileHeaderCollapseMetrics.detailScrollChromeBlurProgress(
            contentMinY: contentMinY,
            initialContentMinY: initialContentMinY
        )
    }

    private var basePlaceName: String {
        let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard let moment = moments[safe: currentIndex],
              let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else {
            return locationName
        }
        return location
    }

    init(
        locationMoments: [Moment],
        initialIndex: Int,
        locationName: String,
        momentAvailability: Binding<[String: Bool]> = .constant([:]),
        isPresented: Binding<Bool>
    ) {
        self._moments = State(initialValue: locationMoments)
        self.initialIndex = initialIndex
        self.locationName = locationName
        self._momentAvailability = momentAvailability
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: initialIndex)
        self._locationDisplayTitle = State(initialValue: locationName)
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)

                locationMomentsScrollView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                    .gesture(locationDismissDragGesture)

                ProfileStickyChromeContainer(
                    blurProgress: chromeBlurProgress,
                    blurFadeTail: ProfileHeaderCollapseMetrics.locationChromeBlurFadeTail,
                    tabsArePinned: false
                ) {
                    FeedPinnedTopChrome(
                        title: locationDisplayTitle,
                        onDismiss: dismissLocationDetail
                    )
                }
                .zIndex(10)
                .allowsHitTesting(true)
            }
            .coordinateSpace(name: "locationDetailOverlay")

            if showContextMenu, let moment = contextMenuMoment {
                ModernContextMenuOverlay(
                    moment: moment,
                    isPresented: $showContextMenu,
                    onEdit: {
                        editedContent = moment.content
                        showEditSheet = true
                    },
                    onDelete: {
                        showDeleteAlert = true
                    },
                    onReport: {
                        // showReportSheet = true // ❌ Ya no se usa sheet
                    }
                )
                .zIndex(1000)
            }

            if isPeeking, let imageURL = peekImageURL {
                ZStack {
                    ScreenshotProtectedView(isProtected: peekIsProtected, fillsContainer: true) {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()

                            KFImage(URL(string: imageURL))
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: UIScreen.main.bounds.width - 32,
                                    height: (UIScreen.main.bounds.width - 32) / max(peekAspectRatio, 0.1)
                                )
                                .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPeeking)
                .allowsHitTesting(false)
                .zIndex(999)
            }
        }
        .navigationBarHidden(true)
        .sheet(
            isPresented: Binding(
                get: { selectedMoment != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedMoment = nil
                    }
                }
            )
        ) {
            if let moment = selectedMoment {
                ModernCommentsView(moment: moment)
                    .environmentObject(firestoreService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let moment = contextMenuMoment {
                EditMomentView(
                    moment: moment,
                    onSave: { payload in
                        updateMoment(payload: payload)
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showSpecificUserStories, onDismiss: {
            selectedStoryUserId = ""
        }) {
            StoriesView(
                startWithUserId: Binding(
                    get: { selectedStoryUserId },
                    set: { selectedStoryUserId = $0 }
                )
            )
            .environmentObject(firestoreService)
            .ignoresSafeArea(.keyboard)
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .fullScreenCover(isPresented: $showUserProfile, onDismiss: {
            selectedUserId = ""
        }) {
            if !selectedUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserProfileView(userId: selectedUserId)
                    .userProfileZoomDestination(userId: selectedUserId, namespace: profileZoomNamespace)
            }
        }
        .alert(NSLocalizedString("locationMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("locationMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("locationMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
            Text("locationMomentDetail.delete.message")
        }
        /*.sheet(isPresented: $showReportSheet) {
            if let moment = contextMenuMoment {
                ReportBottomSheet(moment: moment)
            }
        }*/
        .onAppear {
            let target = min(max(initialIndex, 0), max(0, moments.count - 1))
            currentIndex = target
            trackMomentViewIfNeeded(for: moments[safe: target])
            refreshLocationDisplayTitle()
            VideoMomentsIndex.shared.rebuild(from: moments)
            if let userId = Auth.auth().currentUser?.uid {
                firestoreService.loadSavedMoments(userId: userId)
            }
            GlobalVideoManager.shared.pauseAllVideos()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                activateVideoForIndex(target)
            }
        }
        .onDisappear {
            GlobalVideoManager.shared.pauseAllVideos()
            FeedVisibilityCoordinator.shared.update(all: [:])
            feedViewModel.shutdown()
        }
        .onChange(of: currentIndex) { _, newIndex in
            trackMomentViewIfNeeded(for: moments[safe: newIndex])
            activateVideoForIndex(newIndex)
        }
        .onChange(of: moments.count) { _, _ in
            VideoMomentsIndex.shared.rebuild(from: moments)
        }
        .onChange(of: locationName) { _, _ in
            refreshLocationDisplayTitle()
        }
        .momentZoomNavigationSurface(colorScheme: colorScheme)
    }

    private var locationDismissDragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if value.translation.width > 0 {
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = value.translation.width
                        isDragging = true
                        let progress = min(value.translation.width / 200, 1.0)
                        backgroundOpacity = 1.0 - (progress * 0.4)
                    }
                }
            }
            .onEnded { value in
                let dismissThreshold: CGFloat = 120
                let velocity = value.predictedEndTranslation.width

                if value.translation.width > dismissThreshold || velocity > 300 {
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = UIScreen.main.bounds.width
                        backgroundOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismissLocationDetail()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                        isDragging = false
                        backgroundOpacity = 1.0
                    }
                }
            }
    }

    private func trackMomentViewIfNeeded(for moment: Moment?) {
        guard let moment = moment, let momentId = moment.id else { return }
        guard !moment.authorId.isEmpty else { return }
        guard !trackedMomentViewIds.contains(momentId) else { return }

        trackedMomentViewIds.insert(momentId)
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .momentView, with: moment.authorId)
        }
    }

    private func handleAuthorAvatarTap(userId: String, hasStory: Bool) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }

        if hasStory {
            selectedStoryUserId = normalizedUserId
            showSpecificUserStories = true
        } else {
            openUserProfile(userId: normalizedUserId)
        }
    }

    private func openUserProfile(userId: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }
        selectedUserId = normalizedUserId
        showUserProfile = true
    }

    private func handlePeek(imageURL: String, ratio: CGFloat, isPressing: Bool, moment: Moment) {
        if isPressing, let url = URL(string: imageURL) {
            KingfisherManager.shared.retrieveImage(with: url) { _ in }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if isPressing {
                peekImageURL = imageURL
                peekAspectRatio = ratio
                peekIsProtected = (moment.audience?.lowercased() ?? "") != "everyone"
                isPeeking = true
            } else {
                isPeeking = false
                peekIsProtected = false
            }
        }
    }

    private func prefetchUpcomingMoments(from index: Int) {
        let nextIndex = index + 1
        guard nextIndex < moments.count else { return }

        let endIndex = min(nextIndex + 8, moments.count)
        let upcoming = Array(moments[nextIndex..<endIndex])

        let imageURLs = upcoming.compactMap { moment -> URL? in
            guard let urlString = moment.previewImageURLString else { return nil }
            return URL(string: urlString)
        }
        if !imageURLs.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: imageURLs)
        }

        let videoURLs = VideoPlaybackSelector.shared.preloadURLStrings(from: upcoming, maxMoments: 4)
        if !videoURLs.isEmpty {
            VideoPreloader.shared.preloadAssets(urls: videoURLs)
        }
    }

    private func dismissLocationDetail() {
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
        dismiss()
    }

    private func refreshLocationDisplayTitle() {
        let place = basePlaceName
        locationDisplayTitle = place
        MapLocationDisplayFormatter.resolveTitle(
            place: place,
            coordinate: coordinateForLocationTitle()
        ) { title in
            locationDisplayTitle = title
        }
    }

    private func coordinateForLocationTitle() -> CLLocationCoordinate2D? {
        if let moment = moments[safe: currentIndex],
           let coordinate = moment.locationCoordinate {
            return coordinate.toCLLocationCoordinate2D
        }
        return moments.compactMap(\.locationCoordinate).first?.toCLLocationCoordinate2D
    }

    private func activateVideoForIndex(_ index: Int) {
        guard let moment = moments[safe: index], moment.hasVideoMedia else { return }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        GlobalVideoManager.shared.playVideo(consumerId)
    }

    private func locationMomentsScrollView() -> some View {
        let screenHeight = UIScreen.main.bounds.height
        let feedCardHeight = screenHeight * 0.58

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                    Color.clear
                        .frame(height: ProfileHeaderCollapseMetrics.feedStyleDetailTopInset)

                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        let isAvailable = momentAvailability[moment.mapAvailabilityKey] ?? true

                        ScreenshotProtectedView(
                            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                        ) {
                            ModernPostCardView(
                                moment: moment,
                                availableHeight: feedCardHeight,
                                colorScheme: colorScheme,
                                onComment: { selectedMoment = moment },
                                onNearEnd: {},
                                onHashtagTap: { hashtag in
                                    selectedHashtag = "#\(hashtag)"
                                    showExploreWithHashtag = true
                                },
                                onLocationTap: { _, _ in },
                                onContextMenu: { tappedMoment in
                                    contextMenuMoment = tappedMoment
                                    showContextMenu = true
                                },
                                onTagTap: { userId in
                                    openUserProfile(userId: userId)
                                },
                                onOpenUserProfile: { userId in
                                    openUserProfile(userId: userId)
                                },
                                onAuthorAvatarTap: { userId, hasStory in
                                    handleAuthorAvatarTap(userId: userId, hasStory: hasStory)
                                },
                                profileZoomNamespace: profileZoomNamespace,
                                onPeek: { imageURL, ratio, isPressing in
                                    handlePeek(
                                        imageURL: imageURL,
                                        ratio: ratio,
                                        isPressing: isPressing,
                                        moment: moment
                                    )
                                }
                            )
                            .equatable()
                            .environmentObject(firestoreService)
                            .environment(feedViewModel)
                        }
                        .blur(radius: isAvailable ? 0 : 14)
                        .overlay {
                            if !isAvailable {
                                MomentUnavailableOverlay(compact: false, cornerRadius: 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .id(index)
                        .onAppear {
                            currentIndex = index
                            prefetchUpcomingMoments(from: index)
                        }
                    }
                }
                .padding(.horizontal, FeedMomentCardLayout.listHorizontalPadding)
                .padding(.bottom, 24)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: LocationDetailScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("locationDetailScroll")).minY
                        )
                    }
                )
                .onPreferenceChange(MomentVisibilityPreference.self) { values in
                    FeedVisibilityCoordinator.shared.update(all: values)
                }
            }
            .profileGridNavigationChrome(colorScheme: colorScheme)
            .scrollClipDisabled()
            .coordinateSpace(name: "locationDetailScroll")
            .onPreferenceChange(LocationDetailScrollOffsetPreferenceKey.self) { value in
                contentMinY = value
                if !initialContentMinY.isFinite || initialContentMinY > 10_000 {
                    initialContentMinY = value
                }
            }
            .environment(feedViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                let target = min(max(initialIndex, 0), max(0, moments.count - 1))
                guard target > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    // ✅ NUEVOS: Helpers para información contextual
    private func getAudienceIcon(_ audience: String) -> String {
        switch audience {
        case "everyone": return "globe"
        case "mutuals": return "person.2"
        case "bestFriends": return "heart"
        case "custom", "customList": return "person.3"
        default: return "globe"
        }
    }

    private func getAudienceColor(_ audience: String) -> Color {
        switch audience {
        case "everyone": return .green
        case "mutuals": return .blue
        case "bestFriends": return .pink
        case "custom", "customList": return .orange
        default: return Color(hex: "007AFF")
        }
    }

    private func getAudienceText(_ audience: String) -> String {
        switch audience {
        case "everyone": return "Público"
        case "mutuals": return "Mutuas"
        case "bestFriends": return "Mejores amigos"
        case "custom", "customList": return "Personalizado"
        default: return "Público"
        }
    }


    // ✅ NUEVOS: Funciones auxiliares para menú contextual
    private func updateMoment(payload: EditMomentPayload) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }

        let firestoreService = FirestoreService()
        firestoreService.updateMomentDetails(
            userId: moment.authorId,
            momentId: momentId,
            content: payload.content,
            audience: payload.audience.rawValue,
            customListId: payload.customListId,
            customViewers: payload.customViewers,
            taggedUsers: payload.taggedUsers,
            mentionedUsers: payload.mentionedUsers,
            location: payload.locationName.isEmpty ? nil : payload.locationName,
            locationCoordinate: payload.locationCoordinate.map {
                Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            mediaItems: payload.mediaItems
        ) { error in
            guard error == nil, let momentId = moment.id else { return }
            DispatchQueue.main.async {
                firestoreService.fetchMoment(momentId: momentId, userId: moment.authorId) { result in
                    DispatchQueue.main.async {
                        guard case .success(let updated) = result,
                              let index = moments.firstIndex(where: { $0.id == momentId }) else { return }
                        moments[index] = updated
                    }
                }
            }
        }
    }

    private func deleteMoment() {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }

        isDeleting = true
        let firestoreService = FirestoreService()

        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                self.isDeleting = false

                if error == nil {
                    if let index = moments.firstIndex(where: { $0.id == moment.id }) {
                        moments.remove(at: index)
                        if moments.isEmpty {
                            dismissLocationDetail()
                            return
                        }
                        if index <= currentIndex {
                            currentIndex = min(currentIndex, max(0, moments.count - 1))
                        }
                        if index == currentIndex && currentIndex >= moments.count {
                            dismissLocationDetail()
                        }
                    }
                }
            }
        }
    }
}

private struct LocationDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ✅ Tarjeta de momento de ubicación REFACTORIZADA
enum LocationMomentCardLayout {
    case standalone
    case feed
}

struct LocationMomentCard: View {
    let moment: Moment
    let isAvailable: Bool
    let availableHeight: CGFloat
    let colorScheme: ColorScheme
    var layoutMode: LocationMomentCardLayout = .standalone
    let commentCount: Int
    let isSaved: Bool
    let isSaveLoading: Bool
    let onComment: () -> Void
    let onSave: () -> Void
    let onContextMenu: () -> Void
    let onHashtagTap: (String) -> Void
    let onAvatarTap: (String, Bool) -> Void

    @EnvironmentObject private var firestoreService: FirestoreService
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var showTags: Bool = false // ✅ NUEVO: Control de etiquetas
    @State private var isImmersive: Bool = false // ✅ NUEVO: Soporte para modo inmersivo
    @State private var aspectRatioType: AspectRatioType = .square

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    enum AspectRatioType {
        case square, portrait, landscape, reels

        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8
            case .landscape: return 16.0/9.0
            case .reels: return 9.0/16.0
            }
        }
    }

    private var cardHeight: CGFloat {
        let maxWidth = FeedMomentCardLayout.mediaContentWidth

        guard maxWidth > 0 else {
            return 400 // Fallback seguro
        }

        let aspectRatio: CGFloat
        if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
            aspectRatio = detectedAspectRatio
        } else {
            aspectRatio = aspectRatioType.exactRatio
        }

        let calculatedHeight = maxWidth / aspectRatio

        let dynamicMaxHeight: CGFloat
        switch aspectRatioType {
        case .square:
            dynamicMaxHeight = min(availableHeight * 0.82, 680)
        case .portrait:
            dynamicMaxHeight = min(availableHeight * 0.92, 820)
        case .landscape:
            dynamicMaxHeight = min(availableHeight * 0.68, 440)
        case .reels:
            dynamicMaxHeight = availableHeight * 1.02
        }

        // Para Reels, ocupar casi todo el viewport disponible para evitar huecos inferiores.
        if aspectRatioType == .reels {
            let minReelsHeight = availableHeight * 0.96
            return min(max(calculatedHeight, minReelsHeight), dynamicMaxHeight)
        }

        return min(calculatedHeight, dynamicMaxHeight)
    }

    var body: some View {
        Group {
            if layoutMode == .feed {
                cardContent
                    .padding(.horizontal, 15)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    cardContent
                        .padding(.horizontal, 15)
                        .frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .top)
                }
            }
        }
        .disabled(!isAvailable)
        .blur(radius: isAvailable ? 0 : 20)
        .overlay {
            if !isAvailable {
                MomentUnavailableOverlay(compact: false, cornerRadius: 24)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: layoutMode == .feed ? [] : .top)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    locationMomentImageView

                    VStack {
                        HStack {
                            authorCompactHeader
                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        Spacer()
                    }
                    .zIndex(120)

                    ModernActionButtons(
                        moment: moment,
                        isSaved: .constant(isSaved),
                        isSaveLoading: .constant(isSaveLoading),
                        commentCount: .constant(commentCount),
                        onComment: onComment,
                        onSave: onSave,
                        onContextMenu: onContextMenu,
                        isImmersive: $isImmersive
                    )
                    .environmentObject(firestoreService)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)

            MomentCaptionView(
                moment: moment,
                style: .detail,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap
            )
            .padding(.horizontal, FeedMomentCardLayout.captionHorizontalPadding)

            if !moment.disableComments {
                locationInlineCommentsSection
            }
        }
    }

    private var authorCompactHeader: some View {
        HStack(spacing: 8) {
            StoryRingAvatarView(
                userId: moment.authorId,
                size: 32,
                lineWidth: 2.2,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9,
                onTap: { hasStory in
                    onAvatarTap(moment.authorId, hasStory)
                }
            )

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    onAvatarTap(moment.authorId, false)
                } label: {
                    HStack(spacing: 3) {
                        LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)

                        VerifiedBadgeView(userId: moment.authorId, size: 12)
                    }
                }
                .buttonStyle(.plain)

                Text(moment.timestamp.timeAgoDisplay())
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.clear
                .momentsChromeGlass(in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }


    // ✅ NUEVO: Computed property para mediaItems (consistente con otras vistas)
    private var mediaItems: [MediaItem] {
        // ✅ MODERACIÓN: Usar visibleMediaItems para excluir archivos moderados del carrusel
        let visible = moment.visibleMediaItems
        if !visible.isEmpty {
            return visible
        }

        guard moment.shouldUseLegacyMediaFallback else {
            return [MediaItem(type: .image, url: "")]
        }

        // ✅ FALLBACK: Para momentos legacy que solo tienen imagePath/videoUrl
        var items: [MediaItem] = []
        if let imagePath = moment.imagePath, !imagePath.isEmpty {
            items.append(MediaItem(type: .image, url: imagePath))
        }
        if let videoUrl = moment.videoUrl, !videoUrl.isEmpty {
            items.append(MediaItem(type: .video, url: videoUrl))
        }
        return items.isEmpty ? [MediaItem(type: .image, url: "")] : items
    }

    // ✅ NUEVO: Estado para carrusel
    @State private var currentImageIndex = 0

    // ✅ Imagen principal con aspect ratio dinámico
    private var locationMomentImageView: some View {
        ZStack {
            // ✅ NUEVO: EnhancedCarouselView para múltiples archivos
                EnhancedCarouselView(
                    mediaItems: mediaItems,
                    currentIndex: $currentImageIndex,
                    showTags: $showTags, // ✅ PASAR binding
                    aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                    currentMoment: moment,
                    isImmersive: $isImmersive // ✅ NUEVO
                )
                .carouselImmersivePeekGesture(
                    isImmersive: $isImmersive,
                    mediaItems: mediaItems,
                    currentImageIndex: currentImageIndex,
                    detectedAspectRatio: detectedAspectRatio,
                    realAspectRatio: detectedAspectRatio
                )
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.2), radius: 12, x: 0, y: 8)
            .onAppear {
                detectAspectRatio()
            }

            if moment.hasHiddenLayers,
               moment.hiddenLayerCount > 0,
               mediaItems.count == 1,
               mediaItems.first?.type == .image,
               currentImageIndex == 0 {
                HiddenLayersOverlayView(moment: moment, isImmersive: isImmersive)
                    .frame(height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .zIndex(3)
            }

            // ✅ NUEVO: Indicadores de media múltiple mejorados
            if mediaItems.count > 1 {
                VStack {
                    MomentCarouselPageIndicators(
                        count: mediaItems.count,
                        currentIndex: currentImageIndex
                    )
                    .padding(.top, 20)
                    Spacer()
                }
            }

            // ✅ NUEVO: BOTONES DE ETIQUETAS (Nivel superior del card)
            let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
            if let tags = currentMediaItem?.tags, !tags.isEmpty {
                // Esquina superior izquierda
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring()) {
                                showTags.toggle()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(showTags ? Color(hex: "007AFF") : Color.black.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                                AttachmentIconView(icon: .tagged, preset: .overlayTaggedCompact, tintColor: .white)
                            }
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(100)

                // Esquina inferior izquierda (encima del caption)
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            withAnimation(.spring()) {
                                showTags.toggle()
                            }
                        }) {
                            ZStack {
                                // Background Glass
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 36, height: 36)

                                // Border Gradient Glass
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: showTags ? [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.6)] : [.white.opacity(0.6), .white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 36, height: 36)

                                // Icon tinted if active
                                Image(systemName: showTags ? "person.fill" : "person.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(showTags ? Color(hex: "007AFF") : .white)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, moment.content.isEmpty ? 15 : 15) // En este card el diseño es diferente
                        Spacer()
                    }
                }
                .zIndex(110)
            }
        }
    }

    // ✅ Comentarios inline (como MomentDetailView)
    private var locationInlineCommentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header de comentarios
            HStack {
                AttachmentIconView(icon: .comments, preset: .inlineCommentsHeader, tintColor: Color(hex: "007AFF").opacity(0.9))

                Text("locationMomentDetail.comments")
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if commentCount > 0 {
                    Text("(\(commentCount))")
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 4, x: 0, y: 2)
                }

                Spacer()

                Button(NSLocalizedString("locationMomentDetail.viewAll", comment: "View all")) {
                    onComment()
                }
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundColor(Color(hex: "007AFF"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "007AFF").opacity(0.08))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)

            if commentCount == 0 {
                // Estado vacío de comentarios
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial.opacity(0.75))
                            .frame(width: 54, height: 54)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "007AFF").opacity(0.25), lineWidth: 1.2)
                            )

                        AttachmentIconView(icon: .comments, preset: .commentsEmptyState, tintColor: Color(hex: "007AFF"))
                    }

                    VStack(spacing: 8) {
                        Text("locationMomentDetail.noComments.title")
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))

                        Text("locationMomentDetail.noComments.description")
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundColor(.gray.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Button(NSLocalizedString("locationMomentDetail.comment", comment: "Comment")) {
                        onComment()
                    }
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.68))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.14), Color(hex: "007AFF").opacity(0.22)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 0) // Eliminado padding inferior
    }

    // ✅ NUEVO: Función para detectar aspect ratio
    private func detectAspectRatio() {
        // ✅ PRIMERO: Intentar usar aspect ratio guardado en el momento
        if let savedAspectRatio = moment.aspectRatio {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)

            DispatchQueue.main.async {
                // ✅ Validar que el valor sea finito y positivo
                let ratioValue = aspectRatioFromDB.value
                if ratioValue > 0 && ratioValue.isFinite {
                    self.detectedAspectRatio = ratioValue
                } else {
                    self.detectedAspectRatio = 1.0 // Fallback a square
                }

                // Clasificar el tipo con ratios exactos
                switch aspectRatioFromDB {
                case .landscape:
                    self.aspectRatioType = .landscape
                case .portrait:
                    self.aspectRatioType = .portrait
                case .square:
                    self.aspectRatioType = .square
                case .nineBySixteen:
                    self.aspectRatioType = .reels
                }
            }
            return
        }

        // ✅ FALLBACK: Si no hay aspect ratio guardado, detectar de la imagen
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {
            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.8 // Fallback a 4:5
                self.aspectRatioType = .portrait
            }
            return
        }

        if firstItem.type == .image {
            _ = KFImage(URL(string: firstItem.url))
                .onSuccess { result in
                    let imageSize = result.image.size
                    let ratio = imageSize.width / imageSize.height

                    DispatchQueue.main.async {
                        // ✅ Validar ratio calculado
                        if ratio > 0 && ratio.isFinite {
                            self.detectedAspectRatio = ratio
                            self.classifyAspectRatio(ratio)
                        } else {
                            self.detectedAspectRatio = 1.0
                            self.aspectRatioType = .square
                        }
                    }
                }
                .onFailure { error in
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = 0.8 // Fallback a 4:5
                        self.aspectRatioType = .portrait
                    }
                }
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 1, height: 1) // ✅ Frame mínimo para que funcione
        } else if firstItem.type == .video {
            // Para videos, usar el aspect ratio detectado
            if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
                classifyAspectRatio(detectedAspectRatio)
            } else if !firstItem.url.isEmpty {
                // Si no se ha detectado, detectarlo ahora
                detectVideoAspectRatio(from: firstItem.url)
            }
        }
    }

    private func detectVideoAspectRatio(from urlString: String) {
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let asset = AVURLAsset(url: url)
                let track = try await asset.loadTracks(withMediaType: .video).first

                if let track = track {
                    let size = try await track.load(.naturalSize)
                    let videoRatio = size.width / size.height

                    await MainActor.run {
                        if videoRatio > 0 && videoRatio.isFinite {
                            self.detectedAspectRatio = videoRatio
                            self.classifyAspectRatio(videoRatio)
                        }
                    }
                }
            } catch {
                // Usar ratio por defecto
                await MainActor.run {
                    self.detectedAspectRatio = 1.0
                    self.classifyAspectRatio(1.0)
                }
            }
        }
    }

    // ✅ Clasificar aspect ratio
    private func classifyAspectRatio(_ ratio: CGFloat) {
        let tolerance: CGFloat = 0.05

        if abs(ratio - 1.0) < tolerance {
            self.aspectRatioType = .square
        } else if abs(ratio - 0.8) < tolerance {
            self.aspectRatioType = .portrait
        } else if abs(ratio - 0.5625) < tolerance {
            self.aspectRatioType = .reels
        } else if ratio > 1.4 {
            self.aspectRatioType = .landscape
        } else if ratio < 0.7 {
            self.aspectRatioType = .reels
        } else {
            self.aspectRatioType = .square
        }
    }
}

// MARK: - ✅ Botones de acción REFACTORIZADOS
struct LocationActionButtons: View {
    let moment: Moment  // ✅ CAMBIO AQUÍ
    let commentCount: Int
    let isSaved: Bool
    let isSaveLoading: Bool
    let colorScheme: ColorScheme
    let onComment: () -> Void
    let onSave: () -> Void

    @EnvironmentObject private var firestoreService: FirestoreService

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComment) {
                HStack(spacing: 4) {
                    AttachmentIconView(
                        icon: .comments,
                        preset: .actionChip,
                        style: LinearGradient(
                            colors: commentCount > 0 ?
                            [Color.blue, Color.purple] :
                            adaptiveColors.buttonGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundColor(adaptiveColors.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: commentCount > 0 ?
                                        [Color.blue.opacity(0.6), Color.purple.opacity(0.6)] :
                                        adaptiveColors.buttonStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .scaleEffect(commentCount > 0 ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: commentCount)

            Button(action: onSave) {
                HStack(spacing: 4) {
                    if isSaveLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .tint(adaptiveColors.accent)
                    } else {
                        AttachmentIconView(
                            icon: .bookmark,
                            preset: .actionChip,
                            style: LinearGradient(
                                colors: isSaved ?
                                [Color.yellow, Color.orange] :
                                adaptiveColors.buttonGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: isSaved ?
                                        [Color.yellow.opacity(0.6), Color.orange.opacity(0.6)] :
                                        adaptiveColors.buttonStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .scaleEffect(isSaved ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSaved)
            .disabled(isSaveLoading)

            Spacer()
        }
    }
}

// MARK: - ✅ Contenido expandible (sin cambios - ya está bien)
struct LocationExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false

    private let maxLines = 2
    private let maxCharacters = 80

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content)
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundColor(adaptiveColors.primary)
                .lineLimit(isExpanded ? nil : maxLines)
                .multilineTextAlignment(.leading)
                .shadow(color: adaptiveColors.shadowColor.opacity(0.8), radius: 2, x: 0, y: 1)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
                .background(
                    Text(content)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .lineLimit(maxLines)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.onAppear {
                                    DispatchQueue.main.async {
                                        needsExpansion = content.count > maxCharacters
                                    }
                                }
                            }
                        )
                        .hidden()
                )

            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Text(isExpanded ? "menos" : "más")
                            .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 2, x: 0, y: 1)
                }
                .scaleEffect(isExpanded ? 1.0 : 0.96)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isExpanded)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
    }
}

// MARK: - ✅ Botón seguir (sin cambios - ya está bien)
struct FollowButtonForLocation: View {
    let targetUserId: String
    let colorScheme: ColorScheme
    @State private var followButtonState: FollowButtonState = .canFollow
    @State private var isLoading = false
    @State private var showingUnfollowConfirmation = false

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: toggleFollow) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(adaptiveColors.primary)
                } else {
                    Image(systemName: followIcon)
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(followTitle)
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
            }
            .foregroundColor(adaptiveColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 14), interactive: followButtonState.isActionable)
        }
        .disabled(isLoading || !followButtonState.isActionable)
        .opacity(isPassiveState ? 0.78 : 1)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLoading)
        .onAppear {
            checkFollowStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  userId == targetUserId,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followButtonState = state
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                performFollowToggle()
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }

    private func checkFollowStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        if let cachedState = FollowStateStore.shared.state(for: targetUserId) {
            followButtonState = cachedState
        }

        PrivacyService().getFollowButtonState(viewerId: currentUserId, targetUserId: targetUserId) { state in
            DispatchQueue.main.async {
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: self.targetUserId)
                self.followButtonState = reconciledState
                FollowStateStore.shared.setState(reconciledState, for: self.targetUserId)
            }
        }
    }

    private func toggleFollow() {
        if followButtonState == .following {
            showingUnfollowConfirmation = true
            return
        }

        performFollowToggle()
    }

    private func performFollowToggle() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        isLoading = true

        let firestoreService = FirestoreService()

        if followButtonState == .following {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.followButtonState = .canFollow
                        }
                        FollowStateStore.shared.setState(.canFollow, for: self.targetUserId)
                    }
                }
            }
        } else if followButtonState == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.followButtonState = .canRequestFollow
                        }
                        FollowStateStore.shared.setState(.canRequestFollow, for: self.targetUserId)
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if error == nil {
                        let newState: FollowButtonState = self.followButtonState == .canRequestFollow ? .requestPendingCancellable : .following
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.followButtonState = newState
                        }
                        FollowStateStore.shared.setState(newState, for: self.targetUserId)
                    }
                }
            }
        }
    }

    private var followTitle: String {
        switch followButtonState {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .requestPendingCancellable:
            return NSLocalizedString("feed.follow.cancelRequest", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    private var followIcon: String {
        switch followButtonState {
        case .following:
            return "person.fill.checkmark"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .blocked:
            return "slash.circle"
        default:
            return "person.fill.badge.plus"
        }
    }

    private var isPassiveState: Bool {
        if case .requestPending = followButtonState {
            return true
        }
        return false
    }
}

// MARK: - ✅ Fila de comentario (sin cambios - ya está bien)
struct LocationCommentRow: View {
    let comment: Comment
    let colorScheme: ColorScheme
    var onAvatarTap: ((String, Bool) -> Void)? = nil

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StoryRingAvatarView(
                userId: comment.authorId,
                size: 36,
                lineWidth: 2.2,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9,
                onTap: { hasStory in
                    if let onAvatarTap {
                        onAvatarTap(comment.authorId, hasStory)
                    } else if !hasStory {
                        LegacyNavigationBridge.profile(userId: comment.authorId)
                    }
                }
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Text(comment.username)
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)

                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: comment.authorId, size: 10)
                    }

                    Text(comment.timestamp.timeAgoDisplay())
                        .font(.system(size: legacyPoppinsSize(10)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.7))

                    Spacer()
                }

                Text(comment.content)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundColor(adaptiveColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
        .shadow(color: adaptiveColors.shadowColor, radius: 3, x: 0, y: 1)
    }

}
