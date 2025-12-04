import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import Combine
import WidgetKit

// MARK: - Glassmorphic Components
struct GlassmorphicBackground: View {
    let adaptiveColors: AdaptiveColors
    
    var body: some View {
        ZStack {
            // ✅ FONDO ADAPTATIVO: Instagram-style en modo oscuro
            if adaptiveColors.colorScheme == .dark {
                // Negro elegante tipo Instagram - más suave
                Color(hex: "1A1A1A") // Negro más suave, menos agresivo
                    .ignoresSafeArea()
            } else {
                // Modo claro: mantener el diseño original
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "00A896").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Floating blobs for depth
                GeometryReader { geometry in
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.4))
                        .frame(width: 300, height: 300)
                        .blur(radius: 100)
                        .offset(x: -100, y: -100)
                    
                    Circle()
                        .fill(Color(hex: "02C39A").opacity(0.35))
                        .frame(width: 250, height: 250)
                        .blur(radius: 80)
                        .offset(x: geometry.size.width - 150, y: 200)
                    
                    Circle()
                        .fill(Color(hex: "F0F3BD").opacity(0.4))
                        .frame(width: 200, height: 200)
                        .blur(radius: 60)
                        .offset(x: 50, y: geometry.size.height - 200)
                }
            }
        }
    }
}

