import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import Combine

fileprivate func isPerActorSocialNotification(_ type: NotificationType) -> Bool {
    switch type {
    case .newFollower, .mutualConnection, .followRequest, .requestAccepted:
        return true
    default:
        return false
    }
}

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @StateObject private var storyViewModel = StoryViewModel() // ✅ AGREGADO
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme // ✅ AGREGADO
    @State private var selectedMoment: Moment?
    @State private var storyViewerPresentation: StoryViewerPresentation?
    @State private var selectedConversation: Conversation?
    @State private var showChat = false
    @Namespace private var tabAnimation
    let onNotificationsCleared: (() -> Void)?

    private struct StoryViewerPresentation: Identifiable {
        let id = UUID()
        let story: Story
        let authorId: String
    }
    
    init(onNotificationsCleared: (() -> Void)? = nil) {
        self.onNotificationsCleared = onNotificationsCleared
    }

    enum NotificationTab: String, CaseIterable {
        case all = "notifications.tab.all"
        case reactions = "notifications.tab.reactions"
        case follows = "notifications.tab.follows"
        case comments = "notifications.tab.comments"
        case storyReactions = "notifications.tab.stories"
        case requests = "notifications.tab.requests"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBarView
                contentView
            }
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .navigationDestination(isPresented: $showChat) {
                chatDestination
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("notifications.title")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(
                colorScheme == .dark ?
                Color(hex: "0B1215").opacity(0.72) :
                Color(hex: "FAF9F6").opacity(0.9),
                for: .navigationBar
            )
        }
        .onAppear {
            Task {
                await viewModel.refreshNotifications()
            }
            clearNotificationsAutomatically()
        }
        .onDisappear {
            NotificationBadgeService.shared.clearNotificationBadge()
            onNotificationsCleared?()
        }
        .alert(isPresented: $viewModel.showError) {
            Alert(
                title: Text("notifications.error.title"),
                message: Text(viewModel.errorMessage),
                dismissButton: .default(Text("notifications.ok"))
            )
        }
        .sheet(item: $selectedMoment) { moment in
            MomentDetailView(moment: moment)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $storyViewerPresentation) { presentation in
            StoryViewerScreen(
                story: presentation.story,
                storyCount: 1,
                storyIndex: 0,
                screenSize: UIScreen.main.bounds.size,
                storyViewModel: storyViewModel,
                showingReportSheet: .constant(false),
                showingBlockConfirmation: .constant(false),
                onReportStory: { },
                onBlockUser: { },
                onNext: {
                    storyViewerPresentation = nil
                },
                onPrevious: { },
                onClose: { storyViewerPresentation = nil },
                onProfileTap: { }
            )
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseStoryViewer"))) { _ in
                storyViewerPresentation = nil
            }
        }
    }
    
    private func clearNotificationsAutomatically() {
        
        // 1. Marcar notificaciones como vistas en Firebase
        viewModel.markAllAsRead()
        
        // 2. Actualizar badge service
        NotificationBadgeService.shared.clearNotificationBadge()
        
    }
    
    // ✅ TAB BAR ADAPTATIVO
    @ViewBuilder private var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(NotificationTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 7) {
                            HStack(spacing: 6) {
                                Text(NSLocalizedString(tab.rawValue, comment: "Notification tab"))
                                    .font(.system(size: 14, weight: viewModel.selectedTab == tab ? .semibold : .medium))
                                    .foregroundColor(
                                    viewModel.selectedTab == tab ?
                                        (colorScheme == .dark ? .white : .black) :
                                        .gray.opacity(0.82)
                                    )
                                
                                // Badge para solicitudes pendientes
                                if tab == .requests && viewModel.pendingRequestsCount > 0 {
                                    Text("\(viewModel.pendingRequestsCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                            }
                            
                            if viewModel.selectedTab == tab {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        colorScheme == .dark ? Color.white : Color.black
                                    )
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "tab", in: tabAnimation)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.clear)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var contentView: some View {
        if viewModel.isLoading {
            return AnyView(loadingView)
        } else if filteredNotifications.isEmpty {
            return AnyView(emptyStateView)
        } else {
            return AnyView(notificationsListView)
        }
    }

    private var filteredNotifications: [NotificationGroup] {
        return viewModel.groupedNotifications
    }

    // ✅ LOADING ADAPTATIVO
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    NotificationSkeletonRow(colorScheme: colorScheme) // ✅ PASADO colorScheme
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    // ✅ EMPTY STATE ADAPTATIVO
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: colorScheme == .dark ? [
                            Color.gray.opacity(0.6),
                            Color(hex: "007AFF").opacity(0.4)
                        ] : [
                            Color.gray.opacity(0.8),
                            Color(hex: "007AFF").opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text(emptyStateTitle)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8)) // ✅ ADAPTATIVO
                
                Text(emptyStateMessage)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7)) // ✅ ADAPTATIVO
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private func getEmptyStateIcon() -> String {
        switch viewModel.selectedTab {
        case .comments: return "text.bubble.slash"
        case .storyReactions: return "heart.slash"
        case .requests: return "person.2.slash"
        case .reactions: return "heart.slash"
        case .follows: return "person.badge.plus"
        default: return "bell.slash"
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.selectedTab {
        case .comments: return NSLocalizedString("notifications.empty.comments", comment: "No comments")
        case .storyReactions: return NSLocalizedString("notifications.empty.storyReactions", comment: "No story reactions")
        case .requests: return NSLocalizedString("notifications.empty.requests", comment: "No requests")
        case .reactions: return NSLocalizedString("notifications.empty.reactions", comment: "No reactions")
        case .follows: return NSLocalizedString("notifications.empty.follows", comment: "No new followers")
        default: return NSLocalizedString("notifications.empty.default", comment: "No notifications")
        }
    }

    private var emptyStateMessage: String {
        switch viewModel.selectedTab {
        case .comments: return NSLocalizedString("notifications.empty.comments.message", comment: "Empty comments message")
        case .storyReactions: return NSLocalizedString("notifications.empty.storyReactions.message", comment: "Empty story reactions message")
        case .requests: return NSLocalizedString("notifications.empty.requests.message", comment: "Empty requests message")
        case .reactions: return NSLocalizedString("notifications.empty.reactions.message", comment: "Empty reactions message")
        case .follows: return NSLocalizedString("notifications.empty.follows.message", comment: "Empty follows message")
        default: return NSLocalizedString("notifications.empty.default.message", comment: "Empty default message")
        }
    }

    private var notificationsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.dateKeys, id: \.self) { dateKey in
                    Section {
                        ForEach(viewModel.groupedByDate[dateKey] ?? []) { group in
                            EnhancedNotificationRow(
                                group: group,
                                viewModel: viewModel,
                                colorScheme: colorScheme,
                                onTapAction: {
                                    handleNotificationTap(group: group)
                                }
                            )
                        }
                    } header: {
                        DateHeaderView(dateString: dateKey, colorScheme: colorScheme)
                    }
                }
                
                // ✅ Indicador de carga más notificaciones
                if viewModel.canLoadMore {
                    Button(NSLocalizedString("notifications.loadMore", comment: "Load more button")) {
                        viewModel.loadMoreNotifications()
                    }
                    .disabled(viewModel.isLoadingMore)
                    .padding()
                    
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    
    struct DateHeaderView: View {
        let dateString: String
        let colorScheme: ColorScheme
        
        var body: some View {
            HStack {
                Text(localizedDateString(dateString))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        }
        
        private func localizedDateString(_ dateString: String) -> String {
            switch dateString {
            case "New": return NSLocalizedString("notifications.section.new", comment: "New")
            case "This Week": return NSLocalizedString("notifications.section.this_week", comment: "This Week")
            case "This Month": return NSLocalizedString("notifications.section.this_month", comment: "This Month")
            case "Earlier": return NSLocalizedString("notifications.section.earlier", comment: "Earlier")
            default: return dateString
            }
        }
    }

    private func handleNotificationTap(group: NotificationGroup) {
        let firstNotification = group.notifications.first!
        switch firstNotification.type {
        case .like, .reaction, .comment, .photoTag: // ✅ AÑADIDO .photoTag
            if let momentId = firstNotification.momentId {
                fetchMoment(momentId: momentId, authorId: momentAuthorId(for: firstNotification))
            }
        case .mention: // ✅ Manejar menciones (cualquier contenido)
            if let storyId = firstNotification.storyId {
                navigateToStory(
                    storyId: storyId,
                    authorId: storyAuthorId(for: firstNotification)
                )
            } else if let momentId = firstNotification.momentId {
                fetchMoment(momentId: momentId, authorId: momentAuthorId(for: firstNotification))
            }
        case .newFollower, .followRequest, .mutualConnection, .requestAccepted:
            // Handle follower-related notifications
            break
        case .storyReaction:
            // La historia reaccionada es del usuario actual (es quien recibe la notificación).
            if let storyId = firstNotification.storyId {
                navigateToStory(storyId: storyId, authorId: Auth.auth().currentUser?.uid)
            }
        case .message:
            if let conversationId = firstNotification.conversationId ?? firstNotification.momentId {
                fetchAndNavigateToChat(conversationId: conversationId)
            }
        case .echoSuggestion:
            // 🌊 Navigate to Echo Viewer
            if let echoId = firstNotification.echoId {
                NotificationNavigationService.shared.pendingNavigation = .echo(echoId)
            }
        case .storyChainContinued:
            // 🔗 Navigate to Story Chain
            if let chainId = firstNotification.chainId {
                let chainTitle = firstNotification.chainTitle ?? ""
                NotificationNavigationService.shared.pendingNavigation = .storyChain(chainId, chainTitle)
            }
        case .dataExportReady:
            guard
                let rawUrl = firstNotification.downloadURL,
                let url = URL(string: rawUrl),
                UIApplication.shared.canOpenURL(url)
            else { return }
            UIApplication.shared.open(url)
        case .mediaModeration:
            // 🛡️ Navegar al momento moderado
            if let momentId = firstNotification.momentId {
                fetchMoment(momentId: momentId, authorId: momentAuthorId(for: firstNotification))
            }
        }
    }

    private func momentAuthorId(for notification: Notification) -> String? {
        notification.targetAuthorId
    }

    private func fetchMoment(momentId: String, authorId: String? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ownerId = authorId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firestoreService = FirestoreService()
        firestoreService.fetchMoment(momentId: momentId, userId: ownerId?.isEmpty == false ? ownerId! : userId) { result in
            switch result {
            case .success(let moment):
                DispatchQueue.main.async {
                    self.selectedMoment = moment
                }
            case .failure(_):
                break
            }
        }
    }
    
    // ✅ Navegación real a historias
    private func storyAuthorId(for notification: Notification) -> String? {
        notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    }

    private func navigateToStory(storyId: String, authorId: String?) {
        
        // ✅ Buscar la historia usando StoryViewModel
        let targetAuthorId = authorId?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ✅ Buscar en las historias existentes del StoryViewModel
        for (authorId, stories) in storyViewModel.stories {
            if let story = stories.first(where: { $0.id == storyId }) {
                DispatchQueue.main.async {
                    self.presentStory(story, authorId: authorId)
                }
                return
            }
        }
        
        // ✅ Si no está en cache, buscar en Firestore
        let db = Firestore.firestore()
        guard let targetAuthorId, !targetAuthorId.isEmpty else { return }

        db.collection("users").document(targetAuthorId).collection("stories").document(storyId).getDocument { snapshot, error in
            if error != nil {
                return
            }
            
            guard let snapshot,
                  let story = try? snapshot.data(as: Story.self) else {
                return
            }
            
            DispatchQueue.main.async {
                self.presentStory(story, authorId: targetAuthorId)
            }
        }
    }

    private func presentStory(_ story: Story, authorId: String) {
        let resolvedAuthorId = story.authorId.isEmpty ? authorId : story.authorId
        storyViewModel.stories[resolvedAuthorId] = [story]
        storyViewerPresentation = StoryViewerPresentation(story: story, authorId: resolvedAuthorId)
    }
    
    // ✅ Navegación a chat
    private func fetchAndNavigateToChat(conversationId: String) {
        let db = Firestore.firestore()
        db.collection("conversations").document(conversationId).getDocument { snapshot, error in
            if let snapshot = snapshot, snapshot.exists,
               let conversation = try? snapshot.data(as: Conversation.self) {
                DispatchQueue.main.async {
                    self.selectedConversation = conversation
                    self.showChat = true
                }
            }
        }
    }
    
    // ✅ Destino del chat seguro
    @ViewBuilder
    private var chatDestination: some View {
        if let conversation = selectedConversation {
            ChatRecoveryGateView(onCancel: {
                showChat = false
            }) {
                GlassmorphicChatView(conversation: conversation)
            }
        } else {
            EmptyView()
        }
    }
}

struct NotificationGroup: Identifiable {
    let id: String
    let notifications: [Notification]
    var isUnread: Bool {
        notifications.contains { $0.isPending }
    }
}

// ✅ ENHANCED NOTIFICATION ROW ADAPTATIVO
struct EnhancedNotificationRow: View {
    let group: NotificationGroup
    @ObservedObject var viewModel: NotificationsViewModel
    let colorScheme: ColorScheme
    let onTapAction: () -> Void
    @State private var showProfile = false
    @State private var showStories = false
    @State private var momentImagePath: String?
    @State private var storyImagePath: String?
    @State private var isLoadingMomentImage: Bool = false
    @State private var isLoadingStoryImage: Bool = false
    @State private var momentImageLoadFailed: Bool = false
    @State private var storyImageLoadFailed: Bool = false
    @State private var followButtonState: FollowButtonState = .canFollow
    @State private var isPressed: Bool = false
    @State private var senderUsernameOverride: String?
    @State private var showingUnfollowConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar con Story Ring consistente con el resto de la app
            if isModerationNotification {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(colorScheme == .dark ? "SplashLogoLight" : "SplashLogoDark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1), lineWidth: 1)
                )
            } else if let senderId = group.notifications.first?.senderId, !senderId.isEmpty {
                StoryRingAvatarView(
                    userId: senderId,
                    size: 42,
                    lineWidth: 2.1,
                    showBaseStroke: true,
                    baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12),
                    baseStrokeWidth: 1,
                    onTap: { hasStory in
                        if hasStory {
                            showStories = true
                        } else {
                            showProfile = true
                        }
                    }
                )
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Texto compacto
                Text(messageForGroup(group))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                
                Text(group.notifications.first!.timestamp, style: .relative)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray.opacity(0.72))
            }
            
            Spacer()
            
            trailingContent

            // Indicador de no leído (estilo IG): punto de acento mientras la notificación esté pendiente.
            if group.isUnread {
                Circle()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 8, height: 8)
                    .transition(.opacity)
                    .accessibilityLabel(Text(NSLocalizedString("notifications.unread.indicator", comment: "Unread notification indicator")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isPressed
                ? Color.primary.opacity(0.04)
                : (group.isUnread ? (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, 70)
        }
        .onTapGesture {
            if opensSenderProfileOnTap {
                showProfile = true
            } else {
                onTapAction()
            }
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: group.notifications.first!.senderId)
        }
        .fullScreenCover(isPresented: $showStories) {
            StoriesView(startWithUserId: .constant(group.notifications.first?.senderId ?? ""))
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
        .onAppear {
            resolveSenderDisplayData()
            setupPreviews()
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let targetUserId = group.notifications.first?.senderId,
                  let userId = notification.userInfo?["userId"] as? String,
                  userId == targetUserId,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followButtonState = state
        }
    }

    private var opensSenderProfileOnTap: Bool {
        guard let type = group.notifications.first?.type else { return false }
        return type == .newFollower
            || type == .followRequest
            || type == .mutualConnection
            || type == .requestAccepted
    }
    
    private func setupPreviews() {
        let first = group.notifications.first!
        if first.type == .like || first.type == .comment || first.type == .reaction || first.type == .photoTag || isMomentMention(first) { // ✅ AÑADIDO .photoTag
            if let momentId = first.momentId {
                fetchMomentPreview(
                    momentId: momentId,
                    authorId: momentAuthorId(for: first)
                )
            }
        } else if first.type == .storyReaction || first.type == .storyChainContinued || isStoryMention(first) {
            // El backend ya adjunta la miniatura real (poster de vídeo o foto): úsala sin pedir nada.
            if let preview = first.storyPreviewUrl, !preview.isEmpty {
                storyImagePath = preview
                isLoadingStoryImage = false
                storyImageLoadFailed = false
            } else if let storyId = first.storyId {
                fetchStoryPreview(storyId: storyId, authorId: resolvedStoryAuthorId(for: first))
            }
        }
        
        if first.type == .newFollower || first.type == .mutualConnection {
            checkFollowingStatus()
        }
    }

    // ✅ TRAILING CONTENT ADAPTATIVO
    private var trailingContent: some View {
        Group {
            switch group.notifications.first?.type {
            case .like, .comment, .reaction, .photoTag: // ✅ AÑADIDO .photoTag
                if let path = momentImagePath, let url = URL(string: path), !momentImageLoadFailed {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(Color(hex: "007AFF"))
                                )
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    colorScheme == .dark ?
                                    Color.white.opacity(0.2) :
                                    Color.black.opacity(0.1),
                                    lineWidth: 1
                                ) // ✅ ADAPTATIVO
                        )
                        .onTapGesture {
                            onTapAction()
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(
                                    colorScheme == .dark ?
                                    .white.opacity(0.6) :
                                    .black.opacity(0.5)
                                ) // ✅ ADAPTATIVO
                                .font(.system(size: 16))
                        )
                }

            case .mention:
                if let first = group.notifications.first, isStoryMention(first) {
                    storyMentionThumbnail
                } else if let path = momentImagePath, let url = URL(string: path), !momentImageLoadFailed {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(Color(hex: "007AFF"))
                                )
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "at")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.55))
                                .font(.system(size: 16, weight: .semibold))
                        )
                }

            case .storyReaction:
                HStack(spacing: 8) {
                    if let path = storyImagePath, let url = URL(string: path), !storyImageLoadFailed {
                        ZStack {
                            KFImage(url)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .tint(Color(hex: "007AFF"))
                                        )
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.pink, .orange, .yellow]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                        .white.opacity(0.6) :
                                        .black.opacity(0.5)
                                    ) // ✅ ADAPTATIVO
                                    .font(.system(size: 16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.pink, .orange, .yellow]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                    }
                    
                    if let reaction = group.notifications.first?.reaction {
                        Text(reaction)
                            .font(.system(size: 20))
                            .frame(width: 24, height: 24)
                    }
                }

            case .storyChainContinued:
                if let path = storyImagePath, let url = URL(string: path), !storyImageLoadFailed {
                    ZStack(alignment: .bottomTrailing) {
                        KFImage(url)
                            .placeholder {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(Color(hex: "007AFF"))
                                    )
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )

                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                    .frame(width: 44, height: 44)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(
                                    colorScheme == .dark ?
                                    .white.opacity(0.72) :
                                    .black.opacity(0.62)
                                )
                                .font(.system(size: 17, weight: .semibold))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                }

            case .followRequest:
                HStack(spacing: 8) {
                    Button(NSLocalizedString("notifications.accept", comment: "Accept button")) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.acceptFollowRequest(group: group)
                        }
                    }
                    .buttonStyle(GlassmorphicButtonStyle(
                        color: Color(hex: "007AFF"),
                        colorScheme: colorScheme // ✅ PASADO colorScheme
                    ))
                    
                    Button(NSLocalizedString("notifications.reject", comment: "Reject button")) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.rejectFollowRequest(group: group)
                        }
                    }
                    .buttonStyle(GlassmorphicButtonStyle(
                        color: .red,
                        colorScheme: colorScheme // ✅ PASADO colorScheme
                    ))
                }

            case .newFollower, .mutualConnection:
                Button(action: {
                    toggleFollow()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: notificationFollowIcon)
                            .font(.system(size: 12, weight: .semibold))

                        Text(notificationFollowTitle)
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .liquidGlass(in: Capsule(), interactive: followButtonState.isActionable)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!followButtonState.isActionable)
                .opacity(notificationFollowIsPassive ? 0.78 : 1)

            case .requestAccepted:
                Button(action: { showProfile = true }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

            case .echoSuggestion:
                // 🌊 Echo notification preview with Nova Spark styling
                Button(action: onTapAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        
                        Text(NSLocalizedString("notifications.echo.viewAction", comment: "View Echo button"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [.orange.opacity(0.2), .yellow.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.orange.opacity(0.6), .yellow.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())

            case .dataExportReady:
                Button(action: onTapAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(NSLocalizedString("notifications.export.download", comment: "Download export button"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "007AFF"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "007AFF").opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

            case .mediaModeration:
                // 🛡️ Icono de moderación limpio
                Button(action: onTapAction) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.82))
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PlainButtonStyle())

            default:
                EmptyView()
            }
        }
    }

    private var storyMentionThumbnail: some View {
        Group {
            if let path = storyImagePath, let url = URL(string: path), !storyImageLoadFailed {
                KFImage(url)
                    .placeholder {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.pink, .orange, .yellow]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.55))
                            .font(.system(size: 16, weight: .semibold))
                    )
            }
        }
    }

    private var isModerationNotification: Bool {
        group.notifications.first?.type == .mediaModeration
    }

    private func isStoryMention(_ notification: Notification) -> Bool {
        notification.type == .mention && (notification.mentionContext == "story" || notification.storyId != nil)
    }

    private func isMomentMention(_ notification: Notification) -> Bool {
        notification.type == .mention && !isStoryMention(notification) && notification.momentId != nil
    }

    private func storyAuthorId(for notification: Notification) -> String {
        notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    }

    private func momentAuthorId(for notification: Notification) -> String? {
        notification.targetAuthorId
    }

    // MARK: - Métodos auxiliares (mantenidos del original)
    
    // Resuelve el dueño real de la historia. En storyReaction la historia es del
    // usuario actual (es quien recibe la reacción), no del remitente.
    private func resolvedStoryAuthorId(for notification: Notification) -> String {
        if let authorId = notification.storyAuthorId, !authorId.isEmpty {
            return authorId
        }
        if notification.type == .storyReaction {
            return Auth.auth().currentUser?.uid ?? notification.senderId
        }
        return notification.targetAuthorId ?? notification.senderId
    }

    private func fetchStoryPreview(storyId: String, authorId: String) {
        let userId = authorId
        guard !userId.isEmpty else { return }
        isLoadingStoryImage = true
        
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, error in
                if error != nil {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                    return
                }
                
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                    return
                }
                
                if let previewURL = storyPreviewURL(from: data) {
                    DispatchQueue.main.async {
                        self.storyImagePath = previewURL
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                }
            }
    }

    private func storyPreviewURL(from data: [String: Any]) -> String? {
        let mediaItem = data["mediaItem"] as? [String: Any]
        let mediaType = mediaItem?["type"] as? String

        if mediaType == MediaItem.MediaType.image.rawValue {
            return nonEmptyString(mediaItem?["url"])
                ?? nonEmptyString(data["imagePath"])
        }

        if mediaType == MediaItem.MediaType.video.rawValue {
            return nonEmptyString(mediaItem?["thumbnailUrl"])
                ?? nonEmptyString(data["backgroundFrameURL"])
                ?? nonEmptyString(data["backgroundBlurredFrameURL"])
        }

        return nonEmptyString(data["imagePath"])
            ?? nonEmptyString(mediaItem?["thumbnailUrl"])
            ?? nonEmptyString(data["backgroundFrameURL"])
            ?? nonEmptyString(data["backgroundBlurredFrameURL"])
            ?? nonEmptyString(mediaItem?["url"])
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func messageForGroup(_ group: NotificationGroup) -> AttributedString {
        let firstNotification = group.notifications.first!
        let effectiveSenderUsername = senderDisplayName(for: firstNotification)
        let reactionAggregateCount = (firstNotification.type == .reaction)
            ? max(1, firstNotification.reactionCount ?? group.notifications.count)
            : group.notifications.count
        let hasMultipleActors: Bool
        if firstNotification.type == .reaction {
            hasMultipleActors = reactionAggregateCount > 1
        } else if firstNotification.type == .newFollower || firstNotification.type == .mutualConnection {
            // Agregación: "X y N más comenzaron a seguirte" / "...conexión mutua con X y N más"
            // (grupo ya deduplicado por persona)
            hasMultipleActors = group.notifications.count > 1
        } else if isPerActorSocialNotification(firstNotification.type) {
            // requestAccepted / followRequest: una fila por persona (evento o acción individual)
            hasMultipleActors = false
        } else {
            hasMultipleActors = group.notifications.count > 1
        }

        if hasMultipleActors {
            switch firstNotification.type {
            case .like:
                return AttributedString(String(format: NSLocalizedString("notifications.message.like.multiple", comment: "Multiple likes"), effectiveSenderUsername, group.notifications.count - 1))
            case .reaction:
                // ✅ Mostrar el emoji de la reacción en grande
                if let reactionString = firstNotification.reaction,
                   let reactionType = ReactionType(rawValue: reactionString) {
                    let text = String(format: NSLocalizedString("notifications.message.reaction.multiple.withType", comment: "Multiple reactions with type"), effectiveSenderUsername, reactionType.icon, reactionAggregateCount - 1)
                    var attributed = AttributedString(text)
                    if let range = attributed.range(of: reactionType.icon) {
                        attributed[range].font = .system(size: 18) // Emoji más grande
                    }
                    return attributed
                } else {
                    return AttributedString(String(format: NSLocalizedString("notifications.message.reaction.multiple", comment: "Multiple reactions"), effectiveSenderUsername, reactionAggregateCount - 1))
                }
            case .mention:
                return mentionMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: group.notifications.count - 1
                )
            case .newFollower:
                return AttributedString(String(format: NSLocalizedString("notifications.message.follow.multiple", comment: "Multiple follows"), effectiveSenderUsername, group.notifications.count - 1))
            case .followRequest:
                return AttributedString(String(format: NSLocalizedString("notifications.message.request.multiple", comment: "Multiple requests"), effectiveSenderUsername, group.notifications.count - 1))
            case .requestAccepted:
                return AttributedString(String(format: NSLocalizedString("notifications.message.requestAccepted.multiple", comment: "Multiple accepted requests"), effectiveSenderUsername, group.notifications.count - 1))
            case .mutualConnection:
                return AttributedString(String(format: NSLocalizedString("notifications.message.mutual.multiple", comment: "Multiple mutual connections"), effectiveSenderUsername, group.notifications.count - 1))
            case .comment:
                return commentMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: group.notifications.count - 1
                )
            case .storyReaction:
                return AttributedString(String(format: NSLocalizedString("notifications.message.story.multiple", comment: "Multiple story reactions"), effectiveSenderUsername, group.notifications.count - 1))
            case .message:
                return AttributedString(String(format: NSLocalizedString("notifications.message.message.multiple", comment: "Multiple messages"), effectiveSenderUsername, group.notifications.count - 1))
            case .photoTag:
                return photoTagMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: group.notifications.count - 1
                )
            case .echoSuggestion:
                return AttributedString(NSLocalizedString("notifications.message.echo", comment: "Echo suggestion"))
            case .dataExportReady:
                let exportMessage = firstNotification.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if exportMessage.isEmpty {
                    return AttributedString(NSLocalizedString("notifications.message.dataExportReady", comment: "Data export ready notification"))
                }
                return AttributedString(exportMessage)
            case .storyChainContinued:
                let chainTitle = firstNotification.chainTitle ?? ""
                let isCreator = firstNotification.chainRole != "participant"
                let key = isCreator
                    ? "notifications.message.storyChain.creator.multiple"
                    : "notifications.message.storyChain.participant.multiple"
                return AttributedString(String(format: NSLocalizedString(key, comment: "Multiple story chain continuations"), effectiveSenderUsername, chainTitle, group.notifications.count - 1))
            case .mediaModeration:
                return AttributedString(NSLocalizedString("notifications.message.mediaModeration", comment: "Media moderation notification"))
            }
        } else {
            switch firstNotification.type {
            case .like:
                return AttributedString(String(format: NSLocalizedString("notifications.message.like.single", comment: "Single like"), effectiveSenderUsername))
            case .reaction:
                // ✅ Mostrar el emoji de la reacción en grande
                if let reactionString = firstNotification.reaction,
                   let reactionType = ReactionType(rawValue: reactionString) {
                    let text = String(format: NSLocalizedString("notifications.message.reaction.single.withType", comment: "Single reaction with type"), effectiveSenderUsername, reactionType.icon)
                    var attributed = AttributedString(text)
                    if let range = attributed.range(of: reactionType.icon) {
                        attributed[range].font = .system(size: 18) // Emoji más grande
                    }
                    return attributed
                } else {
                    return AttributedString(String(format: NSLocalizedString("notifications.message.reaction.single", comment: "Single reaction"), effectiveSenderUsername))
                }
            case .mention:
                return mentionMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: nil
                )
            case .newFollower:
                return AttributedString(String(format: NSLocalizedString("notifications.message.follow.single", comment: "Single follow"), effectiveSenderUsername))
            case .followRequest:
                return AttributedString(String(format: NSLocalizedString("notifications.message.request.single", comment: "Single request"), effectiveSenderUsername))
            case .requestAccepted:
                return AttributedString(String(format: NSLocalizedString("notifications.message.requestAccepted.single", comment: "Single accepted request"), effectiveSenderUsername))
            case .mutualConnection:
                return AttributedString(String(format: NSLocalizedString("notifications.message.mutual.single", comment: "Single mutual connection"), effectiveSenderUsername))
            case .comment:
                return commentMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: nil
                )
            case .storyReaction:
                return AttributedString(String(format: NSLocalizedString("notifications.message.story.single", comment: "Single story reaction"), effectiveSenderUsername))
            case .message:
                return AttributedString(String(format: NSLocalizedString("notifications.message.message.single", comment: "Single message"), effectiveSenderUsername))
            case .photoTag:
                return photoTagMessage(
                    for: firstNotification,
                    senderUsername: effectiveSenderUsername,
                    additionalCount: nil
                )
            case .echoSuggestion:
                return AttributedString(NSLocalizedString("notifications.message.echo", comment: "Echo suggestion"))
            case .dataExportReady:
                let exportMessage = firstNotification.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if exportMessage.isEmpty {
                    return AttributedString(NSLocalizedString("notifications.message.dataExportReady", comment: "Data export ready notification"))
                }
                return AttributedString(exportMessage)
            case .storyChainContinued:
                let chainTitle = firstNotification.chainTitle ?? ""
                let isCreator = firstNotification.chainRole != "participant"
                let totalParts = firstNotification.totalParts ?? firstNotification.chainPosition ?? 1
                let key = isCreator
                    ? "notifications.message.storyChain.creator.single"
                    : "notifications.message.storyChain.participant.single"
                return AttributedString(String(format: NSLocalizedString(key, comment: "Single story chain continuation"), effectiveSenderUsername, chainTitle, totalParts))
            case .mediaModeration:
                return AttributedString(NSLocalizedString("notifications.message.mediaModeration", comment: "Media moderation notification"))
            }
        }
    }

    private func mentionMessage(
        for notification: Notification,
        senderUsername: String,
        additionalCount: Int?
    ) -> AttributedString {
        let context = notification.mentionContext
            ?? (notification.storyId != nil ? "story" : (notification.commentId != nil ? "comment" : "moment"))

        let keyPrefix: String
        switch context {
        case "story":
            keyPrefix = "notifications.message.mention.story"
        case "comment":
            keyPrefix = notification.targetAuthorUsername?.isEmpty == false
                ? "notifications.message.mention.comment.withAuthor"
                : "notifications.message.mention.comment"
        default:
            keyPrefix = "notifications.message.mention.moment"
        }

        if let additionalCount {
            if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
                return AttributedString(
                    String(
                        format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple contextual comment mentions with moment author"),
                        senderUsername,
                        additionalCount,
                        targetAuthorUsername
                    )
                )
            }

            return AttributedString(
                String(
                    format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple contextual mentions"),
                    senderUsername,
                    additionalCount
                )
            )
        }

        if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
            return AttributedString(
                String(
                    format: NSLocalizedString("\(keyPrefix).single", comment: "Single contextual comment mention with moment author"),
                    senderUsername,
                    targetAuthorUsername
                )
            )
        }

        return AttributedString(
            String(
                format: NSLocalizedString("\(keyPrefix).single", comment: "Single contextual mention"),
                senderUsername
            )
        )
    }

    private func photoTagMessage(
        for notification: Notification,
        senderUsername: String,
        additionalCount: Int?
    ) -> AttributedString {
        let momentTitle = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let additionalCount {
            if let momentTitle, !momentTitle.isEmpty {
                return AttributedString(
                    String(
                        format: NSLocalizedString("notifications.message.tagged.withTitle.multiple", comment: "Multiple photo tags with moment title"),
                        senderUsername,
                        additionalCount,
                        momentTitle
                    )
                )
            }

            return AttributedString(
                String(
                    format: NSLocalizedString("notifications.message.tagged.multiple", comment: "Multiple photo tags"),
                    senderUsername,
                    additionalCount
                )
            )
        }

        if let momentTitle, !momentTitle.isEmpty {
            return AttributedString(
                String(
                    format: NSLocalizedString("notifications.message.tagged.withTitle.single", comment: "Single photo tag with moment title"),
                    senderUsername,
                    momentTitle
                )
            )
        }

        return AttributedString(
            String(
                format: NSLocalizedString("notifications.message.tagged.single", comment: "Single photo tag"),
                senderUsername
            )
        )
    }

    private func commentMessage(
        for notification: Notification,
        senderUsername: String,
        additionalCount: Int?
    ) -> AttributedString {
        let keyPrefix = notification.mentionContext == "reply"
            ? "notifications.message.reply"
            : "notifications.message.comment"

        if let additionalCount {
            return AttributedString(
                String(
                    format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple comments or replies"),
                    senderUsername,
                    additionalCount
                )
            )
        }

        return AttributedString(
            String(
                format: NSLocalizedString("\(keyPrefix).single", comment: "Single comment or reply"),
                senderUsername
            )
        )
    }

    private func senderDisplayName(for notification: Notification) -> String {
        if let senderUsernameOverride, !senderUsernameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return senderUsernameOverride
        }
        let username = notification.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if username.isEmpty {
            return "Alguien"
        }
        return username
    }

    private func resolveSenderDisplayData() {
        guard let senderId = group.notifications.first?.senderId, !senderId.isEmpty else { return }
        let needsUsernameResolution: Bool = {
            guard let current = group.notifications.first?.senderUsername else { return true }
            let normalized = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || normalized == "alguien"
        }()
        if !needsUsernameResolution { return }

        let firestoreService = FirestoreService()
        firestoreService.fetchUser(userId: senderId) { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    if !user.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.senderUsernameOverride = user.username
                    }
                }
            case .failure:
                break
            }
        }
    }

    private func fetchMomentPreview(momentId: String, authorId: String? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ownerId = authorId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firestoreService = FirestoreService()
        isLoadingMomentImage = true
        firestoreService.fetchMoment(momentId: momentId, userId: ownerId?.isEmpty == false ? ownerId! : userId) { result in
            switch result {
            case .success(let fetchedMoment):
                DispatchQueue.main.async {
                    if let previewPath = fetchedMoment.previewImageURLString, !previewPath.isEmpty {
                        self.loadMomentImage(from: previewPath)
                    } else {
                        self.isLoadingMomentImage = false
                        self.momentImageLoadFailed = true
                    }
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = true
                }
            }
        }
    }

    private func loadMomentImage(from path: String) {
        isLoadingMomentImage = true
        guard let url = URL(string: path) else {
            DispatchQueue.main.async {
                self.isLoadingMomentImage = false
                self.momentImageLoadFailed = true
            }
            return
        }

        ImageDownloader.default.downloadImage(with: url) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.momentImagePath = path
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = false
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = true
                }
            }
        }
    }

    private func checkFollowingStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUserId = group.notifications.first?.senderId else { return }

        if let cachedState = FollowStateStore.shared.state(for: targetUserId) {
            followButtonState = cachedState
        }
        
        PrivacyService().getFollowButtonState(viewerId: currentUserId, targetUserId: targetUserId) { state in
            DispatchQueue.main.async {
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: targetUserId)
                self.followButtonState = reconciledState
                FollowStateStore.shared.setState(reconciledState, for: targetUserId)
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
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUserId = group.notifications.first?.senderId else { return }
        
        if followButtonState == .following {
            viewModel.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.followButtonState = .canFollow
                        FollowStateStore.shared.setState(.canFollow, for: targetUserId)
                    }
                }
            }
        } else {
            viewModel.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        let newState: FollowButtonState = self.followButtonState == .canRequestFollow ? .requestPending : .following
                        self.followButtonState = newState
                        FollowStateStore.shared.setState(newState, for: targetUserId)
                    }
                }
            }
        }
    }

    private var notificationFollowTitle: String {
        switch followButtonState {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    private var notificationFollowIcon: String {
        switch followButtonState {
        case .following:
            return "person.fill.checkmark"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .blocked:
            return "slash.circle"
        default:
            return "person.badge.plus"
        }
    }

    private var notificationFollowIsPassive: Bool {
        if case .requestPending = followButtonState {
            return true
        }
        return false
    }
}

// ✅ PROFILE IMAGE VIEW ADAPTATIVO
struct ProofileImageView: View {
    let imagePath: String?
    let colorScheme: ColorScheme // ✅ AGREGADO
    
    var body: some View {
        Group {
            if let imagePath = imagePath, let url = URL(string: imagePath) {
                KFImage(url)
                    .placeholder {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                    .gray.opacity(0.6) :
                                    .gray.opacity(0.5)
                                ) // ✅ ADAPTATIVO
                            
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color(hex: "00A896"))
                        }
                    }
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(
                            colorScheme == .dark ?
                            .gray.opacity(0.6) :
                            .gray.opacity(0.5)
                        ) // ✅ ADAPTATIVO
                }
            }
        }
    }
}

