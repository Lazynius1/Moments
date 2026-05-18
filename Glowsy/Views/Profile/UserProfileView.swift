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
                StoryViewerScreen(
                    story: stories[selectedStoryIndex],
                    storyCount: stories.count,
                    storyIndex: selectedStoryIndex,
                    screenSize: UIScreen.main.bounds.size,
                    storyViewModel: storyViewModel,
                    // ✅ AGREGAR: Pasar los bindings
                    showingReportSheet: $showingReportSheet,
                    showingBlockConfirmation: $showingBlockConfirmation,
                    onReportStory: {
                        // ✅ NUEVO: Implementar reporte para historias de otros
                        currentStory = stories[selectedStoryIndex]
                        showingReportSheet = true
                    },
                    onBlockUser: {
                        // ✅ NUEVO: Implementar bloqueo para historias de otros
                        currentStory = stories[selectedStoryIndex]
                        showingBlockConfirmation = true
                    },
                    onNext: {
                        if selectedStoryIndex + 1 < stories.count {
                            selectedStoryIndex += 1
                        } else {
                            showStoryViewer = false
                        }
                    },
                    onPrevious: {
                        if selectedStoryIndex > 0 {
                            selectedStoryIndex -= 1
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

// MARK: - ✅ CORREGIDA: Vista pública moderna
struct UserModernPublicProfileView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var selectedMoment: Moment?
    @Binding var showMomentDetail: Bool
    @Binding var selectedMomentIndex: Int
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var scrollOffset: CGFloat
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    @Binding var showProfileImageFullscreen: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void
    
    @State private var showingFullInfo = false // ✅ NUEVO: Colapsable
    @Binding var selectedTab: UserProfileTabType // ✅ NUEVO: Tab seleccionado (Binding)

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Header del perfil
                    UserModernProfileHeader(
                        viewModel: viewModel,
                        storyViewModel: storyViewModel,
                        messagingViewModel: messagingViewModel,
                        showStoryViewer: $showStoryViewer,
                        selectedStoryIndex: $selectedStoryIndex,
                        navigateToChat: $navigateToChat,
                        targetConversation: $targetConversation,
                        showingUserList: $showingUserList,
                        showingMessageRequestAlert: $showingMessageRequestAlert,
                        messageRequestText: $messageRequestText,
                        messageRequestError: $messageRequestError,
                        showingSuccessMessage: $showingSuccessMessage,
                        showProfileImageFullscreen: $showProfileImageFullscreen,
                        onFollowAction: onFollowAction,
                        onDismiss: onDismiss
                    )
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    
                    UserProfileOverviewSection(
                        viewModel: viewModel,
                        showingUserList: $showingUserList,
                        showingInterests: $showingFullInfo,
                        interests: viewModel.userProfile?.interests ?? []
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                    if let userId = viewModel.userProfile?.id {
                        ProfileHighlightsView(
                            userId: userId,
                            isOwnProfile: false,
                            isCompact: true
                        )
                        .padding(.bottom, 12)
                    }

                    // Indicador de refresh
                    if viewModel.isRefreshing {
                        UserModernRefreshIndicator()
                            .padding(.bottom, 12)
                    }

                    
                    // ✅ CORREGIDO: Sección de momentos con tabs
                    VStack(spacing: 0) {
                        // Pills Tabs
                        UserProfilePillTabs(selectedTab: $selectedTab)
                            .frame(maxWidth: 240)
                            .padding(.bottom, 12)
                        
                        // Contenido según tab seleccionado
                        switch selectedTab {
                        case .moments:
                            if viewModel.moments.isEmpty {
                                UserModernEmptyMomentsView()
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: UIScreen.main.bounds.width - 40)
                            } else {
                                GeometryReader { geometry in
                                    let spacing: CGFloat = 4
                                    let columns = 3
                                    let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                    let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                        ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                                            ScreenshotProtectedView(
                                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                            ) {
                                                UserModernMomentThumbnail(
                                                    moment: moment,
                                                    size: itemWidth,
                                                    onTap: {
                                                        selectedMomentIndex = index
                                                        showMomentDetail = true
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .frame(height: calculateGridHeight(itemCount: viewModel.moments.count))
                            }
                        
                        case .tagged:
                            // Contenido de momentos etiquetados
                            Group {
                                if viewModel.isLoadingTagged {
                                    ProgressView()
                                        .tint(UserProfileColors.textPrimary)
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
                                        let spacing: CGFloat = 4
                                        let columns = 3
                                        let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                        let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
                                        
                                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                            ForEach(Array(viewModel.taggedMoments.enumerated()), id: \.element.id) { index, moment in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    UserModernMomentThumbnail(
                                                        moment: moment,
                                                        size: itemWidth,
                                                        onTap: {
                                                            selectedMomentIndex = index
                                                            showMomentDetail = true
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                    .frame(height: calculateGridHeight(itemCount: viewModel.taggedMoments.count))
                                }
                            }
                            .onAppear {
                                if viewModel.taggedMoments.isEmpty && !viewModel.isLoadingTagged {
                                    viewModel.fetchTaggedMoments()
                                }
                            }
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: UserScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                )
                .padding(.bottom, safeAreaBottom + 120)
            }
            .coordinateSpace(name: "scroll")
            .refreshable {
                await withCheckedContinuation { continuation in
                    viewModel.refreshProfile()
                    
                    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        if !viewModel.isRefreshing {
                            timer.invalidate()
                            continuation.resume()
                        }
                    }
                }
            }
            .onPreferenceChange(UserScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
    }
}


// MARK: - ✅ NUEVO: Header moderno como ProfileView
struct UserModernProfileHeader: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    @StateObject private var messageRequestService = MessageRequestService()
    @EnvironmentObject var authService: AuthService // ✅ NUEVO: Para acceder a badges del usuario visitado
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    @Binding var showProfileImageFullscreen: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void // ✅ NUEVO: Para el botón de atrás
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            // ✅ NUEVO: Botón de atrás en la esquina superior izquierda
            HStack {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(UserProfileColors.cardBackground.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .shadow(color: UserProfileColors.shadowColor, radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(UserProfileColors.textPrimary)
                    }
                }
                .scaleEffect(0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            
            // Avatar principal con badges (sin círculo de fondo)
            UserModernAvatarWithBadges(
                userProfile: viewModel.userProfile,
                storyViewModel: storyViewModel,
                showStoryViewer: $showStoryViewer,
                selectedStoryIndex: $selectedStoryIndex,
                showProfileImageFullscreen: Binding<Bool>(
                    get: { self.showProfileImageFullscreen },
                    set: { self.showProfileImageFullscreen = $0 }
                ),
                size: 100
            )
            
            // Información del usuario con badges
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"),
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 20,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 24))
                    
                    // ✅ NUEVO: Badges horizontales del usuario visitado
                    if let userProfile = viewModel.userProfile {
                        UserProfileBadgesView(userProfile: userProfile)
                    }
                }
                
                // Bio expandible adaptativa
                VStack(spacing: 6) {
                    UserExpandableBioView(bio: viewModel.userProfile?.bio ?? NSLocalizedString("userProfile.noBio", comment: "No bio"))

                    if let websiteUrl = viewModel.userProfile?.websiteUrl,
                       !websiteUrl.isEmpty,
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))

                                Text(
                                    websiteUrl
                                        .replacingOccurrences(of: "https://", with: "")
                                        .replacingOccurrences(of: "http://", with: "")
                                )
                                .font(.custom("Poppins-Medium", size: 13))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }
                            .foregroundColor(UserProfileColors.accent)
                            .padding(.vertical, 4)
                        }
                        .padding(.top, 2)
                    }

                }
            }
            
            // Botones de acción adaptativos
            HStack(spacing: 12) {
                Button(action: onFollowAction) {
                    HStack(spacing: 7) {
                        Text(followButtonText)
                            .font(.custom("Poppins-SemiBold", size: 14))

                        if viewModel.followButtonState == .following {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .liquidGlass(in: Capsule(), interactive: viewModel.followButtonState.isActionable)
                }
                .disabled(!viewModel.followButtonState.isActionable)
                .scaleEffect(viewModel.followButtonState.isActionable ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.followButtonState)
                
                Button(action: {
                    guard let currentUserId = Auth.auth().currentUser?.uid,
                          let targetUser = viewModel.userProfile else { return }
                    
                    // ✅ Intentar crear conversación directa primero
                    messagingViewModel.startConversation(with: targetUser, from: currentUserId) { conversation in
                        if let conversation {
                            // ✅ Conversación creada exitosamente
                            targetConversation = conversation
                            navigateToChat = true
                        } else {
                            // ❌ Verificar si es error de seguimiento mutuo
                            let errorMessage = messagingViewModel.errorMessage ?? ""
                            if errorMessage.contains("no siguen mutuamente") || errorMessage.contains("Se requiere una solicitud") {
                                // 📤 Mostrar alerta para crear MessageRequest
                                showingMessageRequestAlert = true
                            }
                        }
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                
                Button(action: {
                    if viewModel.isBlockedByCurrentUser {
                        viewModel.unblockUser(userId: viewModel.userId)
                    } else {
                        viewModel.blockUser(userId: viewModel.userId)
                    }
                }) {
                    Image(systemName: viewModel.isBlockedByCurrentUser ? "person.fill.checkmark" : "person.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.72))
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var followButtonText: String {
        switch viewModel.followButtonState {
        case .ownProfile: 
            return NSLocalizedString("userProfile.followButton.ownProfile", comment: "Own profile")
        case .blocked: 
            return NSLocalizedString("userProfile.followButton.blocked", comment: "Blocked")
        case .following: 
            return NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .canFollow: 
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "Follow")
        case .canRequestFollow: 
            return NSLocalizedString("userProfile.followButton.canRequestFollow", comment: "Request follow")
        case .requestPending: 
            return NSLocalizedString("userProfile.followButton.requestPending", comment: "Request sent")
        }
    }

    private var followButtonColor: Color {
        switch viewModel.followButtonState {
        case .following, .requestPending: return Color.gray.opacity(0.6)
        case .canFollow, .canRequestFollow: return UserProfileColors.accent
        case .ownProfile, .blocked: return Color.gray.opacity(0.4)
        }
    }
}

struct UserRelationshipChip: View {
    let title: String
    let icon: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(title)
                .font(.custom("Poppins-Medium", size: 11))
                .lineLimit(1)
        }
        .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.68))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .liquidGlass(in: Capsule(), interactive: false)
    }
}

struct UserRelationshipManagementSheet: View {
    let username: String
    let profileImagePath: String?
    let userId: String
    let isBestFriend: Bool
    let isMuted: Bool
    let isMutual: Bool
    let customListCount: Int
    let customLists: [CustomAudienceList]
    let isUpdatingBestFriend: Bool
    let isUpdatingMute: Bool
    let isUpdatingLists: Bool
    let onToggleBestFriend: () -> Void
    let onToggleMute: () -> Void
    let onRemoveFromList: (CustomAudienceList) -> Void
    let onUnfollow: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLists = false
    @State private var listPendingRemoval: CustomAudienceList?

    private var relationshipSummaryItems: [String] {
        var items: [String] = []
        if isMutual { items.append(NSLocalizedString("userProfile.relationship.mutual", comment: "")) }
        if customListCount > 0 { items.append(NSLocalizedString("userProfile.relationship.inLists", comment: "")) }
        if isMuted { items.append(NSLocalizedString("userProfile.relationship.muted", comment: "")) }
        return items
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                relationshipAvatar

                VStack(spacing: 4) {
                    Text(String(format: NSLocalizedString("userProfile.relationship.sheet.title", comment: ""), username))
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("userProfile.relationship.sheet.subtitle", comment: ""))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                }

                if !relationshipSummaryItems.isEmpty {
                    Text(relationshipSummaryItems.joined(separator: " · "))
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.46))
                        .lineLimit(1)
                }
            }
            .padding(.top, 18)

            ZStack {
                if showingLists {
                    listsContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    mainContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showingLists)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
                relationshipActionRow(
                    title: isBestFriend
                        ? NSLocalizedString("userProfile.relationship.bestFriends", comment: "")
                        : NSLocalizedString("userProfile.relationship.bestFriends.add", comment: ""),
                    subtitle: isBestFriend
                        ? NSLocalizedString("userProfile.relationship.bestFriends.remove.subtitle", comment: "")
                        : NSLocalizedString("userProfile.relationship.bestFriends.add.subtitle", comment: ""),
                    icon: isBestFriend ? "star.fill" : "star",
                    iconColor: isBestFriend ? .green : nil,
                    isLoading: isUpdatingBestFriend,
                action: onToggleBestFriend
            )

            relationshipActionRow(
                title: isMuted
                    ? NSLocalizedString("userProfile.relationship.mute.disable", comment: "")
                    : NSLocalizedString("userProfile.relationship.mute.enable", comment: ""),
                subtitle: isMuted
                    ? NSLocalizedString("userProfile.relationship.mute.disabled.subtitle", comment: "")
                    : NSLocalizedString("userProfile.relationship.mute.enabled.subtitle", comment: ""),
                icon: isMuted ? "speaker.wave.2" : "speaker.slash",
                iconColor: nil,
                isLoading: isUpdatingMute,
                action: onToggleMute
            )

            Button(action: {
                showingLists = true
            }) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("userProfile.relationship.lists.title", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 15))
                        Text(customListCount > 0
                            ? String(format: NSLocalizedString("userProfile.relationship.lists.count", comment: ""), customListCount)
                            : NSLocalizedString("userProfile.relationship.lists.empty", comment: ""))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17, weight: .semibold))

                        if customListCount > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.46) : .black.opacity(0.38))
                        }
                    }
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onUnfollow) {
                HStack(spacing: 14) {
                    Text(NSLocalizedString("userProfile.relationship.unfollow", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 15))

                    Spacer()

                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.red)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var listsContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button(action: {
                    showingLists = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 34, height: 34)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("userProfile.relationship.lists.title", comment: ""))
                        .font(.custom("Poppins-Bold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(NSLocalizedString("userProfile.relationship.lists.manage", comment: ""))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                }

                Spacer()
            }

            if customLists.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.44) : .black.opacity(0.38))

                    Text(NSLocalizedString("userProfile.relationship.lists.empty", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                VStack(spacing: 0) {
                    ForEach(customLists) { list in
                        Button(action: {
                            listPendingRemoval = list
                        }) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.custom("Poppins-SemiBold", size: 15))
                                    Text(String(format: NSLocalizedString("audience.people.count", comment: ""), list.members.count))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                                }

                                Spacer()

                                if isUpdatingLists {
                                    ProgressView()
                                        .scaleEffect(0.82)
                                } else {
                                    Image(systemName: list.icon ?? "list.bullet")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdatingLists)
                    }
                }
            }
        }
        .confirmationDialog(
            listRemovalTitle,
            isPresented: Binding(
                get: { listPendingRemoval != nil },
                set: { if !$0 { listPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.relationship.lists.remove.action", comment: ""), role: .destructive) {
                if let list = listPendingRemoval {
                    onRemoveFromList(list)
                    listPendingRemoval = nil
                }
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                listPendingRemoval = nil
            }
        } message: {
            Text(listRemovalMessage)
        }
    }

    private var listRemovalTitle: String {
        guard let listPendingRemoval else {
            return NSLocalizedString("userProfile.relationship.lists.remove.title.fallback", comment: "")
        }

        return String(
            format: NSLocalizedString("userProfile.relationship.lists.remove.title", comment: ""),
            username,
            listPendingRemoval.name
        )
    }

    private var listRemovalMessage: String {
        NSLocalizedString("userProfile.relationship.lists.remove.message", comment: "")
    }

    private var relationshipAvatar: some View {
        Group {
            if let profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.58))
            }
        }
        .frame(width: 62, height: 62)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        .clipShape(Circle())
    }

    private func relationshipActionRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color?,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor ?? (colorScheme == .dark ? .white : .black))
                        .frame(width: 24)
                }
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

}

