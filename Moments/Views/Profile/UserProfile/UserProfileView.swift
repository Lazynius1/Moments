import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// ✅ USAR: Sistema de colores adaptativos existente (definido en FeedView.swift)

private struct UserProfileStoryRoute: Identifiable {
    let userId: String
    var id: String { userId }
}

struct UserProfileColors {
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

// ✅ NUEVO: Enum para tabs de UserProfile (sin Guardados)
enum UserProfileTabType: String, CaseIterable {
    case moments = "Moments"
    case tagged = "Etiquetas"

    var icon: String {
        switch self {
        case .moments: return "square.grid.2x2"
        case .tagged: return "person.crop.rectangle"
        }
    }

    var localizedTitle: String {
        switch self {
        case .moments: return NSLocalizedString("profile.tab.moments", comment: "Moments tab")
        case .tagged: return NSLocalizedString("profile.tab.tagged", comment: "Tagged tab")
        }
    }
}

// ✅ NUEVO: Pills Tabs Component para UserProfile
struct UserProfilePillTabs: View {
    @Binding var selectedTab: UserProfileTabType
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
                    ForEach(Array(UserProfileTabType.allCases.enumerated()), id: \.element) { index, tab in
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
                                if tab == .tagged {
                                    AttachmentIconView(icon: .tagged, preset: .profilePillTab)
                                } else {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 12, weight: labelWeight(for: index, width: proxy.size.width)))
                                }

                                Text(tab.localizedTitle)
                                    .font(.custom(labelFontName(for: index, width: proxy.size.width), size: 12))
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
        .frame(height: 38)
    }

    private var currentIndex: Int {
        UserProfileTabType.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private func segmentWidth(for totalWidth: CGFloat) -> CGFloat {
        let innerWidth = totalWidth - 6
        return innerWidth / CGFloat(UserProfileTabType.allCases.count)
    }

    private func baseOffset(for totalWidth: CGFloat) -> CGFloat {
        let segmentWidth = segmentWidth(for: totalWidth)
        let start = -((CGFloat(UserProfileTabType.allCases.count - 1) * segmentWidth) / 2)
        return start + (CGFloat(currentIndex) * segmentWidth)
    }

    private func pillOffset(for totalWidth: CGFloat) -> CGFloat {
        baseOffset(for: totalWidth) + transientOffset
    }

    private func visualIndex(for totalWidth: CGFloat) -> Int {
        let width = segmentWidth(for: totalWidth)
        let start = -((CGFloat(UserProfileTabType.allCases.count - 1) * width) / 2)
        let raw = ((pillOffset(for: totalWidth) - start) / width).rounded()
        return min(max(Int(raw), 0), UserProfileTabType.allCases.count - 1)
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

    private func labelFontName(for index: Int, width: CGFloat) -> String {
        visualIndex(for: width) == index ? "Poppins-SemiBold" : "Poppins-Medium"
    }

    private func constrainedTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let segment = segmentWidth(for: width)
        let minOffset = -((CGFloat(UserProfileTabType.allCases.count - 1) * segment) / 2)
        let maxOffset = ((CGFloat(UserProfileTabType.allCases.count - 1) * segment) / 2)
        let proposed = baseOffset(for: width) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - baseOffset(for: width)
    }

    private func settleSelection(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let segment = segmentWidth(for: width)
        let proposedOffset = baseOffset(for: width) + translation
        let start = -((CGFloat(UserProfileTabType.allCases.count - 1) * segment) / 2)

        // Find the precise fractional index based on the dragged pill's position
        let fractionalIndex = (proposedOffset - start) / segment

        let targetIndex: Int
        let threshold = min(segment * 0.28, 36)

        // If the user dragged enough to show intent but didn't cross the half-way mark
        if abs(translation) > threshold && abs(translation) < segment * 0.5 {
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentIndex + direction, 0), UserProfileTabType.allCases.count - 1)
        } else if abs(translation) < 5 {
            // Es un tap directo, no un arrastre
            targetIndex = min(max(Int(locationX / segment), 0), UserProfileTabType.allCases.count - 1)
        } else {
            // Resolve to the closest index based on the actual final position
            targetIndex = min(max(Int(fractionalIndex.rounded()), 0), UserProfileTabType.allCases.count - 1)
        }

        let targetTab = UserProfileTabType.allCases[targetIndex]
        if targetTab != selectedTab {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedTab = targetTab
            transientOffset = 0
        }
    }
}

