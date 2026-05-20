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
                    .liquidGlass(in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.055 : 0.035))
                    .frame(width: segmentWidth(for: proxy.size.width), height: 34)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 7, x: 0, y: 2)
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
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13, weight: .medium))

                                Text(tab.localizedTitle)
                                    .font(.custom("Poppins-Medium", size: 13))
                            }
                            .foregroundColor(labelColor(for: index, width: proxy.size.width))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: visualIndex(for: proxy.size.width))

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
        .frame(height: 42)
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
        visualIndex(for: width) == index ? ProfileColors.textPrimary : ProfileColors.textSecondary
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
    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var newBio: String = ""
    @State private var showingUserList: UserListType?
    @State private var errorMessage: String?
    @State private var showStoryViewer: Bool = false
    @State private var selectedStoryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var showMomentDetail = false
    @State private var selectedMomentIndex = 0
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var showingThemeSelector = false // ✅ NUEVO: Estado para selector de tema
    // ✅ NUEVO: Estado para código QR
    @State private var isShowingQRCode = false
    @State private var selectedProfileTab: ProfileTabType = .moments  // ✅ NUEVO: Tab selector
    @State private var showProfileImageFullscreen = false // ✅ NUEVO: Estado para ver foto grande
    @State private var selectedExternalProfileUserId: String? = nil
    @State private var showExternalProfile = false
    @State private var editingMoment: Moment? = nil
    @State private var pendingDeleteMoment: Moment? = nil


    enum UserListType: Identifiable {
        case visits
        case admirers
        case connections
        case mutualConnections

        var id: String {
            switch self {
            case .visits: return "visits"
            case .admirers: return "admirers"
            case .connections: return "connections"
            case .mutualConnections: return "mutualConnections"
            }
        }

        var title: String {
            switch self {
            case .visits: return NSLocalizedString("profile.userList.visits", comment: "Visits")
            case .admirers: return NSLocalizedString("profile.ui.followers", comment: "Followers")
            case .connections: return NSLocalizedString("profile.ui.following", comment: "Following")
            case .mutualConnections: return NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom

            NavigationView {
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
                        safeAreaTop: safeAreaTop,
                        safeAreaBottom: safeAreaBottom,
                        isShowingSettings: $isShowingSettings,
                        isShowingEditProfile: $isShowingEditProfile,
                        newBio: $newBio,
                        showingUserList: $showingUserList,
                        showStoryViewer: $showStoryViewer,
                        selectedStoryIndex: $selectedStoryIndex,
                        selectedPhoto: $selectedPhoto,
                        scrollOffset: $scrollOffset,
                        showMomentDetail: $showMomentDetail,
                        selectedMomentIndex: $selectedMomentIndex,
                        showingThemeSelector: $showingThemeSelector,
                        selectedProfileTab: $selectedProfileTab,  // ✅ NUEVO
                        showingQRCode: $isShowingQRCode, // ✅ NUEVO: Binding
                        showProfileImageFullscreen: $showProfileImageFullscreen, // ✅ NUEVO
                        editingMoment: $editingMoment,
                        pendingDeleteMoment: $pendingDeleteMoment
                    )

                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .all)
                .fullScreenCover(isPresented: $isShowingSettings) {
                    SettingsView()
                }
                .fullScreenCover(isPresented: $isShowingEditProfile) {
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
                }
                .sheet(isPresented: $showingThemeSelector) {
                    if let currentUser = authService.currentUser {
                        ProfileThemeSelector(user: currentUser)
                    }
                }
                .sheet(isPresented: $isShowingQRCode) {
                    QRCodeView()
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

                .fullScreenCover(isPresented: $showMomentDetail) {
                    ModernMomentDetailView(
                        moments: selectedProfileTab == .tagged ? viewModel.taggedMoments : viewModel.moments,
                        initialIndex: selectedMomentIndex,
                        topContentInset: selectedProfileTab == .tagged ? 64 : 24,
                        onDismiss: {
                            showMomentDetail = false
                        }
                    )
                }
                .sheet(item: $showingUserList) { listType in
                    switch listType {
                    case .visits:
                        VisitsView()
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                            .interactiveDismissDisabled(false)
                            .presentationBackground(.clear)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                    case .admirers, .connections, .mutualConnections:
                        UserListView(
                            title: listType.title,
                            users: usersForList(type: listType),
                            visitTimestamps: [:],
                            viewModel: viewModel,
                            onDismiss: { showingUserList = nil },
                            rowAction: rowAction(for: listType),
                            onUserTap: { user in
                                openUserProfileFromList(userId: user.id)
                            }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled(false)
                        .presentationBackground(.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .fullScreenCover(isPresented: $showExternalProfile, onDismiss: {
                    selectedExternalProfileUserId = nil
                }) {
                    if let userId = selectedExternalProfileUserId {
                        UserProfileView(userId: userId)
                    }
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
                .animation(.easeInOut(duration: 0.3), value: showingUserList)
                .onChange(of: selectedTab) { newTab in
                    if newTab == 4 {
                        isShowingSettings = false
                        isShowingEditProfile = false
                    }
                }
                .onAppear {
                    Auth.auth().addStateDidChangeListener { auth, user in
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
                    showingUserList = .visits
                }
            }
        }
    }

    private func usersForList(type: UserListType) -> [AppUser] {
        switch type {
        case .visits: return viewModel.visits
        case .admirers: return viewModel.admirers
        case .connections: return viewModel.connections
        case .mutualConnections: return viewModel.mutualConnections
        }
    }

    private func rowAction(for type: UserListType) -> UserListRowAction {
        switch type {
        case .visits, .admirers:
            return .follow
        case .connections, .mutualConnections:
            return .unfollow
        }
    }

    private func openUserProfileFromList(userId: String) {
        showingUserList = nil
        selectedExternalProfileUserId = userId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showExternalProfile = true
        }
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

    // Función auxiliar para calcular altura del grid
    private func calculateGridHeight(itemCount: Int) -> CGFloat {
        let columns = 3
        let rows = ceil(Double(itemCount) / Double(columns))
        let spacing: CGFloat = 4
        let itemWidth = (UIScreen.main.bounds.width - 16 - (spacing * 2)) / 3
        return CGFloat(rows) * itemWidth + (CGFloat(rows - 1) * spacing)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(selectedTab: .constant(4))
            .environmentObject(AuthService())
    }
}