// ✅ NUEVO: Modal elegante para solicitud de mensaje (mismo estilo que MessageRequestsView)
struct MessageRequestModalView: View {
    @Binding var messageText: String
    @Binding var errorMessage: String?
    @Binding var showingSuccessMessage: Bool
    let onSend: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            contentView
            
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("messageRequestModal.title", comment: "Modal title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(adaptiveColors.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
        }
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 24) {
                            // Icono principal
                VStack(spacing: 16) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text(NSLocalizedString("messageRequestModal.description", comment: "Modal description"))
                        .font(.body)
                        .foregroundColor(adaptiveColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            
            // Campo de texto
            VStack(spacing: 12) {
                TextField(NSLocalizedString("messageRequestModal.placeholder", comment: "Message placeholder"), text: $messageText, axis: .vertical)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(adaptiveColors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .focused($isTextFieldFocused)
                    .lineLimit(3...6)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                }
            }
            
            // Botones de acción
            VStack(spacing: 12) {
                Button(action: onSend) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(NSLocalizedString("messageRequestModal.sendButton", comment: "Send button"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                
                Button(action: { dismiss() }) {
                    Text(NSLocalizedString("messageRequestModal.cancelButton", comment: "Cancel button"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(adaptiveColors.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(adaptiveColors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                colors: adaptiveColors.overlayStroke,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 20)
    }
}

//SISTEMA DE BADGES //
struct UserModernAvatarWithBadges: View {
    let userProfile: AppUser?
    @ObservedObject var storyViewModel: StoryViewModel
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var showProfileImageFullscreen: Bool
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ NUEVO: Estado local para el estado de visto (cargado de Firestore)
    @State private var viewedStatusArray: [Bool] = []
    @State private var hasLoadedViewedStatus: Bool = false
    
    private var hasStory: Bool {
        guard let userId = userProfile?.id else { return false }
        return !(storyViewModel.stories[userId]?.isEmpty ?? true)
    }
    
    private var storyCount: Int {
        guard let userId = userProfile?.id else { return 0 }
        return storyViewModel.stories[userId]?.count ?? 0
    }
    
    // ✅ NUEVO: Usar el estado local en lugar del computed property
    private var storyViewedStatus: [Bool] {
        return viewedStatusArray
    }
    
    private var storyAudiences: [String?] {
        guard let userId = userProfile?.id else { return [] }
        return storyViewModel.stories[userId]?.map { $0.audience } ?? []
    }
    
    private var hasUnseenStory: Bool {
        // Si no hemos cargado aún, asumir que hay no vistas para mostrar coloreado
        if !hasLoadedViewedStatus || viewedStatusArray.isEmpty {
            return true
        }
        return viewedStatusArray.contains(false)
    }
    
    private var isOwnStory: Bool {
        return userProfile?.id == Auth.auth().currentUser?.uid
    }

    var body: some View {
        ZStack {
            // Avatar principal - SIN action, el onTapGesture del ZStack maneja todo
            Group {
                if let profileImagePath = userProfile?.profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(UserProfileColors.materialBackground)
                            .frame(width: size, height: size)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: size * 0.45))
                                    .foregroundColor(UserProfileColors.textTertiary)
                            )
                            .overlay(ProgressView().tint(UserProfileColors.accent))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .overlay(avatarBorderOverlay())
                    .shadow(color: UserProfileColors.shadowColor, radius: 15, x: 0, y: 8)
            } else {
                Circle()
                    .fill(UserProfileColors.materialBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundColor(UserProfileColors.textTertiary)
                    )
                    .overlay(avatarBorderOverlay())
                    .shadow(color: UserProfileColors.shadowColor, radius: 12, x: 0, y: 6)
                }
            }
            // ✅ REMOVIDO buttonStyle ya que ahora es Group, no Button
            
            // ✅ NUEVO: Badge principal en esquina superior derecha
            if let primaryBadge = userProfile?.primaryBadge {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: primaryBadge.swiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.3, height: size * 0.3)
                    
                    Text(primaryBadge.emoji)
                        .font(.system(size: size * 0.15))
                }
                .offset(x: size * 0.375, y: -size * 0.375)
                .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
            }
            
            // ✅ NUEVO: Corona Plus en esquina superior izquierda (se oculta si hay tema activo o si está desactivado)
            if userProfile?.isPlusSubscriber == true,
               userProfile?.showPlusBadge == true,
               userProfile?.selectedProfileTheme == nil || userProfile?.selectedProfileTheme == "default" {
                ZStack {
                    Circle()
                        .fill(UserProfileColors.cardBackground)
                        .frame(width: size * 0.27, height: size * 0.27)
                    
                    Image(systemName: "crown.fill")
                        .font(.system(size: size * 0.13, weight: .bold))
                        .foregroundColor(Color(hex: "FFD700"))
                }
                .offset(x: -size * 0.375, y: -size * 0.375)
                .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
            }
            
            // ✅ NUEVO: Indicador de nivel supporter en la parte inferior - OCULTO
            // if let supporterLevel = userProfile?.supporterLevel,
            //    userProfile?.isSupporter == true && supporterLevel != .none {
            //     UserSupporterLevelIndicator(level: supporterLevel)
            //         .offset(x: 0, y: size * 0.54)
            //         .shadow(color: UserProfileColors.shadowColor, radius: 4, x: 0, y: 2)
            // }
        }
        // ✅ TAP: Abrir historias (si hay) o foto fullscreen
        .onTapGesture {
            if hasStory {
                showStoryViewer = true
                selectedStoryIndex = 0
            } else {
                showProfileImageFullscreen = true
            }
        }
        // ✅ LONG PRESS: Siempre abre la foto de perfil en grande
        .onLongPressGesture(minimumDuration: 0.5) {
            showProfileImageFullscreen = true
        }
        // ✅ NUEVO: Cargar estado de visto cuando aparezca o cambien las historias
        .onAppear {
            loadViewedStatus()
        }
        .onChange(of: storyCount) { _, _ in
            // Cuando cambie el número de historias, recargar estado
            loadViewedStatus()
        }
    }
    
    // ✅ NUEVO: Cargar estado de visualización directamente de Firestore (como FeedView)
    private func loadViewedStatus() {
        guard let userId = userProfile?.id,
              let currentUserId = Auth.auth().currentUser?.uid,
              let userStories = storyViewModel.stories[userId],
              !userStories.isEmpty else {
            viewedStatusArray = []
            hasLoadedViewedStatus = true
            return
        }
        
        // Si es historia propia, todas están "vistas"
        if userId == currentUserId {
            viewedStatusArray = Array(repeating: true, count: userStories.count)
            hasLoadedViewedStatus = true
            return
        }
        
        let group = DispatchGroup()
        var tempViewedStatus: [(index: Int, wasViewed: Bool)] = []
        let syncQueue = DispatchQueue(label: "avatar.viewed.status")
        
        for (index, story) in userStories.enumerated() {
            guard let storyId = story.id else {
                syncQueue.async {
                    tempViewedStatus.append((index: index, wasViewed: false))
                }
                continue
            }
            
            group.enter()
            Firestore.firestore().collection("users").document(story.authorId)
                .collection("stories").document(storyId)
                .collection("viewers").document(currentUserId)
                .getDocument { viewerDoc, _ in
                    let wasViewed = viewerDoc?.exists == true
                    syncQueue.async {
                        tempViewedStatus.append((index: index, wasViewed: wasViewed))
                    }
                    group.leave()
                }
        }
        
        group.notify(queue: .main) {
            // Ordenar por índice y extraer solo el estado
            let sortedStatus = tempViewedStatus.sorted { $0.index < $1.index }
            self.viewedStatusArray = sortedStatus.map { $0.wasViewed }
            self.hasLoadedViewedStatus = true
        }
    }    
    // Border inteligente del avatar adaptativo
    @ViewBuilder
    private func avatarBorderOverlay() -> some View {
        if hasStory {
            StorySegmentedRing(
                storyCount: storyCount,
                hasStory: hasStory,
                hasUnseenStory: hasUnseenStory, // ✅ Usar computed property
                storyViewedStatus: storyViewedStatus,
                storyAudiences: storyAudiences,
                isOwnStory: isOwnStory,
                colorScheme: colorScheme,
                ringSize: size,
                lineWidth: 3
            )
        } else if userProfile?.isPlusSubscriber == true && userProfile?.showPlusBadge == true {
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        }
    }
}

// ✅ NUEVO: Vista de badges para el usuario visitado
struct UserProfileBadgesView: View {
    let userProfile: AppUser
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if userProfile.isPlusSubscriber || userProfile.isSupporter {
            HStack(spacing: 8) {
                // Plus Badge (se oculta si hay tema activo o si está desactivado)
                if userProfile.isPlusSubscriber,
                   userProfile.showPlusBadge,
                   userProfile.selectedProfileTheme == nil || userProfile.selectedProfileTheme == "default" {
                    UserPlusBadgeInline()
                }
                
                // Support Badge
                if let primaryBadge = userProfile.primaryBadge {
                    UserSupportBadgeInline(badge: primaryBadge)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: userProfile.isPlusSubscriber)
            .animation(.easeInOut(duration: 0.3), value: userProfile.primaryBadge?.id)
        }
    }
}

// ✅ NUEVO: Plus Badge Inline para UserProfile
struct UserPlusBadgeInline: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            
            Text("userProfile.plus")
                .font(.custom("Poppins-Bold", size: 9))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Support Badge Inline para UserProfile
struct UserSupportBadgeInline: View {
    let badge: UserBadge
    
    var body: some View {
        HStack(spacing: 4) {
            Text(badge.emoji)
                .font(.system(size: 10))
            
            Text(badge.name.uppercased())
                .font(.custom("Poppins-Bold", size: 8))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: badge.swiftUIColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Indicador de nivel supporter para UserProfile
struct UserSupporterLevelIndicator: View {
    let level: SupporterLevel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 2) {
            Text(level.emoji)
                .font(.system(size: 10))
            
            ForEach(0..<levelStars, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "FFD700"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(UserProfileColors.cardBackground)
        .clipShape(Capsule())
    }
    
    private var levelStars: Int {
        switch level {
        case .none: return 0
        case .supporter: return 1
        case .earlyAdopter: return 2
        case .champion: return 3
        case .vip: return 4
        }
    }
}

// MARK: - ✅ NUEVO: Indicador de refresh moderno
struct UserModernRefreshIndicator: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(UserProfileColors.materialBackground)
                    .frame(width: 32, height: 32)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [UserProfileColors.accent, UserProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .scaleEffect(pulseScale)
            }
            
            Text("userProfile.updating")
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(UserProfileColors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(UserProfileColors.materialBackground)
        .clipShape(Capsule())
        .shadow(color: UserProfileColors.shadowColor, radius: 8, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}

// MARK: - ✅ NUEVO: Estadísticas modernas como ProfileView
struct UserProfileOverviewSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.canViewConnections {
                UserModernStatsSection(
                    viewModel: viewModel,
                    showingUserList: $showingUserList,
                    embeddedStyle: true
                )
            }

            if !interests.isEmpty {
                if viewModel.canViewConnections {
                    Divider()
                        .overlay(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.22 : 0.4))
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("profile.interests.title")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(UserProfileColors.textPrimary)

                        Text("\(interests.count)")
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(UserProfileColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(UserProfileColors.materialBackground.opacity(0.7))
                            .clipShape(Capsule())

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(UserProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }

                if showingInterests {
                    UserModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct UserModernStatsSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var showingUserList: UserProfileView.UserListType?
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    private var computedStats: [(String, Int, UserProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.ui.followers", comment: "Followers"), viewModel.admirers.count, .admirers),
            (NSLocalizedString("profile.ui.following", comment: "Following"), viewModel.connections.count, .connections),
            (NSLocalizedString("profile.ui.mutuals", comment: "Mutuals"), viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 8) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    showingUserList = stat.2
                }) {
                    VStack(spacing: 6) {
                        Text("\(stat.1)")
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(UserProfileColors.textPrimary)
                        
                        Text(stat.0)
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(UserProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, embeddedStyle ? 10 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if embeddedStyle && index < computedStats.count - 1 {
                    Rectangle()
                        .fill(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.24 : 0.4))
                        .frame(width: 1, height: 30)
                }
            }
        }
        .padding(.horizontal, embeddedStyle ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
    }
}

// MARK: - ✅ NUEVO: Bio expandible
struct UserExpandableBioView: View {
    let bio: String
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Text(bio)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(UserProfileColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 15))
                        .lineLimit(3)
                        .background(GeometryReader { geometry in
                            Color.clear.onAppear {
                                DispatchQueue.main.async {
                                    needsExpansion = bio.count > 100 || bio.filter { $0 == "\n" }.count > 2
                                }
                            }
                        })
                        .hidden()
                )
                .padding(.horizontal, 40)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
            
            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("userProfile.seeLess", comment: "See less") : NSLocalizedString("userProfile.seeMore", comment: "See more"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(UserProfileColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(UserProfileColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - ✅ Avatar actualizado
struct UserModernAvatar: View {
    let profileImagePath: String?
    let userId: String // ✅ NUEVO: Agregar userId como parámetro
    @ObservedObject var storyViewModel: StoryViewModel
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    private var hasStory: Bool {
        // ✅ CORREGIDO: Usar userId en lugar de profileImagePath
        return !(storyViewModel.stories[userId]?.isEmpty ?? true)
    }
    
    private var storyCount: Int {
        return storyViewModel.stories[userId]?.count ?? 0
    }
    
    private var storyViewedStatus: [Bool] {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let userStories = storyViewModel.stories[userId] else {
            return []
        }
        
        return userStories.map { story in
            guard let storyId = story.id else { return false }
            let viewers = storyViewModel.storyViewers[storyId] ?? []
            return viewers.contains { $0.userId == currentUserId }
        }
    }
    
    private var storyAudiences: [String?] {
        return storyViewModel.stories[userId]?.map { $0.audience } ?? []
    }
    
    private var isOwnStory: Bool {
        return userId == Auth.auth().currentUser?.uid
    }

    var body: some View {
        ZStack {
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: size, height: size)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: size * 0.45))
                                    .foregroundColor(.gray.opacity(0.6))
                            )
                            .overlay(ProgressView().tint(Color(hex: "007AFF")))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill) // ✅ CLAVE: aspectRatio en lugar de scaledToFill
                    .frame(width: size, height: size) // ✅ CLAVE: Frame fijo
                    .clipShape(Circle()) // ✅ CLAVE: Clip después del frame
                    .contentShape(Circle()) // ✅ CLAVE: ContentShape para touch
                    .overlay(
                        StorySegmentedRing(
                            storyCount: storyCount,
                            hasStory: hasStory,
                            hasUnseenStory: !storyViewedStatus.allSatisfy { $0 },
                            storyViewedStatus: storyViewedStatus,
                            storyAudiences: storyAudiences,
                            isOwnStory: isOwnStory,
                            colorScheme: colorScheme,
                            ringSize: size,
                            lineWidth: 3
                        )
                    )
                    .shadow(color: Color(hex: "007AFF").opacity(0.2), radius: 15, x: 0, y: 8)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundColor(.gray.opacity(0.6))
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.clear, Color.clear], // ✅ QUITADO: Borde verde
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0 // ✅ QUITADO: Borde
                            )
                    )
                    .shadow(color: Color(hex: "007AFF").opacity(0.15), radius: 12, x: 0, y: 6)
            }
        }
        .onTapGesture {
            if hasStory {
                showStoryViewer = true
                selectedStoryIndex = 0
            }
        }
    }
}

