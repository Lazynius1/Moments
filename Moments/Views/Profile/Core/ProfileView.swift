import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore // ✅ NUEVO: Para fetchTaggedMoments
import WidgetKit
import FirebaseStorage
import Kingfisher
import CoreMotion
import AVFoundation

struct ProfileColors {
    static var background: Color {
        Color(UIColor.systemBackground)
    }

    static var secondaryBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }

    static var cardBackground: Color {
        Color(UIColor.systemBackground).opacity(0.8)
    }

    static var materialBackground: Color {
        Color(UIColor.systemBackground).opacity(0.95)
    }

    static var textPrimary: Color {
        Color(UIColor.label)
    }

    static var textSecondary: Color {
        Color(UIColor.secondaryLabel)
    }

    static var textTertiary: Color {
        Color(UIColor.tertiaryLabel)
    }

    static var borderColor: Color {
        Color(UIColor.separator)
    }

    static var shadowColor: Color {
        Color(UIColor.label).opacity(0.1)
    }

    // Colores específicos que se mantienen
    static let accent = Color(hex: "007AFF")
    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
}

// MARK: - ✅ NUEVO: Enum para tabs del perfil
enum ProfileTabType: String, CaseIterable {
    case moments = "Moments"
    case saved = "Guardados"
    case tagged = "Etiquetas" // ✅ NUEVO

    var icon: String {
        switch self {
        case .moments: return "square.grid.2x2"
        case .saved: return "bookmark"
        case .tagged: return "person.crop.rectangle" // ✅ NUEVO
        }
    }

    var localizedTitle: String {
        switch self {
        case .moments: return NSLocalizedString("profile.tab.moments", comment: "Moments tab")
        case .saved: return NSLocalizedString("profile.tab.saved", comment: "Saved tab")
        case .tagged: return NSLocalizedString("profile.tab.tagged", comment: "Tagged tab") // ✅ NUEVO
        }
    }
}

struct ProfileMomentDetailRoute: Identifiable, Equatable {
    let id = UUID()
    let moments: [Moment]
    let initialIndex: Int
    let initialMomentId: String?
    var entryKind: ProfileMomentDetailEntryKind = .direct