struct GlasssmorphicCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Glass effect
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.2))
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.25),
                                            Color.white.opacity(0.1)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.5),
                                            Color.white.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
    @State private var offsetValues: [String: CGFloat] = [:]
    
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var navigationService = NotificationNavigationService.shared
    // ✅ HISTORIAS: Estados para anillos de historias
    @State private var userStories: [String: (hasStory: Bool, hasUnseenStory: Bool)] = [:]
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
            }
            .sheet(isPresented: $showingMessageRequests) {
                MessageRequestsView()
            }
            // ✅ CAMBIO 2: navigationDestination en lugar de NavigationLink con isActive
            .navigationDestination(item: $selectedConversation) { conversation in
                GlassmorphicChatView(conversation: conversation)
            }
            .navigationDestination(isPresented: .constant(targetConversationId != nil)) {
                if let conversationId = targetConversationId {
                    // Buscar conversación por ID
                    if let conversation = viewModel.conversations.first(where: { $0.id == conversationId }) {
                        GlassmorphicChatView(conversation: conversation)
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
                } else {
                    viewModel.errorMessage = "Usuario no autenticado"
                }
                
                // ✅ AGREGAR: Verificar si hay conversación objetivo
                if let targetId = targetConversationId {
                    navigateToConversation(id: targetId)
                }
            }
            .onChange(of: authService.currentUser) { _ in
                if let userId = Auth.auth().currentUser?.uid {
                    viewModel.fetchConversations(for: userId)
                }
            }
            // ✅ AGREGAR: Listener para cuando cambie targetConversationId
            .onChange(of: targetConversationId) { newTargetId in
                if let targetId = newTargetId {
                    navigateToConversation(id: targetId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                viewModel.refreshVisibleUsers()
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
    
    // ✅ NUEVO: Función para verificar historias de usuarios
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        for conversation in viewModel.conversations {
            let otherUserId = conversation.otherParticipantId ?? ""
            if !otherUserId.isEmpty {
                checkUserStoryStatus(userId: otherUserId, currentUserId: currentUserId)
            }
        }
    }
    
    private func checkUserStoryStatus(userId: String, currentUserId: String) {
        Firestore.firestore().collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        userStories[userId] = (hasStory: false, hasUnseenStory: false)
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        userStories[userId] = (hasStory: false, hasUnseenStory: false)
                    }
                    return
                }
                
                // Verificar si alguna historia no ha sido vista
                var hasUnseenStory = false
                let group = DispatchGroup()
                
                for story in stories {
                    group.enter()
                    Firestore.firestore().collection("users").document(story.authorId)
                        .collection("stories").document(story.id ?? "")
                        .collection("viewers").document(currentUserId)
                        .getDocument { viewerDoc, _ in
                            let wasViewed = viewerDoc?.exists == true
                            if !wasViewed {
                                hasUnseenStory = true
                            }
                            group.leave()
                        }
                }
                
                group.notify(queue: .main) {
                    userStories[userId] = (hasStory: true, hasUnseenStory: hasUnseenStory)
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
                // New conversation button (izquierda)
                Button(action: {
                    isShowingNewConversation = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22))
                        .foregroundColor(adaptiveColors.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
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
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(adaptiveColors.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .scaleEffect(showingStatusSelector ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: showingStatusSelector)
                }
                
                Spacer()
                
                // Message requests button (derecha)
                Button(action: {
                    showingMessageRequests = true
                }) {
                    ZStack {
                        Image(systemName: "message.circle")
                            .font(.system(size: 22))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                        
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
                
                TextField("Buscar conversaciones...", text: $searchText)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(adaptiveColors.primary)
                    .accentColor(.white)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { newValue in
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
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(adaptiveColors.secondary.opacity(0.3), lineWidth: 1)
            )
            
            if isSearchFocused {
                Button("Cancelar") {
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
                             .foregroundColor(Color(hex: "00A896"))
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
                         .foregroundColor(Color(hex: "00A896"))
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
                 VStack(spacing: 0) { // ✅ Sin spacing entre conversaciones (estilo Instagram)
                     if isSearching {
                         searchResultsSection
                     } else {
                         conversationsSection
                     }
                 }
                 .padding(.horizontal, 0) // ✅ Sin padding horizontal (estilo Instagram)
                 .padding(.vertical, 0) // ✅ Sin padding vertical (estilo Instagram)
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
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        
        let chatService = ChatService()
        chatService.deleteConversationsBetweenUsers(user1Id: currentUserId, user2Id: conversation.otherParticipantId ?? "") { error in
            DispatchQueue.main.async {
                if let error = error {
                    // Error deleting conversation
                } else {
                    // Conversation deleted successfully
                }
            }
        }
    }
    
    private func pinConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        
        let chatService = ChatService()
        if conversation.isPinned == true {
            // Si ya está pinnada, despinnarla
            chatService.unpinConversation(conversationId, for: currentUserId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Error unpinning conversation
                    } else {
                        // Conversation unpinned successfully
                    }
                }
            }
        } else {
            // Si no está pinnada, pinnarla
            chatService.pinConversation(conversationId, for: currentUserId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Error pinning conversation
                    } else {
                        // Conversation pinned successfully
                    }
                }
            }
        }
    }
    
    private func muteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        
        let chatService = ChatService()
        if conversation.isMuted == true {
            // Si ya está silenciada, desilenciarla
            chatService.unmuteConversation(conversationId, for: currentUserId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Error unmuting conversation
                    } else {
                        // Conversation unmuted successfully
                    }
                }
            }
        } else {
            // Si no está silenciada, silenciarla
            chatService.muteConversation(conversationId, for: currentUserId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Error muting conversation
                    } else {
                        // Conversation muted successfully
                    }
                }
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
                        // ✅ Animación de feedback visual
                        offsetValues[conversationId] = -20
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            offsetValues[conversationId] = 0
                            selectedConversation = conversation // ✅ Navegar aquí
                        }
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
                .offset(x: offsetValues[conversationId] ?? 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offsetValues[conversationId])
            }
        }
    }
}

// ✅ NUEVO COMPONENTE: Conversación con swipe actions (estilo Instagram)
struct SwipeableConversationRow: View {
    let conversation: Conversation
    let onTap: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onMute: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var showingActions = false
    
    var body: some View {
        ZStack {
            // ✅ Acciones de fondo (aparecen al deslizar)
            HStack(spacing: 0) {
                Spacer()
                
                // Botón de silenciar (naranja)
                Button(action: onMute) {
                    Image(systemName: conversation.isMuted == true ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 80)
                        .background(conversation.isMuted == true ? Color.green : Color.orange)
                }
                
                // Botón de pin (azul)
                Button(action: onPin) {
                    Image(systemName: conversation.isPinned == true ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 80)
                        .background(conversation.isPinned == true ? Color.gray : Color.blue)
                }
                
                // Botón de eliminar (rojo)
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.red)
                }
            }
            .cornerRadius(20)
            
