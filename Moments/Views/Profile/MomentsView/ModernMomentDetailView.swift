import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation

// MARK: - ✅ Vista detallada de momentos con diseño del feed y aspect ratios
struct ModernMomentDetailView: View {
    let moments: [Moment]
    let initialIndex: Int
    let initialMomentId: String?
    let topContentInset: CGFloat
    let restrictPlaybackToInitialIndex: Bool
    let openCommentsOnAppear: Bool
    let onDismiss: () -> Void
    private let resolvedInitialIndex: Int
    
    @StateObject private var firestoreService = FirestoreService()
    @State private var currentIndex: Int
    
    // ✅ LONG PRESS PEEK: Estado para overlay a nivel de la vista
    @State private var peekImageURL: String? = nil
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    @State private var selectedMoment: Moment?
    @State private var trackedMomentViewIds: Set<String> = []
    @State private var feedViewModel = FeedViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    // ✅ Estados para el menú contextual
    @State private var showContextMenu = false
    @State private var contextMenuMoment: Moment?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    
    // ✅ NUEVOS: Estados para drag transition
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var backgroundOpacity: Double = 1.0
    
    // ✅ NUEVOS: Estados para navegación al explorer
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag: Bool = false
    
    // ✅ NUEVOS: Navegación de perfil desde tags
    @State private var profileRoute: FeedProfileSheetRoute?
    @Namespace private var profileZoomNamespace
    @State private var storyRoute: StoryUserPresentationRoute?
    @State private var selectedLocationMoment: Moment? // ✅ Usar Item Binding para evitar race conditions en SwiftUI
    @State private var hasAppliedInitialScroll = false
    @Environment(\.profileDetailVideoPlaybackEnabled) private var profileDetailVideoPlaybackEnabled
    @Environment(\.profileGridHeroTransitionCoordinator) private var heroCoordinator
    
    private let privacyService = PrivacyService()
    private let firestoreService2 = FirestoreService()
    
    init(
        moments: [Moment],
        initialIndex: Int,
        initialMomentId: String? = nil,
        topContentInset: CGFloat = 64,
        restrictPlaybackToInitialIndex: Bool = false,
        openCommentsOnAppear: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.moments = moments
        self.initialIndex = initialIndex
        self.initialMomentId = initialMomentId
        self.topContentInset = topContentInset
        self.restrictPlaybackToInitialIndex = restrictPlaybackToInitialIndex
        self.openCommentsOnAppear = openCommentsOnAppear
        self.onDismiss = onDismiss
        
        let resolved: Int
        if let initialMomentId,
           let matchedIndex = moments.firstIndex(where: { $0.id == initialMomentId }) {
            resolved = matchedIndex
        } else {
            resolved = initialIndex
        }
        self.resolvedInitialIndex = resolved
        
        let clamped = moments.isEmpty ? 0 : min(max(resolved, 0), moments.count - 1)
        self._currentIndex = State(initialValue: clamped)
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            ZStack {
                ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)

                modernMomentsScrollView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                    .gesture(profileDetailDismissDragGesture)
            }
        