// MARK: - ✅ NUEVO: Intereses modernos como ProfileView
struct UserModernInterestsView: View {
    let interests: [String]
    var showsTitle: Bool = true
    var embeddedStyle: Bool = false
    @State private var currentUserInterests: [String] = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text("userProfile.interests")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(UserProfileColors.textPrimary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        let emoji = interestEmoji(for: interest)
                        let isShared = currentUserInterests.contains(interest)
                        
                        HStack(spacing: 6) {
                            Text(emoji)
                                .font(.system(size: 16))
                            Text(interest)
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(isShared ? .white : UserProfileColors.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, embeddedStyle ? 9 : 10)
                        .background(
                            isShared ?
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [embeddedStyle ? UserProfileColors.materialBackground.opacity(0.62) : UserProfileColors.cardBackground, embeddedStyle ? UserProfileColors.materialBackground.opacity(0.62) : UserProfileColors.cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(UserProfileColors.borderColor.opacity(embeddedStyle && !isShared ? 0.18 : 0), lineWidth: embeddedStyle && !isShared ? 1 : 0)
                        )
                        .shadow(
                            color: isShared ? Color.blue.opacity(0.3) : UserProfileColors.shadowColor,
                            radius: isShared ? 6 : (embeddedStyle ? 0 : 4),
                            x: 0,
                            y: isShared ? 3 : (embeddedStyle ? 0 : 2)
                        )
                        .scaleEffect(isShared ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isShared)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            loadCurrentUserInterests()
        }
    }
    
    private func loadCurrentUserInterests() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        FirestoreService().db.collection("users").document(currentUserId).getDocument { document, error in
            if let data = document?.data(),
               let userInterests = data["interests"] as? [String] {
                DispatchQueue.main.async {
                    self.currentUserInterests = userInterests
                }
            }
        }
    }
    