struct UserProfileView: View {
    @StateObject private var viewModel: UserProfileViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingUserList: UserProfileView.UserListType?
    private let userId: String
    @StateObject private var messagingViewModel = MessagingViewModel()
    @StateObject private var messageRequestService = MessageRequestService()
    @State private var navigateToChat: Bool = false
    @State private var targetConversation: Conversation?
    @ObservedObject private var chatAccessCoordinator = ChatAccessCoordinator.shared
    @State private var showingMessageRequestAlert = false
    @State private var messageRequestText = ""
    @State private var messageRequestError: String?
    @State private var showingSuccessMessage = false
    @State private var showingUnfollowConfirmation = false
    @State private var showingRelationshipSheet = false

    @State private var storyRoute: UserProfileStoryRoute?
    @State private var scrollOffset: CGFloat = 0
    @StateObject private var heroCoordinator = ProfileGridHeroTransitionCoordinator()
    @State private var hasRegisteredVisit = false
    @State private var selectedTab: UserProfileTabType = .moments // ✅ NUEVO: Tab seleccionado
    @State private var selectedNestedProfileUserId: String? = nil
    @State private var showNestedProfile = false
    @Namespace private var profileZoomNamespace

    // ✅ NUEVOS: Estados para navegación al explorer
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag: Bool = false

