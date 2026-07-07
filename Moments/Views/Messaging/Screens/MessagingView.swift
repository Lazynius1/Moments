import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import Combine
import WidgetKit

private struct MessagingStoryRoute: Identifiable {
    let id: String
}

private struct MessagingProfileRoute: Identifiable, Hashable {
    let id: String
}

// MARK: - Glassmorphic Components
struct GlassmorphicBackground: View {
    let adaptiveColors: AdaptiveColors

    var body: some View {
        if adaptiveColors.colorScheme == .dark {
            Color(hex: "0B1215")
                .ignoresSafeArea()
        } else {
            Color(hex: "FAF9F6")
                .ignoresSafeArea()
        }
    }
}

struct GlasssmorphicCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 20))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
}

extension View {
    func glasssmorphic() -> some View {
        self.modifier(GlasssmorphicCard())
    }
}

// MARK: - Main MessagingView
struct MessagingView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var viewModel: MessagingViewModel
    @EnvironmentObject var messageRequestService: MessageRequestService
    @Environment(\.colorScheme) var colorScheme
    @State private var isShowingNewConversation = false
    @State private var selectedConversation: Conversation?
    @Binding var targetConversationId: String?
    var onDismiss: (() -> Void)? = nil

    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var navigationService = NotificationNavigationService.shared
    // ✅ HISTORIAS: Estados para anillos de historias
    // ✅ SOLICITUDES: Estado para mostrar solicitudes
    @State private var showingMessageRequests = false
    @State private var pendingRequestCount = 0

    // ✅ NUEVO: Estado para el selector de estados online
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var showingStatusSelector = false
    @State private var conversationMenuSelection: ConversationMenuSelection?
    @State private var conversationRowFrames: [String: CGRect] = [:]
    @State private var showingArchivedConversations = false
    @State private var actionToastMessage: String?
    @State private var actionToastDismissTask: Task<Void, Never>? = nil
    @Namespace private var profileZoomNamespace
    @State private var profileRoute: MessagingProfileRoute?

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    // ✅ NUEVO: Instancia de PrivacyService para verificar historias
    private let privacyService = PrivacyService()
    @State private var pendingConversationResolveTask: Task<Void, Never>? = nil

    private var conversationIds: [String] {
        viewModel.conversations.compactMap(\.id)
    }

    var body: some View {
        ChatRecoveryGateView(onCancel: onDismiss) {
            messagingLifecycleContent
        }
    }

    private var messagingLifecycleContent: some View {
        applyMessagingForegroundObservers(
            to: applyMessagingCoreObservers(to: messagingNavigationShell)
        )
    }

    private func applyMessagingCoreObservers<V: View>(to content: V) -> some View {
        content
            .onAppear(perform: handleMessagingAppear)
            .onChange(of: conversationIds) { _, _ in
                handleConversationIdsChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatDraftDidChange)) { _ in
                viewModel.refreshDraftOrdering()
            }
            .onReceive(NotificationCenter.default.publisher(for: .conversationVanishModeDidChange)) { notification in
                guard let conversationId = notification.userInfo?["conversationId"] as? String,
                      let active = notification.userInfo?["vanishModeActive"] as? Bool else { return }
                viewModel.updateVanishMode(conversationId: conversationId, active: active)
            }
            .onChange(of: authService.currentUser) { _, _ in
                handleAuthUserChange()
            }
            .onChange(of: targetConversationId) { _, newTargetId in
                handleTargetConversationIdChange(newTargetId)
            }
            .onChange(of: viewModel.conversations) { _, newConversations in
                resolvePendingTargetConversation(in: newConversations)
            }
    }

    private func applyMessagingForegroundObservers<V: View>(to content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                viewModel.refreshVisibleUsers()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationMuteStateChanged"))) { systemNotification in
                handleConversationMuteStateChanged(systemNotification)
            }
            .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
                handlePeriodicUserRefresh()
            }
            .onReceive(navigationService.$pendingNavigation) { navigation in
                handlePendingNavigation(navigation)
            }
            .onDisappear(perform: handleMessagingDisappear)
    }

    private var messagingNavigationShell: some View {
        applyMessagingDestinations(to: applyMessagingChrome(to: messagingMainStack))
    }

    private func applyMessagingChrome<V: View>(to content: V) -> some View {
        content
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: actionToastMessage)
            .coordinateSpace(name: "messagingRoot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { messagingToolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !viewModel.conversations.isEmpty || !viewModel.archivedConversations.isEmpty {
                    searchBar
                }
            }
            .sheet(isPresented: $showingStatusSelector) {
                statusSelectorSheet
            }
            .sheet(isPresented: $showingMessageRequests) {
                messageRequestsSheet
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarHidden(false)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .tabBar)
    }

    private func applyMessagingDestinations<V: View>(to content: V) -> some View {
        content
            .navigationDestination(isPresented: $isShowingNewConversation) {
                newConversationDestination
            }
            .navigationDestination(isPresented: $showingArchivedConversations) {
                archivedConversationsDestination
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                chatDestination(for: conversation)
            }
            .navigationDestination(item: $profileRoute) { route in
                profileDestination(for: route)
            }
    }

    private var statusSelectorSheet: some View {
        OnlineStatusSelectorView(
            currentStatus: onlineStatusService.currentUserStatus,
            onStatusSelected: { newStatus in
                onlineStatusService.setGlobalStatus(newStatus)
                showingStatusSelector = false
            }
        )
    }

    private var messageRequestsSheet: some View {
        MessageRequestsView()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    private var messagingMainStack: some View {
        ZStack {
            GlassmorphicBackground(adaptiveColors: adaptiveColors)

            conversationList

            GeometryReader { proxy in
                ConversationContextMenuOverlay(
                    selection: $conversationMenuSelection,
                    containerSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets,
                    colorScheme: colorScheme,
                    onMarkUnread: markConversationUnread,
                    onPin: pinConversation,
                    onMute: muteConversation,
                    onArchive: archiveConversation,
                    onUnarchive: unarchiveConversation,
                    onDelete: deleteConversation
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(conversationMenuSelection != nil)

            if let actionToastMessage {
                VStack {
                    Spacer()
                    MessagingActionToast(text: actionToastMessage, colorScheme: colorScheme)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .zIndex(3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var newConversationDestination: some View {
        GlassmorphicNewConversationView(viewModel: viewModel) { conversation in
            isShowingNewConversation = false
            if let conversation {
                selectedConversation = conversation
            }
        }
    }

    private var archivedConversationsDestination: some View {
        ArchivedConversationsView(
            viewModel: viewModel,
            selectedConversation: $selectedConversation,
            onMarkUnread: markConversationUnread,
            onPin: pinConversation,
            onMute: muteConversation,
            onUnarchive: unarchiveConversation,
            onDelete: deleteConversation
        )
    }

    private func chatDestination(for conversation: Conversation) -> some View {
        GlassmorphicChatView(
            conversation: conversation,
            session: ChatSessionEngine.shared.session(for: conversation)
        )
    }

    private func profileDestination(for route: MessagingProfileRoute) -> some View {
        UserProfileView(userId: route.id)
            .userProfileZoomDestination(userId: route.id, namespace: profileZoomNamespace)
    }

    private func handleMessagingAppear() {
        if let userId = Auth.auth().currentUser?.uid {
            viewModel.fetchConversations(for: userId)
            messageRequestService.listenToPendingRequests(for: userId)
            updatePendingRequestCount(for: userId)
        }

        preloadRecentChatSessions()

        if let targetId = targetConversationId {
            navigateToConversation(id: targetId)
        }

        triggerCatchUpIfNeeded()
    }

    private func handleConversationIdsChange() {
        triggerCatchUpIfNeeded()
        preloadRecentChatSessions()
    }

    private func handleAuthUserChange() {
        if let userId = Auth.auth().currentUser?.uid {
            viewModel.errorMessage = nil
            viewModel.fetchConversations(for: userId)
            messageRequestService.listenToPendingRequests(for: userId)
            updatePendingRequestCount(for: userId)
        } else {
            viewModel.stopListening()
            viewModel.errorMessage = nil
            viewModel.conversations = []
            viewModel.archivedConversations = []
            viewModel.filteredConversations = []
            viewModel.hasUnreadMessages = false
            messageRequestService.removeAllListeners()
            messageRequestService.pendingRequests = []
            messageRequestService.errorMessage = nil
            ChatAccessCoordinator.shared.invalidate()
            ChatSessionEngine.shared.invalidateAll()
            selectedConversation = nil
        }
    }

    private func handleTargetConversationIdChange(_ newTargetId: String?) {
        guard let targetId = newTargetId else { return }
        navigateToConversation(id: targetId)
    }

    private func resolvePendingTargetConversation(in conversations: [Conversation]) {
        guard let targetId = targetConversationId else { return }
        guard let conversation = conversations.first(where: { $0.id == targetId }) else { return }
        selectedConversation = conversation
        targetConversationId = nil
        pendingConversationResolveTask?.cancel()
        pendingConversationResolveTask = nil
    }

    private func handleConversationMuteStateChanged(_ systemNotification: Foundation.Notification) {
        let userInfo = systemNotification.userInfo
        let conversationId = userInfo?["conversationId"] as? String
        let isMuted = userInfo?["isMuted"] as? Bool
        guard let conversationId, let isMuted else { return }
        viewModel.applyLocalConversationState(conversationId: conversationId, isMuted: isMuted)
    }

    private func handlePeriodicUserRefresh() {
        guard !viewModel.conversations.isEmpty else { return }
        viewModel.refreshVisibleUsers()
    }

    private func handlePendingNavigation(_ navigation: NotificationNavigationService.PendingNavigation?) {
        guard let navigation else { return }
        guard case .conversation(let conversationId) = navigation else { return }
        targetConversationId = conversationId
        navigationService.clearPendingNavigation()
    }

    private func handleMessagingDisappear() {
        actionToastDismissTask?.cancel()
        actionToastDismissTask = nil
        actionToastMessage = nil
        viewModel.stopListening()
        messageRequestService.removeAllListeners()
    }

    private func triggerCatchUpIfNeeded() {
        guard LocalFirstMessagingSettings.isEnabled else { return }
        MessageCatchUpService.shared.syncRecent(conversations: viewModel.conversations)
    }

    private func preloadRecentChatSessions() {
        guard LocalFirstMessagingSettings.isEnabled else { return }
        let cached = LocalPersistenceService.shared.loadConversations()
        guard !cached.isEmpty else { return }
        let userId = Auth.auth().currentUser?.uid ?? ""
        let sorted = cached.sorted { lhs, rhs in
            let lhsUnread = !(lhs.readStatus[userId] ?? true)
            let rhsUnread = !(rhs.readStatus[userId] ?? true)
            if lhsUnread != rhsUnread { return lhsUnread && !rhsUnread }
            return lhs.timestamp > rhs.timestamp
        }
        ChatSessionEngine.shared.preloadRecentSessions(from: sorted, limit: 5)
    }

    private func navigateToConversation(id: String) {
        pendingConversationResolveTask?.cancel()

        if let conversation = (viewModel.conversations + viewModel.archivedConversations).first(where: { $0.id == id }) {
            selectedConversation = conversation
            targetConversationId = nil
        } else {
            // Configurar una tarea de timeout por si no se resuelve en 3 segundos
            pendingConversationResolveTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if targetConversationId == id {
                        targetConversationId = nil
                    }
                    pendingConversationResolveTask = nil
                }
            }
        }
    }

    private func openConversationProfile(userId: String) {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profileRoute = MessagingProfileRoute(id: trimmed)
    }

    // ✅ SOLICITUDES: Función para actualizar el conteo de solicitudes pendientes
    private func updatePendingRequestCount(for userId: String) {
        messageRequestService.getPendingRequestCount(for: userId) { count in
            DispatchQueue.main.async {
                self.pendingRequestCount = count

                // ✅ Widget: Guardar conteo de solicitudes de mensaje pendientes
                let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
                widgetDefaults?.set(count, forKey: "widget_pending_message_requests")
                WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
            }
        }
    }

    // MARK: - Toolbar nativo (scroll edge blur del sistema en iOS 26)

    @ToolbarContentBuilder
    private var messagingToolbarContent: some ToolbarContent {
        if onDismiss != nil {
            ToolbarItem(placement: .topBarLeading) {
                messagingToolbarBackButton
            }
            .chatHideSharedBackgroundIfAvailable()
        } else {
            ToolbarItem(placement: .topBarLeading) {
                messagingToolbarComposeButton
            }
            .chatHideSharedBackgroundIfAvailable()
        }

        ToolbarItem(placement: .principal) {
            messagingToolbarTitleStack
        }

        if onDismiss != nil {
            ToolbarItem(placement: .topBarTrailing) {
                messagingToolbarTrailingCluster
            }
            .chatHideSharedBackgroundIfAvailable()
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                messagingToolbarRequestsButton
            }
            .chatHideSharedBackgroundIfAvailable()
        }
    }

    private var messagingToolbarBackButton: some View {
        ProfileChromeIconButton(
            systemName: "chevron.left",
            foregroundColor: adaptiveColors.primary,
            preset: .navigationBack,
            action: { onDismiss?() }
        )
    }

    private var messagingToolbarTrailingCluster: some View {
        ProfileChromeControlsCluster {
            ProfileChromeIconButton(
                systemName: "square.and.pencil",
                foregroundColor: adaptiveColors.primary,
                preset: .toolbarAction,
                standaloneGlass: false,
                action: { isShowingNewConversation = true }
            )

            messagingToolbarRequestsClusterButton
        }
    }

    private var messagingToolbarComposeButton: some View {
        Button(action: { isShowingNewConversation = true }) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(adaptiveColors.primary)
                .frame(width: 40, height: 40)
                .modifier(ChatToolbarIconGlassModifier())
        }
        .buttonStyle(.plain)
    }

    private var messagingToolbarRequestsButton: some View {
        Button(action: { showingMessageRequests = true }) {
            ZStack {
                Image(systemName: "message.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .modifier(ChatToolbarIconGlassModifier())

                if pendingRequestCount > 0 {
                    Text("\(pendingRequestCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(hex: "FF3B30")))
                        .offset(x: 12, y: -12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var messagingToolbarRequestsClusterButton: some View {
        Button(action: { showingMessageRequests = true }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message.circle")
                    .font(.system(size: MomentsGlassControlMetrics.toolbarIconSize, weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(
                        width: MomentsGlassControlMetrics.toolbarControlSize,
                        height: MomentsGlassControlMetrics.toolbarControlSize
                    )

                if pendingRequestCount > 0 {
                    Text("\(pendingRequestCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(hex: "FF3B30")))
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var messagingToolbarTitleStack: some View {
        VStack(spacing: 2) {
            Text("messaging.title")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
                .lineLimit(1)

            Button(action: { showingStatusSelector = true }) {
                HStack(spacing: 4) {
                    Image(systemName: onlineStatusService.currentUserStatus.icon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(onlineStatusService.currentUserStatus.color)

                    Text(onlineStatusService.currentUserStatus.displayName)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(adaptiveColors.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // ✅ Barra de búsqueda
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(adaptiveColors.secondary)
                    .font(.system(size: 16))

                TextField(NSLocalizedString("messaging.search.placeholder", comment: "Search conversations placeholder"), text: $searchText)
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundColor(adaptiveColors.primary)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearching = !newValue.isEmpty
                        }
                        if !newValue.isEmpty {
                            viewModel.searchConversationsAndUsers(query: newValue)
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearching = false
                        isSearchFocused = false
                        viewModel.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(adaptiveColors.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .momentsChromeGlass(in: Capsule())

            if isSearchFocused {
                Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                    searchText = ""
                    isSearching = false
                    isSearchFocused = false
                    viewModel.clearSearch()
                }
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundColor(adaptiveColors.primary)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearchFocused)
    }

    @ViewBuilder
     private var conversationList: some View {
         if let errorMessage = viewModel.errorMessage {
             VStack(spacing: 20) {
                 Spacer()

                 VStack(spacing: 12) {
                     Image(systemName: "exclamationmark.triangle.fill")
                         .font(.system(size: 50))
                         .foregroundColor(.white.opacity(0.8))

                     Text(errorMessage)
                         .font(.system(size: legacyPoppinsSize(16)))
                         .foregroundColor(.white)
                         .multilineTextAlignment(.center)
                         .padding(.horizontal)

                     Button(action: {
                         if let userId = Auth.auth().currentUser?.uid {
                             viewModel.fetchConversations(for: userId)
                         }
                     }) {
                         Text("messaging.retry")
                             .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                             .foregroundColor(Color(hex: "007AFF"))
                             .padding(.horizontal, 30)
                             .padding(.vertical, 12)
                             .background(Color.white.opacity(0.9))
                             .clipShape(Capsule())
                     }
                 }
                 .padding(30)
                 .glassmorphic()
                 .padding(.horizontal, 40)

                 Spacer()
             }
         } else if viewModel.conversations.isEmpty && viewModel.archivedConversations.isEmpty && !isSearching {
             VStack(spacing: 20) {
                 Spacer()

                 VStack(spacing: 16) {
                     Image(systemName: "bubble.left.and.bubble.right.fill")
                         .font(.system(size: 60))
                         .foregroundColor(.white.opacity(0.8))

                     Text("messaging.noConversations.title")
                         .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                         .foregroundColor(.white)

                     Text("messaging.noConversations.subtitle")
                         .font(.system(size: legacyPoppinsSize(14)))
                         .foregroundColor(.white.opacity(0.8))

                     Button(action: {
                         isShowingNewConversation = true
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                             Text("messaging.newConversation")
                         }
                         .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                         .foregroundColor(Color(hex: "007AFF"))
                         .padding(.horizontal, 24)
                         .padding(.vertical, 12)
                         .background(Color.white.opacity(0.9))
                         .clipShape(Capsule())
                     }
                     .padding(.top, 10)
                 }
                 .padding(40)
                 .glassmorphic()
                 .padding(.horizontal, 30)

                 Spacer()
             }
         } else if isSearching {
             List {
                 searchResultsListContent
             }
             .listStyle(.plain)
             .scrollContentBackground(.hidden)
             .messagingListEdgeToEdge()
             .chatScrollEdgeEffect()
         } else {
             List {
                 conversationsSection
             }
             .listStyle(.plain)
             .scrollContentBackground(.hidden)
             .chatScrollEdgeEffect()
             .scrollDisabled(conversationMenuSelection != nil)
             .onPreferenceChange(ConversationRowFrameKey.self) { conversationRowFrames = $0 }
             .refreshable {
                 if let userId = Auth.auth().currentUser?.uid {
                     viewModel.fetchConversations(for: userId)
                 }
             }
         }
     }

    @ViewBuilder
    private var searchResultsListContent: some View {
        if !viewModel.filteredConversations.isEmpty {
            Section {
                ForEach(viewModel.filteredConversations) { conversation in
                    searchResultConversationRow(conversation)
                }
            } header: {
                messagingSearchSectionHeader("messaging.conversations")
            }
        }

        if !viewModel.searchedUsers.isEmpty {
            Section {
                ForEach(viewModel.searchedUsers) { user in
                    SearchUserRow(user: user) { conversation in
                        if let conversation = conversation {
                            selectedConversation = conversation
                            searchText = ""
                            isSearching = false
                            isSearchFocused = false
                            viewModel.clearSearch()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } header: {
                messagingSearchSectionHeader("messaging.users")
            }
        }

        if viewModel.filteredConversations.isEmpty && viewModel.searchedUsers.isEmpty && !searchText.isEmpty {
            Section {
                messagingSearchEmptyState
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func searchResultConversationRow(_ conversation: Conversation) -> some View {
        GlassmorphicConversationRow(
            conversation: conversation,
            profileZoomNamespace: profileZoomNamespace,
            onOpenProfile: { openConversationProfile(userId: conversation.otherParticipantId) },
            onTap: { selectedConversation = conversation }
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func messagingSearchSectionHeader(_ title: LocalizedStringKey) -> some View {
        MessagingSectionHeader(title: title, adaptiveColors: adaptiveColors)
    }

    private var messagingSearchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(adaptiveColors.secondary.opacity(0.6))

            Text("messaging.noResults")
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)

            Text("messaging.noResults.description")
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }

    // ✅ NUEVAS FUNCIONES: Acciones de swipe
    private func deleteConversation(_ conversation: Conversation) {
        viewModel.deleteConversation(conversation)
    }

    private func pinConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        let chatService = ChatService.shared
        if conversation.isPinned == true {
            viewModel.applyLocalConversationState(conversationId: conversationId, isPinned: false)
            // Si ya está pinnada, despinnarla
            chatService.unpinConversation(conversationId, for: currentUserId) { _ in
            }
        } else {
            viewModel.applyLocalConversationState(conversationId: conversationId, isPinned: true)
            // Si no está pinnada, pinnarla
            chatService.pinConversation(conversationId, for: currentUserId) { _ in
            }
        }
    }

    private func markConversationUnread(_ conversation: Conversation) {
        HapticManager.shared.lightImpact()
        viewModel.markConversationAsUnread(conversation)
    }

    private func muteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        let chatService = ChatService.shared
        if conversation.isMuted == true {
            viewModel.applyLocalConversationState(conversationId: conversationId, isMuted: false)
            // Si ya está silenciada, desilenciarla
            chatService.unmuteConversation(conversationId, for: currentUserId) { _ in
            }
        } else {
            viewModel.applyLocalConversationState(conversationId: conversationId, isMuted: true)
            // Si no está silenciada, silenciarla
            chatService.muteConversation(conversationId, for: currentUserId) { _ in
            }
        }
    }

    private func archiveConversation(_ conversation: Conversation) {
        HapticManager.shared.lightImpact()
        viewModel.archiveConversation(conversation)
        showActionToast(NSLocalizedString("messaging.toast.archived", comment: "Conversation archived toast"))
    }

    private func unarchiveConversation(_ conversation: Conversation) {
        HapticManager.shared.lightImpact()
        viewModel.unarchiveConversation(conversation)
        showActionToast(NSLocalizedString("messaging.toast.unarchived", comment: "Conversation unarchived toast"))
    }

    private func showActionToast(_ message: String) {
        actionToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            actionToastMessage = message
        }
        actionToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                actionToastMessage = nil
            }
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        if !viewModel.archivedConversations.isEmpty {
            archivedConversationsEntryRow
        }

        ForEach(viewModel.conversations) { conversation in
            if let conversationId = conversation.id, !conversationId.isEmpty {
                conversationRow(conversation)
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        let isMenuSelected = conversationMenuSelection?.conversation.id == conversation.id

        ConversationPressableRow(
            conversation: conversation,
            isMenuSelected: isMenuSelected,
            colorScheme: colorScheme,
            profileZoomNamespace: profileZoomNamespace,
            onOpenProfile: { openConversationProfile(userId: conversation.otherParticipantId) },
            onTap: {
                selectedConversation = conversation
            },
            onLongPress: {
                guard let conversationId = conversation.id,
                      let frame = conversationRowFrames[conversationId],
                      frame.width > 0, frame.height > 0 else { return }
                conversationMenuSelection = ConversationMenuSelection(
                    conversation: conversation,
                    rowFrame: frame
                )
            }
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .zIndex(isMenuSelected ? 1 : 0)
    }

    private var archivedConversationsEntryRow: some View {
        let userId = Auth.auth().currentUser?.uid ?? ""
        let unreadCount = viewModel.archivedUnreadCount(for: userId)

        return Button {
            showingArchivedConversations = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                Text(
                    unreadCount > 0
                        ? String(format: NSLocalizedString("messaging.section.archivedWithUnread", comment: "Archived section with unread count"), unreadCount)
                        : NSLocalizedString("messaging.section.archived", comment: "Archived section")
                )
                .font(.system(size: legacyPoppinsSize(15), weight: .semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.45)
            }
            .foregroundStyle(adaptiveColors.primary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Pressable row wrapper (scale feedback)

struct ConversationPressableRow: View {
    let conversation: Conversation
    let isMenuSelected: Bool
    let colorScheme: ColorScheme
    let profileZoomNamespace: Namespace.ID
    let onOpenProfile: () -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressing = false

    var body: some View {
        GlassmorphicConversationRow(
            conversation: conversation,
            profileZoomNamespace: profileZoomNamespace,
            onOpenProfile: onOpenProfile,
            onTap: onTap,
            listInteraction: ConversationListInteraction(
                onTap: onTap,
                onLongPress: {
                    // No reseteamos isPressing aquí — el gesture .ended lo hace
                    // via onPressingChanged(false), manteniendo el scale visible
                    onLongPress()
                },
                onPressingChanged: { pressing in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                        isPressing = pressing
                    }
                }
            )
        )
        .background {
            // Frame capturado en espacio global para alinearse con el overlay ignoresSafeArea
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .preference(
                        key: ConversationRowFrameKey.self,
                        value: [conversation.id ?? "": frame] as [String: CGRect]
                    )
            }
        }
        .modifier(ConversationRowMenuHighlight(
            isSelected: isMenuSelected,
            colorScheme: colorScheme
        ))
        .scaleEffect((isPressing || isMenuSelected) ? 0.92 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressing || isMenuSelected)
    }
}

// ✅ COMPONENTE para usuarios encontrados en búsqueda
struct SearchUserRow: View {
    let user: AppUser
    let onTap: (Conversation?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            if let userId = Auth.auth().currentUser?.uid {
                ChatService().getOrCreateConversation(between: userId, and: user.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let conversationId):

                            let conversation = Conversation(
                                id: conversationId,
                                participants: [userId, user.id],
                                lastMessage: "",
                                timestamp: Date(),
                                readStatus: [userId: true, user.id: false],
                                otherParticipantId: user.id,
                                otherParticipantUsername: user.username,
                                otherParticipantProfileImagePath: user.profileImagePath
                            )

                            onTap(conversation)

                        case .failure:
                            onTap(nil)
                        }
                    }
                }
            } else {
                onTap(nil)
            }
        }) {
            HStack(spacing: 14) {
                AsyncProfileImageView(userId: user.id)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("messaging.tapToStartConversation")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "007AFF"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glassmorphic Conversation Row
struct GlassmorphicConversationRow: View {
    let conversation: Conversation
    let profileZoomNamespace: Namespace.ID
    let onOpenProfile: () -> Void
    let onTap: () -> Void
    var listInteraction: ConversationListInteraction? = nil
    @Environment(\.colorScheme) var colorScheme

    @State private var storyRoute: MessagingStoryRoute?
    @State private var liveOtherParticipantUsername: String = ""
    @State private var isOtherParticipantUnavailable: Bool = false
    @State private var isOtherParticipantBlockedByCurrentUser: Bool = false
    @State private var draftText: String = ""
    private let firestoreService = FirestoreService()

    private var displayUsername: String {
        let fallback = conversation.otherParticipantUsername ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    var body: some View {
        HStack(spacing: 12) {
            conversationAvatar

            rowContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            refreshOtherParticipantUsername()
            refreshOtherParticipantAvailability()
            refreshDraft()
        }
        .onChange(of: conversation.otherParticipantId) { _, _ in
            refreshOtherParticipantUsername()
            refreshOtherParticipantAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatDraftDidChange)) { notification in
            guard (notification.userInfo?["conversationId"] as? String) == conversation.id else { return }
            refreshDraft()
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.id))
                .ignoresSafeArea(.keyboard)
        }
    }

    @ViewBuilder
    private var conversationAvatar: some View {
        if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
            Button(action: onOpenProfile) {
                ProfileUnavailableAvatar(size: 56)
                    .userProfileZoomSource(
                        userId: conversation.otherParticipantId,
                        namespace: profileZoomNamespace,
                        cornerRadius: 28
                    )
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            StoryRingAvatarView(
                userId: conversation.otherParticipantId,
                size: 56,
                lineWidth: 2.5,
                isOwnStory: false,
                hapticsEnabled: true,
                profileZoomNamespace: profileZoomNamespace
            ) { hasStory in
                guard !isOtherParticipantBlockedByCurrentUser else {
                    onOpenProfile()
                    return
                }

                if hasStory {
                    storyRoute = MessagingStoryRoute(id: conversation.otherParticipantId)
                } else {
                    onOpenProfile()
                }
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        let content = HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                usernameRow
                messagePreviewRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            conversationTrailingIndicator
        }

        if let listInteraction {
            ZStack {
                content
                ProfileMomentThumbnailGestureOverlay(
                    onTap: listInteraction.onTap,
                    onLongPress: listInteraction.onLongPress,
                    onPressingChanged: listInteraction.onPressingChanged
                )
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var usernameRow: some View {
        let label = HStack(spacing: 4) {
            Text(displayUsername)
                .font(.system(size: 16, weight: .semibold))
                .strikethrough(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser, color: colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(isOtherParticipantUnavailable ? 0.72 : 1.0))

            if !isOtherParticipantUnavailable {
                VerifiedBadgeView(userId: conversation.otherParticipantId, size: 14)
            }

            if conversation.isPinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }

            if conversation.isMuted == true {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
        }

        if listInteraction == nil {
            Button(action: onOpenProfile) {
                label
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            label
        }
    }

    @ViewBuilder
    private var messagePreviewRow: some View {
        let cleanDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsUnavailablePreview = isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser
        let showsDraftPreview = !showsUnavailablePreview && !cleanDraft.isEmpty
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        let isUnread = !(conversation.readStatus[currentUserId] ?? true)
        let isOwnLastMessage = conversation.isOwnLastMessage(for: currentUserId)

        let resolvedPreview: String = {
            if showsDraftPreview {
                return String(
                    format: NSLocalizedString("chat.draft.preview", comment: "Draft conversation preview"),
                    cleanDraft
                )
            } else if let reaction = conversation.lastMessageReaction,
                      isOwnLastMessage {
                return "\(reaction.emoji) " + NSLocalizedString("chat.preview.reacted", comment: "Reacted to your message")
            } else if conversation.unreadCount >= 2 {
                let format = NSLocalizedString("chat.unreadCount.preview", comment: "X new messages preview")
                if format == "chat.unreadCount.preview" {
                    return String(format: "%d mensajes nuevos", conversation.unreadCount)
                }
                return String(format: format, conversation.unreadCount)
            } else if isOwnLastMessage,
                      conversation.lastMessageSeenAt?[conversation.otherParticipantId] != nil {
                return NSLocalizedString("chat.seen", comment: "Seen")
            } else if isOwnLastMessage {
                return NSLocalizedString("chat.status.sent", comment: "Sent")
            } else {
                return conversation.inboxMessagePreview(for: currentUserId)
            }
        }()

        let previewColor: Color = {
            if showsDraftPreview { return Color(hex: "3F6F8F") }
            if isUnread { return colorScheme == .dark ? .white : .black }
            return colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
        }()

        let secondaryColor = colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.38)
        let relativeTimeSource: Date = {
            if isOwnLastMessage,
               let seenAt = conversation.lastMessageSeenAt?[conversation.otherParticipantId] {
                return seenAt
            }
            return conversation.timestamp
        }()
        let relativeTime = MomentsFormat.relativeTime(from: relativeTimeSource, style: .compactBare)

        let row = HStack(spacing: 6) {
            Text(
                showsUnavailablePreview
                    ? NSLocalizedString("messaging.profileUnavailable.preview", comment: "Unavailable profile preview")
                    : resolvedPreview
            )
            .font(.system(size: 14, weight: (isUnread && !showsDraftPreview) ? .semibold : .regular))
            .foregroundColor(previewColor)
            .lineLimit(1)
            .layoutPriority(-1)

            Text(relativeTime)
                .font(.system(size: 14))
                .foregroundColor(secondaryColor)
                .fixedSize(horizontal: true, vertical: false)
        }

        if listInteraction == nil {
            Button(action: onTap) {
                row
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            row
        }
    }

    @ViewBuilder
    private var conversationTrailingIndicator: some View {
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        let isUnread = !(conversation.readStatus[currentUserId] ?? true)

        if conversation.showsViewOnceInboxPlayButton(for: currentUserId) {
            ChatViewOnceInboxIndicator()
        } else if conversation.vanishModeActive == true {
            ChatVanishInboxIndicator(isUnread: isUnread)
        } else if isUnread {
            Circle()
                .fill(Color(hex: "007AFF"))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                )
        }
    }

    private func refreshDraft() {
        guard let conversationId = conversation.id else {
            draftText = ""
            return
        }
        draftText = ChatDraftStore.shared.draft(for: conversationId)
    }

    private func refreshOtherParticipantUsername() {
        let otherUserId = conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else {
            liveOtherParticipantUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: otherUserId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                self.liveOtherParticipantUsername = fetchedUsername
            }
        }
    }

    private func refreshOtherParticipantAvailability() {
        let otherUserId = conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty, NetworkMonitor.shared.isConnected else { return }

        firestoreService.checkPublicProfileAvailability(userId: otherUserId) { availability in
            DispatchQueue.main.async {
                guard self.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                if availability == .unavailable {
                    self.markOtherParticipantUnavailable(clearLiveUsername: true)
                } else {
                    self.refreshOtherParticipantBlockAvailability(userId: otherUserId)
                }
            }
        }
    }

    private func refreshOtherParticipantBlockAvailability(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.checkIfBlocked(currentUserId: currentUserId, targetUserId: userId) { isBlockedByCurrentUser, isCurrentUserBlocked, _ in
            DispatchQueue.main.async {
                guard self.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == userId else { return }

                if isBlockedByCurrentUser || isCurrentUserBlocked {
                    self.isOtherParticipantBlockedByCurrentUser = isBlockedByCurrentUser
                    self.markOtherParticipantUnavailable(clearLiveUsername: false)
                } else {
                    self.isOtherParticipantBlockedByCurrentUser = false
                    self.isOtherParticipantUnavailable = false
                    self.refreshOtherParticipantUsername()
                }
            }
        }
    }

    private func markOtherParticipantUnavailable(clearLiveUsername: Bool) {
        isOtherParticipantUnavailable = true
        if clearLiveUsername {
            liveOtherParticipantUsername = ""
            isOtherParticipantBlockedByCurrentUser = false
        }
        disableUnavailableParticipantStories()
    }

    private func disableUnavailableParticipantStories() {
        storyRoute = nil
    }
}

// Nueva conversación — pantalla completa
struct GlassmorphicNewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: MessagingViewModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var profileZoomNamespace
    @State private var searchText = ""
    @State private var showingUserProfile: AppUser?
    let onConversationCreated: (Conversation?) -> Void

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            GlassmorphicBackground(adaptiveColors: adaptiveColors)

            VStack(spacing: 0) {
                newConversationToField
                newConversationUserList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { newConversationToolbarContent }
        .navigationDestination(item: $showingUserProfile) { user in
            UserProfileView(userId: user.id)
                .userProfileZoomDestination(userId: user.id, namespace: profileZoomNamespace)
        }
        .onAppear {
            viewModel.searchUsers(query: "")
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchUsers(query: newValue)
        }
    }

    @ToolbarContentBuilder
    private var newConversationToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: adaptiveColors.primary,
                preset: .navigationBack,
                action: { dismiss() }
            )
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .principal) {
            Text("messaging.new.title")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
        }
    }

    private var newConversationToField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("messaging.new.to")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)

                TextField("messaging.new.searchPlaceholder", text: $searchText)
                    .font(.system(size: 16))
                    .foregroundStyle(adaptiveColors.primary)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        viewModel.searchUsers(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(adaptiveColors.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .overlay(adaptiveColors.secondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private var newConversationUserList: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.system(size: 14))
                .foregroundStyle(.red.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MessagingSectionHeader(title: "messaging.new.suggestions", adaptiveColors: adaptiveColors)
        }

        List {
            Section {
                if viewModel.suggestedUsers.isEmpty && searchText.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 24)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if viewModel.suggestedUsers.isEmpty && !searchText.isEmpty {
                    newConversationEmptyResults
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.suggestedUsers) { user in
                        NewConversationUserRow(
                            user: user,
                            profileZoomNamespace: profileZoomNamespace,
                            onOpenProfile: { showingUserProfile = user },
                            onSelect: { openConversation(with: user) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .messagingListEdgeToEdge()
        .chatScrollEdgeEffect()
        .scrollDismissesKeyboard(.interactively)
    }

    private var newConversationEmptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.slash")
                .font(.system(size: 32))
                .foregroundStyle(adaptiveColors.secondary.opacity(0.5))

            Text("messaging.noResults")
                .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func openConversation(with user: AppUser) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        viewModel.startConversation(with: user, from: userId, initialMessage: nil) { conversation in
            guard let conversation else { return }
            onConversationCreated(conversation)
        }
    }
}

private struct NewConversationUserRow: View {
    let user: AppUser
    let profileZoomNamespace: Namespace.ID
    let onOpenProfile: () -> Void
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpenProfile) {
                AsyncProfileImageView(userId: user.id)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .userProfileZoomSource(
                        userId: user.id,
                        namespace: profileZoomNamespace,
                        cornerRadius: 28
                    )
            }
            .buttonStyle(.plain)

            Button(action: onSelect) {
                Text(user.username)
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Message Composer View
struct MessagingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MessagingView(targetConversationId: .constant(nil))
                .environmentObject(AuthService())
                .environmentObject(MessagingViewModel())
        }
    }
}
