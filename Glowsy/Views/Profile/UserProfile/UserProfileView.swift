import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// ✅ USAR: Sistema de colores adaptativos existente (definido en FeedView.swift)

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
        visualIndex(for: width) == index ? UserProfileColors.textPrimary : UserProfileColors.textSecondary
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
    @State private var showingMessageRequestAlert = false
    @State private var messageRequestText = ""
    @State private var messageRequestError: String?
    @State private var showingSuccessMessage = false
    @State private var selectedMoment: Moment?
    @State private var showingUnfollowConfirmation = false
    @State private var showingRelationshipSheet = false

    @StateObject private var storyViewModel = StoryViewModel()
    @State private var showStoryViewer: Bool = false
    @State private var selectedStoryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var showMomentDetail = false
    @State private var selectedMomentIndex = 0
    // NUEVO: Estado para el gesto de arrastre
    @State private var dragAmount = CGSize.zero
    @State private var isDragging = false
    @State private var hasRegisteredVisit = false
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var currentStory: Story?
    @State private var selectedTab: UserProfileTabType = .moments // ✅ NUEVO: Tab seleccionado
    @State private var selectedNestedProfileUserId: String? = nil
    @State private var showNestedProfile = false

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
        ZStack {
            EnhancedProfileBackground(
                profileImagePath: viewModel.userProfile?.profileImagePath,
                scrollOffset: scrollOffset,
                profileTheme: viewModel.userProfile?.currentProfileTheme ?? .default,
                user: viewModel.userProfile
            )
            .ignoresSafeArea(.all, edges: .all)

            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom

                contentView(safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom)
            }
        }
        .navigationBarHidden(true)
        .offset(x: dragAmount.width)
        .opacity(isDragging ? 0.8 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width > 0 {
                        dragAmount = value.translation
                        isDragging = true
                    }
                }
                .onEnded { value in
                    withAnimation(.spring()) {
                        if value.translation.width > 100 {
                            dismiss()
                        } else {
                            dragAmount = .zero
                            isDragging = false
                        }
                    }
                }
        )
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
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            .presentationBackground(.clear)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .fullScreenCover(isPresented: $showNestedProfile, onDismiss: {
            selectedNestedProfileUserId = nil
        }) {
            if let userId = selectedNestedProfileUserId {
                UserProfileView(userId: userId)
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
        .fullScreenCover(isPresented: $navigateToChat) {
            if let conversation = targetConversation {
                ChatRecoveryGateView(onCancel: {
                    navigateToChat = false
                }) {
                    GlassmorphicChatView(conversation: conversation)
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
        // ✅ CORREGIDO: Eliminar el sheet duplicado y usar solo fullScreenCover
        .fullScreenCover(isPresented: $showMomentDetail) {
            ModernMomentDetailView(
                moments: selectedTab == .moments ? viewModel.moments : viewModel.taggedMoments,
                initialIndex: selectedMomentIndex,
                topContentInset: selectedTab == .moments ? 24 : 64,
                onDismiss: {
                    showMomentDetail = false
                }
            )
        }
        .fullScreenCover(isPresented: $showStoryViewer) {
            if let stories = storyViewModel.stories[userId], !stories.isEmpty {
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
                        // ✅ NUEVO: Implementar reporte para historias de otros
                        currentStory = stories[safeStoryIndex]
                        showingReportSheet = true
                    },
                    onBlockUser: {
                        // ✅ NUEVO: Implementar bloqueo para historias de otros
                        currentStory = stories[safeStoryIndex]
                        showingBlockConfirmation = true
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
                    onProfileTap: { }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingUserList)
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: "Unfollow confirmation title"),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: "Unfollow action"), role: .destructive) {
                viewModel.unfollowUser(userId: userId)
            }

            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: "Unfollow confirmation message"))
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

                // ✅ USAR NUEVA FUNCIÓN con filtrado automático
                storyViewModel.fetchStoriesForUserProfile(userId: userId, viewerId: currentUserId)

                // Cargar conversaciones
                messagingViewModel.fetchConversations(for: currentUserId)

            } else {

            }

            // ✅ Cargar datos del perfil
            viewModel.fetchProfile()
            viewModel.checkFollowButtonState()
            if let currentUserId = Auth.auth().currentUser?.uid {
                messagingViewModel.fetchConversations(for: currentUserId)
            }
        }
    }

    // ✅ NUEVA: Función para enviar solicitud de mensaje
    private func sendMessageRequest() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
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
                    storyViewModel: storyViewModel,
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
                    showStoryViewer: $showStoryViewer,
                    selectedStoryIndex: $selectedStoryIndex
                )
            } else {
                // ✅ CORREGIDO: Vista pública con parámetros correctos
                UserModernPublicProfileView(
                    viewModel: viewModel,
                    storyViewModel: storyViewModel,
                    messagingViewModel: messagingViewModel,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    showingUserList: $showingUserList,
                    selectedMoment: $selectedMoment,
                    showMomentDetail: $showMomentDetail,
                    selectedMomentIndex: $selectedMomentIndex,
                    showStoryViewer: $showStoryViewer,
                    selectedStoryIndex: $selectedStoryIndex,
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
        default:
            break
        }
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