    static func == (lhs: ProfileMomentDetailRoute, rhs: ProfileMomentDetailRoute) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ✅ NUEVO: Pill Tabs Component
struct ProfilePillTabs: View {
    @Binding var selectedTab: ProfileTabType
    @Environment(\.colorScheme) var colorScheme
    @State private var transientOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.clear)
                    .momentsChromeGlass(
                        in: Capsule(),
                        interactive: false,
                        tint: ProfilePillTabPalette.trackTint(for: colorScheme)
                    )
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.clear)
                    .frame(width: segmentWidth(for: proxy.size.width), height: 31)
                    .momentsChromeGlass(
                        in: Capsule(),
                        interactive: true,
                        tint: ProfilePillTabPalette.selectedThumbTint(for: colorScheme)
                    )
                    .shadow(color: ProfilePillTabPalette.selectedShadowColor(for: colorScheme), radius: 7, x: 0, y: 2)
                    .offset(x: pillOffset(for: proxy.size.width))

                HStack(spacing: 0) {
                    ForEach(Array(ProfileTabType.allCases.enumerated()), id: \.element) { index, tab in
                        Button(action: {
                            if tab != selectedTab {
                                HapticManager.shared.selection()
                            }
                            withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
                                selectedTab = tab
                                transientOffset = 0
                            }
                        }) {
                            HStack(spacing: 6) {
                                if tab == .saved {
                                    AttachmentIconView(icon: .bookmark, preset: .profilePillTab)
                                } else if tab == .tagged {
                                    AttachmentIconView(icon: .tagged, preset: .profilePillTab)
                                } else {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 12, weight: labelWeight(for: index, width: proxy.size.width)))
                                }

                                Text(tab.localizedTitle)
                                    .font(.system(size: legacyPoppinsSize(12), weight: labelWeight(for: index, width: proxy.size.width)))
                            }
                            .foregroundColor(labelColor(for: index, width: proxy.size.width))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
                .animation(MotionPolicy.animation(.smooth(duration: 0.18, extraBounce: 0.01), value: visualIndex(for: proxy.size.width)), value: visualIndex(for: proxy.size.width))

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    transientOffset = constrainedTranslation(value.translation.width, width: proxy.size.width)
                                }
                            }
                            .onEnded { value in
                                settleSelection(translation: value.translation.width, locationX: value.location.x, width: proxy.size.width)
                            }
                    )
            }
        }
        .frame(height: 38)
    }

    private var currentIndex: Int {
        ProfileTabType.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private func segmentWidth(for totalWidth: CGFloat) -> CGFloat {
        let innerWidth = totalWidth - 6
        return innerWidth / CGFloat(ProfileTabType.allCases.count)
    }

    private func baseOffset(for totalWidth: CGFloat) -> CGFloat {
        let segmentWidth = segmentWidth(for: totalWidth)
        let start = -((CGFloat(ProfileTabType.allCases.count - 1) * segmentWidth) / 2)
        return start + (CGFloat(currentIndex) * segmentWidth)
    }

    private func pillOffset(for totalWidth: CGFloat) -> CGFloat {
        baseOffset(for: totalWidth) + transientOffset
    }

    private func visualIndex(for totalWidth: CGFloat) -> Int {
        let width = segmentWidth(for: totalWidth)
        let start = -((CGFloat(ProfileTabType.allCases.count - 1) * width) / 2)
        let raw = ((pillOffset(for: totalWidth) - start) / width).rounded()
        return min(max(Int(raw), 0), ProfileTabType.allCases.count - 1)
    }

    private func labelColor(for index: Int, width: CGFloat) -> Color {
        if visualIndex(for: width) == index {
            return ProfilePillTabPalette.selectedLabelColor(for: colorScheme)
        }
        return ProfilePillTabPalette.unselectedLabelColor(for: colorScheme)
    }

    private func labelWeight(for index: Int, width: CGFloat) -> Font.Weight {
        visualIndex(for: width) == index ? .semibold : .medium
    }

    private func constrainedTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let segment = segmentWidth(for: width)
        let minOffset = -((CGFloat(ProfileTabType.allCases.count - 1) * segment) / 2)
        let maxOffset = ((CGFloat(ProfileTabType.allCases.count - 1) * segment) / 2)
        let proposed = baseOffset(for: width) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - baseOffset(for: width)
    }

    private func settleSelection(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let segment = segmentWidth(for: width)
        let proposedOffset = baseOffset(for: width) + translation
        let start = -((CGFloat(ProfileTabType.allCases.count - 1) * segment) / 2)

        // Find the precise fractional index based on the dragged pill's position
        let fractionalIndex = (proposedOffset - start) / segment

        let targetIndex: Int
        let threshold = min(segment * 0.28, 36)

        // If the user dragged enough to show intent but didn't cross the half-way mark
        if abs(translation) > threshold && abs(translation) < segment * 0.5 {
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentIndex + direction, 0), ProfileTabType.allCases.count - 1)
        } else if abs(translation) < 5 {
            // Es un tap directo, no un arrastre
            targetIndex = min(max(Int(locationX / segment), 0), ProfileTabType.allCases.count - 1)
        } else {
            // Resolve to the closest index based on the actual final position
            targetIndex = min(max(Int(fractionalIndex.rounded()), 0), ProfileTabType.allCases.count - 1)
        }

        let targetTab = ProfileTabType.allCases[targetIndex]
        if targetTab != selectedTab {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedTab = targetTab
            transientOffset = 0
        }
    }
}

