import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @StateObject private var storyViewModel = StoryViewModel() // ✅ AGREGADO
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme // ✅ AGREGADO
    @State private var selectedTab: NotificationTab = .all
    @State private var selectedMoment: Moment?
    @State private var showStoryViewer = false // ✅ AGREGADO
    @State private var selectedStory: Story? // ✅ AGREGADO
    @Namespace private var tabAnimation
    let onNotificationsCleared: (() -> Void)?
    
    init(onNotificationsCleared: (() -> Void)? = nil) {
        self.onNotificationsCleared = onNotificationsCleared
    }

    enum NotificationTab: String, CaseIterable {
        case all = "notifications.tab.all"
        case likes = "notifications.tab.likes"
        case follows = "notifications.tab.follows"
        case mentions = "notifications.tab.mentions"
        case storyReactions = "notifications.tab.stories"
        case requests = "notifications.tab.requests"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                tabBarView
                contentView
            }
            .background(
                Group {
                    if colorScheme == .dark {
                        // Mismo fondo que el Feed - negro suave y elegante
                        Color(hex: "0A0A0A")
                    } else {
                        // Fondo claro elegante
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color(hex: "f8f9fa"),
                                Color(hex: "e9ecef"),
                                Color.white
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .navigationBarHidden(true)
            .onAppear {
                print("🔔 NotificationsView apareció - iniciando limpieza automática")
                
                // Cargar notificaciones
                viewModel.fetchNotifications()
                
                // Marcar como vistas inmediatamente
                clearNotificationsAutomatically()
            }
            .onDisappear {
                print("🔔 NotificationsView desapareció - notificando al parent")
                onNotificationsCleared?()
            }
            .alert(isPresented: $viewModel.showError) {
                Alert(
                    title: Text("notifications.error.title"),
                    message: Text(viewModel.errorMessage ?? "Ocurrió un error desconocido"),
                    dismissButton: .default(Text("notifications.ok"))
                )
            }
            .sheet(item: $selectedMoment) { moment in
                MomentDetailView(moment: moment)
            }
                        .fullScreenCover(isPresented: $showStoryViewer) {
                if let story = selectedStory {
                    GlassmorphicStoryViewer(
                        story: story,
                        storyCount: 1,
                        storyIndex: 0,
                        screenSize: UIScreen.main.bounds.size,
                        storyViewModel: storyViewModel,
                        showingReportSheet: .constant(false),
                        showingBlockConfirmation: .constant(false),
                        onReportStory: { },
                        onBlockUser: { },
                        onNext: { 
                            // ✅ Cerrar automáticamente al terminar
                            showStoryViewer = false 
                        },
                        onPrevious: { },
                        onClose: { showStoryViewer = false },
                        onProfileTap: { }
                    )
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseStoryViewer"))) { _ in
                        showStoryViewer = false
                    }
                }
            }
        }
    }
    
    private func clearNotificationsAutomatically() {
        print("🔔 NotificationsView: Limpiando notificaciones automáticamente")
        
        // 1. Marcar notificaciones como vistas en Firebase
        viewModel.clearUnreadNotifications()
        
        // 2. Actualizar badge service
        NotificationBadgeService.shared.clearNotificationBadge()
        
        print("✅ NotificationsView: Limpieza automática completada")
    }
    
    // ✅ HEADER ADAPTATIVO
    private var headerView: some View {
        HStack {
                            Text("notifications.title")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .stroke(
                            colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.1),
                            lineWidth: 0.5
                        ),
                    alignment: .bottom
                )
        )
    }

    // ✅ TAB BAR ADAPTATIVO
    @ViewBuilder private var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(NotificationTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text(NSLocalizedString(tab.rawValue, comment: "Notification tab"))
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(
                                        selectedTab == tab ?
                                        (colorScheme == .dark ? .white : .black) :
                                        .gray
                                    )
                                
                                // Badge para solicitudes pendientes
                                if tab == .requests && viewModel.pendingRequestsCount > 0 {
                                    Text("\(viewModel.pendingRequestsCount)")
                                        .font(.custom("Poppins-Bold", size: 10))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                            }
                            
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.6)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
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
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
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
        switch selectedTab {
        case .all:
            return viewModel.groupedNotifications
        case .likes:
            return viewModel.groupedNotifications.filter { $0.notifications.first?.type == .like }
        case .follows:
            return viewModel.groupedNotifications.filter {
                let type = $0.notifications.first?.type
                return type == .newFollower || type == .mutualConnection
            }
        case .mentions:
            return viewModel.groupedNotifications.filter { $0.notifications.first?.type == .comment }
        case .storyReactions:
            return viewModel.groupedNotifications.filter { $0.notifications.first?.type == .storyReaction }
        case .requests:
            return viewModel.groupedNotifications.filter { $0.notifications.first?.type == .followRequest }
        }
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
                            Color(hex: "00A896").opacity(0.4)
                        ] : [
                            Color.gray.opacity(0.8),
                            Color(hex: "00A896").opacity(0.6)
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
        switch selectedTab {
        case .mentions: return "text.bubble.slash"
        case .storyReactions: return "heart.slash"
        case .requests: return "person.2.slash"
        case .likes: return "heart.slash"
        case .follows: return "person.badge.plus"
        default: return "bell.slash"
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .mentions: return "Sin menciones"
        case .storyReactions: return "Sin reacciones"
        case .requests: return "Sin solicitudes"
        case .likes: return "Sin me gusta"
        case .follows: return "Sin nuevos seguidores"
        default: return "Sin notificaciones"
        }
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case .mentions: return "Cuando alguien comente en tus momentos, aparecerá aquí"
        case .storyReactions: return "Cuando alguien reaccione a tus historias, aparecerá aquí"
        case .requests: return "Cuando alguien quiera seguirte, aparecerá aquí"
        case .likes: return "Cuando alguien le dé me gusta a tus momentos, aparecerá aquí"
        case .follows: return "Cuando alguien te siga, aparecerá aquí"
        default: return "Cuando alguien interactúe contigo, aparecerá aquí"
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
                    Button("Cargar más") {
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
            .padding(.top, 8)
        }
    }
    
    struct DateHeaderView: View {
        let dateString: String
        let colorScheme: ColorScheme
        
        var body: some View {
            HStack {
                Text(dateString)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Group {
                    if colorScheme == .dark {
                        // Mismo fondo que el Feed - negro suave y elegante
                        Color(hex: "0A0A0A")
                    } else {
                        // Fondo claro elegante
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color(hex: "f8f9fa"),
                                Color(hex: "e9ecef"),
                                Color.white
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
        }
    }

    private func handleNotificationTap(group: NotificationGroup) {
        let firstNotification = group.notifications.first!
        switch firstNotification.type {
        case .like, .comment:
            if let momentId = firstNotification.momentId {
                fetchMoment(momentId: momentId)
            }
        case .mention: // ✅ Manejar menciones (cualquier contenido)
            if let storyId = firstNotification.storyId {
                navigateToStory(storyId: storyId)
            } else if let momentId = firstNotification.momentId {
                fetchMoment(momentId: momentId)
            }
        case .newFollower, .followRequest, .mutualConnection:
            print("Tapped notification for user with ID: \(firstNotification.senderId)")
        case .profileVisit:
            print("Tapped visit notification, navigating to VisitsView")
        case .storyReaction:
            print("Tapped story reaction notification for story: \(firstNotification.storyId ?? "")")
        }
    }

    private func fetchMoment(momentId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let firestoreService = FirestoreService()
        firestoreService.fetchMoment(momentId: momentId, userId: userId) { result in
            switch result {
            case .success(let moment):
                DispatchQueue.main.async {
                    self.selectedMoment = moment
                }
            case .failure(let error):
                print("Error fetching moment: \(error.localizedDescription)")
            }
        }
    }
    
    // ✅ Navegación real a historias
    private func navigateToStory(storyId: String) {
        print("📱 Navegando a historia: \(storyId)")
        
        // ✅ Buscar la historia usando StoryViewModel
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ Buscar en las historias existentes del StoryViewModel
        for (authorId, stories) in storyViewModel.stories {
            if let story = stories.first(where: { $0.id == storyId }) {
                DispatchQueue.main.async {
                    self.selectedStory = story
                    self.showStoryViewer = true
                    print("✅ Historia encontrada y navegando: \(story.id)")
                }
                return
            }
        }
        
        // ✅ Si no está en cache, buscar en Firestore
        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error navegando a historia: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data(),
                  let story = try? Firestore.Decoder().decode(Story.self, from: data) else {
                print("❌ No se pudo decodificar la historia")
                return
            }
            
            DispatchQueue.main.async {
                self.selectedStory = story
                self.showStoryViewer = true
                print("✅ Historia encontrada en Firestore y navegando: \(story.id)")
            }
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
    let colorScheme: ColorScheme // ✅ AGREGADO
    let onTapAction: () -> Void
    @State private var senderProfileImagePath: String?
    @State private var isLoadingImage: Bool = true
    @State private var imageLoadFailed: Bool = false
    @State private var showProfile = false
    @State private var momentImagePath: String?
    @State private var storyImagePath: String?
    @State private var isLoadingMomentImage: Bool = false
    @State private var isLoadingStoryImage: Bool = false
    @State private var momentImageLoadFailed: Bool = false
    @State private var storyImageLoadFailed: Bool = false
    @State private var isFollowing: Bool = false
    @State private var retryCount: Int = 0
    @State private var isPressed: Bool = false
    private let maxRetries: Int = 2

    var body: some View {
        ZStack {
            // ✅ FONDO - mismo que mensajes
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: colorScheme == .dark ?
                    .black.opacity(0.1) :
                    .gray.opacity(0.15),
                    radius: isPressed ? 2 : 8,
                    x: 0,
                    y: isPressed ? 1 : 4
                )

            HStack(spacing: 15) {
                ProofileImageView(
                    imagePath: senderProfileImagePath,
                    colorScheme: colorScheme // ✅ PASADO colorScheme
                )
                .frame(width: 52, height: 52)
                .clipShape(Circle())

                .shadow(
                    color: colorScheme == .dark ?
                    .black.opacity(0.2) :
                    .gray.opacity(0.3),
                    radius: 4, x: 0, y: 2
                )
                .onTapGesture {
                    showProfile = true
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(messageForGroup(group))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black) // ✅ ADAPTATIVO
                        .lineLimit(2)
                    
                    Text(group.notifications.first!.timestamp, style: .relative)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7)) // ✅ ADAPTATIVO
                }
                
                Spacer()
                
                trailingContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTapAction()
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
        .onAppear {
            fetchSenderProfileImage()
            
            if group.notifications.first?.type == .like || group.notifications.first?.type == .comment {
                if let momentId = group.notifications.first?.momentId {
                    fetchMomentPreview(momentId: momentId)
                }
            } else if group.notifications.first?.type == .storyReaction {
                if let storyId = group.notifications.first?.storyId {
                    fetchStoryPreview(storyId: storyId)
                }
            }
            
            if group.notifications.first?.type == .newFollower || group.notifications.first?.type == .mutualConnection {
                checkFollowingStatus()
            }
        }
    }

    // ✅ TRAILING CONTENT ADAPTATIVO
    private var trailingContent: some View {
        Group {
            switch group.notifications.first?.type {
            case .like, .comment:
                if let path = momentImagePath, let url = URL(string: path), !momentImageLoadFailed {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(Color(hex: "00A896"))
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
                                                .tint(Color(hex: "00A896"))
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

            case .followRequest:
                HStack(spacing: 8) {
                    Button("Aceptar") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.acceptFollowRequest(group: group)
                        }
                    }
                    .buttonStyle(GlassmorphicButtonStyle(
                        color: Color(hex: "00A896"),
                        colorScheme: colorScheme // ✅ PASADO colorScheme
                    ))
                    
                    Button("Rechazar") {
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
                    Text(isFollowing ? "feed.following" : "feed.follow")
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            isFollowing ?
                            LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)], startPoint: .leading, endPoint: .trailing)
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
                        .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())

            case .profileVisit:
                Button(action: onTapAction) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "00A896").opacity(0.5), lineWidth: 1)
                        )
                }

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Métodos auxiliares (mantenidos del original)
    
    private func fetchStoryPreview(storyId: String) {
        guard let userId = group.notifications.first?.storyAuthorId else { return }
        isLoadingStoryImage = true
        
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, error in
                if let error = error {
                    print("Error fetching story preview: \(error.localizedDescription)")
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
                
                if let mediaItem = data["mediaItem"] as? [String: Any],
                   let mediaUrl = mediaItem["url"] as? String {
                    DispatchQueue.main.async {
                        self.storyImagePath = mediaUrl
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

    private func messageForGroup(_ group: NotificationGroup) -> String {
        let firstNotification = group.notifications.first!
        if group.notifications.count > 1 && firstNotification.type != .profileVisit {
            switch firstNotification.type {
            case .like:
                return String(format: NSLocalizedString("notifications.message.like.multiple", comment: "Multiple likes"), firstNotification.senderUsername, group.notifications.count - 1)
            case .mention:
                return String(format: NSLocalizedString("notifications.message.mention.multiple", comment: "Multiple mentions"), firstNotification.senderUsername, group.notifications.count - 1)
            case .newFollower:
                return String(format: NSLocalizedString("notifications.message.follow.multiple", comment: "Multiple follows"), firstNotification.senderUsername, group.notifications.count - 1)
            case .followRequest:
                return String(format: NSLocalizedString("notifications.message.request.multiple", comment: "Multiple requests"), firstNotification.senderUsername, group.notifications.count - 1)
            case .mutualConnection:
                return String(format: NSLocalizedString("notifications.message.mutual.multiple", comment: "Multiple mutual connections"), firstNotification.senderUsername, group.notifications.count - 1)
            case .comment:
                return String(format: NSLocalizedString("notifications.message.comment.multiple", comment: "Multiple comments"), firstNotification.senderUsername, group.notifications.count - 1)
            case .storyReaction:
                return String(format: NSLocalizedString("notifications.message.story.multiple", comment: "Multiple story reactions"), firstNotification.senderUsername, group.notifications.count - 1)
            case .profileVisit:
                return String(format: NSLocalizedString("notifications.message.visit.multiple", comment: "Multiple profile visits"), firstNotification.visitCount ?? 0)
            }
        } else {
            switch firstNotification.type {
            case .like:
                return String(format: NSLocalizedString("notifications.message.like.single", comment: "Single like"), firstNotification.senderUsername)
            case .mention:
                return String(format: NSLocalizedString("notifications.message.mention.single", comment: "Single mention"), firstNotification.senderUsername)
            case .newFollower:
                return String(format: NSLocalizedString("notifications.message.follow.single", comment: "Single follow"), firstNotification.senderUsername)
            case .followRequest:
                return String(format: NSLocalizedString("notifications.message.request.single", comment: "Single request"), firstNotification.senderUsername)
            case .mutualConnection:
                return String(format: NSLocalizedString("notifications.message.mutual.single", comment: "Single mutual connection"), firstNotification.senderUsername)
            case .comment:
                return String(format: NSLocalizedString("notifications.message.comment.single", comment: "Single comment"), firstNotification.senderUsername)
            case .storyReaction:
                return String(format: NSLocalizedString("notifications.message.story.single", comment: "Single story reaction"), firstNotification.senderUsername)
            case .profileVisit:
                return String(format: NSLocalizedString("notifications.message.visit.single", comment: "Single profile visit"), firstNotification.visitCount ?? 0)
            }
        }
    }

    private func fetchSenderProfileImage() {
        guard let senderId = group.notifications.first?.senderId, retryCount < maxRetries else {
            DispatchQueue.main.async {
                self.isLoadingImage = false
                self.imageLoadFailed = true
            }
            return
        }

        if let cachedPath = viewModel.getProfileImagePath(for: senderId) {
            DispatchQueue.main.async {
                self.senderProfileImagePath = cachedPath.isEmpty ? nil : cachedPath
                self.isLoadingImage = false
                self.imageLoadFailed = cachedPath.isEmpty
            }
            return
        }

        let firestoreService = FirestoreService()
        firestoreService.fetchUser(userId: senderId) { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    self.senderProfileImagePath = user.profileImagePath?.isEmpty ?? true ? nil : user.profileImagePath
                    self.isLoadingImage = false
                    self.imageLoadFailed = user.profileImagePath?.isEmpty ?? true
                    self.viewModel.updateProfileImageCache(for: senderId, imagePath: user.profileImagePath)
                }
            case .failure(let error):
                print("Error fetching sender profile for \(senderId): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.retryCount += 1
                    if self.retryCount < self.maxRetries {
                        self.fetchSenderProfileImage()
                    } else {
                        self.isLoadingImage = false
                        self.imageLoadFailed = true
                        self.viewModel.updateProfileImageCache(for: senderId, imagePath: nil)
                    }
                }
            }
        }
    }

    private func fetchMomentPreview(momentId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let firestoreService = FirestoreService()
        isLoadingMomentImage = true
        firestoreService.fetchMoment(momentId: momentId, userId: userId) { result in
            switch result {
            case .success(let fetchedMoment):
                DispatchQueue.main.async {
                    if let imagePath = fetchedMoment.imagePath, !imagePath.isEmpty {
                        self.loadMomentImage(from: imagePath)
                    } else {
                        self.isLoadingMomentImage = false
                        self.momentImageLoadFailed = true
                    }
                }
            case .failure(let error):
                print("Error fetching moment preview: \(error.localizedDescription)")
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
            print("Invalid URL for moment image: \(path)")
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
            case .failure(let error):
                print("Kingfisher error loading moment image: \(error.localizedDescription)")
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
        
        viewModel.checkIfFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { result in
            switch result {
            case .success(let following):
                DispatchQueue.main.async {
                    self.isFollowing = following
                }
            case .failure(let error):
                print("Error checking following status: \(error.localizedDescription)")
            }
        }
    }

    private func toggleFollow() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUserId = group.notifications.first?.senderId else { return }
        
        if isFollowing {
            viewModel.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if let error = error {
                    print("Error unfollowing user: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.isFollowing = false
                    }
                }
            }
        } else {
            viewModel.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if let error = error {
                    print("Error following user: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.isFollowing = true
                    }
                }
            }
        }
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

class NotificationsViewModel: ObservableObject {
    @Published var notifications: [Notification] = []
    @Published var groupedNotifications: [NotificationGroup] = []
    @Published var groupedByDate: [String: [NotificationGroup]] = [:] // ✅ Nueva estructura por fecha
    @Published var dateKeys: [String] = [] // ✅ Claves de fecha ordenadas
    @Published var isLoading: Bool = true
    @Published var isLoadingMore: Bool = false // ✅ Para paginación
    @Published var canLoadMore: Bool = true // ✅ Control de paginación
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    @Published var hasUnreadNotifications: Bool = false
    @Published var pendingRequestsCount: Int = 0
    
    private let firestoreService = FirestoreService()
    private var listener: ListenerRegistration?
    private var userProfileImageCache: [String: String?] = [:]
    private let pageSize = 20 // ✅ Tamaño de página
    private var lastDocument: DocumentSnapshot? // ✅ Para paginación
    private var allNotificationsLoaded = false // ✅ Control de carga completa

    func fetchNotifications() {
        guard let userId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.errorMessage = "Usuario no autenticado."
                self.showError = true
                self.isLoading = false
            }
            return
        }

        // Reset para nueva carga
        lastDocument = nil
        allNotificationsLoaded = false
        
        listener?.remove()
        
        var query = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: pageSize)
        
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error al cargar notificaciones: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }

            guard let documents = snapshot?.documents else {
                DispatchQueue.main.async {
                    self.notifications = []
                    self.groupedNotifications = []
                    self.groupedByDate = [:]
                    self.dateKeys = []
                    self.hasUnreadNotifications = false
                    self.pendingRequestsCount = 0
                    self.canLoadMore = false
                }
                return
            }

            // Guardar último documento para paginación
            self.lastDocument = documents.last
            self.canLoadMore = documents.count == self.pageSize

            let newNotifications = documents.compactMap { doc -> Notification? in
                do {
                    let notification = try doc.data(as: Notification.self)
                    if notification.senderId.isEmpty && notification.type != .profileVisit {
                        print("Invalid notification with empty senderId: \(doc.documentID)")
                        return nil
                    }
                    return notification
                } catch {
                    print("Error al decodificar notificación \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
            
            let validNotifications = newNotifications.filter { notification in
                let daysSinceNotification = Calendar.current.dateComponents([.day], from: notification.timestamp, to: Date()).day ?? 0
                return daysSinceNotification <= 30
            }
            
            DispatchQueue.main.async {
                self.notifications = validNotifications
                
                self.pendingRequestsCount = validNotifications.filter {
                    $0.type == .followRequest && $0.isPending
                }.count
            }
            
            let senderIds = Set(validNotifications.filter { $0.type != .profileVisit }.map { $0.senderId }).filter { !$0.isEmpty }
            self.updateProfileImageCache(for: Array(senderIds)) {
                DispatchQueue.main.async {
                    self.groupNotifications()
                    self.hasUnreadNotifications = self.groupedNotifications.contains { $0.isUnread }
                }
            }
        }
    }
    
    // ✅ Nueva función para cargar más notificaciones
    func loadMoreNotifications() {
        guard let userId = Auth.auth().currentUser?.uid,
              canLoadMore && !isLoadingMore && !allNotificationsLoaded,
              let lastDoc = lastDocument else {
            return
        }
        
        isLoadingMore = true
        
        let query = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .order(by: "timestamp", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
        
        query.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoadingMore = false
            }
            
            if let error = error {
                print("Error loading more notifications: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                DispatchQueue.main.async {
                    self.canLoadMore = false
                    self.allNotificationsLoaded = true
                }
                return
            }
            
            // Actualizar último documento
            self.lastDocument = documents.last
            
            let newNotifications = documents.compactMap { doc -> Notification? in
                do {
                    let notification = try doc.data(as: Notification.self)
                    if notification.senderId.isEmpty && notification.type != .profileVisit {
                        return nil
                    }
                    return notification
                } catch {
                    print("Error decoding notification: \(error)")
                    return nil
                }
            }
            
            let validNotifications = newNotifications.filter { notification in
                let daysSinceNotification = Calendar.current.dateComponents([.day], from: notification.timestamp, to: Date()).day ?? 0
                return daysSinceNotification <= 30
            }
            
            DispatchQueue.main.async {
                // Agregar nuevas notificaciones a las existentes
                self.notifications.append(contentsOf: validNotifications)
                
                // Actualizar estado de paginación
                self.canLoadMore = documents.count == self.pageSize
                if documents.count < self.pageSize {
                    self.allNotificationsLoaded = true
                }
            }
            
            // Actualizar cache de imágenes para nuevos usuarios
            let senderIds = Set(validNotifications.filter { $0.type != .profileVisit }.map { $0.senderId }).filter { !$0.isEmpty }
            self.updateProfileImageCache(for: Array(senderIds)) {
                DispatchQueue.main.async {
                    self.groupNotifications()
                }
            }
        }
    }
    
    private func updateProfileImageCache(for userIds: [String], completion: @escaping () -> Void) {
        let uncachedUserIds = userIds.filter { self.userProfileImageCache[$0] == nil }
        
        guard !uncachedUserIds.isEmpty else {
            completion()
            return
        }
        
        let dispatchGroup = DispatchGroup()
        let batchSize = 10
        let batches = stride(from: 0, to: uncachedUserIds.count, by: batchSize).map {
            Array(uncachedUserIds[$0..<min($0 + batchSize, uncachedUserIds.count)])
        }
        
        for batch in batches {
            dispatchGroup.enter()
            
            firestoreService.fetchUsers(userIds: batch) { [weak self] result in
                defer { dispatchGroup.leave() }
                
                switch result {
                case .success(let users):
                    for user in users {
                        self?.userProfileImageCache[user.id] = user.profileImagePath?.isEmpty ?? true ? nil : user.profileImagePath
                    }
                    
                    let foundUserIds = Set(users.map { $0.id })
                    for userId in batch where !foundUserIds.contains(userId) {
                        self?.userProfileImageCache[userId] = nil
                    }
                    
                case .failure(let error):
                    print("Error fetching users batch: \(error.localizedDescription)")
                    for userId in batch {
                        self?.userProfileImageCache[userId] = nil
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion()
        }
    }

    func getProfileImagePath(for userId: String) -> String? {
        return userProfileImageCache[userId] ?? nil
    }

    func updateProfileImageCache(for userId: String, imagePath: String?) {
        userProfileImageCache[userId] = imagePath
    }

    func clearUnreadNotifications() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No user ID available")
            return
        }
        
        let db = Firestore.firestore()
        let notificationsRef = db.collection("users").document(userId).collection("notifications")
            .whereField("isPending", isEqualTo: true)
        
        notificationsRef.getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("❌ Error fetching unread notifications: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al cargar notificaciones: \(error.localizedDescription)"
                    self?.showError = true
                }
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                print("🔔 No unread notifications to clear")
                DispatchQueue.main.async {
                    self?.hasUnreadNotifications = false
                    self?.pendingRequestsCount = 0
                }
                return
            }
            
            print("🔔 Clearing \(documents.count) unread notifications")
            
            let batch = db.batch()
            for document in documents {
                print("🔔 Marking notification as read: \(document.documentID)")
                batch.updateData(["isPending": false], forDocument: document.reference)
            }
            
            batch.commit { error in
                if let error = error {
                    print("❌ Error committing batch update: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.errorMessage = "Error al marcar notificaciones como vistas: \(error.localizedDescription)"
                        self?.showError = true
                    }
                } else {
                    print("✅ Successfully cleared \(documents.count) notifications")
                    DispatchQueue.main.async {
                        for document in documents {
                            if let index = self?.notifications.firstIndex(where: { $0.id == document.documentID }) {
                                self?.notifications[index].isPending = false
                            }
                        }
                        self?.groupNotifications()
                        self?.hasUnreadNotifications = false
                        self?.pendingRequestsCount = self?.notifications.filter {
                            $0.type == .followRequest && $0.isPending
                        }.count ?? 0
                    }
                }
            }
        }
    }

    // ✅ Nueva función de agrupación por fecha
    private func groupNotifications() {
        let calendar = Calendar.current
        var tempGroupedByDate: [String: [NotificationGroup]] = [:]
        
        // Primero agrupa por usuario/tipo como antes
        var groupedDict: [String: [Notification]] = [:]
        for notification in notifications {
            let key: String
            if notification.type == .profileVisit {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                key = "visit_\(dateFormatter.string(from: notification.timestamp))"
            } else {
                key = "\(notification.type.rawValue)_\(notification.senderId)"
            }
            
            if groupedDict[key] == nil {
                groupedDict[key] = []
            }
            groupedDict[key]?.append(notification)
        }
        
        // Crea grupos por usuario/tipo
        let userGroups = groupedDict.map { key, notifications in
            let sortedNotifications = notifications.sorted { $0.timestamp > $1.timestamp }
            return NotificationGroup(id: key, notifications: sortedNotifications)
        }
        
        // Agrupa por fecha
        for group in userGroups {
            let date = group.notifications.first!.timestamp
            let dateKey = calendar.startOfDay(for: date)
            let dateString = formatDateKey(dateKey)
            
            if tempGroupedByDate[dateString] == nil {
                tempGroupedByDate[dateString] = []
            }
            tempGroupedByDate[dateString]?.append(group)
        }
        
        // Ordena los grupos dentro de cada fecha
        for dateString in tempGroupedByDate.keys {
            tempGroupedByDate[dateString]?.sort { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
        }
        
        // Actualiza las propiedades publicadas
        self.groupedByDate = tempGroupedByDate
        
        // Crea las claves de fecha ordenadas
        self.dateKeys = tempGroupedByDate.keys.sorted { dateString1, dateString2 in
            // Ordenar por prioridad: Hoy > Ayer > fechas anteriores
            let priority1 = getDatePriority(dateString1)
            let priority2 = getDatePriority(dateString2)
            
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            // Si ambas son fechas normales, ordenar por fecha real
            if priority1 == 0 && priority2 == 0 {
                let date1 = getDateFromString(dateString1)
                let date2 = getDateFromString(dateString2)
                return date1 > date2
            }
            
            return priority1 > priority2
        }
        
        // Mantén compatibilidad con la estructura anterior
        self.groupedNotifications = tempGroupedByDate.flatMap { _, groups in groups }
            .sorted { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
    }

    private func formatDateKey(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Hoy"
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d 'de' MMMM"
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.string(from: date)
        }
    }
    
    private func getDatePriority(_ dateString: String) -> Int {
        switch dateString {
        case "Hoy": return 2
        case "Ayer": return 1
        default: return 0
        }
    }
    
    private func getDateFromString(_ dateString: String) -> Date {
        if dateString == "Hoy" {
            return Date()
        } else if dateString == "Ayer" {
            return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d 'de' MMMM"
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.date(from: dateString) ?? Date.distantPast
        }
    }

    func acceptFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let followRequestNotifications = group.notifications.filter { $0.type == .followRequest && $0.isPending }
        
        for notification in followRequestNotifications {
            firestoreService.acceptFollowRequest(
                notificationId: notification.id,
                recipientId: userId,
                senderId: notification.senderId
            ) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "Error al aceptar solicitud, Intentelo de nuevo mas tarde."
                        self?.showError = true
                    } else {
                        self?.pendingRequestsCount = max(0, (self?.pendingRequestsCount ?? 1) - 1)
                        
                        if let index = self?.notifications.firstIndex(where: { $0.id == notification.id }) {
                            self?.notifications[index].isPending = false
                        }
                        
                        self?.groupNotifications()
                    }
                }
            }
        }
    }

    func rejectFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let followRequestNotifications = group.notifications.filter { $0.type == .followRequest && $0.isPending }
        
        for notification in followRequestNotifications {
            firestoreService.rejectFollowRequest(
                notificationId: notification.id,
                recipientId: userId,
                senderId: notification.senderId
            ) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "Error al rechazar solicitud: \(error.localizedDescription)"
                        self?.showError = true
                    } else {
                        self?.pendingRequestsCount = max(0, (self?.pendingRequestsCount ?? 1) - 1)
                        self?.notifications.removeAll { $0.id == notification.id }
                        self?.groupNotifications()
                    }
                }
            }
        }
    }

    func checkIfFollowing(currentUserId: String, targetUserId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { isFollowing in
            completion(.success(isFollowing))
        }
    }

    func followUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                    self?.showError = true
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func unfollowUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al dejar de seguir usuario: \(error.localizedDescription)"
                    self?.showError = true
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    deinit {
        listener?.remove()
        print("NotificationsViewModel deinitializada")
    }
}