    // ✅ NUEVO: Estado para mostrar imagen de perfil ampliada
    @State private var showProfileImageFullscreen: Bool = false

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId))
    }

    enum UserListType: Identifiable {
        case admirers
        case connections
        case mutualConnections

        var id: String {
            switch self {
            case .admirers: return "admirers"
            case .connections: return "connections"
            case .mutualConnections: return "mutualConnections"
            }
        }

        var title: String {
            switch self {
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

            ZStack {
                EnhancedProfileBackground(
                    profileImagePath: viewModel.userProfile?.profileImagePath,
                    scrollOffset: scrollOffset,
                    profileTheme: viewModel.userProfile?.currentProfileTheme ?? .default,
                    user: viewModel.userProfile
                )
                .ignoresSafeArea(.all, edges: .all)

                contentView(safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom)

                ProfileGridHeroDetailLayer(
                    coordinator: heroCoordinator,
                    containerSize: geometry.size,
                    safeAreaInsets: EdgeInsets(
                        top: geometry.safeAreaInsets.top,
                        leading: geometry.safeAreaInsets.leading,
                        bottom: geometry.safeAreaInsets.bottom,
                        trailing: geometry.safeAreaInsets.trailing
                    ),
                    moments: selectedTab == .moments ? viewModel.moments : viewModel.taggedMoments,
                    zoomFeedKind: selectedTab == .tagged ? .userProfileTagged : .userProfileMoments
                )
                .zIndex(100)
            }
        }
        .environmentObject(heroCoordinator)
        .environment(\.profileGridHeroTransitionCoordinator, heroCoordinator)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $showingUserList) { listType in
            UserListView(
                title: listType.title,
                users: usersForListType(listType),
                visitTimestamps: [:],
                viewModel: viewModel,
                onDismiss: { showingUserList = nil },
                rowAction: rowAction(for: listType),
                onUserTap: { user in
                    openNestedUserProfile(userId: user.id)
                },
                profileZoomNamespace: profileZoomNamespace
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            .presentationBackground(.clear)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .navigationDestination(isPresented: $showNestedProfile) {
            if let userId = selectedNestedProfileUserId {
                UserProfileView(userId: userId)
                    .userProfileZoomDestination(userId: userId, namespace: profileZoomNamespace)
            }
        }
        .onChange(of: showNestedProfile) { _, isShowing in
            if !isShowing {
                selectedNestedProfileUserId = nil
            }
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .sheet(isPresented: $showProfileImageFullscreen) {
            ProfileImageViewer(
                profileImagePath: viewModel.userProfile?.profileImagePath,
                username: viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User")
            )
            .presentationDetents([.fraction(0.99)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let conversation = targetConversation {
                Group {
                    if chatAccessCoordinator.accessState == .available {
                        GlassmorphicChatView(
                            conversation: conversation,
                            session: ChatSessionEngine.shared.session(for: conversation)
                        )
                    } else {
                        ChatRecoveryGateView(onCancel: {
                            navigateToChat = false
                        }) {
                            GlassmorphicChatView(
                                conversation: conversation,
                                session: ChatSessionEngine.shared.session(for: conversation)
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingMessageRequestAlert) {
            MessageRequestModalView(
                messageText: $messageRequestText,
                errorMessage: $messageRequestError,
                showingSuccessMessage: $showingSuccessMessage,
                onSend: sendMessageRequest,
                onDismiss: {
                    showingMessageRequestAlert = false
                    messageRequestText = ""
                    messageRequestError = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            .presentationBackground(.clear)
        }
        .alert(NSLocalizedString("messageRequestModal.success.title", comment: "Success title"), isPresented: $showingSuccessMessage) {
            Button(NSLocalizedString("common.ok", comment: "OK button")) {
                showingSuccessMessage = false
            }
        } message: {
            Text(NSLocalizedString("messageRequestModal.success.message", comment: "Success message"))
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
        }
        .animation(.easeInOut(duration: 0.3), value: showingUserList)
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: "Unfollow confirmation title"),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: "Unfollow action"), role: .destructive) {
                viewModel.unfollowUser(userId: userId)
                viewModel.refreshProfile()
            }

            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(unfollowConfirmationMessage)
        }
        .sheet(isPresented: $showingRelationshipSheet) {
            UserRelationshipManagementSheet(
                username: viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"),
                profileImagePath: viewModel.userProfile?.profileImagePath,
                userId: userId,
                isBestFriend: viewModel.isInBestFriends,
                isMuted: viewModel.isMutedByCurrentUser,
                isMutual: viewModel.isMutualRelationship,
                customListCount: viewModel.customListMembershipCount,
                customLists: viewModel.customListsContainingProfile,
                isUpdatingBestFriend: viewModel.isUpdatingBestFriend,
                isUpdatingMute: viewModel.isUpdatingMute,
                isUpdatingLists: viewModel.isUpdatingLists,
                onToggleBestFriend: {
                    viewModel.toggleBestFriend()
                },
                onToggleMute: {
                    viewModel.toggleMute()
                },
                onRemoveFromList: { list in
                    viewModel.removeFromCustomList(list)
                },
                onUnfollow: {
                    showingRelationshipSheet = false
                    showingUnfollowConfirmation = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let currentUserId = Auth.auth().currentUser?.uid {
                // ✅ Todo dentro del if let currentUserId

                // Registrar visita
                if !hasRegisteredVisit {
                    hasRegisteredVisit = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        viewModel.registerVisit()
                    }
                }

                // Cargar datos del perfil
                viewModel.fetchProfile()
                viewModel.checkFollowButtonState()

                // Cargar conversaciones
                messagingViewModel.fetchConversations(for: currentUserId)

            } else {
                viewModel.fetchProfile()
                viewModel.checkFollowButtonState()
            }
        }
        .onDisappear {
            // Reset profile transition and detail states immediately when leaving this user's profile view
            heroCoordinator.resetToIdle()
        }
    }

    // ✅ NUEVA: Función para enviar solicitud de mensaje
    private func sendMessageRequest() {
        guard Auth.auth().currentUser?.uid != nil,
              let targetUser = viewModel.userProfile else { return }

        let message = messageRequestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            messageRequestError = NSLocalizedString("messageRequestModal.error.empty", comment: "Empty message error")
            return
        }

        messageRequestService.sendMessageRequest(
            to: targetUser.id,
            message: message
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showingMessageRequestAlert = false
                    messageRequestText = ""
                    messageRequestError = nil
                    showingSuccessMessage = true
                case .failure(let error):
                    messageRequestError = String(format: NSLocalizedString("messageRequestModal.error.generic", comment: "Generic error"), error.localizedDescription)
                }
            }
        }
    }

    private func contentView(safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> some View {
        Group {
            if viewModel.isLoading {
                UserModernLoadingView()
            } else if viewModel.isBlockedByCurrentUser {
                UserModernBlockedByMeProfileView(
                    userProfile: viewModel.userProfile,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    onUnblock: {
                        viewModel.unblockUser(userId: userId)
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            } else if viewModel.isProfileUnavailable {
                UserModernUnavailableProfileView(
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    onDismiss: {
                        dismiss()
                    }
                )
            } else if !viewModel.canViewContent {
                UserModernPrivateProfileView(
                    userProfile: viewModel.userProfile,
                    userId: userId,
                    messagingViewModel: messagingViewModel,
                    viewModel: viewModel,
                    followButtonState: viewModel.followButtonState,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    navigateToChat: $navigateToChat,
                    targetConversation: $targetConversation,
                    showingMessageRequestAlert: $showingMessageRequestAlert,
                    messageRequestText: $messageRequestText,
                    messageRequestError: $messageRequestError,
                    showingSuccessMessage: $showingSuccessMessage,
                    onFollowAction: {
                        handleFollowAction()
                    },
                    onDismiss: {
                        dismiss()
                    },
                    onOpenStories: {
                        storyRoute = UserProfileStoryRoute(userId: userId)
                    }
                )
            } else {
                // ✅ CORREGIDO: Vista pública con parámetros correctos
                UserModernPublicProfileView(
                    viewModel: viewModel,
                    messagingViewModel: messagingViewModel,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    showingUserList: $showingUserList,
                    navigateToChat: $navigateToChat,
                    targetConversation: $targetConversation,
                    scrollOffset: $scrollOffset,
                    showingMessageRequestAlert: $showingMessageRequestAlert,
                    messageRequestText: $messageRequestText,
                    messageRequestError: $messageRequestError,
                    showingSuccessMessage: $showingSuccessMessage,
                    showProfileImageFullscreen: $showProfileImageFullscreen,
                    onFollowAction: {
                        handleFollowAction()
                    },
                    onDismiss: {
                        dismiss()
                    },
                    onOpenStories: {
                        storyRoute = UserProfileStoryRoute(userId: userId)
                    },
                    selectedTab: $selectedTab // ✅ NUEVO
                )
            }
        }
    }

    private func handleFollowAction() {
        switch viewModel.followButtonState {
        case .following:
            viewModel.loadRelationshipManagementState()
            showingRelationshipSheet = true
        case .canFollow, .canRequestFollow:
            viewModel.followUser(userId: userId)
        case .requestPendingCancellable:
            viewModel.cancelFollowRequest(userId: userId)
        default:
            break
        }
    }

    private var unfollowConfirmationMessage: String {
        if viewModel.userProfile?.isPrivate == true {
            return NSLocalizedString("userProfile.unfollow.confirm.private.message", comment: "Private profile unfollow confirmation message")
        }
        return NSLocalizedString("userProfile.unfollow.confirm.message", comment: "Unfollow confirmation message")
    }

    private func usersForListType(_ listType: UserListType) -> [AppUser] {
        switch listType {
        case .admirers: return viewModel.admirers
        case .connections: return viewModel.connections
        case .mutualConnections: return viewModel.mutualConnections
        }
    }

    private func rowAction(for listType: UserListType) -> UserListRowAction {
        switch listType {
        case .admirers:
            return .follow
        case .connections, .mutualConnections:
            return .unfollow
        }
    }

    private func openNestedUserProfile(userId: String) {
        showingUserList = nil
        selectedNestedProfileUserId = userId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showNestedProfile = true
        }
    }
}

struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        UserProfileView(userId: "123")
    }
}