    private func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}

// MARK: - ✅ NUEVO: Thumbnail de momento moderno como ProfileView
struct UserModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ NUEVOS: Estados para thumbnails de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                // ✅ NUEVO: Lógica actualizada para manejar videos y imágenes
                if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
                    // Es un momento nuevo con mediaItems
                    if mediaItem.type == .video {
                        // ✅ NUEVO: Priorizar thumbnailUrl si existe
                        if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                            imageView(imageURL: thumbnailUrl)
                        } else {
                            // Si no hay thumbnail URL (legacy), generar uno
                            videoThumbnailView(videoURL: mediaItem.url)
                        }
                    } else {
                        // ✅ NUEVO: Mostrar imagen desde mediaItems
                        imageView(imageURL: mediaItem.url)
                    }
                } else if let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) {
                    // ✅ MANTENER: Fallback para momentos legacy con imagePath
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(UserProfileColors.cardBackground)
                                .frame(width: size, height: size)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(UserProfileColors.textTertiary)
                                )
                                .overlay(ProgressView().tint(UserProfileColors.accent))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(borderOverlay())
                        .clipped()
                } else {
                    // ✅ MANTENER: Placeholder para sin contenido
                    emptyContentView()
                }
                
                // ✅ NUEVO: Indicador de video
                if let mediaItem = moment.primaryVisibleMediaItem, mediaItem.type == .video {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
                }
                
                // ✅ MANTENER: Contador de likes
                // ✅ NUEVO: El autor siempre ve el contador, los demás solo si no está oculto
                if let likeCount = moment.reactions["heart"]?.count, likeCount > 0,
                   (moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts) {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 9))
                        Text(String(format: NSLocalizedString("userProfile.likes.count", comment: "Likes count"), likeCount))
                            .font(.custom("Poppins-Medium", size: 9))
                            .foregroundColor(UserProfileColors.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(UserProfileColors.materialBackground)
                    .clipShape(Capsule())
                    .padding(4)
                }
                
                // ✅ NUEVO: Indicador de publicación programada (Solo para el autor)
                if moment.isScheduled && moment.authorId == Auth.auth().currentUser?.uid {
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(moment.scheduledRemainingText)
                                    .font(.custom("Poppins-Bold", size: 9))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .shadow(color: UserProfileColors.shadowColor, radius: 4, x: 0, y: 2)
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { isPressed = $0 }, perform: {})
    }
    
    // ✅ NUEVA: Vista para thumbnails de video
    @ViewBuilder
    private func videoThumbnailView(videoURL: String) -> some View {
        ZStack {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(borderOverlay())
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(UserProfileColors.cardBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(UserProfileColors.accent)
                                        .scaleEffect(0.8)
                                    Text("userProfile.video.loading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(UserProfileColors.textTertiary)
                                    Text("userProfile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            }
                        }
                    )
                    .overlay(borderOverlay())
            }
        }
        .onAppear {
            loadVideoThumbnail(from: videoURL)
        }
    }
    
    // ✅ NUEVA: Vista para imágenes desde mediaItems
    @ViewBuilder
    private func imageView(imageURL: String) -> some View {
        if let url = getImageURL(from: imageURL) {
            KFImage(url)
                .placeholder {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(UserProfileColors.cardBackground)
                        .overlay(
                            VStack(spacing: 6) {
                                ProgressView()
                                    .tint(UserProfileColors.accent)
                                    .scaleEffect(0.8)
                                Text("userProfile.image.loading")
                                    .font(.custom("Poppins-Regular", size: 8))
                                    .foregroundColor(UserProfileColors.textSecondary)
                            }
                        )
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .overlay(borderOverlay())
                .clipped()
        } else {
            emptyContentView()
        }
    }
    
    // ✅ NUEVA: Vista para contenido vacío
    @ViewBuilder
    private func emptyContentView() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(UserProfileColors.cardBackground)
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(UserProfileColors.textTertiary)
                    
                    Text(moment.content.isEmpty ? NSLocalizedString("userProfile.noContent", comment: "No content") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(UserProfileColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 3)
                }
            )
            .overlay(borderOverlay())
    }
    
    // ✅ NUEVA: Overlay de borde reutilizable
    @ViewBuilder
    private func borderOverlay() -> some View {
        EmptyView()
    }
    
    // ✅ NUEVA: Función para cargar thumbnail de video
    private func loadVideoThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        
        isLoadingVideoThumbnail = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2) // Retina
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                DispatchQueue.main.async {
                    self.videoThumbnail = uiImage
                    self.isLoadingVideoThumbnail = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingVideoThumbnail = false
                }
            }
        }
    }
    
    private func getImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }
}

