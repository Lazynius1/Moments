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
    static let accent = Color(hex: "00A896")
    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
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
    
    // ✅ NUEVOS: Estados para navegación al explorer
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag: Bool = false

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
            case .admirers: return "Admiradores"
            case .connections: return "Conexiones"
            case .mutualConnections: return "Conexiones Mutuas"
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
                onDismiss: { showingUserList = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
            .presentationBackground(.clear)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .fullScreenCover(isPresented: $navigateToChat) {
            if let conversation = targetConversation {
                GlassmorphicChatView(conversation: conversation)
            }
        }
        // ✅ CORREGIDO: Eliminar el sheet duplicado y usar solo fullScreenCover
        .fullScreenCover(isPresented: $showMomentDetail) {
            ModernMomentDetailView(
                moments: viewModel.moments,
                initialIndex: selectedMomentIndex,
                onDismiss: {
                    showMomentDetail = false
                }
            )
        }
        .fullScreenCover(isPresented: $showStoryViewer) {
            if let stories = storyViewModel.stories[userId], !stories.isEmpty {
                GlassmorphicStoryViewer(
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

    private func contentView(safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> some View {
        Group {
            if viewModel.isLoading {
                UserModernLoadingView()
            } else if viewModel.isBlockedByCurrentUser || viewModel.isCurrentUserBlocked {
                UserModernBlockedView(
                    isBlockedByCurrentUser: viewModel.isBlockedByCurrentUser,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                    onUnblock: {
                        viewModel.unblockUser(userId: userId)
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            } else if !viewModel.canViewContent {
                UserModernPrivateProfileView(
                    userProfile: viewModel.userProfile,
                    userId: userId,
                    storyViewModel: storyViewModel,
                    viewModel: viewModel,
                    followButtonState: viewModel.followButtonState,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
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
                    onFollowAction: {
                        handleFollowAction()
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            }
        }
    }

    private func handleFollowAction() {
        switch viewModel.followButtonState {
        case .following:
            viewModel.unfollowUser(userId: userId)
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
    let onFollowAction: () -> Void
    let onDismiss: () -> Void

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
                        onFollowAction: onFollowAction,
                        onDismiss: onDismiss
                    )
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                    
                    // Indicador de refresh
                    if viewModel.isRefreshing {
                        UserModernRefreshIndicator()
                            .padding(.bottom, 20)
                    }
                    
                    // Estadísticas
                    if viewModel.canViewConnections {
                        UserModernStatsSection(
                            viewModel: viewModel,
                            showingUserList: $showingUserList
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    
                    // Intereses
                    if let interests = viewModel.userProfile?.interests, !interests.isEmpty {
                        UserModernInterestsView(
                            interests: interests
                        )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                    
                    // ✅ CORREGIDO: Sección de momentos
                    VStack(spacing: 0) {
                        // Header de momentos
                        HStack {
                            Text("userProfile.moments")
                                .font(.custom("Poppins-SemiBold", size: 20))
                                .foregroundColor(UserProfileColors.textPrimary) // <- CAMBIO AQUÍ
                            
                            Spacer()
                            
                            Text(String(format: NSLocalizedString("userProfile.moments.count", comment: "Moments count"), viewModel.moments.count))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(UserProfileColors.textSecondary) // <- CAMBIO AQUÍ
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(UserProfileColors.cardBackground) // <- CAMBIO AQUÍ
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(UserProfileColors.borderColor, lineWidth: 0.5) // <- CAMBIO AQUÍ
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .frame(maxWidth: UIScreen.main.bounds.width)
                        
                        if viewModel.moments.isEmpty {
                            UserModernEmptyMomentsView()
                                .padding(.horizontal, 20)
                                .frame(maxWidth: UIScreen.main.bounds.width - 40)
                        } else {
                            // GRID RESPONSIVE IGUAL QUE PROFILEVIEW
                            GeometryReader { geometry in
                                let spacing: CGFloat = 4
                                let columns = 3
                                let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                    ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                                        UserModernMomentThumbnail(
                                            moment: moment,
                                            size: itemWidth, // Pasar el tamaño calculado
                                            onTap: {
                                                selectedMomentIndex = index
                                                showMomentDetail = true
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            .frame(height: calculateGridHeight(itemCount: viewModel.moments.count))
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
    let onFollowAction: () -> Void
    let onDismiss: () -> Void // ✅ NUEVO: Para el botón de atrás
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 28) {
            // ✅ NUEVO: Botón de atrás en la esquina superior izquierda
            HStack {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(UserProfileColors.cardBackground.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .shadow(color: UserProfileColors.shadowColor, radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(UserProfileColors.textPrimary)
                    }
                }
                .scaleEffect(0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Avatar principal con badges (sin círculo de fondo)
            UserModernAvatarWithBadges(
                userProfile: viewModel.userProfile,
                storyViewModel: storyViewModel,
                showStoryViewer: $showStoryViewer,
                selectedStoryIndex: $selectedStoryIndex,
                size: 120
            )
            
            // Información del usuario con badges
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? "Usuario",
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 22,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "00A896"), Color(hex: "6B73FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 28))
                    
                    // ✅ NUEVO: Badges horizontales del usuario visitado
                    if let userProfile = viewModel.userProfile {
                        UserProfileBadgesView(userProfile: userProfile)
                    }
                }
                
                // Bio expandible adaptativa
                UserExpandableBioView(bio: viewModel.userProfile?.bio ?? "Sin biografía")
            }
            
            // Conexiones mutuas adaptativas - Solo mostrar si se pueden ver las mutuas Y hay datos
            if viewModel.canViewConnections && 
               viewModel.visibleConnectionTypes.canViewMutualConnections && 
               viewModel.visibleConnectionTypes.canViewConnections && 
               viewModel.visibleConnectionTypes.canViewAdmirers && 
               !viewModel.mutualConnections.isEmpty {
                Button(action: { showingUserList = .mutualConnections }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14))
                        
                        Text(String(format: NSLocalizedString("userProfile.mutualConnections", comment: "Mutual connections"), viewModel.mutualConnections.prefix(3).map { $0.username }.joined(separator: ", ")))
                            .font(.custom("Poppins-Medium", size: 13))
                            .lineLimit(1)
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.85))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(UserProfileColors.cardBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [UserProfileColors.accent.opacity(0.4), UserProfileColors.borderColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
            }
            
            // Botones de acción adaptativos
            HStack(spacing: 16) {
                Button(action: onFollowAction) {
                    Text(followButtonText)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(followButtonColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [followButtonColor.opacity(0.6), UserProfileColors.borderColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: followButtonColor.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .disabled(!viewModel.followButtonState.isActionable)
                .scaleEffect(viewModel.followButtonState.isActionable ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.followButtonState)
                
                Button(action: {
                    guard let currentUserId = Auth.auth().currentUser?.uid,
                          let targetUser = viewModel.userProfile else { return }
                    
                    // ✅ Intentar crear conversación directa primero
                    messagingViewModel.startConversation(with: targetUser, from: currentUserId) {
                        if let conversation = messagingViewModel.selectedConversation {
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
                        .frame(width: 50, height: 50)
                        .background(UserProfileColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(UserProfileColors.borderColor, lineWidth: 1)
                        )
                        .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                
                Button(action: {
                    if viewModel.isBlockedByCurrentUser {
                        viewModel.unblockUser(userId: viewModel.userId)
                    } else {
                        viewModel.blockUser(userId: viewModel.userId)
                    }
                }) {
                    Image(systemName: viewModel.isBlockedByCurrentUser ? "person.fill.checkmark" : "person.fill.xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(.horizontal, 28)
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
            Button("OK") {
                showingSuccessMessage = false
            }
        } message: {
            Text(NSLocalizedString("messageRequestModal.success.message", comment: "Success message"))
        }
    }

    private var followButtonText: String {
        switch viewModel.followButtonState {
        case .ownProfile: return "Tu perfil"
        case .blocked: return "Bloqueado"
        case .following: return "Siguiendo"
        case .canFollow: return "Seguir"
        case .canRequestFollow: return "Solicitar"
        case .requestPending: return "Solicitado"
        }
    }

    private var followButtonColor: Color {
        switch viewModel.followButtonState {
        case .following, .requestPending: return Color.gray.opacity(0.6)
        case .canFollow, .canRequestFollow: return UserProfileColors.accent
        case .ownProfile, .blocked: return Color.gray.opacity(0.4)
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
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    private var hasStory: Bool {
        guard let userId = userProfile?.id else { return false }
        return !(storyViewModel.stories[userId]?.isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            // Avatar principal
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
        .onTapGesture {
            if hasStory {
                showStoryViewer = true
                selectedStoryIndex = 0
            }
        }
    }
    
    // Border inteligente del avatar adaptativo
    @ViewBuilder
    private func avatarBorderOverlay() -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    gradient: hasStory ?
                    Gradient(colors: [.red, .purple, .blue, .pink]) :
                    (userProfile?.isPlusSubscriber == true && userProfile?.showPlusBadge == true ?
                     Gradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")]) :
                     Gradient(colors: [UserProfileColors.accent, UserProfileColors.borderColor])),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: hasStory ? 3 : (userProfile?.isPlusSubscriber == true && userProfile?.showPlusBadge == true ? 3 : 2)
            )
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
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
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
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
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
        .overlay(
            Capsule()
                .stroke(Color(hex: "FFD700").opacity(0.5), lineWidth: 0.5)
        )
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
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        UserProfileColors.accent.opacity(0.6),
                                        UserProfileColors.borderColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                
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
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            UserProfileColors.borderColor,
                            UserProfileColors.accent.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
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
struct UserModernStatsSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var showingUserList: UserProfileView.UserListType?
    @Environment(\.colorScheme) var colorScheme
    
    private var computedStats: [(String, Int, UserProfileView.UserListType)] {
        [
            ("Admiradores", viewModel.admirers.count, .admirers),
            ("Conexiones", viewModel.connections.count, .connections),
            ("Mutuas", viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    showingUserList = stat.2
                }) {
                    VStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("userProfile.stats.count", comment: "Stats count"), stat.1))
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(UserProfileColors.textPrimary)
                        
                        Text(stat.0)
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(UserProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(UserProfileColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        UserProfileColors.borderColor,
                                        UserProfileColors.accent.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                .scaleEffect(1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
            }
        }
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
                                    needsExpansion = bio.count > 100
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
    
    private var hasStory: Bool {
        // ✅ CORREGIDO: Usar userId en lugar de profileImagePath
        return !(storyViewModel.stories[userId]?.isEmpty ?? true)
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
                            .overlay(ProgressView().tint(Color(hex: "00A896")))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill) // ✅ CLAVE: aspectRatio en lugar de scaledToFill
                    .frame(width: size, height: size) // ✅ CLAVE: Frame fijo
                    .clipShape(Circle()) // ✅ CLAVE: Clip después del frame
                    .contentShape(Circle()) // ✅ CLAVE: ContentShape para touch
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: hasStory ?
                                    Gradient(colors: [.red, .purple, .blue, .pink]) :
                                    Gradient(colors: [Color.clear, Color.clear]), // ✅ QUITADO: Borde verde
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: hasStory ? 3 : 0 // ✅ QUITADO: Borde cuando no hay story
                            )
                    )
                    .shadow(color: Color(hex: "00A896").opacity(0.2), radius: 15, x: 0, y: 8)
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
                    .shadow(color: Color(hex: "00A896").opacity(0.15), radius: 12, x: 0, y: 6)
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
    @State private var currentUserInterests: [String] = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                Text("userProfile.interests")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(UserProfileColors.textPrimary)
            
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
                        .padding(.vertical, 10)
                        .background(
                            isShared ?
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [UserProfileColors.cardBackground, UserProfileColors.cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    isShared ?
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8), Color.pink.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            UserProfileColors.borderColor,
                                            UserProfileColors.accent.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isShared ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isShared ? Color.blue.opacity(0.3) : UserProfileColors.shadowColor,
                            radius: isShared ? 6 : 4,
                            x: 0,
                            y: isShared ? 3 : 2
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
        switch interest.lowercased() {
        case "gamer": return "🎮"
        case "league of legends": return "��"
        case "bcn": return "🏠"
        case "kpop": return "��"
        case "fotografía": return "📸"
        case "cine": return "🎬"
        case "música": return "🎶"
        case "tecnología": return "💻"
        case "moda": return "👗"
        case "arte": return "🎨"
        case "deportes": return "⚽"
        case "viajes": return "✈️"
        case "cocina": return "👨‍🍳"
        case "lectura": return "📚"
        case "anime": return "🍜"
        default: return "✨"
        }
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
                if let mediaItem = moment.mediaItems?.first, !mediaItem.url.isEmpty {
                    // Es un momento nuevo con mediaItems
                    if mediaItem.type == .video {
                        // ✅ NUEVO: Mostrar thumbnail de video
                        videoThumbnailView(videoURL: mediaItem.url)
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
                if let mediaItem = moment.mediaItems?.first, mediaItem.type == .video {
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
                if let likeCount = moment.reactions["heart"]?.count, likeCount > 0 {
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
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                LinearGradient(
                    colors: [
                        UserProfileColors.borderColor,
                        UserProfileColors.accent.opacity(0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(UserProfileColors.materialBackground)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        UserProfileColors.accent.opacity(0.4),
                                        UserProfileColors.borderColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "camera.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [UserProfileColors.accent, UserProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("userProfile.noMoments.title")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(UserProfileColors.textPrimary)
                
                Text("userProfile.noMoments.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(UserProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(UserProfileColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            UserProfileColors.borderColor,
                            UserProfileColors.accent.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
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
    @ObservedObject var viewModel: UserProfileViewModel // ✅ NUEVO: Para acceder a los datos reales
    let followButtonState: FollowButtonState
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onFollowAction: () -> Void
    let onDismiss: () -> Void
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            // ✅ HEADER ELEGANTE CON AVATAR
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: safeAreaTop + 20)
                
                // Avatar con historias - CENTRADO PERFECTO
                UserModernAvatar(
                    profileImagePath: userProfile?.profileImagePath,
                    userId: self.userId,
                    storyViewModel: storyViewModel,
                    showStoryViewer: $showStoryViewer,
                    selectedStoryIndex: $selectedStoryIndex,
                    size: 100
                )
                .frame(maxWidth: .infinity, alignment: .center)
                
                // ✅ INFO DEL USUARIO MEJORADA - CENTRADA PERFECTAMENTE
                VStack(spacing: 16) {
                    // Username con badge - CENTRADO PERFECTO
                    ZStack {
                        HStack(spacing: 8) {
                            Text(userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                                .font(.custom("Poppins-Bold", size: 26))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "00A896"), Color(hex: "6B73FF")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            VerifiedBadgeView(userId: self.userId, size: 22)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Bio con mejor estilo - CENTRADA
                    if let bio = userProfile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(.gray.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // ✅ BOTÓN DE ACCIÓN MEJORADO - CENTRADO PERFECTO
                Button(action: onFollowAction) {
                    HStack(spacing: 8) {
                        Image(systemName: followButtonIcon)
                            .font(.system(size: 16, weight: .medium))
                        Text(followButtonText)
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(followButtonColor)
                            .shadow(color: followButtonColor.opacity(0.3), radius: 12, x: 0, y: 6)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!followButtonState.isActionable)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer()
                .frame(height: 40) // ✅ REDUCIDO: Menos espacio para subir la sección
            
            // ✅ STATS REALES RESPETANDO PRIVACIDAD (como en UserProfile)
            VStack(spacing: 20) {
                // ✅ Layout horizontal único con los 4 stats
                HStack(spacing: 16) {
                    // ✅ Momentos (siempre visibles)
                    StatItem(
                        icon: "photo.stack.fill", 
                        value: "\(viewModel.moments.count)", 
                        label: NSLocalizedString("profile.moments.title", comment: "Moments"), 
                        color: Color(hex: "00A896")
                    )
                    
                    // ✅ Admiradores (solo si se pueden ver)
                    if viewModel.visibleConnectionTypes.canViewAdmirers {
                        StatItem(
                            icon: "heart.fill", 
                            value: "\(viewModel.admirers.count)", 
                            label: NSLocalizedString("profile.stats.admirers", comment: "Admiradores"), 
                            color: Color(hex: "6B73FF")
                        )
                    } else {
                        StatItem(
                            icon: "heart.fill", 
                            value: "?", 
                            label: NSLocalizedString("profile.stats.admirers", comment: "Admiradores"), 
                            color: Color.gray.opacity(0.6)
                        )
                    }
                    
                    // ✅ Conexiones (solo si se pueden ver)
                    if viewModel.visibleConnectionTypes.canViewConnections {
                        StatItem(
                            icon: "person.2.fill", 
                            value: "\(viewModel.connections.count)", 
                            label: NSLocalizedString("profile.stats.connections", comment: "Conexiones"), 
                            color: Color(hex: "9B59B6")
                        )
                    } else {
                        StatItem(
                            icon: "person.2.fill", 
                            value: "?", 
                            label: NSLocalizedString("profile.stats.connections", comment: "Conexiones"), 
                            color: Color.gray.opacity(0.6)
                        )
                    }
                    
                    // ✅ Conexiones mutuas (solo si se pueden ver)
                    if viewModel.visibleConnectionTypes.canViewMutualConnections {
                        StatItem(
                            icon: "person.2.circle.fill", 
                            value: "\(viewModel.mutualConnections.count)", 
                            label: NSLocalizedString("profile.stats.mutuals", comment: "Mutuas"), 
                            color: Color(hex: "FF6B6B")
                        )
                    } else {
                        StatItem(
                            icon: "person.2.circle.fill", 
                            value: "?", 
                            label: NSLocalizedString("profile.stats.mutuals", comment: "Mutuas"), 
                            color: Color.gray.opacity(0.6)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(height: 32)
            
            // ✅ SECCIÓN DE PERFIL PRIVADO EN CARD ELEGANTE
            VStack(spacing: 24) {
                // Icono de candado moderno
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .frame(width: 70, height: 70)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Mensaje explicativo mejorado
                VStack(spacing: 16) {
                    Text("userProfile.private.title")
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("userProfile.private.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .padding(.horizontal, 24)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "6B73FF").opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(height: safeAreaBottom + 30)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "00A896").opacity(0.05),
                    Color(hex: "6B73FF").opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var followButtonText: String {
        switch followButtonState {
        case .ownProfile:
            return "Tu perfil"
        case .blocked:
            return "Bloqueado"
        case .following:
            return "Siguiendo"
        case .canFollow:
            return "Seguir"
        case .canRequestFollow:
            return "Solicitar seguimiento"
        case .requestPending:
            return "Solicitud enviada"
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
class UserProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var isFollowing: Bool = false
    @Published var isBlockedByCurrentUser: Bool = false
    @Published var isCurrentUserBlocked: Bool = false
    @Published var isLoading: Bool = true
    @Published var followButtonState: FollowButtonState = .canFollow
    @Published var canViewContent: Bool = false
    @Published var canViewConnections: Bool = false
    @Published var isRefreshing: Bool = false
    
    // ✅ NUEVAS PROPIEDADES: Control granular de visibilidad
    @Published var visibleConnectionTypes = VisibleConnectionTypes(
        canViewAdmirers: false,
        canViewConnections: false,
        canViewMutualConnections: false
    )
    
    let userId: String
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    // Cache local para tracking de unfollows recientes
    private var recentUnfollows: Set<String> = []
    private var lastUnfollowTime: [String: Date] = [:]

    init(userId: String) {
        self.userId = userId
    }

    func fetchProfile() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        isLoading = true
        checkIfBlocked()
        
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    self.userProfile = profile
                }
                self.checkContentVisibility(currentUserId: currentUserId)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
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
        checkConnectionsVisibility(currentUserId: currentUserId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshGroup.leave()
        }
        
        // 3. Refresh conexiones con verificación directa
        refreshGroup.enter()
        self.fetchConnectionsDirect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
        privacyService.canViewUserContent(viewerId: currentUserId, targetUserId: userId) { [weak self] canView in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canViewContent = canView
                if canView {
                    self.fetchConnectionsDirect()
                    self.checkConnectionsVisibility(currentUserId: currentUserId)
                } else {
                    self.isLoading = false
                }
            }
        }
    }
    
    // ✅ FUNCIÓN CLAVE: Verificar visibilidad de conexiones con configuraciones de privacidad
    private func checkConnectionsVisibility(currentUserId: String) {
        privacyService.getVisibleConnectionTypes(viewerId: currentUserId, targetUserId: userId) { [weak self] visibleTypes in
            DispatchQueue.main.async {
                self?.visibleConnectionTypes = visibleTypes
                // Para compatibilidad con código existente
                self?.canViewConnections = visibleTypes.canViewAdmirers || visibleTypes.canViewConnections || visibleTypes.canViewMutualConnections
            }
        }
    }


    
    // ✅ FUNCIÓN MEJORADA: Fetch conexiones directo con filtrado de privacidad
    private func fetchConnectionsDirect() {
        // ✅ SOLO consultar following si tengo permisos
        if visibleConnectionTypes.canViewConnections {
            firestoreService.db.collection("users").document(userId).collection("following")
                .getDocuments { [weak self] followingSnapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        return
                    }
                    
                    let followingIds = followingSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []
                    
                    // Filtrar unfollows recientes
                    let filteredFollowingIds = followingIds.filter { userId in
                        if let unfollowTime = self.lastUnfollowTime[userId] {
                            let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                            if timeSinceUnfollow < 5.0 {
                                return false
                            } else {
                                self.lastUnfollowTime.removeValue(forKey: userId)
                                self.recentUnfollows.remove(userId)
                            }
                        }
                        return true
                    }
                
                // ✅ SOLO consultar followers si tengo permisos
                if self.visibleConnectionTypes.canViewAdmirers {
                    self.firestoreService.db.collection("users").document(self.userId).collection("followers")
                        .getDocuments { [weak self] followersSnapshot, error in
                            guard let self = self else { return }
                            
                            if let error = error {
                                return
                            }
                            
                            let followerIds = followersSnapshot?.documents.compactMap { doc in
                                doc.data()["userId"] as? String
                            } ?? []
                            
                            // Categorizar conexiones respetando privacidad
                            self.categorizeConnectionsWithPrivacy(
                                followingIds: filteredFollowingIds,
                                followerIds: followerIds
                            )
                        }
                } else {
                    // Categorizar conexiones sin followers
                    self.categorizeConnectionsWithPrivacy(
                        followingIds: filteredFollowingIds,
                        followerIds: []
                    )
                }
            }
        } else {
            // Categorizar conexiones sin following
            self.categorizeConnectionsWithPrivacy(
                followingIds: [],
                followerIds: []
            )
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Categorizar conexiones respetando configuraciones de privacidad
    private func categorizeConnectionsWithPrivacy(followingIds: [String], followerIds: [String]) {
        let followingSet = Set(followingIds)
        let followersSet = Set(followerIds)
        
        let mutualIds = followingSet.intersection(followersSet)
        let connectionIds = followingSet.subtracting(mutualIds)
        let admirerIds = followersSet.subtracting(mutualIds)
        
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
        var visibleMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "profile.moments.filter")
        
        for moment in moments {
            group.enter()
            privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                if canView {
                    syncQueue.async {
                        visibleMoments.append(moment)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original de los momentos
            let orderedVisibleMoments = moments.filter { moment in
                visibleMoments.contains { $0.id == moment.id }
            }
            
            completion(orderedVisibleMoments)
        }
    }
    
    private func filterStoriesForAudience(stories: [Story], viewerId: String, completion: @escaping ([Story]) -> Void) {
        let group = DispatchGroup()
        var visibleStories: [Story] = []
        let syncQueue = DispatchQueue(label: "profile.stories.filter")
        
        for story in stories {
            group.enter()
            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                if canView {
                    syncQueue.async {
                        visibleStories.append(story)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original de las historias
            let orderedVisibleStories = stories.filter { story in
                visibleStories.contains { $0.id == story.id }
            }
            
            completion(orderedVisibleStories)
        }
    }

    
    func checkFollowButtonState() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { [weak self] state in
            DispatchQueue.main.async {
                self?.followButtonState = state
                self?.isFollowing = (state == .following)
            }
        }
    }

    func registerVisit() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else {
            return
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
                self.checkFollowButtonState()
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
            // ✅ MEJORADO: Usar HashtagText personalizado con tap gestures específicos
            if isExpanded {
                UserHashtagText(
                    content: content,
                    colorScheme: colorScheme,
                    onHashtagTap: onHashtagTap
                )
            } else {
                UserHashtagText(
                    content: String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                    colorScheme: colorScheme,
                    onHashtagTap: onHashtagTap
                )
            }
            
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

struct UserHashtagText: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        // ✅ SOLUCIÓN FINAL: Usar Text con enlaces tappables
        Text(buildAttributedString())
            .font(.custom("Poppins-Regular", size: 14))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
            .environment(\.openURL, OpenURLAction { url in
                // ✅ Manejar taps en hashtags a través de URLs personalizadas
                if url.scheme == "hashtag", let hashtag = url.host {
                    onHashtagTap(hashtag)
                    return .handled
                }
                return .systemAction
            })
    }
    
    // ✅ CLAVE: Construir AttributedString con enlaces en hashtags
    private func buildAttributedString() -> AttributedString {
        var attributed = AttributedString(content)
        
        // Color base para todo el texto
        attributed.foregroundColor = .white.opacity(0.95)
        
        // Buscar y procesar hashtags
        let pattern = "#(\\w+)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = NSString(string: content)
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: content, range: range).reversed() // Reversed para no alterar índices
            
            for match in matches {
                // Obtener el hashtag completo y el término sin #
                let fullHashtag = nsString.substring(with: match.range) // #barcelona
                let hashtagTerm = nsString.substring(with: match.range(at: 1)) // barcelona
                
                // Convertir a rangos de Swift
                if let swiftRange = Range(match.range, in: content),
                   let attributedRange = swiftRange.toAttributedStringRange(in: attributed) {
                    
                    // Aplicar estilo al hashtag
                    attributed[attributedRange].foregroundColor = Color(hex: "667eea")
                    attributed[attributedRange].font = .custom("Poppins-SemiBold", size: 14)
                    attributed[attributedRange].link = URL(string: "hashtag://\(hashtagTerm)")
                }
            }
        }
        
        return attributed
    }
}

