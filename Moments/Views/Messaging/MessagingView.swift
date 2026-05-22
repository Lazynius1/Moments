import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import Combine
import WidgetKit

private struct MessagingStoryRoute: Identifiable {
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
                .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
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
    @State private var selectedConversation: Conversation? // ✅ Solo para navigationDestination
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

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    // ✅ NUEVO: Instancia de PrivacyService para verificar historias
    private let privacyService = PrivacyService()

    var body: some View {
        ChatRecoveryGateView(onCancel: onDismiss) {
            NavigationStack { // ✅ CAMBIO 1: NavigationStack en lugar de NavigationView
                ZStack {
                    GlassmorphicBackground(adaptiveColors: adaptiveColors)

                    VStack(spacing: 0) {
                        glassmorphicTopBar

                        if !viewModel.conversations.isEmpty {
                            searchBar
                        }

                        conversationList
                    }
                }
                .navigationBarHidden(true)
                .sheet(isPresented: $isShowingNewConversation) {
                    GlassmorphicNewConversationView(viewModel: viewModel) { conversation in
                        if let conversation = conversation {
                            selectedConversation = conversation // ✅ Navegar automáticamente
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingMessageRequests) {
                    MessageRequestsView()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                // ✅ CAMBIO 2: navigationDestination en lugar de NavigationLink con isActive
                .navigationDestination(item: $selectedConversation) { conversation in
                    ChatRecoveryGateView(onCancel: {
                        selectedConversation = nil
                    }) {
                        GlassmorphicChatView(conversation: conversation)
                    }
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { targetConversationId != nil },
                        set: { isPresented in
                            if !isPresented {
                                targetConversationId = nil
                            }
                        }
                    )
                ) {
                    if let conversationId = targetConversationId {
                        // Buscar conversación por ID
                        if let conversation = viewModel.conversations.first(where: { $0.id == conversationId }) {
                            ChatRecoveryGateView(onCancel: {
                                targetConversationId = nil
                            }) {
                                GlassmorphicChatView(conversation: conversation)
                            }
                        } else {
                            // Fallback si no se encuentra la conversación
                            Text("messaging.conversation.notFound")
                                .onAppear {
                                    targetConversationId = nil
                                }
                        }
                    }
                }

                .onAppear {
                    if let userId = Auth.auth().currentUser?.uid {
                        viewModel.fetchConversations(for: userId)
                        // ✅ SOLICITUDES: Escuchar solicitudes pendientes
                        messageRequestService.listenToPendingRequests(for: userId)
                        updatePendingRequestCount(for: userId)
                    }

                    // ✅ AGREGAR: Verificar si hay conversación objetivo
                    if let targetId = targetConversationId {
                        navigateToConversation(id: targetId)
                    }
                }
                .onChange(of: authService.currentUser) { _, _ in
                    if let userId = Auth.auth().currentUser?.uid {
                        viewModel.errorMessage = nil
                        viewModel.fetchConversations(for: userId)
                        messageRequestService.listenToPendingRequests(for: userId)
                        updatePendingRequestCount(for: userId)
                    } else {
                        viewModel.stopListening()
                        viewModel.errorMessage = nil
                        viewModel.conversations = []
                        viewModel.filteredConversations = []
                        viewModel.hasUnreadMessages = false
                        messageRequestService.removeAllListeners()
                        messageRequestService.pendingRequests = []
                        messageRequestService.errorMessage = nil
                    }
                }
                // ✅ AGREGAR: Listener para cuando cambie targetConversationId
                .onChange(of: targetConversationId) { _, newTargetId in
                    if let targetId = newTargetId {
                        navigateToConversation(id: targetId)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    viewModel.refreshVisibleUsers()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationMuteStateChanged"))) { notification in
                    guard let conversationId = notification.userInfo?["conversationId"] as? String,
                          let isMuted = notification.userInfo?["isMuted"] as? Bool else { return }
                    viewModel.applyLocalConversationState(conversationId: conversationId, isMuted: isMuted)
                }
                .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
                    if !viewModel.conversations.isEmpty {
                        viewModel.refreshVisibleUsers()
                    }
                }
                .onReceive(navigationService.$pendingNavigation) { navigation in
                    guard let navigation = navigation else { return }

                    if case .conversation(let conversationId) = navigation {
                        targetConversationId = conversationId
                        navigationService.clearPendingNavigation()
                    }
                }
                .onDisappear {
                    viewModel.stopListening()
                    messageRequestService.removeAllListeners()
                }
            }
        }
    }

    private func navigateToConversation(id: String) {
        // Buscar conversación en la lista cargada
        if let conversation = viewModel.conversations.first(where: { $0.id == id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedConversation = conversation
                targetConversationId = nil  // Limpiar objetivo
            }
        } else {
            // Esperar un poco y reintentar (por si las conversaciones se están cargando)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let conversation = viewModel.conversations.first(where: { $0.id == id }) {
                    selectedConversation = conversation
                    targetConversationId = nil
                } else {
                    targetConversationId = nil
                }
            }
        }
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

    private var glassmorphicTopBar: some View {
        VStack(spacing: 8) {
            HStack {
                if let onDismiss = onDismiss {
                    // Close button if presented fullscreen
                    Button(action: { onDismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 44, height: 44)
                            .liquidGlass(in: Circle())
                    }
                } else {
                    // New conversation button (izquierda)
                    Button(action: {
                        isShowingNewConversation = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 22))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 44, height: 44)
                            .liquidGlass(in: Circle())
                    }
                }

                Spacer()

                // Title centered con selector de estados
                VStack(spacing: 4) {
                    Text("messaging.title")
                        .font(.custom("Poppins-Bold", size: 26))
                        .foregroundColor(adaptiveColors.primary)

                    // ✅ NUEVO: Selector de estados online
                    Button(action: {
                        showingStatusSelector = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: onlineStatusService.currentUserStatus.icon)
                                .font(.system(size: 12))
                                .foregroundColor(onlineStatusService.currentUserStatus.color)

                            Text(onlineStatusService.currentUserStatus.displayName)
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.secondary)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(adaptiveColors.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule())
                    }
                    .scaleEffect(showingStatusSelector ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: showingStatusSelector)
                }

                Spacer()

                HStack(spacing: 12) {
                    if onDismiss != nil {
                        // New conversation button moved here if presented fullscreen
                        Button(action: {
                            isShowingNewConversation = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 20))
                                .foregroundColor(adaptiveColors.primary)
                                .frame(width: 44, height: 44)
                                .liquidGlass(in: Circle())
                        }
                    }

                    // Message requests button (derecha)
                    Button(action: {
                        showingMessageRequests = true
                    }) {
                        ZStack {
                            Image(systemName: "message.circle")
                                .font(.system(size: 22))
                                .foregroundColor(adaptiveColors.primary)
                                .frame(width: 44, height: 44)
                                .liquidGlass(in: Circle())

                            // Badge for pending requests
                            if pendingRequestCount > 0 {
                                Text("\(pendingRequestCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color(hex: "FF3B30"))
                                    )
                                    .offset(x: 12, y: -12)
                            }
                        }
                    }
                }
            }

            // ✅ NUEVO: Sheet para seleccionar estado
            .sheet(isPresented: $showingStatusSelector) {
                OnlineStatusSelectorView(
                    currentStatus: onlineStatusService.currentUserStatus,
                    onStatusSelected: { newStatus in
                        onlineStatusService.setGlobalStatus(newStatus)
                        showingStatusSelector = false
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // ✅ NUEVO: Barra de búsqueda
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(adaptiveColors.secondary)
                    .font(.system(size: 16))

                TextField(NSLocalizedString("messaging.search.placeholder", comment: "Search conversations placeholder"), text: $searchText)
                    .font(.custom("Poppins-Regular", size: 15))
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
            .liquidGlass(in: Capsule())

            if isSearchFocused {
                Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                    searchText = ""
                    isSearching = false
                    isSearchFocused = false
                    viewModel.clearSearch()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(adaptiveColors.primary)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
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
                         .font(.custom("Poppins-Regular", size: 16))
                         .foregroundColor(.white)
                         .multilineTextAlignment(.center)
                         .padding(.horizontal)

                     Button(action: {
                         if let userId = Auth.auth().currentUser?.uid {
                             viewModel.fetchConversations(for: userId)
                         }
                     }) {
                         Text("messaging.retry")
                             .font(.custom("Poppins-SemiBold", size: 16))
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
         } else if viewModel.conversations.isEmpty && !isSearching {
             VStack(spacing: 20) {
                 Spacer()

                 VStack(spacing: 16) {
                     Image(systemName: "bubble.left.and.bubble.right.fill")
                         .font(.system(size: 60))
                         .foregroundColor(.white.opacity(0.8))

                     Text("messaging.noConversations.title")
                         .font(.custom("Poppins-SemiBold", size: 18))
                         .foregroundColor(.white)

                     Text("messaging.noConversations.subtitle")
                         .font(.custom("Poppins-Regular", size: 14))
                         .foregroundColor(.white.opacity(0.8))

                     Button(action: {
                         isShowingNewConversation = true
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                             Text("messaging.newConversation")
                         }
                         .font(.custom("Poppins-SemiBold", size: 16))
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
         } else {
             ScrollView(showsIndicators: false) {
                 VStack(spacing: 0) { // ✅ Sin spacing entre conversaciones
                     if isSearching {
                         searchResultsSection
                     } else {
                         conversationsSection
                     }
                 }
                 .padding(.horizontal, 0) // ✅ Sin padding horizontal
                 .padding(.vertical, 0) // ✅ Sin padding vertical
             }
         }
     }

    // ✅ NUEVO: Sección de resultados de búsqueda
    @ViewBuilder
    private var searchResultsSection: some View {
        // Conversaciones existentes que coinciden
        if !viewModel.filteredConversations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("messaging.conversations")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 4)

                ForEach(viewModel.filteredConversations) { conversation in
                    // ✅ CAMBIO 3: Button en lugar de NavigationLink
                    Button(action: {
                        selectedConversation = conversation
                    }) {
                        SearchConversationRow(conversation: conversation)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }

        // Usuarios encontrados
        if !viewModel.searchedUsers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("messaging.users")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.top, viewModel.filteredConversations.isEmpty ? 0 : 16)

                ForEach(viewModel.searchedUsers) { user in
                    SearchUserRow(user: user) { conversation in
                        if let conversation = conversation {
                            selectedConversation = conversation // ✅ Navegar automáticamente
                            searchText = ""
                            isSearching = false
                            isSearchFocused = false
                            viewModel.clearSearch()
                        }
                    }
                }
            }
        }

        // Sin resultados
        if viewModel.filteredConversations.isEmpty && viewModel.searchedUsers.isEmpty && !searchText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.6))

                Text("messaging.noResults")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)

                Text("messaging.noResults.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .glassmorphic()
        }
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

    // ✅ NUEVO: Sección de conversaciones normales con swipe actions
    @ViewBuilder
    private var conversationsSection: some View {
        ForEach(viewModel.conversations) { conversation in
            if let conversationId = conversation.id, !conversationId.isEmpty {
                SwipeableConversationRow(
                    conversation: conversation,
                    onTap: {
                        selectedConversation = conversation
                    },
                    onDelete: {
                        deleteConversation(conversation)
                    },
                    onPin: {
                        pinConversation(conversation)
                    },
                    onMute: {
                        muteConversation(conversation)
                    }
                )
            }
        }
    }
}

