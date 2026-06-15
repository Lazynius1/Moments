import SwiftUI
import FirebaseAuth
import Kingfisher
import CoreLocation

/// Detalle de un solo momento con card estilo feed (actividad, notificaciones, chat…).
struct SingleMomentDetailView: View {
    let chromeTitle: String?

    @State private var moment: Moment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var firestoreService = FirestoreService.shared
    @State private var feedViewModel = FeedViewModel()
    @State private var selectedMoment: Moment?
    @State private var trackedMomentView = false

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var backgroundOpacity: Double = 1.0
    @State private var contentMinY: CGFloat = .greatestFiniteMagnitude
    @State private var initialContentMinY: CGFloat = .greatestFiniteMagnitude

    @State private var showContextMenu = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var editedContent = ""
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId = ""
    @State private var selectedHashtag = ""
    @State private var showExploreWithHashtag = false
    @State private var showingLocationMap = false
    @State private var selectedLocationName = ""
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?

    @State private var peekImageURL: String?
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    @Namespace private var profileZoomNamespace
    @State private var showUserProfile = false
    @State private var selectedUserId = ""

    init(moment: Moment, chromeTitle: String? = nil) {
        self._moment = State(initialValue: moment)
        self.chromeTitle = chromeTitle
    }

    private var resolvedChromeTitle: String {
        if let chromeTitle {
            let trimmed = chromeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let username = moment.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        return NSLocalizedString("explore.title", comment: "Explore")
    }

    private var chromeBlurProgress: CGFloat {
        ProfileHeaderCollapseMetrics.detailScrollChromeBlurProgress(
            contentMinY: contentMinY,
            initialContentMinY: initialContentMinY
        )
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)

                singleMomentScrollView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                    .gesture(singleDismissDragGesture)

                ProfileStickyChromeContainer(
                    blurProgress: chromeBlurProgress,
                    blurFadeTail: ProfileHeaderCollapseMetrics.feedDetailChromeBlurFadeTail,
                    tabsArePinned: false
                ) {
                    FeedPinnedTopChrome(
                        title: resolvedChromeTitle,
                        onDismiss: dismissDetail
                    )
                }
                .zIndex(10)
                .allowsHitTesting(true)
            }

            if showContextMenu {
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
            if let selectedMoment {
                ModernCommentsView(moment: selectedMoment)
                    .environmentObject(firestoreService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditMomentView(
                moment: moment,
                onSave: { payload in
                    updateMoment(payload: payload)
                }
            )
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
        .fullScreenCover(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: selectedLocationName,
                coordinate: selectedLocationCoordinate,
                isPresented: $showingLocationMap
            )
        }
        .fullScreenCover(isPresented: $showUserProfile, onDismiss: {
            selectedUserId = ""
        }) {
            if !selectedUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserProfileView(userId: selectedUserId)
                    .userProfileZoomDestination(userId: selectedUserId, namespace: profileZoomNamespace)
            }
        }
        .alert(NSLocalizedString("modernMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
            Text("modernMomentDetail.delete.message")
        }
        .onAppear {
            trackMomentViewIfNeeded()
            VideoMomentsIndex.shared.rebuild(from: [moment])
            if let userId = Auth.auth().currentUser?.uid {
                firestoreService.loadSavedMoments(userId: userId)
            }
            GlobalVideoManager.shared.pauseAllVideos()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                activateVideoIfNeeded()
            }
        }
        .onDisappear {
            GlobalVideoManager.shared.pauseAllVideos()
            FeedVisibilityCoordinator.shared.update(all: [:])
            feedViewModel.shutdown()
        }
        .momentZoomNavigationSurface(colorScheme: colorScheme)
    }

    private func singleMomentScrollView() -> some View {
        let screenHeight = UIScreen.main.bounds.height
        let feedCardHeight = screenHeight * 0.58

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                Color.clear
                    .frame(height: ProfileHeaderCollapseMetrics.feedStyleDetailTopInset)

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
                        onContextMenu: { _ in
                            showContextMenu = true
                        },
                        onTagTap: { userId in
                            handleAvatarTap(userId: userId, hasStory: false)
                        },
                        onOpenUserProfile: { userId in
                            handleAvatarTap(userId: userId, hasStory: false)
                        },
                        profileZoomNamespace: profileZoomNamespace,
                        onPeek: { imageURL, ratio, isPressing in
                            handlePeek(imageURL: imageURL, ratio: ratio, isPressing: isPressing)
                        }
                    )
                    .equatable()
                    .environmentObject(firestoreService)
                    .environment(feedViewModel)
                }
            }
            .padding(.horizontal, FeedMomentCardLayout.listHorizontalPadding)
            .padding(.bottom, 24)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("singleMomentScroll")).minY
                    )
                }
            )
            .onPreferenceChange(MomentVisibilityPreference.self) { values in
                FeedVisibilityCoordinator.shared.update(all: values)
            }
        }
        .profileGridNavigationChrome(colorScheme: colorScheme)
        .scrollClipDisabled()
        .coordinateSpace(name: "singleMomentScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            contentMinY = value
            if !initialContentMinY.isFinite || initialContentMinY > 10_000 {
                initialContentMinY = value
            }
        }
        .environment(feedViewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var singleDismissDragGesture: some Gesture {
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
                        dismissDetail()
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

    private func dismissDetail() {
        dismiss()
    }

    private func activateVideoIfNeeded() {
        guard moment.hasVideoMedia else { return }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        GlobalVideoManager.shared.playVideo(consumerId)
    }

    private func trackMomentViewIfNeeded() {
        guard !trackedMomentView, moment.id != nil, !moment.authorId.isEmpty else { return }
        trackedMomentView = true
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .momentView, with: moment.authorId)
        }
    }

    private func handleAvatarTap(userId: String, hasStory: Bool) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }

        if hasStory {
            selectedStoryUserId = normalizedUserId
            showSpecificUserStories = true
        } else {
            selectedUserId = normalizedUserId
            showUserProfile = true
        }
    }

    private func handlePeek(imageURL: String, ratio: CGFloat, isPressing: Bool) {
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

    private func updateMoment(payload: EditMomentPayload) {
        guard let momentId = moment.id else { return }

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
                        guard case .success(let updated) = result else { return }
                        moment = updated
                    }
                }
            }
        }
    }

    private func deleteMoment() {
        guard let momentId = moment.id else { return }

        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                guard error == nil else { return }
                dismissDetail()
            }
        }
    }
}