// MARK: - Función auxiliar para calcular altura del grid (añadir a UserModernPublicProfileView)
private func calculateGridHeight(itemCount: Int) -> CGFloat {
    let columns = 3
    let rows = ceil(Double(itemCount) / Double(columns))
    let spacing: CGFloat = 4
    let totalSpacing = spacing * CGFloat(columns - 1) + 16
    let itemWidth = (UIScreen.main.bounds.width - totalSpacing) / 3
    return CGFloat(rows) * itemWidth + (CGFloat(rows - 1) * spacing)
}

// MARK: - ✅ NUEVO: Estado vacío moderno como ProfileView
struct UserModernEmptyMomentsView: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "camera",
            titleKey: "userProfile.noMoments.title",
            subtitleKey: "userProfile.noMoments.description"
        )
    }
}
// MARK: - UserModernBlockedView (sin cambios - ya estaba bien)
struct UserModernBlockedView: View {
    let isBlockedByCurrentUser: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onUnblock: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
                .frame(height: safeAreaTop)

            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        )
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(0.8))
                }
                
                VStack(spacing: 16) {
                    Text(isBlockedByCurrentUser ? NSLocalizedString("userProfile.blockedUser", comment: "Blocked user") : NSLocalizedString("userProfile.restrictedAccess", comment: "Restricted access"))
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(.white)
                    Text(isBlockedByCurrentUser ?
                         NSLocalizedString("userProfile.blockedByYou", comment: "You blocked this user") :
                         NSLocalizedString("userProfile.blockedYou", comment: "This user blocked you"))
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                VStack(spacing: 12) {
                    if isBlockedByCurrentUser {
                        Button(action: onUnblock) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.system(size: 16))
                                Text("userProfile.unblockUser")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(hex: "00A896"))
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    Button(action: onDismiss) {
                        Text("userProfile.back")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }

            Spacer()
        }
        .padding(.bottom, safeAreaBottom + 20)
        // NUEVO: Gesto para cerrar
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 {
                        onDismiss()
                    }
                }
        )
    }
}

// MARK: - UserModernPrivateProfileView (mejorada con stats reales y card)
struct UserModernPrivateProfileView: View {
    let userProfile: AppUser?
    let userId: String
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    @ObservedObject var viewModel: UserProfileViewModel // ✅ NUEVO: Para acceder a los datos reales
    let followButtonState: FollowButtonState
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: safeAreaTop + 20)

                UserModernAvatar(
                    profileImagePath: userProfile?.profileImagePath,
                    userId: self.userId,
                    storyViewModel: storyViewModel,
                    showStoryViewer: $showStoryViewer,
                    selectedStoryIndex: $selectedStoryIndex,
                    size: 100
                )
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text(userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                            .font(.custom("Poppins-Bold", size: 26))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        VerifiedBadgeView(userId: self.userId, size: 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if let bio = userProfile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 12) {
                    Button(action: {
                        HapticManager.shared.mediumImpact()
                        onFollowAction()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: followButtonIcon)
                                .font(.system(size: 15, weight: .medium))
                            Text(followButtonText)
                                .font(.custom("Poppins-SemiBold", size: 14))

                            if followButtonState == .following {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .liquidGlass(in: Capsule(), interactive: followButtonState.isActionable)
                    }
                    .disabled(!followButtonState.isActionable)

                    Button(action: {
                        guard let currentUserId = Auth.auth().currentUser?.uid,
                              let targetUser = userProfile else { return }
                        
                        messagingViewModel.startConversation(with: targetUser, from: currentUserId) { conversation in
                            if let conversation {
                                targetConversation = conversation
                                navigateToChat = true
                            } else if let error = messagingViewModel.errorMessage {
                                let lowercasedError = error.lowercased()
                                if lowercasedError.contains("no siguen mutuamente") || lowercasedError.contains("solicitud") {
                                    showingMessageRequestAlert = true
                                }
                            }
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.54) : .black.opacity(0.48))

                VStack(spacing: 8) {
                    Text("userProfile.private.title")
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("userProfile.private.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 42)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
            Spacer()
        }
    }
    
    private var followButtonText: String {
        switch followButtonState {
        case .ownProfile:
            return NSLocalizedString("userProfile.followButton.ownProfile", comment: "Own profile")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "Blocked")
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .canFollow:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "Follow")
        case .canRequestFollow:
            return NSLocalizedString("userProfile.followButton.canRequestFollow", comment: "Request follow")
        case .requestPending:
            return NSLocalizedString("userProfile.followButton.requestPending", comment: "Request sent")
        }
    }

    private var followButtonColor: Color {
        switch followButtonState {
        case .following, .requestPending:
            return Color.gray.opacity(0.6)
        case .canFollow, .canRequestFollow:
            return Color(hex: "00A896")
        case .ownProfile, .blocked:
            return Color.gray.opacity(0.4)
        }
    }
    
    // ✅ NUEVO: Icono para el botón según el estado
    private var followButtonIcon: String {
        switch followButtonState {
        case .ownProfile:
            return "person.circle.fill"
        case .blocked:
            return "slash.circle"
        case .following:
            return "checkmark.circle.fill"
        case .canFollow:
            return "person.badge.plus"
        case .canRequestFollow:
            return "envelope.circle"
        case .requestPending:
            return "clock.circle"
        }
    }
}

// MARK: - Neutral unavailable profile state
struct ProfileUnavailableAvatar: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                )

            Image(systemName: "person.slash")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
        }
        .frame(width: size, height: size)
    }
}