// ✅ NUEVO COMPONENTE: Conversación con swipe actions
struct SwipeableConversationRow: View {
    let conversation: Conversation
    let onTap: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onMute: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showingActions = false
    @State private var isSwipeGestureActive = false
    @Environment(\.colorScheme) private var colorScheme

    private var rowMaskColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var swipeHighlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035)
    }

    private let swipeOpenThreshold: CGFloat = 96
    private let swipeMaxOffset: CGFloat = 200
    private let swipeActivationThreshold: CGFloat = 34

    var body: some View {
        ZStack {
            // ✅ Acciones de fondo (aparecen al deslizar)
            HStack(spacing: 4) {
                Spacer()

                // Botón de silenciar
                Button(action: {
                    closeSwipeThenPerform(onMute)
                }) {
                    Image(systemName: conversation.isMuted == true ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)

                // Botón de pin
                Button(action: {
                    closeSwipeThenPerform(onPin)
                }) {
                    Image(systemName: conversation.isPinned == true ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)

                // Botón de eliminar
                Button(action: {
                    closeSwipeThenPerform(onDelete)
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .opacity(offset < -12 ? 1 : 0)
            .allowsHitTesting(offset < -12)
            .zIndex(2)

            // ✅ Fila de conversación principal
            GlassmorphicConversationRow(conversation: conversation, onTap: onTap)
                .background(offset < -2 ? rowMaskColor : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(swipeHighlightColor)
                        .opacity(offset < -2 ? min(abs(offset) / 140, 1) : 0)
                )
                .offset(x: offset)
                .contentShape(Rectangle())
                .zIndex(1)
                .gesture(
                    DragGesture(minimumDistance: 24, coordinateSpace: .local)
                        .onChanged { value in
                            let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                            guard isHorizontal else { return }

                            if !isSwipeGestureActive {
                                guard abs(value.translation.width) > swipeActivationThreshold else { return }
                                isSwipeGestureActive = true
                            }

                            if showingActions {
                                offset = min(0, max(-swipeMaxOffset + value.translation.width, -swipeMaxOffset))
                            } else if value.translation.width < 0 {
                                offset = max(value.translation.width, -swipeMaxOffset)
                            }
                        }
                        .onEnded { value in
                            defer { isSwipeGestureActive = false }

                            guard isSwipeGestureActive else { return }

                            let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                            guard isHorizontal else { return }

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                let proposedOffset = showingActions
                                    ? (-swipeMaxOffset + value.translation.width)
                                    : value.translation.width

                                if proposedOffset < -swipeOpenThreshold {
                                    offset = -swipeMaxOffset
                                    showingActions = true
                                } else {
                                    offset = 0
                                    showingActions = false
                                }
                            }
                        }
                )
                .onTapGesture {
                    if offset == 0 {
                        onTap()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = 0
                            showingActions = false
                        }
                    }
                }
        }
        .clipped()
    }

    private func closeSwipeThenPerform(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            offset = 0
            showingActions = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            action()
        }
    }
}

// ✅ COMPONENTE para resultados de conversaciones en búsqueda
struct SearchConversationRow: View {
    let conversation: Conversation
    @State private var liveOtherParticipantUsername: String = ""

    private var displayUsername: String {
        let fallback = conversation.otherParticipantUsername ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    var body: some View {
        HStack(spacing: 14) {
            AsyncProfileImageView(userId: conversation.otherParticipantId)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayUsername)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.white)

                Text(conversation.messagePreview)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassmorphic()
        .onAppear {
            refreshOtherParticipantUsername()
        }
        .onChange(of: conversation.otherParticipantId) { _, _ in
            refreshOtherParticipantUsername()
        }
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
}

// ✅ COMPONENTE ACTUALIZADO para usuarios en búsqueda
struct SearchUserRow: View {
    let user: AppUser
    let onTap: (Conversation?) -> Void

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
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(.white)

                    Text("messaging.tapToStartConversation")
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "007AFF"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassmorphic()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Glassmorphic Conversation Row
struct GlassmorphicConversationRow: View {
    let conversation: Conversation
    let onTap: () -> Void // ✅ NUEVO: Callback para abrir el chat
    @Environment(\.colorScheme) var colorScheme

    // ✅ NUEVO: Estados para navegación
    @State private var showingUserProfile = false
    @State private var storyRoute: MessagingStoryRoute?
    @State private var liveOtherParticipantUsername: String = ""
    @State private var isOtherParticipantUnavailable: Bool = false
    @State private var isOtherParticipantBlockedByCurrentUser: Bool = false
    private let firestoreService = FirestoreService()

    private var displayUsername: String {
        let fallback = conversation.otherParticipantUsername ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
                    Button(action: {
                        showingUserProfile = true
                    }) {
                        ProfileUnavailableAvatar(size: 56)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    StoryRingAvatarView(
                        userId: conversation.otherParticipantId,
                        size: 56,
                        lineWidth: 2.5,
                        isOwnStory: false,
                        hapticsEnabled: true
                    ) { hasStory in
                        guard !isOtherParticipantBlockedByCurrentUser else {
                            showingUserProfile = true
                            return
                        }

                        if hasStory {
                            storyRoute = MessagingStoryRoute(id: conversation.otherParticipantId)
                        } else {
                            showingUserProfile = true
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // ✅ SEPARADO: Botón solo para el nombre (siempre al perfil)
                    Button(action: {
                        showingUserProfile = true
                    }) {
                        HStack(spacing: 4) {
                            Text(displayUsername)
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .strikethrough(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser, color: colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(isOtherParticipantUnavailable ? 0.72 : 1.0))

                            // ✅ INSIGNIA DE VERIFICADO
                            if !isOtherParticipantUnavailable {
                                VerifiedBadgeView(userId: conversation.otherParticipantId, size: 14)
                            }

                            // ✅ INDICADOR DE PIN
                            if conversation.isPinned == true {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }

                            // ✅ INDICADOR DE MUTE
                            if conversation.isMuted == true {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // ✅ SEPARADO: Botón para el resto de la fila (abrir chat)
                Button(action: {
                    onTap() // ✅ Abrir el chat
                }) {
                    Text(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser ? NSLocalizedString("messaging.profileUnavailable.preview", comment: "Unavailable profile preview") : conversation.messagePreview)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(formattedTimestamp(conversation.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.5))

                if !(conversation.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) {
                    Circle()
                        .fill(Color(hex: "007AFF"))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
        .onAppear {
            refreshOtherParticipantUsername()
            refreshOtherParticipantAvailability()
        }
        .onChange(of: conversation.otherParticipantId) { _, _ in
            refreshOtherParticipantUsername()
            refreshOtherParticipantAvailability()
        }
        // ✅ NUEVO: Sheet para mostrar historias del usuario
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.id))
                .ignoresSafeArea(.keyboard) // ✅ Prevenir shift del keyboard
        }
        // ✅ NUEVO: Sheet para navegación al perfil del usuario
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: conversation.otherParticipantId)
        }
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

    private func formattedTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("notifications.date.yesterday", comment: "Yesterday")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// ✅ ACTUALIZADA: Glassmorphic New Conversation View CON CALLBACK
struct GlassmorphicNewConversationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: MessagingViewModel
    @EnvironmentObject var messageRequestService: MessageRequestService
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText: String = ""
    @State private var selectedUser: AppUser?
    @State private var showingMessageComposer = false
    @State private var messageText = ""
    let onConversationCreated: (Conversation?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color.clear.liquidGlass(in: Circle(), interactive: true))
                }

                Spacer()

                Text(NSLocalizedString("messaging.new.title", comment: "New conversation title"))
                    .font(.custom("Poppins-SemiBold", size: 22))
                    .foregroundColor(.primary)

                Spacer()

                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 20)

            VStack(spacing: 24) {
                    // ✅ LIQUID GLASS SEARCH BAR (CÁPSULA)
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary.opacity(searchText.isEmpty ? 0.3 : 0.7))
                            .scaleEffect(searchText.isEmpty ? 1.0 : 1.1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: searchText.isEmpty)

                        TextField("", text: $searchText, prompt:
                            Text(NSLocalizedString("messaging.new.searchPlaceholder", comment: "Search user placeholder"))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                .font(.system(size: 17))
                        )
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .accentColor(Color(hex: "4F46E5"))
                        .onChange(of: searchText) { _, newValue in
                            viewModel.searchUsers(query: newValue)
                        }

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.primary.opacity(0.4))
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .liquidGlass(in: Capsule())
                    .padding(.horizontal, 14)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.red.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                            .padding(.horizontal, 14)
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(viewModel.suggestedUsers) { user in
                                GlassmorphicUserRow(
                                    user: user,
                                    isSelected: selectedUser?.id == user.id,
                                    onTap: { selectedUser = user }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    }

                    if selectedUser != nil {
                        Button(action: {
                            showingMessageComposer = true
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.fill")
                                Text("messaging.startConversation")
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: "4F46E5").opacity(0.4), radius: 20, x: 0, y: 10)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
            }
        }
        //.preferredColorScheme(.dark) // ❌ ELIMINADO: Respetar tema del sistema/app
        .navigationBarHidden(true)
        .sheet(isPresented: $showingMessageComposer) {
            MessageComposerView(
                selectedUser: selectedUser,
                messageText: $messageText,
                onSend: sendMessageOrRequest
            )
        }
    }

    // ✅ NUEVA: Función para enviar mensaje o solicitud
    private func sendMessageOrRequest() {
        guard let selectedUser = selectedUser,
              let userId = Auth.auth().currentUser?.uid,
              !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let userMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Intentar crear conversación directa primero
        viewModel.startConversation(with: selectedUser, from: userId, initialMessage: userMessage) { conversation in
            DispatchQueue.main.async {
                if let conversation {
                    // Conversación creada/recuperada con envío inicial exitoso
                    showingMessageComposer = false
                    dismiss()
                    onConversationCreated(conversation)
                } else {
                    // Verificar el tipo de error
                    let errorMessage = viewModel.errorMessage ?? ""

                    if viewModel.requiresMessageRequest {
                        // No se pudo crear conversación directa, enviar solicitud
                        sendMessageRequest()
                    } else {
                        viewModel.errorMessage = errorMessage.isEmpty
                            ? NSLocalizedString("messaging.error.startConversationFailed", comment: "Failed to start conversation")
                            : errorMessage
                    }
                }
            }
        }
    }

    // ✅ NUEVA: Función para enviar solicitud de mensaje
    private func sendMessageRequest() {
        guard let selectedUser = selectedUser,
              Auth.auth().currentUser?.uid != nil else {
            return
        }


        messageRequestService.sendMessageRequest(
            to: selectedUser.id,
            message: messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    dismiss()
                    // Mostrar mensaje de éxito
                    viewModel.requiresMessageRequest = false
                    viewModel.errorMessage = NSLocalizedString("messaging.request.sent", comment: "Message request sent successfully")
                case .failure(let error):
                    viewModel.errorMessage = String(
                        format: NSLocalizedString("messaging.error.sendRequest", comment: "Failed to send message request"),
                        error.localizedDescription
                    )
                }
            }
        }
    }
}

struct GlassmorphicUserRow: View {
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // ✅ Usar AsyncProfileImageView
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.1),
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)

                    AsyncProfileImageView(userId: user.id)
                        .frame(width: 46, height: 46)
                }

                Text(user.username)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "4F46E5"))
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "4F46E5").opacity(0.15))
                    }
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Message Composer View
struct MessagingView_Previews: PreviewProvider {
    static var previews: some View {
        MessagingView(targetConversationId: .constant(nil))
            .environmentObject(AuthService())
            .environmentObject(MessagingViewModel())
    }
}