// ✅ SKELETON VIEW ADAPTATIVO
struct NotificationSkeletonRow: View {
    let colorScheme: ColorScheme // ✅ AGREGADO
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.05),
                            lineWidth: 0.5
                        ) // ✅ ADAPTATIVO
                )
            
            HStack(spacing: 15) {
                Circle()
                    .fill(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                        Color.gray.opacity(0.2)
                    ) // ✅ ADAPTATIVO
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            colorScheme == .dark ?
                            Color.gray.opacity(0.3) :
                            Color.gray.opacity(0.2)
                        ) // ✅ ADAPTATIVO
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            colorScheme == .dark ?
                            Color.gray.opacity(0.3) :
                            Color.gray.opacity(0.2)
                        ) // ✅ ADAPTATIVO
                        .frame(width: 100, height: 12)
                }
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                        Color.gray.opacity(0.2)
                    ) // ✅ ADAPTATIVO
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

// ✅ BUTTON STYLES GLASSMORPHIC ADAPTATIVO
struct GlassmorphicButtonStyle: ButtonStyle {
    let color: Color
    let colorScheme: ColorScheme // ✅ AGREGADO
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Poppins-SemiBold", size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.3) :
                        Color.black.opacity(0.2),
                        lineWidth: 1
                    ) // ✅ ADAPTATIVO
            )
            .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var notifications: [Notification] = []
    @Published var groupedByDate: [String: [NotificationGroup]] = [:]
    @Published var dateKeys: [String] = []
    @Published var groupedNotifications: [NotificationGroup] = []
    @Published var selectedTab: NotificationsView.NotificationTab = .all {
        didSet { groupNotifications() }
    }
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var pendingRequestsCount = 0
    @Published var hasUnreadNotifications = false
    @Published var canLoadMore = true
    @Published var isLoadingMore = false
    
    private let firestoreService = FirestoreService()
    private let notificationService = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var userProfileImageCache: [String: String] = [:]

    init() {
        setupSubscribers()
    }

    private func setupSubscribers() {
        notificationService.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newNotifications in
                self?.notifications = newNotifications
                self?.groupNotifications()
                self?.updatePendingCounts()
            }
            .store(in: &cancellables)
            
        notificationService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)

        notificationService.$isLoadingMore
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoadingMore, on: self)
            .store(in: &cancellables)

        notificationService.$canLoadMore
            .receive(on: DispatchQueue.main)
            .assign(to: \.canLoadMore, on: self)
            .store(in: &cancellables)
    }

    func refreshNotifications() async {
        notificationService.startObserving()
    }

    func loadMoreNotifications() {
        notificationService.loadMore()
    }

    private func updatePendingCounts() {
        self.hasUnreadNotifications = notificationService.unreadCount > 0
        self.pendingRequestsCount = notifications.filter {
            $0.type == .followRequest && $0.isPending
        }.count
    }

    func markAsRead(_ notification: Notification) {
        notificationService.markAsRead(notification)
    }

    func markAllAsRead() {
        notificationService.markAllAsRead()
    }

    // ✅ Agrupación eficiente por periodos de tiempo
    private func groupNotifications() {
        // ✅ 1. Filtrar notificaciones según la pestaña seleccionada
        let filtered = notifications.filter { notification in
            switch selectedTab {
            case .all:
                return true
            case .reactions:
                return notification.type == .reaction
            case .follows:
                return notification.type == .newFollower || notification.type == .mutualConnection || notification.type == .requestAccepted
            case .comments:
                return notification.type == .comment || notification.type == .like || isMomentOrCommentMention(notification)
            case .storyReactions:
                return notification.type == .storyReaction || notification.type == .storyChainContinued || isStoryMention(notification)
            case .requests:
                return notification.type == .followRequest
            }
        }
        
        // ✅ 2. Agrupar las notificaciones filtradas
        var groupedDict: [String: [Notification]] = [:]
        
        for notification in filtered {
            let key: String
            if notification.type == .newFollower || notification.type == .mutualConnection {
                // Agrupar seguidores nuevos y conexiones mutuas recientes
                // en una fila "X y N más", separados por sección temporal.
                // Offline-safe: opera sobre la caché local.
                key = "\(notification.type.rawValue)_agg_\(getSectionKey(for: notification.timestamp))"
            } else if isPerActorSocialNotification(notification.type) {
                // requestAccepted / followRequest: una fila por sender (evento o acción individual)
                key = "\(notification.type.rawValue)_\(notification.senderId)"
            } else if notification.type == .storyChainContinued {
                // Agrupar por cadena: el evento trae chainId, no commentId/storyId.
                let chain = notification.chainId ?? notification.storyId ?? "general"
                key = "storyChainContinued_\(chain)"
            } else {
                let contentId = notification.commentId ?? notification.storyId ?? notification.momentId ?? "general"
                let context = notification.mentionContext ?? inferredMentionContext(notification)
                key = "\(notification.type.rawValue)_\(context)_\(contentId)"
            }
            
            if groupedDict[key] == nil {
                groupedDict[key] = []
            }
            groupedDict[key]?.append(notification)
        }
        
        let groups = groupedDict.map { key, notifications -> NotificationGroup in
            let sorted = notifications.sorted { $0.timestamp > $1.timestamp }
            // Seguidores / mutuas agregados: contar una sola vez por persona (evita inflar "y N más" con duplicados legacy)
            if key.contains("_agg_") {
                var seenSenders = Set<String>()
                let dedupedBySender = sorted.filter { seenSenders.insert($0.senderId).inserted }
                return NotificationGroup(id: key, notifications: dedupedBySender)
            }
            return NotificationGroup(id: key, notifications: sorted)
        }
        
        var tempSections: [String: [NotificationGroup]] = [:]
        for group in groups {
            let section = getSectionKey(for: group.notifications.first!.timestamp)
            if tempSections[section] == nil { tempSections[section] = [] }
            tempSections[section]?.append(group)
        }
        
        for key in tempSections.keys {
            tempSections[key]?.sort { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
        }
        
        self.groupedByDate = tempSections
        self.dateKeys = ["New", "This Week", "This Month", "Earlier"].filter { tempSections[$0] != nil }
        self.groupedNotifications = groups.sorted { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
        
        // ✅ #5: Batch preload sender profiles to avoid N+1 queries
        preloadSenderProfiles(for: filtered)
    }
    
    // ✅ #5: Pre-cargar perfiles de senders en batch (evita N+1 queries por fila)
    private func preloadSenderProfiles(for notifications: [Notification]) {
        let senderIds = Set(notifications.map { $0.senderId }.filter { !$0.isEmpty })
        let uncachedIds = senderIds.filter { userProfileImageCache[$0] == nil }
        
        guard !uncachedIds.isEmpty else { return }
        
        // Firestore 'in' queries support max 30 items
        let chunks = Array(uncachedIds).chunked(into: 30)
        
        for chunk in chunks {
            Firestore.firestore().collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { [weak self] snapshot, error in
                    guard let self = self, let docs = snapshot?.documents else { return }
                    
                    DispatchQueue.main.async {
                        for doc in docs {
                            let data = doc.data()
                            if let imagePath = data["profileImagePath"] as? String, !imagePath.isEmpty {
                                self.userProfileImageCache[doc.documentID] = imagePath
                            }
                        }
                    }
                }
        }
    }

    private func isStoryMention(_ notification: Notification) -> Bool {
        notification.type == .mention && (notification.mentionContext == "story" || notification.storyId != nil)
    }

    private func isMomentOrCommentMention(_ notification: Notification) -> Bool {
        notification.type == .mention && !isStoryMention(notification)
    }

    private func inferredMentionContext(_ notification: Notification) -> String {
        guard notification.type == .mention else { return "default" }
        if notification.storyId != nil { return "story" }
        if notification.commentId != nil { return "comment" }
        if notification.momentId != nil { return "moment" }
        return "mention"
    }

    private func getSectionKey(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return "New"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return "This Week"
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now), date > monthAgo {
            return "This Month"
        } else {
            return "Earlier"
        }
    }

    func deleteNotification(_ notification: Notification) {
        notificationService.deleteNotification(notification)
    }

    // ✅ Acciones de solicitudes de seguimiento simplificadas (OFFLINE AWARE)
    func acceptFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let notification = group.notifications.first(where: { $0.type == .followRequest }),
              let notificationId = notification.id else { return }
        // 1. Delegar a LocalPersistence (Optimistic UI + Sync)
        Task {
            await LocalPersistenceService.shared.acceptFollowRequest(
                notificationId: notificationId,
                senderId: notification.senderId,
                recipientId: userId
            )
            
            // 2. Actualizar estado local del view model para reflejar cambio inmediato
            DispatchQueue.main.async {
                if let index = self.notifications.firstIndex(where: { $0.id == notificationId }) {
                    self.notifications[index].isPending = false
                    self.groupNotifications() // Reagrupar para actualizar UI
                    self.updatePendingCounts()
                }
            }
        }
    }

    func rejectFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        for notification in group.notifications where notification.type == .followRequest {
            guard let notificationId = notification.id else { continue }
            
            // 1. Delegar a LocalPersistence (Optimistic UI + Sync)
            Task {
                await LocalPersistenceService.shared.rejectFollowRequest(
                    notificationId: notificationId,
                    senderId: notification.senderId,
                    recipientId: userId
                )
                
                // 2. Actualizar estado local del view model para reflejar cambio inmediato
                DispatchQueue.main.async {
                    self.notifications.removeAll { $0.id == notificationId }
                    self.groupNotifications() // Reagrupar para actualizar UI
                    self.updatePendingCounts()
                }
            }
        }
    }

    func checkIfFollowing(currentUserId: String, targetUserId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // ✅ OFFLINE-FIRST: Verificar en caché local
        let isFollowingCached = LocalPersistenceService.shared.isFollowing(targetUserId: targetUserId)
        completion(.success(isFollowingCached))
        
        // 🔄 Actualizar en background para consistencia estricta
        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { isFollowingNetwork in
            // Si el estado de red difiere del caché local, notificamos de nuevo
            if isFollowingNetwork != isFollowingCached {
                completion(.success(isFollowingNetwork))
            }
        }
    }

    func followUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func unfollowUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }
    
    func getProfileImagePath(for userId: String) -> String? {
        return userProfileImageCache[userId]
    }

    func updateProfileImageCache(for userId: String, imagePath: String?) {
        userProfileImageCache[userId] = imagePath
    }
}
