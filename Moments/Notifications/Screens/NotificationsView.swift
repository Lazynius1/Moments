import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import Combine

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @StateObject private var storyViewModel = StoryViewModel() // ✅ AGREGADO
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme // ✅ AGREGADO
    @State private var selectedMoment: Moment?
    @State private var moderationReviewNotification: Notification?
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
        .sheet(item: $moderationReviewNotification) { notification in
            ModerationReviewRequestSheet(
                notification: notification,
                isPresented: Binding(
                    get: { moderationReviewNotification != nil },
                    set: { if !$0 { moderationReviewNotification = nil } }
                )
            )
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
                                },
                                onModerationReviewTap: { notification in
                                    moderationReviewNotification = notification
                                }
                            )
                        }
                    } header: {
                        NotificationDateHeaderView(dateString: dateKey, colorScheme: colorScheme)
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
