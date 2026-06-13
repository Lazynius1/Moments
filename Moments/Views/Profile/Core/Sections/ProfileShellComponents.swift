import SwiftUI
import PhotosUI
import Kingfisher
import FirebaseAuth

// MARK: - Fondo dinámico con temas
struct ModernBackgroundView: View {
    let profileImagePath: String?
    let scrollOffset: CGFloat
    let profileTheme: ProfileTheme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Gradiente base basado en el tema del perfil
            if colorScheme == .dark {
                profileTheme.darkBackgroundGradient
            } else {
                profileTheme.backgroundGradient
            }

            // Imagen de perfil como fondo adaptativo
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                GeometryReader { geometry in
                    KFImage(url)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 30)
                        .opacity(colorScheme == .dark ? 0.15 : 0.08)
                        .scaleEffect(1.2)
                        .offset(y: scrollOffset * 0.2)
                        .ignoresSafeArea()
                }
            }

            // Overlay adaptativo para legibilidad
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: colorScheme == .dark ? [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.5),
                            Color.black.opacity(0.7)
                        ] : [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()

            // Overlay de glassmorphism adaptativo
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.03)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - ModernProfileContentView (Actualizada con refresh)
struct ModernProfileContentView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    let profileZoomNamespace: Namespace.ID
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var isShowingSettings: Bool
    @Binding var isShowingEditProfile: Bool
    @Binding var newBio: String
    @Binding var showingUserList: ProfileView.UserListType?
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var scrollOffset: CGFloat
    @Binding var showingThemeSelector: Bool
    @Binding var selectedProfileTab: ProfileTabType  // ✅ NUEVO: Tab selector
    @Binding var showingQRCode: Bool // ✅ NUEVO: Binding para QR
    @Binding var showProfileImageFullscreen: Bool // ✅ NUEVO
    @Binding var isShowingIncognito: Bool
    let isIncognitoActive: Bool
    @Binding var editingMoment: Moment?
    @Binding var pendingDeleteMoment: Moment?
    @StateObject private var savedMomentsViewModel = SavedMomentsViewModel()  // ✅ NUEVO: Guardados
    @State private var showingFullInfo = false // ✅ NUEVO: Para expandir intereses dentro del bloque social
    @EnvironmentObject private var heroCoordinator: ProfileGridHeroTransitionCoordinator
    @State private var gridPreviewMoment: Moment?
    @State private var zoomDestination: ProfileMomentZoomDestination?
    @State private var identityMinY: CGFloat = .greatestFiniteMagnitude
    @State private var tabsMinY: CGFloat = .greatestFiniteMagnitude
    @Environment(\.colorScheme) private var colorScheme

    private var usernameCollapseProgress: CGFloat {
        ProfileHeaderCollapseMetrics.progress(forTabsMinY: tabsMinY)
    }

    private var tabsArePinned: Bool {
        ProfileHeaderCollapseMetrics.tabsArePinned(tabsMinY: tabsMinY)
    }

    var body: some View {
        if viewModel.isLoading {
            ModernLoadingView()
        } else if let errorMessage = viewModel.errorMessage {
            ModernErrorView(errorMessage: errorMessage, onRetry: {
                if let userId = Auth.auth().currentUser?.uid {
                    viewModel.fetchProfile(userId: userId)
                }
            })
        } else {
            NavigationStack {
                ZStack(alignment: .top) {
                ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: ProfileHeaderCollapseMetrics.topContentInset)

                        ModernProfileHeader(
                            viewModel: viewModel,
                            storyViewModel: storyViewModel,
                            isShowingSettings: $isShowingSettings,
                            isShowingEditProfile: $isShowingEditProfile,
                            newBio: $newBio,
                            showStoryViewer: $showStoryViewer,
                            selectedStoryIndex: $selectedStoryIndex,
                            showingThemeSelector: $showingThemeSelector,
                            showingQRCode: $showingQRCode,
                            showProfileImageFullscreen: $showProfileImageFullscreen,
                            isShowingIncognito: $isShowingIncognito,
                            isIncognitoActive: isIncognitoActive,
                            profileZoomNamespace: profileZoomNamespace,
                            usernameCollapseProgress: usernameCollapseProgress
                        )
                        .padding(.top, ProfileHeaderCollapseMetrics.headerTopPadding)
                        .padding(.bottom, 4)

                        ProfileOverviewCard(
                            viewModel: viewModel,
                            showingUserList: $showingUserList,
                            showingInterests: $showingFullInfo,
                            interests: viewModel.userProfile?.interests ?? []
                        )
                        .padding(.bottom, 4)

                        // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                        ProfileHighlightsView(
                            userId: viewModel.userProfile?.id ?? "",
                            isOwnProfile: viewModel.userProfile?.id == Auth.auth().currentUser?.uid,
                            isCompact: true
                        )
                        .padding(.bottom, 6)

                        if viewModel.isRefreshing {
                            ModernRefreshIndicator()
                                .padding(.bottom, 10)
                        }


                        VStack(spacing: 0) {
                            // ✅ NUEVO: Pill Tabs para cambiar entre Moments y Guardados
                            ProfilePillTabs(selectedTab: $selectedProfileTab)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)
                            .frame(maxWidth: UIScreen.main.bounds.width)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ProfileTabsMinYPreferenceKey.self,
                                        value: geometry.frame(in: .named("profileGridOverlay")).minY
                                    )
                                }
                            )
                            .opacity(tabsArePinned ? 0 : 1)

                            // ✅ NUEVO: Contenido basado en el tab seleccionado
                            switch selectedProfileTab {
                            case .moments:
                                if viewModel.moments.isEmpty {
                                    ModernEmptyMomentsView()
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: UIScreen.main.bounds.width - 40)
                                } else {
                                    GeometryReader { geometry in
                                        ProfileMomentsBentoGrid(
                                            moments: viewModel.moments,
                                            availableWidth: geometry.size.width,
                                            descriptors: ProfileBentoTileAssigner.assign(moments: viewModel.moments)
                                        ) { moment, itemWidth, index, descriptor in
                                            ScreenshotProtectedView(
                                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                            ) {
                                                ModernMomentThumbnail(
                                                    moment: moment,
                                                    size: itemWidth,
                                                    customListNamesById: viewModel.customListNamesById,
                                                    zoomNamespace: profileZoomNamespace,
                                                    zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, gridIndex: index),
                                                    onTap: {
                                                        heroCoordinator.openDirectDetail(
                                                            moments: viewModel.moments,
                                                            initialIndex: index,
                                                            feedKind: .ownMoments
                                                        )
                                                    },
                                                    onLongPress: {
                                                        openGridMenu(moment: moment, index: index)
                                                    },
                                                    usesDiscreetAudienceIcon: true,
                                                    showsAudienceBadge: false,
                                                    gridIndex: index,
                                                    descriptor: descriptor
                                                )
                                            }
                                        }
                                    }
                                    .frame(height: calculateBentoGridHeight(moments: viewModel.moments))
                                }

                            case .saved:
                                // ✅ NUEVO: Contenido real de guardados
                                ProfileSavedContent(
                                    viewModel: savedMomentsViewModel,
                                    zoomNamespace: profileZoomNamespace
                                )
                                .onAppear {
                                    if savedMomentsViewModel.moments.isEmpty && !savedMomentsViewModel.isLoading {
                                        savedMomentsViewModel.loadSavedMoments()
                                    }
                                }

                            case .tagged:
                                // ✅ NUEVO: Contenido de momentos donde has sido etiquetado
                                Group {
                                    if viewModel.isLoadingTagged {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(height: 400)
                                    } else if viewModel.taggedMoments.isEmpty {
                                        ProfileSectionEmptyState(
                                            icon: "person.crop.rectangle",
                                            titleKey: "profile.tagged.empty.title",
                                            subtitleKey: "profile.tagged.empty.description"
                                        )
                                        .frame(height: 400, alignment: .top)
                                    } else {
                                        GeometryReader { geometry in
                                            ProfileMomentsBentoGrid(
                                                moments: viewModel.taggedMoments,
                                                availableWidth: geometry.size.width,
                                                descriptors: ProfileBentoTileAssigner.simple(moments: viewModel.taggedMoments)
                                            ) { moment, itemWidth, index, descriptor in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    ModernMomentThumbnail(
                                                        moment: moment,
                                                        size: itemWidth,
                                                        customListNamesById: viewModel.customListNamesById,
                                                        zoomNamespace: profileZoomNamespace,
                                                        zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, gridIndex: index),
                                                        onTap: {
                                                            heroCoordinator.openDirectDetail(
                                                                moments: viewModel.taggedMoments,
                                                                initialIndex: index,
                                                                feedKind: .taggedMoments
                                                            )
                                                        },
                                                        showsAudienceBadge: false,
                                                        gridIndex: index,
                                                        descriptor: descriptor
                                                    )
                                                }
                                            }
                                        }
                                        .frame(height: calculateTaggedGridHeight(moments: viewModel.taggedMoments))
                                    }
                                }
                                .onAppear {
                                    if viewModel.taggedMoments.isEmpty && !viewModel.isLoadingTagged,
                                       let userId = viewModel.userProfile?.id {
                                        viewModel.fetchTaggedMoments(userId: userId)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                        }
                    )
                    .padding(.bottom, safeAreaBottom + 100)
                }
                .coordinateSpace(name: "scroll")
                .refreshable {
                    await withCheckedContinuation { continuation in
                        var savedRefreshCompleted = true

                        viewModel.refreshProfile()

                        if selectedProfileTab == .saved {
                            savedRefreshCompleted = false
                            savedMomentsViewModel.loadSavedMoments { _ in
                                savedRefreshCompleted = true
                            }
                        }

                        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            Task { @MainActor in
                                if !viewModel.isRefreshing && savedRefreshCompleted {
                                    timer.invalidate()
                                    continuation.resume()
                                }
                            }
                        }
                    }
                }
                .profileGridNavigationChrome(colorScheme: colorScheme)
                .scrollDisabled(heroCoordinator.isInteractive)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .onPreferenceChange(ProfileIdentityMinYPreferenceKey.self) { value in
                    identityMinY = value
                }
                .onPreferenceChange(ProfileTabsMinYPreferenceKey.self) { value in
                    tabsMinY = value
                }
                .onPreferenceChange(ProfileGridThumbnailFramePreferenceKey.self) { frames in
                    heroCoordinator.ingestThumbnailFrames(frames)
                }
                .scrollClipDisabled()

                VStack(spacing: 8) {
                    ProfileOwnPinnedTopChrome(
                        username: viewModel.userProfile?.username ?? "Usuario",
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        collapseProgress: usernameCollapseProgress,
                        isShowingSettings: $isShowingSettings,
                        showingQRCode: $showingQRCode,
                        isShowingIncognito: $isShowingIncognito,
                        isIncognitoActive: isIncognitoActive,
                        profileZoomNamespace: profileZoomNamespace
                    )

                    if tabsArePinned {
                        ProfilePillTabs(selectedTab: $selectedProfileTab)
                            .transition(.opacity)
                    }
                }
                .padding(.top, ProfileHeaderCollapseMetrics.topChromePadding)
                .padding(.horizontal, 20)
                .padding(.bottom, tabsArePinned ? 8 : 0)
                .background {
                    ProfileProgressiveBlurBackground(progress: usernameCollapseProgress)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.18), value: tabsArePinned)
                .zIndex(10)
                }
                .coordinateSpace(name: "profileGridOverlay")
                .navigationDestination(item: $zoomDestination) { destination in
                    ProfileMomentZoomDetailDestination(
                        destination: destination,
                        moments: momentsForZoomDestination(destination),
                        namespace: profileZoomNamespace,
                        onRemoveSavedMoment: destination.feedKind == .savedMoments ? { moment in
                            if let momentId = moment.id {
                                savedMomentsViewModel.removeMoment(momentId: momentId)
                            }
                        } : nil
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .profileNavigationSurface(colorScheme: colorScheme)
                .onAppear {
                    heroCoordinator.openZoomDetail = { zoomDestination = $0 }
                    heroCoordinator.clearZoomNavigation = { zoomDestination = nil }
                    heroCoordinator.onEdit = { moment in
                        editingMoment = moment
                    }
                    heroCoordinator.onDelete = { moment in
                        pendingDeleteMoment = moment
                    }
                    heroCoordinator.onArchive = { moment in
                        guard let momentId = moment.id else { return }
                        FirestoreService.shared.archiveMoment(userId: moment.authorId, momentId: momentId) { _ in
                            viewModel.moments.removeAll { $0.id == momentId }
                        }
                    }
                    heroCoordinator.onAdjustPreview = { moment in
                        gridPreviewMoment = moment
                    }
                    heroCoordinator.onPin = { moment, shouldPin, replaceOldest in
                        handleGridPin(moment: moment, shouldPin: shouldPin, replaceOldest: replaceOldest)
                    }
                }
            .sheet(item: $gridPreviewMoment) { moment in
                if let imagePath = moment.previewImageURLString,
                   let url = profileGridPreviewImageURL(from: imagePath) {
                    ProfileGridPreviewEditorView(
                        imageURL: url,
                        initialSettings: moment.gridPreviewSettings,
                        onSave: { settings in
                            saveGridPreview(for: moment, settings: settings)
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func profileGridPreviewImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }

    private func saveGridPreview(for moment: Moment, settings: MomentGridPreviewSettings) {
        guard let momentId = moment.id else { return }
        let previousSettings = moment.gridPreviewSettings

        viewModel.applyGridPreview(momentId: momentId, settings: settings)

        FirestoreService.shared.updateMomentGridPreview(
            userId: moment.authorId,
            momentId: momentId,
            settings: settings
        ) { error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                viewModel.applyGridPreview(momentId: momentId, settings: previousSettings)
            }
        }
    }

    private func openGridMenu(moment: Moment, index: Int) {
        heroCoordinator.openMenu(moment: moment, index: index)
    }

    private func momentsForZoomDestination(_ destination: ProfileMomentZoomDestination) -> [Moment] {
        switch destination.feedKind {
        case .ownMoments:
            return viewModel.moments
        case .taggedMoments:
            return viewModel.taggedMoments
        case .userProfileMoments, .userProfileTagged:
            return []
        case .savedMoments:
            return heroCoordinator.zoomMomentsSnapshot
        }
    }

    private func handleGridPin(moment: Moment, shouldPin: Bool, replaceOldest: Bool) {
        guard let momentId = moment.id else { return }
        let pinnedAt = Date()

        if shouldPin {
            let completion: (Error?) -> Void = { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    if replaceOldest, let oldestId = viewModel.oldestPinnedMomentId(excluding: momentId) {
                        viewModel.applyPinReplacement(
                            unpinningMomentId: oldestId,
                            pinningMomentId: momentId,
                            pinnedAt: pinnedAt
                        )
                    } else {
                        viewModel.applyMomentPinState(
                            momentId: momentId,
                            isPinned: true,
                            pinnedAt: pinnedAt
                        )
                    }
                }
            }

            if replaceOldest {
                FirestoreService.shared.pinMomentReplacingOldestIfNeeded(
                    userId: moment.authorId,
                    momentId: momentId,
                    pinnedMoments: viewModel.moments,
                    completion: completion
                )
            } else {
                FirestoreService.shared.pinMoment(
                    userId: moment.authorId,
                    momentId: momentId,
                    completion: completion
                )
            }
        } else {
            FirestoreService.shared.unpinMoment(userId: moment.authorId, momentId: momentId) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    viewModel.applyMomentPinState(
                        momentId: momentId,
                        isPinned: false,
                        pinnedAt: pinnedAt
                    )
                }
            }
        }
    }

    private func calculateBentoGridHeight(moments: [Moment]) -> CGFloat {
        let descriptors = ProfileBentoTileAssigner.assign(moments: moments)
        return ProfileMomentsGridMetrics.bentoHeight(tileKinds: descriptors.map(\.layoutKind))
    }

    private func calculateTaggedGridHeight(moments: [Moment]) -> CGFloat {
        let descriptors = ProfileBentoTileAssigner.simple(moments: moments)
        return ProfileMomentsGridMetrics.bentoHeight(tileKinds: descriptors.map(\.layoutKind))
    }
}

// MARK: -  Indicador de refresh
struct ModernRefreshIndicator: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: 32, height: 32)
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ProfileColors.accent, ProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .scaleEffect(pulseScale)
            }

                            Text("profile.updating")
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(ProfileColors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ProfileColors.materialBackground)
        .clipShape(Capsule())
        .clipShape(Capsule())
        .shadow(color: ProfileColors.shadowColor, radius: 8, x: 0, y: 4)
        .onAppear {
            guard !MotionPolicy.reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
        .onDisappear {
            rotationAngle = 0
            pulseScale = 1.0
        }
    }
}