            // ✅ Fila de conversación principal (estilo Instagram)
            VStack(spacing: 0) {
                GlassmorphicConversationRow(conversation: conversation, onTap: onTap)
                    .background(Color.clear) // ✅ Sin fondo sólido, mantener transparencia
                    .offset(x: offset)
                
                // ✅ Separador sutil como Instagram
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.leading, 80) // Alineado con el texto
            }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = max(value.translation.width, -200)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if value.translation.width < -100 {
                                    offset = -200
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
}

// ✅ COMPONENTE para resultados de conversaciones en búsqueda
struct SearchConversationRow: View {
    let conversation: Conversation
    
    var body: some View {
        HStack(spacing: 14) {
            AsyncProfileImageView(userId: conversation.otherParticipantId ?? "")
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.otherParticipantUsername ?? "Usuario")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.white)
                
                Text(conversation.lastMessage ?? "Inicia un chat")
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
                            
                        case .failure(let error):
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
                    .foregroundColor(Color(hex: "00A896"))
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
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    
    // ✅ NUEVO: Estados para navegación
    @State private var showingUserProfile = false
    @State private var showingStories = false
    @State private var storiesUserId: String = ""
    
    // ✅ NUEVO: Instancia de PrivacyService para verificar historias
    private let privacyService = PrivacyService()
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // ✅ SEPARADO: Botón solo para la foto (historias o perfil)
                Button(action: {
                    if hasStory {
                        // ✅ SI TIENE HISTORIAS: Establecer userId y abrir StoriesView
                        storiesUserId = conversation.otherParticipantId
                        showingStories = true
                    } else {
                        // ✅ SI NO TIENE HISTORIAS: Ir al perfil
                        showingUserProfile = true
                    }
                }) {
                    AsyncProfileImageView(userId: conversation.otherParticipantId ?? "")
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: hasUnseenStory,
                                storyViewedStatus: storyViewedStatus,
                                isOwnStory: false,
                                colorScheme: colorScheme,
                                ringSize: 56,
                                lineWidth: 2.5
                            )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // ✅ SEPARADO: Botón solo para el nombre (siempre al perfil)
                    Button(action: {
                        showingUserProfile = true
                    }) {
                        HStack(spacing: 4) {
                            Text(conversation.otherParticipantUsername ?? "Usuario")
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(.white)
                            
                            // ✅ INSIGNIA DE VERIFICADO
                            VerifiedBadgeView(userId: conversation.otherParticipantId ?? "", size: 14)
                            
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
                    Text(conversation.lastMessage ?? "Inicia un chat")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(formattedTimestamp(conversation.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                if !(conversation.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .fill(Color(hex: "00A896"))
                                .frame(width: 8, height: 8)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassmorphic() // ✅ Mantener el efecto glassmorphic único
        .onAppear {
            checkUserStories()
        }
        // ✅ NUEVO: Sheet para mostrar historias del usuario
        .sheet(isPresented: $showingStories) {
            StoriesView(startWithUserId: .constant(storiesUserId))
        }
        // ✅ NUEVO: Sheet para navegación al perfil del usuario
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: conversation.otherParticipantId)
        }
    }
    
    // ✅ ACTUALIZADO: Función para verificar historias del usuario (con filtrado de privacidad como en reels)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = conversation.otherParticipantId ?? ""
        guard !otherUserId.isEmpty else { return }
        
        // ✅ USAR LA MISMA LÓGICA DE REELS: Verificar historias con filtrado de privacidad
        Firestore.firestore().collection("users").document(otherUserId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                // ✅ FILTRADO DE PRIVACIDAD: Solo contar historias que se pueden ver
                let group = DispatchGroup()
                var visibleStories: [(story: Story, wasViewed: Bool)] = []
                let syncQueue = DispatchQueue(label: "story.visibility.check")
                
                for story in stories {
                    group.enter()
                    // ✅ USAR PRIVACY SERVICE como en reels
                    self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                        if canView {
                            if let storyId = story.id {
                                group.enter()
                                Firestore.firestore().collection("users").document(story.authorId)
                                    .collection("stories").document(storyId)
                                    .collection("viewers").document(currentUserId)
                                    .getDocument { viewerDoc, _ in
                                        let wasViewed = viewerDoc?.exists == true
                                        syncQueue.async {
                                            visibleStories.append((story: story, wasViewed: wasViewed))
                                        }
                                        group.leave()
                                    }
                            } else {
                                syncQueue.async {
                                    visibleStories.append((story: story, wasViewed: false))
                                }
                            }
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    if !visibleStories.isEmpty {
                        self.hasStory = true
                        let storyCount = visibleStories.count
                        // Ordenar por timestamp y extraer el estado de visto
                        let sortedStories = visibleStories.sorted { story1, story2 in
                            (story1.story.timestamp ?? Date.distantPast) < (story2.story.timestamp ?? Date.distantPast)
                        }
                        let viewedStatus = sortedStories.map { $0.wasViewed }
                        let hasUnseenVisible = viewedStatus.contains(false)
                        
                        self.storyCount = storyCount
                        self.storyViewedStatus = viewedStatus
                        self.hasUnseenStory = hasUnseenVisible
                    } else {
                        self.hasStory = false
                        self.hasUnseenStory = false
                        self.storyCount = 0
                        self.storyViewedStatus = []
                    }
                }
            }
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
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
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassmorphicBackground(adaptiveColors: adaptiveColors)
                
                VStack(spacing: 20) {
                    // Search bar with glass effect
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Buscar usuario...", text: $searchText)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.white)
                            .accentColor(.white)
                    }
                    .padding(14)
                    .glassmorphic()
                    .padding(.horizontal)
                    .onChange(of: searchText) { newValue in
                        viewModel.searchUsers(query: newValue)
                    }
                    
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(10)
                            .glassmorphic()
                            .padding(.horizontal)
                    }
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.suggestedUsers) { user in
                                GlassmorphicUserRow(
                                    user: user,
                                    isSelected: selectedUser?.id == user.id,
                                    onTap: { selectedUser = user }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    if let selectedUser = selectedUser {
                        Button(action: {
                            showingMessageComposer = true
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.fill")
                                Text("messaging.startConversation")
                            }
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(Color(hex: "00A896"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Nueva conversación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
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
        viewModel.startConversation(with: selectedUser, from: userId, initialMessage: userMessage) {
            DispatchQueue.main.async {
                // Verificar si se creó la conversación exitosamente
                if let createdConversation = viewModel.conversations.first(where: { $0.otherParticipantId == selectedUser.id }) {
                    // Conversación creada exitosamente, enviar mensaje
                    dismiss()
                    onConversationCreated(createdConversation)
                } else {
                    // Verificar el tipo de error
                    let errorMessage = viewModel.errorMessage ?? ""
                    
                    if errorMessage.contains("no siguen mutuamente") || errorMessage.contains("Se requiere una solicitud") {
                        // No se pudo crear conversación directa, enviar solicitud
                        sendMessageRequest()
                    } else {
                        // Otro tipo de error
                    }
                }
            }
        }
    }
    
    // ✅ NUEVA: Función para enviar solicitud de mensaje
    private func sendMessageRequest() {
        guard let selectedUser = selectedUser,
              let userId = Auth.auth().currentUser?.uid else {
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
                    viewModel.errorMessage = "Solicitud de mensaje enviada. El usuario recibirá una notificación."
                case .failure(let error):
                    viewModel.errorMessage = "Error al enviar solicitud: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct GlassmorphicUserRow: View {
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // ✅ Usar AsyncProfileImageView
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
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
                    .foregroundColor(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.15))
                    }
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Message Composer View
struct MessageComposerView: View {
    let selectedUser: AppUser?
    @Binding var messageText: String
    let onSend: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "00A896").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // User Info
                    if let user = selectedUser {
                        VStack(spacing: 12) {
                            AsyncProfileImageView(userId: user.id)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            
                            Text(user.username)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(adaptiveColors.primary)
                            
                            Text("messaging.writeMessageToStart")
                                .font(.body)
                                .foregroundColor(adaptiveColors.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }
                    
                    Spacer()
                    
                    // Message Input
                    VStack(spacing: 16) {
                        TextField("Escribe tu mensaje...", text: $messageText, axis: .vertical)
                            .font(.body)
                            .foregroundColor(adaptiveColors.primary)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(adaptiveColors.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(adaptiveColors.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .lineLimit(3...6)
                        
                        Button(action: {
                            onSend()
                        }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("messaging.sendMessage")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                          adaptiveColors.secondary : Color(hex: "00A896"))
                            )
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Nuevo mensaje")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// ✅ NUEVO: Vista para seleccionar estado online
struct OnlineStatusSelectorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    let currentStatus: OnlineStatus
    let onStatusSelected: (OnlineStatus) -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background glassmórfico
                LinearGradient(
                    gradient: Gradient(colors: adaptiveColors.chatBackground),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(currentStatus.color)
                        
                        Text("Estado actual")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(adaptiveColors.secondary)
                        
                        Text(currentStatus.displayName)
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(adaptiveColors.primary)
                    }
                    .padding(.top, 20)
                    
                    // Estados disponibles
                    VStack(spacing: 12) {
                        ForEach(OnlineStatus.allCases, id: \.self) { status in
                            Button(action: {
                                onStatusSelected(status)
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: status.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(status.color)
                                        .frame(width: 24)
                                    
                                    Text(status.displayName)
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(adaptiveColors.primary)
                                    
                                    Spacer()
                                    
                                    if status == currentStatus {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(adaptiveColors.accent)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(adaptiveColors.cardBackground)
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            status == currentStatus ? 
                                            adaptiveColors.accent.opacity(0.5) : 
                                            Color.clear,
                                            lineWidth: 2
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Botón de cerrar
                    Button(action: { dismiss() }) {
                        Text("Cerrar")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(adaptiveColors.cardBackground)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(adaptiveColors.accent.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// ✅ ACTUALIZADO: MessagingViewModel con funciones de búsqueda
class MessagingViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var suggestedUsers: [AppUser] = []
    @Published var hasUnreadMessages: Bool = false
    @Published var selectedConversation: Conversation?
    @Published var errorMessage: String?
    
    // ✅ NUEVO: Propiedades para búsqueda
    @Published var filteredConversations: [Conversation] = []
    @Published var searchedUsers: [AppUser] = []
    @Published var isSearchingContent: Bool = false
    
    private let chatService = ChatService()
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        chatService.removeAllListeners()
    }
    
    func fetchConversations(for userId: String) {
        chatService.fetchConversations(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let conversations):
                    self.conversations = conversations.filter { $0.id != nil && !$0.id!.isEmpty }
                    self.hasUnreadMessages = conversations.contains { !($0.readStatus[userId] ?? true) }
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = "Error al cargar conversaciones: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func refreshUserData(userId: String) {
        UserCacheService.shared.refreshUser(userId: userId) { [weak self] user in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Actualizar conversaciones que contengan este usuario
                for i in 0..<self.conversations.count {
                    if self.conversations[i].otherParticipantId == userId {
                        self.conversations[i] = Conversation(
                            id: self.conversations[i].id,
                            participants: self.conversations[i].participants,
                            lastMessage: self.conversations[i].lastMessage,
                            timestamp: self.conversations[i].timestamp,
                            readStatus: self.conversations[i].readStatus,
                            otherParticipantId: userId,
                            otherParticipantUsername: user?.username ?? "Usuario",
                            otherParticipantProfileImagePath: user?.profileImagePath ?? ""
                        )
                    }
                }
                
                // También actualizar conversaciones filtradas si estamos buscando
                for i in 0..<self.filteredConversations.count {
                    if self.filteredConversations[i].otherParticipantId == userId {
                        self.filteredConversations[i] = Conversation(
                            id: self.filteredConversations[i].id,
                            participants: self.filteredConversations[i].participants,
                            lastMessage: self.filteredConversations[i].lastMessage,
                            timestamp: self.filteredConversations[i].timestamp,
                            readStatus: self.filteredConversations[i].readStatus,
                            otherParticipantId: userId,
                            otherParticipantUsername: user?.username ?? "Usuario",
                            otherParticipantProfileImagePath: user?.profileImagePath ?? ""
                        )
                    }
                }
                
            }
        }
    }

    // ✅ NUEVA: Refrescar los primeros usuarios visibles (como Instagram)
    func refreshVisibleUsers() {
        let visibleUsers = Array(conversations.prefix(10)) // Primeros 10
        for conversation in visibleUsers {
            // ✅ O DIRECTAMENTE ASÍ:
            refreshUserData(userId: conversation.otherParticipantId)
        }
    }
    
    // ✅ NUEVO: Búsqueda de conversaciones y usuarios
    func searchConversationsAndUsers(query: String) {
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        
        isSearchingContent = true
        
        // Filtrar conversaciones existentes
        filteredConversations = conversations.filter { conversation in
            let username = conversation.otherParticipantUsername?.lowercased() ?? ""
            let lastMessage = conversation.lastMessage?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return username.contains(searchQuery) || lastMessage.contains(searchQuery)
        }
        
        // Buscar usuarios (excluyendo los que ya tienen conversación)
        let existingUserIds = Set(conversations.compactMap { $0.otherParticipantId })
        
        FirestoreService().fetchSuggestedUsers { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSearchingContent = false
                
                switch result {
                case .success(let users):
                    self.searchedUsers = users.filter { user in
                        let matchesQuery = user.username.lowercased().contains(query.lowercased())
                        let notCurrentUser = user.id != Auth.auth().currentUser?.uid
                        let noExistingConversation = !existingUserIds.contains(user.id)
                        
                        return matchesQuery && notCurrentUser && noExistingConversation
                    }
                case .failure(let error):
                    self.searchedUsers = []
                }
            }
        }
    }
    
    // ✅ NUEVO: Limpiar búsqueda
    func clearSearch() {
        filteredConversations = []
        searchedUsers = []
        isSearchingContent = false
    }
    
    // ✅ NUEVO: Crear o encontrar conversación
    func createOrFindConversation(with user: AppUser, from userId: String, completion: @escaping (Conversation?) -> Void) {
        // Verificar si ya existe una conversación
        if let existingConversation = conversations.first(where: { $0.otherParticipantId == user.id }) {
            completion(existingConversation)
            return
        }
        
        // Verificar permisos antes de crear
        chatService.canSendMessage(from: userId, to: user.id) { [weak self] result in
            switch result {
            case .success(let canSend):
                if !canSend {
                    DispatchQueue.main.async {
                        self?.errorMessage = "No puedes iniciar una conversación con este usuario."
                    }
                    completion(nil)
                    return
                }
                
                // ✅ Crear conversación bidireccional
                self?.chatService.createBidirectionalConversation(user1Id: userId, user2Id: user.id) { result in
                    switch result {
                    case .success(let conversationId):
                        // Refrescar conversaciones para obtener la nueva
                        DispatchQueue.main.async {
                            self?.fetchConversations(for: userId)
                        }
                        completion(nil) // La conversación aparecerá en el refresh
                        
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self?.errorMessage = "Error al crear la conversación: \(error.localizedDescription)"
                        }
                        completion(nil)
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al verificar permisos: \(error.localizedDescription)"
                }
                completion(nil)
            }
        }
    }
    
    // ✅ NUEVO: Crear nueva conversación
    private func createNewConversation(with user: AppUser, from userId: String, completion: @escaping (Conversation?) -> Void) {
        let participants = [userId, user.id].sorted()
        let readStatus: [String: Bool] = [userId: true, user.id: false]
        let conversationData: [String: Any] = [
            "participants": participants,
            "lastMessage": "",
            "timestamp": FieldValue.serverTimestamp(),
            "readStatus": readStatus,
            "otherParticipantId": user.id,
            "otherParticipantUsername": user.username,
            "otherParticipantProfileImagePath": user.profileImagePath ?? ""
        ]
        
        let conversationRef = Firestore.firestore().collection("conversations").document()
        let conversationId = conversationRef.documentID
        
        conversationRef.setData(conversationData) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al crear la conversación: \(error.localizedDescription)"
                }
                completion(nil)
                return
            }
            
            let newConversation = Conversation(
                id: conversationId,
                participants: participants,
                lastMessage: "",
                timestamp: Date(),
                readStatus: readStatus,
                otherParticipantId: user.id,
                otherParticipantUsername: user.username,
                otherParticipantProfileImagePath: user.profileImagePath ?? ""
            )
            
            DispatchQueue.main.async {
                self?.conversations.insert(newConversation, at: 0)
                self?.selectedConversation = newConversation
            }
            
            completion(newConversation)
        }
    }
    
    func searchUsers(query: String) {
        if query.isEmpty {
            suggestedUsers = []
            return
        }
        // Assuming FirestoreService is still needed for user search
        FirestoreService().fetchSuggestedUsers { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.suggestedUsers = users.filter {
                        $0.username.lowercased().contains(query.lowercased()) &&
                        $0.id != Auth.auth().currentUser?.uid
                    }
                case .failure(let error):
                    self?.errorMessage = "Error al buscar usuarios: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startConversation(with user: AppUser, from userId: String, initialMessage: String? = nil, completion: @escaping () -> Void) {
        
        // Check if conversation already exists
        if let existingConversation = conversations.first(where: { $0.otherParticipantId == user.id && $0.id != nil }) {
            DispatchQueue.main.async {
                self.selectedConversation = existingConversation
                completion()
            }
            return
        }
        
        // Check if can send message
        chatService.canSendMessage(from: userId, to: user.id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let canSend):
                if !canSend {
                    DispatchQueue.main.async {
                        self.errorMessage = "No puedes iniciar una conversación con este usuario."
                        completion()
                    }
                    return
                }
                
                // ✅ Crear conversación con verificación de seguimiento mutuo
                self.chatService.getOrCreateConversation(between: userId, and: user.id, initialMessage: initialMessage) { result in
                    switch result {
                    case .success(let conversationId):
                        DispatchQueue.main.async {
                            // Refrescar para obtener la nueva conversación
                            self.fetchConversations(for: userId)
                            self.errorMessage = nil
                            completion()
                        }
                        
                    case .failure(let error):
                        DispatchQueue.main.async {
                            if error.localizedDescription.contains("no siguen mutuamente") {
                                self.errorMessage = "Los usuarios no se siguen mutuamente. Se requiere una solicitud de mensaje."
                            } else {
                                self.errorMessage = "Error al crear la conversación: \(error.localizedDescription)"
                            }
                            completion()
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Error al verificar permisos: \(error.localizedDescription)"
                    completion()
                }
            }
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        chatService.deleteConversationsBetweenUsers(
            user1Id: Auth.auth().currentUser?.uid ?? "",
            user2Id: conversation.otherParticipantId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al eliminar conversación: \(error.localizedDescription)"
                }
            } else {
                DispatchQueue.main.async {
                    self?.conversations.removeAll { $0.id == conversationId }
                    self?.hasUnreadMessages = self?.conversations.contains { !($0.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) } ?? false
                }
            }
        }
    }
    
    func markConversationAsUnread(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        Firestore.firestore()
            .collection("conversations")
            .document(conversationId)
            .updateData(["readStatus.\(Auth.auth().currentUser?.uid ?? "")": false]) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Error al marcar como no leído: \(error.localizedDescription)"
                    }
                } else {
                    DispatchQueue.main.async {
                        if let index = self?.conversations.firstIndex(where: { $0.id == conversationId }) {
                            var updatedConversation = conversation
                            var readStatus = conversation.readStatus
                            readStatus[Auth.auth().currentUser?.uid ?? ""] = false
                            updatedConversation.readStatus = readStatus
                            self?.conversations[index] = updatedConversation
                            self?.hasUnreadMessages = true
                        }
                    }
                }
            }
    }
    
    func stopListening() {
        chatService.removeAllListeners()
    }
}

struct MessagingView_Previews: PreviewProvider {
    static var previews: some View {
        MessagingView(targetConversationId: .constant(nil))
            .environmentObject(AuthService())
            .environmentObject(MessagingViewModel())
    }
}
