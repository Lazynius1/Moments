import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import Combine

// MARK: - Glassmorphic Components
struct GlassmorphicBackground: View {
    let adaptiveColors: AdaptiveColors
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: adaptiveColors.messagingBackground), // ✅ SIMPLIFICADO
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating blobs for depth
            GeometryReader { geometry in
                Circle()
                    .fill(Color(hex: "00A896").opacity(adaptiveColors.colorScheme == .dark ? 0.3 : 0.4))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: -100, y: -100)
                
                Circle()
                    .fill(Color(hex: "02C39A").opacity(adaptiveColors.colorScheme == .dark ? 0.3 : 0.35))
                    .frame(width: 250, height: 250)
                    .blur(radius: 80)
                    .offset(x: geometry.size.width - 150, y: 200)
                
                Circle()
                    .fill(Color(hex: "F0F3BD").opacity(adaptiveColors.colorScheme == .dark ? 0.3 : 0.4))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: 50, y: geometry.size.height - 200)
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
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
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
                        Text("Conversación no encontrada")
                            .onAppear {
                                targetConversationId = nil
                            }
                    }
                }
            }
            
            .onAppear {
                if let userId = Auth.auth().currentUser?.uid {
                    viewModel.fetchConversations(for: userId)
                } else {
                    viewModel.errorMessage = "Usuario no autenticado"
                }
                
                // ✅ AGREGAR: Verificar si hay conversación objetivo
                if let targetId = targetConversationId {
                    print("🎯 MessagingView: Buscando conversación objetivo: \(targetId)")
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
                    print("🎯 MessagingView: Nuevo objetivo de conversación: \(targetId)")
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
                    print("🔔 MessagingView: Navegando a conversación \(conversationId)")
                    targetConversationId = conversationId
                    navigationService.clearPendingNavigation()
                }
            }
        }
    }
    
    private func navigateToConversation(id: String) {
        // Buscar conversación en la lista cargada
        if let conversation = viewModel.conversations.first(where: { $0.id == id }) {
            print("✅ Conversación encontrada en lista: \(id)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedConversation = conversation
                targetConversationId = nil  // Limpiar objetivo
            }
        } else {
            print("⚠️ Conversación no encontrada en lista: \(id)")
            // Esperar un poco y reintentar (por si las conversaciones se están cargando)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let conversation = viewModel.conversations.first(where: { $0.id == id }) {
                    print("✅ Conversación encontrada tras reintento: \(id)")
                    selectedConversation = conversation
                    targetConversationId = nil
                } else {
                    print("❌ Conversación no encontrada tras reintento: \(id)")
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
    
    private var glassmorphicTopBar: some View {
        HStack {
            // Camera button with glass effect
            Button(action: {
                print("Opening camera")
            }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 44, height: 44)
                    .glassmorphic()
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Title with glass background
            Text("Mensajes")
                .font(.custom("Poppins-Bold", size: 26))
                .foregroundColor(adaptiveColors.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .glassmorphic()
                .clipShape(Capsule())
            
            Spacer()
            
            // New conversation button
            Button(action: {
                isShowingNewConversation = true
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 44, height: 44)
                    .glassmorphic()
                    .clipShape(Circle())
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
                    .foregroundColor(adaptiveColors.mediaIconColor)
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
                            .foregroundColor(adaptiveColors.mediaIconColor)
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
                    .stroke(adaptiveColors.searchBarStroke, lineWidth: 1)
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
                         Text("Reintentar")
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
                     
                     Text("No tienes conversaciones aún")
                         .font(.custom("Poppins-SemiBold", size: 18))
                         .foregroundColor(.white)
                     
                     Text("Inicia una nueva conversación")
                         .font(.custom("Poppins-Regular", size: 14))
                         .foregroundColor(.white.opacity(0.8))
                     
                     Button(action: {
                         isShowingNewConversation = true
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                             Text("Nueva conversación")
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
                 VStack(spacing: 12) {
                     if isSearching {
                         searchResultsSection
                     } else {
                         conversationsSection
                     }
                 }
                 .padding(.horizontal, 16)
                 .padding(.vertical, 10)
             }
         }
     }
    
    // ✅ NUEVO: Sección de resultados de búsqueda
    @ViewBuilder
    private var searchResultsSection: some View {
        // Conversaciones existentes que coinciden
        if !viewModel.filteredConversations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conversaciones")
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
                Text("Usuarios")
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
                
                Text("Sin resultados")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                
                Text("No se encontraron usuarios ni conversaciones")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .glassmorphic()
        }
    }
    
    // ✅ NUEVO: Sección de conversaciones normales
    @ViewBuilder
    private var conversationsSection: some View {
        ForEach(viewModel.conversations) { conversation in
            if let conversationId = conversation.id, !conversationId.isEmpty {
                Button(action: {
                    print("🔍 Conversation tapped: \(conversationId)")
                    // ✅ Animación de feedback visual
                    offsetValues[conversationId] = -20
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        offsetValues[conversationId] = 0
                        selectedConversation = conversation // ✅ Navegar aquí
                    }
                }) {
                    GlassmorphicConversationRow(conversation: conversation)
                        .offset(x: offsetValues[conversationId] ?? 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offsetValues[conversationId])
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
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
                            print("✅ Conversation ready: \(conversationId)")
                            
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
                            print("❌ Error creating conversation: \(error)")
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
                    
                    Text("Tocar para iniciar conversación")
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
    @Environment(\.colorScheme) var colorScheme
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                AsyncProfileImageView(userId: conversation.otherParticipantId ?? "")
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 0)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(conversation.otherParticipantUsername ?? "Usuario")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: conversation.otherParticipantId ?? "", size: 14)
                }
                
                Text(conversation.lastMessage ?? "Inicia un chat")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
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
        .glassmorphic()
        .onAppear {
            checkUserStories()
        }
    }
    
    private var storyRingGradient: LinearGradient {
        if hasUnseenStory {
            // ✅ HISTORIA NO VISTA: Gradiente azul → morado → rosa
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasStory {
            // ✅ HISTORIA YA VISTA: Gris según el tema
            return LinearGradient(
                colors: colorScheme == .dark ?
                [Color.gray.opacity(0.5), Color.gray.opacity(0.7)] :
                [Color.gray.opacity(0.7), Color.gray.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // ✅ SIN HISTORIAS: Sin anillo (transparente)
            return LinearGradient(
                colors: [Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = conversation.otherParticipantId ?? ""
        guard !otherUserId.isEmpty else { return }
        
        Firestore.firestore().collection("users").document(otherUserId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        hasStory = false
                        hasUnseenStory = false
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        hasStory = false
                        hasUnseenStory = false
                    }
                    return
                }
                
                // Verificar si alguna historia no ha sido vista
                var hasUnseen = false
                let group = DispatchGroup()
                
                for story in stories {
                    group.enter()
                    Firestore.firestore().collection("users").document(story.authorId)
                        .collection("stories").document(story.id ?? "")
                        .collection("viewers").document(currentUserId)
                        .getDocument { viewerDoc, _ in
                            let wasViewed = viewerDoc?.exists == true
                            if !wasViewed {
                                hasUnseen = true
                            }
                            group.leave()
                        }
                }
                
                group.notify(queue: .main) {
                    hasStory = true
                    hasUnseenStory = hasUnseen
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
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText: String = ""
    @State private var selectedUser: AppUser?
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
                            if let userId = Auth.auth().currentUser?.uid {
                                // ✅ USAR startConversation Y NAVEGAR
                                viewModel.startConversation(with: selectedUser, from: userId) {
                                    DispatchQueue.main.async {
                                        // ✅ BUSCAR LA CONVERSACIÓN CREADA
                                        if let createdConversation = viewModel.conversations.first(where: { $0.otherParticipantId == selectedUser.id }) {
                                            // ✅ CERRAR MODAL Y NAVEGAR
                                            dismiss()
                                            onConversationCreated(createdConversation)
                                        } else if viewModel.errorMessage == nil {
                                            // ✅ FALLBACK: Crear conversación manual
                                            let conversation = Conversation(
                                                id: UUID().uuidString,
                                                participants: [userId, selectedUser.id],
                                                lastMessage: "",
                                                timestamp: Date(),
                                                readStatus: [userId: true, selectedUser.id: false],
                                                otherParticipantId: selectedUser.id,
                                                otherParticipantUsername: selectedUser.username,
                                                otherParticipantProfileImagePath: selectedUser.profileImagePath
                                            )
                                            
                                            dismiss()
                                            onConversationCreated(conversation)
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.fill")
                                Text("Iniciar conversación")
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
        print("MessagingViewModel deinitialized")
    }
    
    func fetchConversations(for userId: String) {
        print("MessagingViewModel: Fetching conversations for user: \(userId)")
        chatService.fetchConversations(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let conversations):
                    print("Fetched \(conversations.count) conversations")
                    self.conversations = conversations.filter { $0.id != nil && !$0.id!.isEmpty }
                    self.hasUnreadMessages = conversations.contains { !($0.readStatus[userId] ?? true) }
                    self.errorMessage = nil
                case .failure(let error):
                    print("Error fetching conversations: \(error.localizedDescription)")
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
                
                print("🔄 Usuario actualizado: \(userId)")
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
        print("🔄 Refrescando usuarios visibles...")
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
                    print("Error searching users: \(error.localizedDescription)")
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
                        print("✅ Conversación bidireccional creada: \(conversationId)")
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
        print("Searching users with query: \(query)")
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
                    print("Error searching users: \(error.localizedDescription)")
                    self?.errorMessage = "Error al buscar usuarios: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startConversation(with user: AppUser, from userId: String, completion: @escaping () -> Void) {
        print("Starting conversation with user: \(user.id)")
        
        // Check if conversation already exists
        if let existingConversation = conversations.first(where: { $0.otherParticipantId == user.id && $0.id != nil }) {
            print("Existing conversation found: \(existingConversation.id!)")
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
                    print("Cannot start conversation with \(user.id)")
                    DispatchQueue.main.async {
                        self.errorMessage = "No puedes iniciar una conversación con este usuario."
                        completion()
                    }
                    return
                }
                
                // ✅ Crear conversación bidireccional
                self.chatService.createBidirectionalConversation(user1Id: userId, user2Id: user.id) { result in
                    switch result {
                    case .success(let conversationId):
                        print("✅ Conversación bidireccional creada: \(conversationId)")
                        DispatchQueue.main.async {
                            // Refrescar para obtener la nueva conversación
                            self.fetchConversations(for: userId)
                            self.errorMessage = nil
                            completion()
                        }
                        
                    case .failure(let error):
                        print("Error creating bidirectional conversation: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.errorMessage = "Error al crear la conversación: \(error.localizedDescription)"
                            completion()
                        }
                    }
                }
                
            case .failure(let error):
                print("Error checking permissions: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Error al verificar permisos: \(error.localizedDescription)"
                    completion()
                }
            }
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("Cannot delete conversation: no valid ID")
            return
        }
        
        print("Deleting conversation: \(conversationId)")
        chatService.deleteConversationsBetweenUsers(
            user1Id: Auth.auth().currentUser?.uid ?? "",
            user2Id: conversation.otherParticipantId
        ) { [weak self] error in
            if let error = error {
                print("Error deleting conversation: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al eliminar conversación: \(error.localizedDescription)"
                }
            } else {
                print("Conversation deleted successfully")
                DispatchQueue.main.async {
                    self?.conversations.removeAll { $0.id == conversationId }
                    self?.hasUnreadMessages = self?.conversations.contains { !($0.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) } ?? false
                }
            }
        }
    }
    
    func markConversationAsUnread(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("Cannot mark conversation as unread: no valid ID")
            return
        }
        
        print("Marking conversation as unread: \(conversationId)")
        Firestore.firestore()
            .collection("conversations")
            .document(conversationId)
            .updateData(["readStatus.\(Auth.auth().currentUser?.uid ?? "")": false]) { [weak self] error in
                if let error = error {
                    print("Error marking as unread: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.errorMessage = "Error al marcar como no leído: \(error.localizedDescription)"
                    }
                } else {
                    print("Conversation marked as unread")
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
        print("Stopped listening to conversations")
    }
}

struct MessagingView_Previews: PreviewProvider {
    static var previews: some View {
        MessagingView(targetConversationId: .constant(nil))
            .environmentObject(AuthService())
            .environmentObject(MessagingViewModel())
    }
}
