import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import CoreLocation

/// Detalle de momentos del explorer: scroll vertical estilo feed + chrome con blur.
struct ExploreMomentDetailView: View {
    @State private var moments: [Moment]
    let initialIndex: Int
    let initialMomentId: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var firestoreService = FirestoreService.shared
    @State private var currentIndex: Int
    @State private var selectedMoment: Moment?
    @State private var trackedMomentViewIds: Set<String> = []

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var backgroundOpacity: Double = 1.0

    @State private var showContextMenu = false
    @State private var contextMenuMoment: Moment?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var editedContent = ""
    @State private var storyRoute: StoryUserPresentationRoute?
    @State private var selectedHashtag = ""
    @State private var showExploreWithHashtag = false
    @State private var feedViewModel = FeedViewModel()

    // Peek + mapa (paridad con feed)
    @State private var peekImageURL: String?
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    @State private var showingLocationMap = false
    @State private var selectedLocationName = ""
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?
    @Namespace private var profileZoomNamespace
    @State private var profileRoute: FeedProfileSheetRoute?

    private var chromeTitle: String {
        NSLocalizedString("explore.title", comment: "Explore")
    }

    init(moments: [Moment], initialIndex: Int, initialMomentId: String? = nil) {
        self._moments = State(initialValue: moments)
        self.initialIndex = initialIndex
        self.initialMomentId = initialMomentId

        let resolvedIndex: Int
        if let initialMomentId,
           let matched = moments.firstIndex(where: { $0.id == initialMomentId }) {
            resolvedIndex = matched
        } else {
            resolvedIndex = initialIndex
        }
        let clamped = moments.isEmpty ? 0 : min(max(resolvedIndex, 0), moments.count - 1)
        self._currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            ZStack {
                ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)

                exploreMomentsScrollView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                    .gesture(exploreDismissDragGesture)
            }

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
                    onReport: {}
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
                                    width: UIApplication.shared.activeWindowSize.width - 32,
                                    height: (UIApplication.shared.activeWindowSize.width - 32) / max(peekAspectRatio, 0.1)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { exploreDetailToolbarContent }
        .momentsScrollEdgeChrome()
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
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
                .environmentObject(firestoreService)
                .ignoresSafeArea(.keyboard)
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .navigationDestination(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: selectedLocationName,
                coordinate: selectedLocationCoordinate,
                isPresented: $showingLocationMap
            )
        }
        .userProfileNavigationDestination(item: $profileRoute, namespace: profileZoomNamespace)
        .alert(NSLocalizedString("modernMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
            Text("modernMomentDetail.delete.message")
        }
        .onAppear {
            let target = resolvedInitialIndex
            currentIndex = target
            trackMomentViewIfNeeded(for: moments[safe: target])
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
        .momentZoomNavigationSurface(colorScheme: colorScheme)
    }

    private var resolvedInitialIndex: Int {
        if let initialMomentId,
           let matched = moments.firstIndex(where: { $0.id == initialMomentId }) {
            return matched
        }
        guard moments.indices.contains(initialIndex) else { return 0 }
        return initialIndex
    }

    private var exploreDismissDragGesture: some Gesture {
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
                        dragOffset = UIApplication.shared.activeWindowSize.width
                        backgroundOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismissExploreDetail()
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

    private func dismissExploreDetail() {
        dismiss()
    }

    private func activateVideoForIndex(_ index: Int) {
        guard let moment = moments[safe: index], moment.hasVideoMedia else { return }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        GlobalVideoManager.shared.playVideo(consumerId)
    }

    private func exploreMomentsScrollView() -> some View {
                    let screenHeight = UIApplication.shared.activeWindowSize.height
                    let feedCardHeight = screenHeight * 0.58
                    let adAfterIndices = FeedAdPlacement.indicesAfterWhichToShowAd(
            momentIds: moments.map { $0.id ?? "" },
            minGap: 3,
            maxGap: 5
        )

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                    ForEach(Array(moments.enumerated()), id: \.element.feedViewIdentity) { index, moment in
                        VStack(spacing: max(15, screenHeight * 0.02)) {
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
                                    onLocationTap: { locationName, coordinate in
                                        selectedLocationName = locationName
                                        selectedLocationCoordinate = coordinate
                                        showingLocationMap = true
                                    },
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
                                    },
                                    reelsVideos: nil
                                )
                                .equatable()
                                .feedMomentVisibility(momentId: GlobalVideoManager.profileVideoConsumerId(for: moment))
                                .environmentObject(firestoreService)
                                .environment(feedViewModel)
                            }

                            if adAfterIndices.contains(index) {
                                SmartNativeAdView(slotId: "explore-\(moment.id ?? "\(index)")")
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
                .feedScrollVisibilityAnchor()
            }
            .scrollClipDisabled()
            .environment(feedViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                let target = resolvedInitialIndex
                guard target > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var exploreDetailToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: AdaptiveColors(colorScheme: colorScheme).primary,
                preset: .navigationBack,
                action: dismissExploreDetail
            )
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .principal) {
            Text(chromeTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).primary)
                .lineLimit(1)
        }
    }

    private func trackMomentViewIfNeeded(for moment: Moment?) {
        guard let moment, let momentId = moment.id else { return }
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
            storyRoute = StoryUserPresentationRoute(userId: normalizedUserId)
        } else {
            openUserProfile(userId: normalizedUserId)
        }
    }

    private func openUserProfile(userId: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }
        profileRoute = FeedProfileSheetRoute(userId: normalizedUserId)
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

        let imageURLs = VideoPlaybackSelector.shared.imagePrefetchURLs(from: upcoming, maxMoments: 8)
        if !imageURLs.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: imageURLs)
        }

        let videoURLs = VideoPlaybackSelector.shared.preloadURLStrings(from: upcoming, maxMoments: 4)
        if !videoURLs.isEmpty {
            VideoPreloader.shared.preloadAssets(urls: videoURLs)
        }
    }

    private func updateMoment(payload: EditMomentPayload) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }

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
            guard error == nil else { return }
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

        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                guard error == nil,
                      let index = moments.firstIndex(where: { $0.id == moment.id }) else { return }

                moments.remove(at: index)
                if moments.isEmpty {
                    dismissExploreDetail()
                    return
                }
                currentIndex = min(currentIndex, max(0, moments.count - 1))
            }
        }
    }
}