struct UserModernUnavailableProfileView: View {
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 42, height: 42)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, safeAreaTop + 8)

            Spacer()

            VStack(spacing: 20) {
                ProfileUnavailableAvatar(size: 92)

                VStack(spacing: 10) {
                    Text("userProfile.unavailable.title")
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text("userProfile.unavailable.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 42)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
            Spacer()
                .frame(height: safeAreaBottom + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }
}

struct UserModernBlockedByMeProfileView: View {
    let userProfile: AppUser?
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onUnblock: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var username: String {
        userProfile?.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User")
            : NSLocalizedString("userProfile.user", comment: "User")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 42, height: 42)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, safeAreaTop + 8)

            VStack(spacing: 18) {
                blockedAvatar

                VStack(spacing: 8) {
                    Text(username)
                        .font(.custom("Poppins-Bold", size: 28))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if let bio = userProfile?.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 34)
                    }
                }

                HStack(spacing: 22) {
                    blockedStat(label: NSLocalizedString("profile.ui.posts", comment: "Posts"))
                    blockedStat(label: NSLocalizedString("profile.ui.followers", comment: "Followers"))
                    blockedStat(label: NSLocalizedString("profile.ui.following", comment: "Following"))
                }
                .padding(.top, 2)
            }
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("userProfile.blockedByMe.title")
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("userProfile.blockedByMe.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }

                Button(action: onUnblock) {
                    Text("userProfile.unblockUser")
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }

            Spacer()
                .frame(height: safeAreaBottom + 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }

    @ViewBuilder
    private var blockedAvatar: some View {
        if let path = userProfile?.profileImagePath, let url = URL(string: path) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .opacity(0.72)
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                )
        } else {
            ProfileUnavailableAvatar(size: 104)
        }
    }

    private func blockedStat(label: String) -> some View {
        VStack(spacing: 4) {
            Text("--")
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.66))

            Text(label)
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.42) : .black.opacity(0.38))
        }
        .frame(minWidth: 72)
    }
}