        // Overlays globales
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
            .transition(.opacity)
        }
        
        // 2. Share Sheet Overlay (Sin fondo nativo)
        if showShareSheet, let moment = contextMenuMoment {
            ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1001)
        }
        
        // 3. ✅ LONG PRESS PEEK: Overlay a pantalla completa
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
                                height: (UIScreen.main.bounds.width - 32) / peekAspectRatio
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
        // .sheet(isPresented: $showShareSheet) REMOVED
        .alert(NSLocalizedString("modernMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
                            Text("modernMomentDetail.delete.message")
        }
        /*.sheet(isPresented: $showReportSheet) {
            if let moment = contextMenuMoment {
                ReportBottomSheet(moment: moment)
            }
        }*/
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .userProfileNavigationDestination(item: $profileRoute, namespace: profileZoomNamespace)
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
                .environmentObject(firestoreService)
                .ignoresSafeArea(.keyboard)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedLocationMoment != nil },
            set: { if !$0 { selectedLocationMoment = nil } }
        )) {
            if let moment = selectedLocationMoment {
                LocationMapView(
                    locationName: resolvedLocationName(moment.location ?? ""),
                    coordinate: moment.locationCoordinate?.toCLLocationCoordinate2D,
                    isPresented: Binding(
                        get: { selectedLocationMoment != nil },
                        set: { if !$0 { selectedLocationMoment = nil } }
                    )
                )
            }
        }
        .onAppear {
            let target = clampedInitialIndex
            currentIndex = target
            VideoMomentsIndex.shared.rebuild(from: moments)

            if openCommentsOnAppear, let moment = moments[safe: target] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    selectedMoment = moment
                }
            }

            // Hero → detalle: no pausar; el handoff mantiene el mismo player en marcha.
            let initialMoment = moments[safe: target]
            let hasHeroHandoff = initialMoment.map {
                GlobalVideoManager.shared.hasPendingProfileDetailHandoff(
                    forMomentId: GlobalVideoManager.profileVideoConsumerId(for: $0)
                )
            } ?? false

            if !hasHeroHandoff {
                GlobalVideoManager.shared.pauseAllVideos()
                // Entrada directa desde el grid: activar el video inicial una vez
                // que el player ya se haya registrado (dos ciclos de layout, ~150ms).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    activateVideoForIndex(target)
                }
            }
            // Para el path hero, la activación la gestiona el coordinator vía
            // profileDetailVideoPlaybackEnabled + restrictPlaybackToInitialIndex.

            trackMomentViewIfNeeded(for: moments[safe: target])
        }
        .onChange(of: profileDetailVideoPlaybackEnabled) { _, enabled in
            guard enabled, restrictPlaybackToInitialIndex else { return }
            activateInitialProfileVideoIfNeeded()
        }
        .onDisappear {
            GlobalVideoManager.shared.pauseAllVideos()
            FeedVisibilityCoordinator.shared.update(all: [:])
            feedViewModel.shutdown()
        }
        .onChange(of: currentIndex) { _, newIndex in
            trackMomentViewIfNeeded(for: moments[safe: newIndex])
            // Activar el video del nuevo índice al paginar en el detalle.
            activateVideoForIndex(newIndex)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { profileDetailToolbarContent }
        .momentsScrollEdgeChrome()
    }

    @ToolbarContentBuilder
    private var profileDetailToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: adaptiveColors.primary,
                preset: .navigationBack,
                action: {
                    withAnimation(.easeOut(duration: 0.18)) {
                        onDismiss()
                    }
                }
            )
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .principal) {
            if let moment = moments[safe: currentIndex] {
                LiveUsernameContent(userId: moment.authorId, fallbackUsername: moment.username) { username in
                    VStack(spacing: 1) {
                        Text(username)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(adaptiveColors.primary)
                            .lineLimit(1)

                        Text(NSLocalizedString("profile.tab.moments", comment: "Moments tab title"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 200)
                }
            }
        }
    }

    private var profileDetailDismissDragGesture: some Gesture {
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
                        heroCoordinator?.isDismissingInteractively = true
                        onDismiss()
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
    
    private var clampedInitialIndex: Int {
        clampedIndex(resolvedInitialIndex)
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard !moments.isEmpty else { return 0 }
        return min(max(index, 0), moments.count - 1)
    }

    private func resolvedLocationName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NSLocalizedString("feed.location.default", comment: "Default location name")
    }
    
    private func openLocationMap(for moment: Moment) {
        self.selectedLocationMoment = moment
    }

    private func openUserProfile(userId: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }
        profileRoute = FeedProfileSheetRoute(userId: normalizedUserId)
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
    
    private func handleDetailPeek(moment: Moment, imageURL: String, ratio: CGFloat, isPressing: Bool) {
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

    @ViewBuilder
    private func detailMomentRow(
        index: Int,
        moment: Moment,
        feedCardHeight: CGFloat
    ) -> some View {
        let isProtected = (moment.audience?.lowercased() ?? "") != "everyone"

        ScreenshotProtectedView(isProtected: isProtected) {
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
                onLocationTap: { _, _ in
                    openLocationMap(for: moment)
                },
                onContextMenu: { tappedMoment in
                    contextMenuMoment = tappedMoment
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showContextMenu = true
                    }
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
                    handleDetailPeek(moment: moment, imageURL: imageURL, ratio: ratio, isPressing: isPressing)
                }
            )
            .equatable()
            .environmentObject(firestoreService)
            .environment(feedViewModel)
        }
        .id(index)
        .onAppear {
            currentIndex = index
        }
    }

    private func activateInitialProfileVideoIfNeeded() {
        activateVideoForIndex(clampedInitialIndex)
    }

    /// Activa (pin + play) el video del índice dado, o pausa todos si no hay video.
    private func activateVideoForIndex(_ index: Int) {
        guard let moment = moments[safe: index] else { return }
        guard moment.hasVideoMedia else {
            // Si el post actual no tiene video, no hay nada que reproducir.
            return
        }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        GlobalVideoManager.shared.playVideo(consumerId)
    }

    private func mergedVisibilityValues(_ values: [String: CGFloat]) -> [String: CGFloat] {
        guard restrictPlaybackToInitialIndex, profileDetailVideoPlaybackEnabled else { return values }
        guard let moment = moments[safe: clampedInitialIndex] else { return values }

        var merged = values
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        merged[consumerId] = max(merged[consumerId] ?? 0, 1.0)
        return merged
    }

    // ✅ ScrollView principal MODIFICADO para conectar con el menú contextual
    private func modernMomentsScrollView() -> some View {
        let screenHeight = UIScreen.main.bounds.height
        let feedCardHeight = screenHeight * 0.58

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        detailMomentRow(
                            index: index,
                            moment: moment,
                            feedCardHeight: feedCardHeight
                        )
                    }
                }
                .padding(.horizontal, FeedMomentCardLayout.listHorizontalPadding)
                .padding(.bottom, 24)
                .onPreferenceChange(MomentVisibilityPreference.self) { values in
                    FeedVisibilityCoordinator.shared.update(all: mergedVisibilityValues(values))
                }
            }
            .scrollClipDisabled()
            .environment(\.profileDetailDirectVideoPlayback, restrictPlaybackToInitialIndex)
            .environment(feedViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                applyInitialScrollIfNeeded(using: proxy)
            }
        }
    }
    
    // ✅ Resto de funciones (updateMoment, deleteMoment, etc.)...
    private func updateMoment(payload: EditMomentPayload) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        firestoreService2.updateMomentDetails(
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
        ) { _ in }
    }
    
    private func deleteMoment() {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        firestoreService2.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
            }
        }
    }
    
    private func applyInitialScrollIfNeeded(using proxy: ScrollViewProxy) {
        guard !hasAppliedInitialScroll else { return }
        hasAppliedInitialScroll = true

        let target = clampedInitialIndex
        guard target > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

// MARK: - ✅ Resto de componentes (mantener igual)
struct ModernDetailBackground: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
        }
    }
}

struct DetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