// ✅ NUEVO: Separated Floating Tabs Component para el perfil propio
struct ProfileFloatingTabBar: View {
    @Binding var selectedTab: ProfileTabType
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProfileTabType.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button(action: {
                    if tab != selectedTab {
                        HapticManager.shared.selection()
                    }
                    MotionPolicy.withOptionalAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        if tab == .saved {
                            AttachmentIconView(icon: .bookmark, preset: .profilePillTab)
                        } else if tab == .tagged {
                            AttachmentIconView(icon: .tagged, preset: .profilePillTab)
                        } else {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        }

                        Text(tab.localizedTitle)
                            .font(.system(size: legacyPoppinsSize(12), weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .momentsChromeGlass(
                        in: Capsule(),
                        interactive: true
                    )
                }
                .buttonStyle(.plain)
                .environment(\.colorScheme, isSelected ? (colorScheme == .dark ? .light : .dark) : colorScheme)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = ProfileViewModel()
    @Binding var selectedTab: Int
    @StateObject private var storyViewModel = StoryViewModel()
    @StateObject private var incognitoModeService = IncognitoModeService.shared
    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var newBio: String = ""
    @State private var socialConnectionsRoute: SocialConnectionsRoute?
    @State private var errorMessage: String?
    @State private var showStoryViewer: Bool = false
    @State private var selectedStoryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @StateObject private var heroCoordinator = ProfileGridHeroTransitionCoordinator()
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var showingThemeSelector = false // ✅ NUEVO: Estado para selector de tema
    // ✅ NUEVO: Estado para código QR
    @State private var isShowingQRCode = false
    @State private var selectedProfileTab: ProfileTabType = .moments  // ✅ NUEVO: Tab selector
    @State private var showProfileImageFullscreen = false // ✅ NUEVO: Estado para ver foto grande
    @State private var isShowingIncognito = false
    @Namespace private var profileZoomNamespace
    @State private var editingMoment: Moment? = nil
    @State private var pendingDeleteMoment: Moment? = nil
    enum UserListType: Identifiable {
        case visits
        case followers
        case following
        case mutuals

        var id: String {
            switch self {
            case .visits: return "visits"
            case .followers: return "followers"
            case .following: return "following"
            case .mutuals: return "mutuals"
            }
        }

        var title: String {
            switch self {
            case .visits: return NSLocalizedString("profile.userList.visits", comment: "Visits")
            case .followers: return NSLocalizedString("profile.ui.followers", comment: "Followers")
            case .following: return NSLocalizedString("profile.ui.following", comment: "Following")
            case .mutuals: return NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom

            ZStack {
                ZStack {
                    // Fondo dinámico mejorado con efectos (FULLSCREEN)
                    EnhancedProfileBackground(
                        profileImagePath: viewModel.userProfile?.profileImagePath,
                        scrollOffset: scrollOffset,
                        profileTheme: viewModel.userProfile?.currentProfileTheme ?? .default,
                        user: viewModel.userProfile
                    )
                    .ignoresSafeArea(.all, edges: .all)

                    ModernProfileContentView(
                        viewModel: viewModel,
                        storyViewModel: storyViewModel,
                        profileZoomNamespace: profileZoomNamespace,
                        safeAreaTop: safeAreaTop,
                        safeAreaBottom: safeAreaBottom,
                        isShowingSettings: $isShowingSettings,
                        isShowingEditProfile: $isShowingEditProfile,
                        newBio: $newBio,
                        socialConnectionsRoute: $socialConnectionsRoute,
                        showStoryViewer: $showStoryViewer,
                        selectedStoryIndex: $selectedStoryIndex,
                        selectedPhoto: $selectedPhoto,
                        scrollOffset: $scrollOffset,
                        showingThemeSelector: $showingThemeSelector,
                        selectedProfileTab: $selectedProfileTab,  // ✅ NUEVO
                        showingQRCode: $isShowingQRCode, // ✅ NUEVO: Binding
                        showProfileImageFullscreen: $showProfileImageFullscreen, // ✅ NUEVO
                        isShowingIncognito: $isShowingIncognito,
                        isIncognitoActive: incognitoModeService.isActive,
                        editingMoment: $editingMoment,
                        pendingDeleteMoment: $pendingDeleteMoment
                    )
                    .environmentObject(heroCoordinator)
                }
                .ignoresSafeArea(.all, edges: .all)
                .navigationDestination(isPresented: $isShowingSettings) {
                    SettingsView()
                        .navigationTransition(.zoom(sourceID: "settings-view", in: profileZoomNamespace))
                }
                .navigationDestination(isPresented: $isShowingEditProfile) {
                    ModernEditProfileView(
                        selectedPhoto: $selectedPhoto,
                        newBio: $newBio,
                        onSave: { photo, bio, website, interests in
                            if let photo = photo {
                                viewModel.uploadProfilePicture(item: photo)
                            }
                            viewModel.updateProfileDetails(bio: bio, websiteUrl: website, interests: interests)
                        }
                    )
                    .navigationTransition(.zoom(sourceID: "edit-profile-view", in: profileZoomNamespace))
                }
                .sheet(isPresented: $showingThemeSelector) {
                    if let currentUser = authService.currentUser {
                        ProfileThemeSelector(user: currentUser)
                    }
                }
                .sheet(isPresented: $isShowingQRCode) {
                    QRCodeView()
                }
                .sheet(isPresented: $isShowingIncognito) {
                    IncognitoModeSheet(service: incognitoModeService)
                }
                .sheet(isPresented: $showProfileImageFullscreen) {
                    if let profileImagePath = viewModel.userProfile?.profileImagePath {
                        ProfileImageViewer(
                            profileImagePath: profileImagePath,
                            username: viewModel.userProfile?.username ?? "Yo"
                        )
                        .presentationDetents([.fraction(0.99)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(.clear)
                    }
                }
                .sheet(item: $editingMoment) { moment in
                    EditMomentView(
                        moment: moment,
                        onSave: { payload in
                            updateMoment(payload: payload, for: moment)
                        }
                    )
                }

                .navigationDestination(item: $socialConnectionsRoute) { route in
                    SocialConnectionsScreen(
                        route: route,
                        username: viewModel.userProfile?.username ?? "",
                        availableTabs: SocialConnectionTab.ownProfileTabs,
                        includesVisits: true,
                        isOwnProfile: true,
                        currentUser: viewModel.userProfile,
                        inCommonUsers: [],
                        followers: viewModel.followers,
                        following: viewModel.following,
                        mutuals: viewModel.mutuals,
                        suggestedUsers: [],
                        viewerInterests: viewModel.userProfile?.interests ?? [],
                        visitTimestamps: viewModel.visitTimestamps,
                        listViewModel: viewModel,
                        profileZoomNamespace: profileZoomNamespace
                    )
                }
                .alert(
                    NSLocalizedString("contextMenu.delete.title", comment: "Delete moment alert title"),
                    isPresented: Binding(
                        get: { pendingDeleteMoment != nil },
                        set: { if !$0 { pendingDeleteMoment = nil } }
                    ),
                    presenting: pendingDeleteMoment
                ) { moment in
                    Button(NSLocalizedString("contextMenu.delete.cancel", comment: "Cancel button"), role: .cancel) {
                        pendingDeleteMoment = nil
                    }
                    Button(NSLocalizedString("contextMenu.delete.confirm", comment: "Delete button"), role: .destructive) {
                        deleteMoment(moment)
                    }
                } message: { _ in
                    Text(NSLocalizedString("contextMenu.delete.message", comment: "Delete moment confirmation message"))
                }
                .fullScreenCover(isPresented: $showStoryViewer) {
                    if let userId = Auth.auth().currentUser?.uid,
                       let stories = storyViewModel.stories[userId], !stories.isEmpty {
                        let safeStoryIndex = min(max(selectedStoryIndex, 0), stories.count - 1)

                        StoryViewerScreen(
                            story: stories[safeStoryIndex],
                            storyCount: stories.count,
                            storyIndex: safeStoryIndex,
                            screenSize: UIScreen.main.bounds.size,
                            storyViewModel: storyViewModel,
                            // ✅ AGREGAR: Pasar los bindings
                            showingReportSheet: $showingReportSheet,
                            showingBlockConfirmation: $showingBlockConfirmation,
                            onReportStory: {
                                // Para historias propias, no aplica reporte
                            },
                            onBlockUser: {
                                // Para historias propias, no aplica bloqueo
                            },
                            onNext: {
                                if safeStoryIndex + 1 < stories.count {
                                    selectedStoryIndex = safeStoryIndex + 1
                                } else {
                                    showStoryViewer = false
                                }
                            },
                            onStoryDeleted: {
                                let liveStoryCount = storyViewModel.stories[userId]?.count ?? 0
                                if liveStoryCount > 0 {
                                    selectedStoryIndex = min(safeStoryIndex, liveStoryCount - 1)
                                } else {
                                    showStoryViewer = false
                                }
                            },
                            onPrevious: {
                                if safeStoryIndex > 0 {
                                    selectedStoryIndex = safeStoryIndex - 1
                                }
                            },
                            onClose: { showStoryViewer = false },
                            onProfileTap: {
                                // Para historias propias, no aplica navegación de perfil
                            }
                        )
                    }
                }
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: socialConnectionsRoute), value: socialConnectionsRoute)
                .onChange(of: selectedTab) { _, newTab in
                    if newTab == 4 {
                        isShowingSettings = false
                        isShowingEditProfile = false
                    } else {
                        // ✅ Resetear detalle y menús al salir del tab de perfil
                        heroCoordinator.dismissMenu()
                        heroCoordinator.dismissDetail()
                    }
                }
                .onAppear {
                    incognitoModeService.loadState()
                    _ = Auth.auth().addStateDidChangeListener { _, user in
                        if let userId = user?.uid {
                            viewModel.fetchProfile(userId: userId)
                            storyViewModel.fetchStories(for: userId, includeConnections: false)
                            storyViewModel.checkActiveStories(userId: userId)
                        } else {
                            viewModel.isLoading = false
                            viewModel.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowProfileVisits"))) { _ in
                    socialConnectionsRoute = SocialConnectionsRoute(initialTab: .visits)
                }
                .onDisappear {
                    // Reset profile transition and detail states immediately when switching tabs or leaving the screen
                    heroCoordinator.resetToIdle()
                }

            ProfileGridHeroDetailLayer(
                coordinator: heroCoordinator,
                containerSize: geometry.size,
                safeAreaInsets: EdgeInsets(
                    top: geometry.safeAreaInsets.top,
                    leading: geometry.safeAreaInsets.leading,
                    bottom: geometry.safeAreaInsets.bottom,
                    trailing: geometry.safeAreaInsets.trailing
                ),
                moments: selectedProfileTab == .moments ? viewModel.moments : (selectedProfileTab == .tagged ? viewModel.taggedMoments : []),
                zoomFeedKind: selectedProfileTab == .tagged ? .taggedMoments : .ownMoments
            )
            .zIndex(100)
            }
        }
        .environmentObject(heroCoordinator)
        .environment(\.profileGridHeroTransitionCoordinator, heroCoordinator)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
    }

    private func updateMoment(payload: EditMomentPayload, for moment: Moment) {
        guard let momentId = moment.id else { return }

        FirestoreService.shared.updateMomentDetails(
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
                editingMoment = nil
                viewModel.refreshProfile()
            }
        }
    }

    private func deleteMoment(_ moment: Moment) {
        guard let momentId = moment.id else { return }

        FirestoreService.shared.deleteMoment(userId: moment.authorId, momentId: momentId) { _ in
            DispatchQueue.main.async {
                viewModel.moments.removeAll { $0.id == momentId }
                LocalPersistenceService.shared.deleteMoment(momentId: momentId)
                pendingDeleteMoment = nil
            }
        }
    }

}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(selectedTab: .constant(4))
            .environmentObject(AuthService())
    }
}