// MARK: - ✅ COMPONENTE STATS NO TAPEABLE
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserModernLoadingView (sin cambios - ya estaba bien)
struct UserModernLoadingView: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(UserProfileColors.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [UserProfileColors.accent, UserProfileColors.textPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
                            Text("userProfile.loading")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(UserProfileColors.textSecondary)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - UserFlowLayout (sin cambios - ya estaba bien)
struct UserFlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = UserFlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = UserFlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct UserFlowResult {
        var size = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(x: currentX, y: currentY, width: subviewSize.width, height: subviewSize.height))
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - UserScrollOffsetPreferenceKey (sin cambios)
struct UserScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - UserModernBackgroundView con temas
struct UserModernBackgroundView: View {
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

// MARK: - UserMomentPreviewView (sin cambios - ya estaba bien)
struct UserMomentPreviewView: View {
    let moment: Moment
    let onHashtagTap: (String) -> Void

    var body: some View {
        VStack {
            if let imagePath = moment.imagePath, let url = URL(string: imagePath) {
                KFImage(url)
                    .placeholder {
                        Color.gray.opacity(0.2)
                            .frame(width: UIScreen.main.bounds.width - 32, height: (UIScreen.main.bounds.width - 32) * 0.75)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(ProgressView().tint(.gray))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width - 32, height: (UIScreen.main.bounds.width - 32) * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: UIScreen.main.bounds.width - 32, height: (UIScreen.main.bounds.width - 32) * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundColor(.gray))
            }
            UserExpandableContentView(
                content: moment.content,
                colorScheme: .dark,
                onHashtagTap: onHashtagTap
            )
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}

// MARK: - ✅ VIEWMODEL
@MainActor
class UserProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var taggedMoments: [Moment] = [] // ✅ NUEVO
    @Published var isLoadingTagged: Bool = false // ✅ NUEVO
    @Published var isFollowing: Bool = false
    @Published var isBlockedByCurrentUser: Bool = false
    @Published var isCurrentUserBlocked: Bool = false
    @Published var isLoading: Bool = true
    @Published var followButtonState: FollowButtonState = .canFollow
    @Published var canViewContent: Bool = false
    @Published var canViewConnections: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var isProfileUnavailable: Bool = false
    @Published var isInBestFriends: Bool = false
    @Published var isMutedByCurrentUser: Bool = false
    @Published var isMutualRelationship: Bool = false
    @Published var customListMembershipCount: Int = 0
    @Published var customListsContainingProfile: [CustomAudienceList] = []
    @Published var isUpdatingBestFriend: Bool = false
    @Published var isUpdatingMute: Bool = false
    @Published var isUpdatingLists: Bool = false
    
    // ✅ NUEVAS PROPIEDADES: Control granular de visibilidad
    @Published var visibleConnectionTypes = VisibleConnectionTypes(
        canViewAdmirers: false,
        canViewConnections: false,
        canViewMutualConnections: false
    )
    
    let userId: String
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    private let bestFriendsService = BestFriendsService()
    
    // Cache local para tracking de unfollows recientes
    private var recentUnfollows: Set<String> = []
    private var lastUnfollowTime: [String: Date] = [:]
    private var followStateObserver: NSObjectProtocol?

    init(userId: String) {
        self.userId = userId
        followStateObserver = NotificationCenter.default.addObserver(
            forName: FollowStateStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            Task { @MainActor [weak self] in
                guard let self, changedUserId == self.userId else { return }
                self.followButtonState = state
                self.isFollowing = (state == .following)
            }
        }
    }

    deinit {
        if let followStateObserver {
            NotificationCenter.default.removeObserver(followStateObserver)
        }
    }

    func fetchProfile() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        isLoading = true
        isProfileUnavailable = false
        
        // ✅ SwiftData: Carga inicial desde caché local (Instagram-like)
        if let cachedProfile = LocalPersistenceService.shared.loadUser(userId: userId) {
            DispatchQueue.main.async {
                if cachedProfile.isActive {
                    self.userProfile = cachedProfile
                    self.isLoading = false
                } else {
                    self.userProfile = nil
                    self.canViewContent = false
                    self.isProfileUnavailable = true
                    self.isLoading = false
                }
            }
        }
        
        // ✅ Cargar conexiones del caché
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingIds: cachedConnections.following.map(\.id),
                targetFollowerIds: cachedConnections.followers.map(\.id)
            )
        }
        
        checkIfBlocked()

        firestoreService.checkPublicProfileAvailability(userId: userId) { [weak self] availability in
            guard let self = self else { return }
            guard availability == .unavailable else { return }
            DispatchQueue.main.async {
                self.userProfile = nil
                self.canViewContent = false
                self.isProfileUnavailable = true
                self.isLoading = false
            }
        }
        
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    guard !self.isProfileUnavailable else { return }
                    guard profile.isActive else {
                        self.userProfile = nil
                        self.canViewContent = false
                        self.isProfileUnavailable = true
                        self.isLoading = false
                        return
                    }

                    self.isProfileUnavailable = false
                    self.userProfile = profile
                }
                if profile.isActive {
                    self.checkContentVisibility(currentUserId: currentUserId)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if self.isUnavailableProfileError(error) {
                        self.userProfile = nil
                        self.canViewContent = false
                        self.isProfileUnavailable = true
                    }
                    self.isLoading = false
                }
            }
        }
    }

    private func isUnavailableProfileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let documentNotFound = NSLocalizedString("errors.documentNotFound", comment: "Document not found")
        return nsError.code == -1 && nsError.localizedDescription == documentNotFound
    }
    
    // ✅ FUNCIÓN DE REFRESH COMPLETA
    func refreshProfile() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }
        
        guard !isRefreshing && !isLoading else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshing = true
        }
        
        // Delay mínimo para que Firestore procese cambios recientes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performRefresh(currentUserId: currentUserId)
        }
    }
    
    private func performRefresh(currentUserId: String) {
        let refreshGroup = DispatchGroup()
        var hasErrors = false
        
        // 1. Refresh perfil principal
        refreshGroup.enter()
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    self?.userProfile = profile
                }
            case .failure(let error):
                hasErrors = true
            }
            refreshGroup.leave()
        }
        
        // 2. Re-verificar permisos de privacidad
        refreshGroup.enter()
        checkConnectionsVisibility(currentUserId: currentUserId) {
            refreshGroup.leave()
        }
        
        // 3. Refresh conexiones con verificación directa
        refreshGroup.enter()
        self.checkConnectionsVisibility(currentUserId: currentUserId) {
            self.fetchConnectionsDirect()
            refreshGroup.leave()
        }
        
        // 4. Refresh momentos
        refreshGroup.enter()
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else {
                refreshGroup.leave()
                return
            }
            
            switch result {
            case .success(let allMoments):
                // ✅ Aplicar filtrado de audiencia
                self.filterMomentsForAudience(moments: allMoments, viewerId: currentUserId) { filteredMoments in
                    DispatchQueue.main.async {
                        self.moments = filteredMoments
                    }
                    refreshGroup.leave()
                }
            case .failure(let error):
                hasErrors = true
                refreshGroup.leave()
            }
        }
        
        // 5. Refresh momentos etiquetados
        refreshGroup.enter()
        self.fetchTaggedMoments {
            refreshGroup.leave()
        }
        
        // Cuando terminen todas las operaciones
        refreshGroup.notify(queue: .main) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.isRefreshing = false
            }
            
            if !hasErrors {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }
    
    private func checkContentVisibility(currentUserId: String) {
        if currentUserId == userId {
            canViewContent = true
            checkConnectionsVisibility(currentUserId: currentUserId) {
                self.fetchConnectionsDirect()
            }
            return
        }

        privacyService.canViewUserContent(viewerId: currentUserId, targetUserId: userId) { [weak self] canView in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canViewContent = canView
                if canView {
                    self.checkConnectionsVisibility(currentUserId: currentUserId) {
                        self.fetchConnectionsDirect()
                    }
                } else {
                    self.isLoading = false
                }
            }
        }
    }
    
    // ✅ FUNCIÓN CLAVE: Verificar visibilidad de conexiones con configuraciones de privacidad
    private func checkConnectionsVisibility(currentUserId: String, completion: (() -> Void)? = nil) {
        privacyService.getVisibleConnectionTypes(viewerId: currentUserId, targetUserId: userId) { [weak self] visibleTypes in
            DispatchQueue.main.async {
                self?.visibleConnectionTypes = visibleTypes
                // Para compatibilidad con código existente
                self?.canViewConnections = visibleTypes.canViewAdmirers || visibleTypes.canViewConnections || visibleTypes.canViewMutualConnections
                completion?()
            }
        }
    }


    
    // ✅ FUNCIÓN MEJORADA: Fetch conexiones directo con filtrado de privacidad
    private func fetchConnectionsDirect() {
        let group = DispatchGroup()
        var targetFollowingIds: [String] = []
        var targetFollowerIds: [String] = []
        
        if visibleConnectionTypes.canViewConnections || visibleConnectionTypes.canViewMutualConnections {
            group.enter()
            firestoreService.db.collection("users").document(userId).collection("following")
                .getDocuments { [weak self] followingSnapshot, error in
                    defer { group.leave() }
                    guard let self = self else { return }
                    guard error == nil else { return }
                    
                    let followingIds = followingSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []
                    
                    targetFollowingIds = followingIds.filter { followedUserId in
                        if let unfollowTime = self.lastUnfollowTime[followedUserId] {
                            let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                            if timeSinceUnfollow < 5.0 {
                                return false
                            } else {
                                self.lastUnfollowTime.removeValue(forKey: followedUserId)
                                self.recentUnfollows.remove(followedUserId)
                            }
                        }
                        return true
                    }
                }
        }
        
        if visibleConnectionTypes.canViewAdmirers || visibleConnectionTypes.canViewMutualConnections {
            group.enter()
            firestoreService.db.collection("users").document(userId).collection("followers")
                .getDocuments { followersSnapshot, error in
                    defer { group.leave() }
                    guard error == nil else { return }
                    
                    targetFollowerIds = followersSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []
                }
        }
        
        group.notify(queue: .main) {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingIds: targetFollowingIds,
                targetFollowerIds: targetFollowerIds
            )
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Obtener momentos etiquetados con filtrado de audiencia
    func fetchTaggedMoments(completion: (() -> Void)? = nil) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }
        
        isLoadingTagged = true
        
        // Buscar momentos donde el usuario del perfil está etiquetado
        firestoreService.db.collectionGroup("moments")
            .whereField("taggedUsers", arrayContains: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
                guard let self = self else {
                    completion?()
                    return
                }
                
                if let error = error {
                    print("❌ Error loading tagged moments: \(error)")
                    DispatchQueue.main.async {
                        self.isLoadingTagged = false
                        completion?()
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self.isLoadingTagged = false
                        self.taggedMoments = []
                        completion?()
                    }
                    return
                }
                
                let allMoments = documents.compactMap { doc -> Moment? in
                    guard let moment = try? doc.data(as: Moment.self) else { return nil }
                    return moment.isArchived == true ? nil : moment
                }
                
                // ✅ IMPORTANTE: Filtrar por audiencia usando PrivacyService
                self.privacyService.filterVisibleContent(moments: allMoments, for: currentUserId) { filteredMoments in
                    DispatchQueue.main.async {
                        self.taggedMoments = filteredMoments
                        self.isLoadingTagged = false
                        completion?()
                    }
                }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Categorizar conexiones respetando configuraciones de privacidad
    private func categorizeConnectionsWithPrivacy(targetFollowingIds: [String], targetFollowerIds: [String]) {
        let targetFollowingSet = Set(targetFollowingIds)
        let targetFollowerSet = Set(targetFollowerIds)
        
        let mutualIds: Set<String> = visibleConnectionTypes.canViewMutualConnections
            ? targetFollowingSet.intersection(targetFollowerSet)
            : []
        let connectionIds = targetFollowingSet.subtracting(mutualIds)
        let admirerIds = targetFollowerSet.subtracting(mutualIds)
        
        let fetchGroup = DispatchGroup()
        
        // ✅ SOLO cargar si tengo permisos específicos
        if visibleConnectionTypes.canViewMutualConnections {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(mutualIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.mutualConnections = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.mutualConnections = []
            }
        }
        
        if visibleConnectionTypes.canViewConnections {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(connectionIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.connections = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.connections = []
            }
        }
        
        if visibleConnectionTypes.canViewAdmirers {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(admirerIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.admirers = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.admirers = []
            }
        }
        
        // ✅ Cargar momentos cuando terminen todas las conexiones
        fetchGroup.notify(queue: .main) {
            self.fetchMoments()
            self.isLoading = false
            
            // ✅ SwiftData: Persistir conexiones en el caché local
            let allFollowers = self.mutualConnections + self.admirers
            let allFollowing = self.mutualConnections + self.connections
            LocalPersistenceService.shared.saveFollowers(userId: self.userId, followers: allFollowers)
            LocalPersistenceService.shared.saveFollowing(userId: self.userId, following: allFollowing)
        }
    }
    
    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            firestoreService.fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                switch result {
                case .success(let users):
                    allUsers.append(contentsOf: users)
                case .failure(let error):
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
    }
    
    func fetchMoments() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }
        
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let allMoments):
                // ✅ FILTRAR momentos por audiencia usando PrivacyService
                self.filterMomentsForAudience(moments: allMoments, viewerId: currentUserId) { filteredMoments in
                    DispatchQueue.main.async {
                        self.moments = filteredMoments
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.moments = []
                }
            }
        }
    }
    
    private func filterMomentsForAudience(moments: [Moment], viewerId: String, completion: @escaping ([Moment]) -> Void) {
        let group = DispatchGroup()
        var visibleIds: Set<String> = []
        let lock = NSLock()
        
        for moment in moments {
            group.enter()
            privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                if canView, let id = moment.id {
                    lock.lock()
                    visibleIds.insert(id)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original de los momentos
            let orderedVisibleMoments = moments.filter { moment in
                guard let id = moment.id else { return false }
                return visibleIds.contains(id)
            }
            
            completion(orderedVisibleMoments)
        }
    }
    
    private func filterStoriesForAudience(stories: [Story], viewerId: String, completion: @escaping ([Story]) -> Void) {
        let group = DispatchGroup()
        var visibleIds: Set<String> = []
        let lock = NSLock()
        
        for story in stories {
            group.enter()
            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                if canView, let id = story.id {
                    lock.lock()
                    visibleIds.insert(id)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original de las historias
            let orderedVisibleStories = stories.filter { story in
                guard let id = story.id else { return false }
                return visibleIds.contains(id)
            }
            
            completion(orderedVisibleStories)
        }
    }

    
    func checkFollowButtonState() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        if let cachedState = FollowStateStore.shared.state(for: userId) {
            followButtonState = cachedState
            isFollowing = (cachedState == .following)
        }

        privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: self.userId)
                self.followButtonState = reconciledState
                self.isFollowing = (reconciledState == .following)
                FollowStateStore.shared.setState(reconciledState, for: self.userId)
            }
        }
    }

    func loadRelationshipManagementState() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else { return }

        privacyService.checkIfBestFriend(userId: currentUserId, friendId: userId) { [weak self] isBestFriend in
            DispatchQueue.main.async {
                self?.isInBestFriends = isBestFriend
            }
        }

        firestoreService.fetchMutedUserIds(userId: currentUserId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                self?.isMutedByCurrentUser = mutedIds.contains(self?.userId ?? "")
            }
        }

        privacyService.checkMutualConnection(user1: currentUserId, user2: userId) { [weak self] isMutual in
            DispatchQueue.main.async {
                self?.isMutualRelationship = isMutual
            }
        }

        firestoreService.fetchCustomLists(for: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let lists):
                    let matchingLists = lists.filter { $0.members.contains(self.userId) }
                    self.customListsContainingProfile = matchingLists
                    self.customListMembershipCount = matchingLists.count
                case .failure:
                    self.customListsContainingProfile = []
                    self.customListMembershipCount = 0
                }
            }
        }
    }

    func removeFromCustomList(_ list: CustomAudienceList) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let listId = list.id,
              currentUserId != userId,
              !isUpdatingLists else { return }

        isUpdatingLists = true
        firestoreService.removeMembersFromCustomList(
            listId: listId,
            ownerId: currentUserId,
            memberIds: [userId]
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingLists = false
                if error == nil {
                    self.customListsContainingProfile.removeAll { $0.id == list.id }
                    self.customListMembershipCount = self.customListsContainingProfile.count
                }
            }
        }
    }

    func toggleBestFriend() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId,
              !isUpdatingBestFriend else { return }

        isUpdatingBestFriend = true
        let shouldAdd = !isInBestFriends

        let completion: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingBestFriend = false
                if error == nil {
                    self.isInBestFriends = shouldAdd
                }
            }
        }

        if shouldAdd {
            bestFriendsService.addBestFriend(currentUserId: currentUserId, friendId: userId, completion: completion)
        } else {
            bestFriendsService.removeBestFriend(currentUserId: currentUserId, friendId: userId, completion: completion)
        }
    }

    func toggleMute() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId,
              !isUpdatingMute else { return }

        isUpdatingMute = true
        let shouldMute = !isMutedByCurrentUser

        firestoreService.db.collection("users").document(currentUserId).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            var muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any] ?? [:]
            var mutedUsers = Set((muteSettings["mutedUsers"] as? [String] ?? []).filter { !$0.isEmpty })

            if shouldMute {
                mutedUsers.insert(self.userId)
            } else {
                mutedUsers.remove(self.userId)
            }

            muteSettings["mutedUsers"] = Array(mutedUsers)

            self.firestoreService.db.collection("users").document(currentUserId).updateData([
                "muteSettings": muteSettings
            ]) { error in
                DispatchQueue.main.async {
                    self.isUpdatingMute = false
                    if error == nil {
                        self.isMutedByCurrentUser = shouldMute
                    }
                }
            }
        }
    }

    func registerVisit() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else {
            return
        }
        
        // Track the visit locally for affinity scoring
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .profileVisit, with: userId)
        }
        
        // ✅ UNA SOLA LÍNEA - Todo se maneja en FirestoreService
        firestoreService.registerVisit(visitorId: currentUserId, to: userId) { error in
            // Silently handle error
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Follow user con actualización inmediata de UI
    func followUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid, let userProfile = self.userProfile else { return }
        
        // Limpiar unfollow reciente si existe
        recentUnfollows.remove(userId)
        lastUnfollowTime.removeValue(forKey: userId)
        
        if userProfile.isPrivate {
            firestoreService.sendFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error {
                        return
                    }
                    self.followButtonState = .requestPending
                    FollowStateStore.shared.setState(.requestPending, for: userId)
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error {
                        return
                    }
                    
                    self.followButtonState = .following
                    self.isFollowing = true
                    FollowStateStore.shared.setState(.following, for: userId)
                    
                    // Actualizar UI inmediatamente si tengo permisos para ver admirers
                    if self.visibleConnectionTypes.canViewAdmirers,
                       let admirerIndex = self.admirers.firstIndex(where: { $0.id == userId }) {
                        let user = self.admirers.remove(at: admirerIndex)
                        if self.visibleConnectionTypes.canViewMutualConnections {
                            self.mutualConnections.append(user)
                        }
                    } else if self.visibleConnectionTypes.canViewConnections {
                        // Obtener usuario y agregarlo a conexiones si puedo verlas
                        self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                            if case .success(let user) = result {
                                DispatchQueue.main.async {
                                    if self?.visibleConnectionTypes.canViewConnections == true {
                                        self?.connections.append(user)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Unfollow user con actualización inmediata de UI
    func unfollowUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Marcar como unfollow reciente
        recentUnfollows.insert(userId)
        lastUnfollowTime[userId] = Date()
        
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                // Limpiar cache de unfollow si falló
                self.recentUnfollows.remove(userId)
                self.lastUnfollowTime.removeValue(forKey: userId)
                return
            }
            
            DispatchQueue.main.async {
                self.followButtonState = .canFollow
                self.isFollowing = false
                FollowStateStore.shared.setState(.canFollow, for: userId)
                
                // Actualizar UI inmediatamente respetando permisos de privacidad
                if self.visibleConnectionTypes.canViewMutualConnections,
                   let mutualIndex = self.mutualConnections.firstIndex(where: { $0.id == userId }) {
                    let user = self.mutualConnections.remove(at: mutualIndex)
                    if self.visibleConnectionTypes.canViewAdmirers {
                        self.admirers.append(user)
                    }
                } else if self.visibleConnectionTypes.canViewConnections,
                          let connectionIndex = self.connections.firstIndex(where: { $0.id == userId }) {
                    self.connections.remove(at: connectionIndex)
                }
            }
        }
    }

    func checkIfFollowing() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.fetchConnections(userId: currentUserId) { [weak self] result in
            guard let self = self else { return }
            if case .success(let connections) = result {
                let followingIds = connections.map { $0.userId }
                DispatchQueue.main.async {
                    self.isFollowing = followingIds.contains(self.userId)
                }
            }
        }
    }

    func checkIfBlocked() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.checkIfBlocked(currentUserId: currentUserId, targetUserId: userId) { [weak self] isBlockedByCurrentUser, isCurrentUserBlocked, error in
            guard let self = self else { return }
            if let error = error {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = isBlockedByCurrentUser
                self.isCurrentUserBlocked = isCurrentUserBlocked
                self.canViewContent = false
                self.isProfileUnavailable = isCurrentUserBlocked
            }
        }
    }

    func blockUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.blockUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = true
                self.isProfileUnavailable = true
                self.followButtonState = .blocked
                self.isFollowing = false
            }
        }
    }

    func unblockUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.unblockUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = false
                self.isProfileUnavailable = false
                self.checkFollowButtonState()
                self.fetchProfile()
            }
        }
    }
}

struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        UserProfileView(userId: "123")
    }
}

// MARK: - ✅ UserExpandableContentView para UserProfileView
struct UserExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    
    private let maxLines = 2
    private let maxCharacters = 15
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MomentHashtagText(
                content: isExpanded ? content : String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                textFont: .custom("Poppins-Regular", size: 14),
                hashtagFont: .custom("Poppins-SemiBold", size: 14),
                baseColor: .white.opacity(0.95),
                textAlignment: .center,
                shadowColor: .black.opacity(0.8),
                shadowRadius: 3,
                shadowX: 0,
                shadowY: 1,
                onHashtagTap: onHashtagTap
            )
            
            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("userProfile.seeLess", comment: "See less") : NSLocalizedString("userProfile.seeMore", comment: "See more"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(UserProfileColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(UserProfileColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
                .scaleEffect(isExpanded ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isExpanded)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

// MARK: - ProfileImageViewer
struct ProfileImageViewer: View {
    let profileImagePath: String?
    let username: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Fondo de cristal esmerilado (Glassmorphism)
            // No usamos ignoresSafeArea para que se vea el "sheet" flotando
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
            
            // Capa de "frost" (congelado) para efecto premium
            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.02)
            
            // Sutil resplandor de la marca (00A896) muy tenue
            LinearGradient(
                colors: [
                    Color(hex: "00A896").opacity(0.02),
                    Color.clear,
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack {
                Spacer()
                
                // Imagen de perfil
                if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                    KFImage(url)
                        .placeholder {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 300, height: 300)
                                .overlay(
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 120))
                                        .foregroundColor(.gray.opacity(0.6))
                                )
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width - 40)
                        .clipShape(Circle())
                        .scaleEffect(scale)
                        .offset(dragOffset)
                        .gesture(
                            SimultaneousGesture(
                                // Gesture de zoom
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(0.5, min(3.0, value))
                                    },
                                // Gesture de arrastre
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        // Si se arrastra hacia abajo lo suficiente, cerrar
                                        if value.translation.height > 100 {
                                            dismiss()
                                        } else {
                                            withAnimation(.spring()) {
                                                dragOffset = .zero
                                            }
                                        }
                                    }
                            )
                        )
                } else {
                    // Placeholder si no hay imagen
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 300, height: 300)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 120))
                                    .foregroundColor(.secondary)
                                Text(username)
                                    .font(.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(.primary)
                            }
                        )
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                }
                
                Spacer()
            }
        }
        .onTapGesture {
            dismiss()
        }
    }
}
