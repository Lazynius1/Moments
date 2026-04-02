
struct LocationMapData {
    let name: String
    let coordinate: CLLocationCoordinate2D?
}


import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import UIKit
import MapKit
import UserNotifications
import Combine
import WidgetKit
import SwiftData

private extension Moment {
    var feedViewIdentity: String {
        if let id, !id.isEmpty {
            return "\(authorId)_\(id)"
        }
        return "\(authorId)_\(timestamp.timeIntervalSince1970)_\(content.prefix(24))"
    }
}

struct FeedView: View {
    private typealias StoryUserState = (userId: String, hasStory: Bool, hasUnseenStory: Bool, storyCount: Int, storyViewedStatus: [Bool], storyAudiences: [String?])

    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @StateObject private var messagingViewModel = MessagingViewModel()
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var storyViewModel = StoryViewModel()
    @StateObject private var uploadService = BackgroundMomentUploadService.shared
    @StateObject private var storyUploadService = BackgroundStoryUploadService.shared
    @StateObject private var adManager = NativeAdManager()
    @StateObject private var notificationSummaryService = NotificationSummaryService.shared
    @ObservedObject private var badgeService = NotificationBadgeService.shared // ✅ NUEVO
    @StateObject private var navigationService = NotificationNavigationService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared // ✅ NUEVO: NetworkMonitor
    private let privacyService = PrivacyService()
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var showStories = false
    @State private var selectedMoment: Moment?
    @Binding var showCreatorView: Bool
    @State private var currentTime = Date()
    @Environment(\.colorScheme) var colorScheme
    @State private var storyUsers: [StoryUserState] = []
    @State private var isLoadingStories = true
    @State private var selectedFeedType: FeedType = UserDefaults.standard.selectedFeedType
    @State private var showingLocationMap = false
    @State private var selectedLocationName: String = ""
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    // 🔗 STORY CHAINS: Variables para navegación
    @State private var showStoryChain = false
    @State private var selectedChainId: String = ""
    @State private var selectedChainTitle: String = ""
    // ✅ NUEVO: Cache básico para optimización
    @State private var cachedStories: [String: Bool] = [:]
    @State private var cachedUnseenStories: [String: Bool] = [:]
    @State private var cachedStoriesTimestamp: Date = Date()
    @State private var widgetReloadWorkItem: DispatchWorkItem?
    @State private var hasLoadedInitialData = false
    // ✅ NUEVO: Mapa global
    @State private var hasUnreadMessages: Bool = false
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId: String = ""
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag = false
    @State private var showGlobalContextMenu = false
    @State private var selectedMomentForMenu: Moment?
    @State private var showShareSheet = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    @State private var isFeedHeaderHidden = false
    
    // ✅ LONG PRESS PEEK: Estado para overlay a nivel del feed
    @State private var peekImageURL: String? = nil
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    
    @State private var targetConversationId: String? = nil
    @State private var targetMomentId: String? = nil
    @State private var showMomentDetail = false
    @State private var targetMomentUserId: String? = nil
    @State private var showExplore = false // ✅ NUEVO
    
    // 🌊 ECHOES: Estados para indicadores
    @State private var pendingEchoes: [Echo] = []
    @State private var showEchoHistory = false
    @State private var showPendingEchoInvitation = false
    @State private var selectedPendingEchoId: String = ""
    @State private var pendingEchoesListener: ListenerRegistration?
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var feedHeaderHeight: CGFloat { 76 }
    private var feedSelectorHeight: CGFloat { 35 }
    private var floatingSelectorTopInset: CGFloat { isFeedHeaderHidden ? 18 : feedHeaderHeight }
    private var feedContentTopInset: CGFloat { floatingSelectorTopInset + feedSelectorHeight + 25 }
    
    var body: some View {
        ZStack {
            modernBackgroundView
                .ignoresSafeArea(.all)
            
            mainContent
            
            // ✅ Pill flotante sobre el contenido
            floatingFeedSelector
            
            // ✅ NUEVO: Banners de estado de red (COMO OVERLAY)
                .overlay(
                    VStack {
                        OfflineBanner(networkMonitor: networkMonitor) {
                            forceRefresh()
                        }
                        SlowConnectionBanner(networkMonitor: networkMonitor)
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .top)
                    , alignment: .top
                )
            
            // ✅ LONG PRESS PEEK: Overlay a pantalla completa
            if isPeeking, let imageURL = peekImageURL {
                ZStack {
                    ScreenshotProtectedView(isProtected: peekIsProtected, fillsContainer: true) {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()
                            
                            KFImage(URL(string: imageURL))
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: UIScreen.main.bounds.width - 32,
                                    height: (UIScreen.main.bounds.width - 32) / peekAspectRatio
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPeeking)
                .allowsHitTesting(false)
                .zIndex(998)
            }
                
                if showGlobalContextMenu, let moment = selectedMomentForMenu {
                    ModernContextMenuOverlay(
                        moment: moment,
                        isPresented: $showGlobalContextMenu,
                        onEdit: {
                            editedContent = moment.content
                            showEditSheet = true
                        },
                        onDelete: {
                            showDeleteAlert = true
                        },
                        onReport: {
                            // showReportSheet = true // ❌ Ya no se usa sheet
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1000)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showGlobalContextMenu)
                }
                

                
            if showShareSheet, let moment = selectedMomentForMenu {
                ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1001)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showShareSheet)
            }
            
            VStack {
                NotificationSummaryPopup(
                    isPresented: $notificationSummaryService.shouldShowSummary,
                    unreadNotifications: badgeService.unreadNotificationsCount,
                    unreadMessages: badgeService.unreadMessagesCount,
                    colorScheme: colorScheme
                )
                
                Spacer() // Para que se mantenga arriba
            }
            .zIndex(2000) // Por encima de todo
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                loadInitialData()
                
                // ✅ PREFETCHING POR COMPORTAMIENTO (ESTRATEGIA 2 - LOCAL)
                // Precargamos las historias de los primeros 5 círculos que YA aparecen en pantalla.
                // Como 'storyUsers' ya ha sido filtrado por la lógica de visibilidad del servidor y la app,
                // estamos 100% seguros de que solo precargamos contenido que el usuario TIENE permiso de ver.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    let topStoryUsers = storyUsers.prefix(5)
                    for user in topStoryUsers {
                        // Solo precargamos si tiene historias y no es el usuario actual
                        if user.hasStory && user.userId != Auth.auth().currentUser?.uid {
                            FirestoreService.shared.prefetchStoriesForUser(userId: user.userId)
                        }
                    }
                }
                
                startTimeUpdate()
                
                setupServiceConnections()
                
            // ✅ Solicitar permiso de notificaciones al cargar el feed (solo si no se ha decidido aún)
                requestNotificationPermissionIfNeeded()
                
                // ✅ SETUP DE LISTENERS
                badgeService.setupListeners()
                
                // 🌊 ECHOES: Cargar invitaciones pendientes
                setupPendingEchoesListener()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    notificationSummaryService.checkShouldShowSummary(
                        unreadNotifications: badgeService.unreadNotificationsCount,
                        unreadMessages: badgeService.unreadMessagesCount
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                notificationSummaryService.markAppClosed()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    notificationSummaryService.checkShouldShowSummary(
                        unreadNotifications: badgeService.unreadNotificationsCount,
                        unreadMessages: badgeService.unreadMessagesCount
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowMessages"))) { _ in
                showMessages = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCreatorView"))) { _ in
                showCreatorView = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExploreView"))) { _ in
                showExplore = true
            }
        .onDisappear {
            // cleanupListeners() // ❌ ELIMINAR
        }
            .fullScreenCover(isPresented: $showNotifications) {
                NotificationsView(onNotificationsCleared: {

                // ✅ No es necesario actualizar hasUnreadNotifications localmente
                // badgeService.clearAppBadge() // ❌ No llamar aquí, NotificationsView ya lo maneja
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NotificationsCleared"),
                        object: nil
                    )
                })
            }
            .fullScreenCover(isPresented: $showMessages) {
                MessagingView(targetConversationId: $targetConversationId, onDismiss: {
                    showMessages = false
                })
                .environmentObject(messagingViewModel)
                .environmentObject(firestoreService)
            }
            .fullScreenCover(isPresented: $showSpecificUserStories) {
                StoriesView(startWithUserId: $selectedStoryUserId)
                    .environmentObject(firestoreService)
                    .ignoresSafeArea(.keyboard) // ✅ Agregar aquí
            }
            .fullScreenCover(isPresented: $showStories) {
                StoriesView()
                    .environmentObject(firestoreService)
                    .ignoresSafeArea(.keyboard) // ✅ Agregar aquí
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedMoment != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedMoment = nil
                        }
                    }
                )
            ) {
                if let moment = selectedMoment {
                    ModernCommentsView(moment: moment)
                        .environmentObject(firestoreService)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showExploreWithHashtag) {
                ExploreView(initialSearchQuery: selectedHashtag)
            }
            .sheet(isPresented: $showExplore) {
                ExploreView()
            }
            .fullScreenCover(isPresented: $showingLocationMap) {
                LocationMapView(
                    locationName: selectedLocationName.isEmpty ? NSLocalizedString("feed.location.default", comment: "Default location name") : selectedLocationName,
                    coordinate: selectedLocationCoordinate,
                    isPresented: $showingLocationMap
                )
            }
        .onChange(of: showingLocationMap) { isShowing in
            if isShowing {
                // ✅ El onChange es crucial para el funcionamiento, pero sin prints
            }
        }


            .sheet(isPresented: $showMomentDetail) {
                if let momentId = targetMomentId, let userId = targetMomentUserId {
                    MomentDetailFromNotificationView(
                        momentId: momentId,
                        userId: userId,
                        isPresented: $showMomentDetail
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        targetMomentId = nil
                        targetMomentUserId = nil
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let moment = selectedMomentForMenu {
                    EditMomentView(
                        moment: moment,
                        editedContent: $editedContent,
                        onSave: { newContent in
                            updateMoment(moment: moment, newContent: newContent)
                        }
                    )
                }
            }
            .alert(NSLocalizedString("feed.actions.delete.title", comment: "Delete moment alert title"), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("feed.actions.cancel", comment: "Cancel action"), role: .cancel) { }
                Button(NSLocalizedString("feed.actions.delete", comment: "Delete action"), role: .destructive) {
                    if let moment = selectedMomentForMenu {
                        deleteMoment(moment: moment)
                    }
                }
            } message: {
                Text("feed.delete.confirm")
            }
            /*.sheet(isPresented: $showReportSheet) {
                if let moment = selectedMomentForMenu {
                    ReportBottomSheet(moment: moment)
                }
            }*/
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNotifications"))) { _ in
            showNotifications = true
        }
        .onReceive(navigationService.$pendingNavigation) { navigation in
            guard let navigation = navigation else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                switch navigation {
                case .conversation(let conversationId):
                    targetConversationId = conversationId  // ✅ PASAR el ID
                    showMessages = true
                    
                case .moment(let momentId, let userId):  // ✅ AHORA CON userId
                    targetMomentId = momentId
                    targetMomentUserId = userId  // ✅ NUEVA variable
                    showMomentDetail = true
                    
                case .profile(let userId):
                    // Navegando a perfil
                    break
                    
                case .notifications(let filter):
                    showNotifications = true
                    
                default:
                    // Tipo de navegación no implementado
                    break
                }
                
                navigationService.clearPendingNavigation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StoryUploaded"))) { _ in
            if let userId = Auth.auth().currentUser?.uid {
                Task {
                    await loadStoryUsers(userId: userId)
                }
            }
        }
        // ✅ RESTAURADO: Listener para navegación a perfil interna
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfileInFeed"))) { notification in
            if let userId = notification.object as? String, !userId.isEmpty {
                selectedUserId = userId
                showUserProfile = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfileInFeed"))) { notification in
            if let userId = notification.object as? String, !userId.isEmpty {
                selectedUserId = userId
                showUserProfile = true
            }
        }
        // 🔗 STORY CHAINS: Listener para navegación a cadenas
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToStoryChainInFeed"))) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String {
                selectedChainId = chainId
                selectedChainTitle = chainTitle
                showStoryChain = true
            }
        }

        .onChange(of: badgeService.unreadNotificationsCount) { count in

        }
        .environmentObject(firestoreService)
            .sheet(isPresented: $showUserProfile) {
                if !selectedUserId.isEmpty {
                    UserProfileView(userId: selectedUserId)
                }
            }
            // 🌊 ECHOES: Sheet para invitación pendiente
            .sheet(isPresented: $showPendingEchoInvitation) {
                if !selectedPendingEchoId.isEmpty {
                    EchoInvitationView(
                        echoId: selectedPendingEchoId,
                        isPresented: $showPendingEchoInvitation,
                        onAccept: { echoId in
                            // Navegar al visor tras aceptar
                            NotificationNavigationService.shared.pendingNavigation = .echo(echoId)
                        }
                    )
                }
            }
            // 🌊 ECHOES: Sheet para historial
            .sheet(isPresented: $showEchoHistory) {
                EchoHistoryView()
            }
        // 🔗 STORY CHAINS: Eliminado en Feed; centralizado en StoryModels
    }
    
    private func setupServiceConnections() {
        // Conectar UploadService con FeedViewModel
        uploadService.setFeedViewModel(viewModel)

    }
    
    // ✅ Nuevo: Solicitud de permisos de notificaciones desde el Feed en primera carga
    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                // ✅ Solicitar permisos si no se han decidido
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                // ✅ Si ya están otorgados, registrar para notificaciones remotas para obtener/refrescar token
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    // 🌊 ECHOES: Configurar listener para invitaciones pendientes
    private func setupPendingEchoesListener() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        pendingEchoesListener = EchoService.shared.fetchPendingEchoes(userId: userId) { echoes in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.pendingEchoes = echoes
            }
        }
    }
    
    // Mantener funciones existentes como updateMoment y deleteMoment sin cambios
    private func updateMoment(moment: Moment, newContent: String) {
        guard let momentId = moment.id else { return }
        
        firestoreService.updateMoment(
            userId: moment.authorId,
            momentId: momentId,
            content: newContent
        ) { error in
            if let error = error {
                // Error al actualizar momento
            } else {
                // Momento actualizado exitosamente
            }
        }
    }
    
    private func deleteMoment(moment: Moment) {
        guard let momentId = moment.id else { return }
        
        isDeleting = true
        
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                self.isDeleting = false
                
                if let error = error {
                    // Error al eliminar momento
                } else {
                    // Momento eliminado exitosamente
                    self.viewModel.moments.removeAll { $0.id == momentId }
                    self.showGlobalContextMenu = false
                    self.selectedMomentForMenu = nil
                }
            }
        }
    }

    // ✅ Fondo moderno como ProfileView
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                Color(hex: "0B1215")
                    .ignoresSafeArea()
            } else {
                Color(hex: "FAF9F6")
                    .ignoresSafeArea()
            }
        }
    }
    
    private var mainContent: some View {
        ZStack(alignment: .top) {
            scrollableContent
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 0) {
                modernHeaderView
                
                // 🔥 NUEVO: Barra de progreso de uploads
                uploadProgressBar
            }
            .offset(y: isFeedHeaderHidden ? -(feedHeaderHeight + 20) : 0)
            .opacity(isFeedHeaderHidden ? 0 : 1)
            .allowsHitTesting(!isFeedHeaderHidden)
            .padding(.top, -8)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isFeedHeaderHidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // ✅ NUEVO: Pill flotante sobre el contenido con indicadores de Echo
    private var floatingFeedSelector: some View {
        VStack {
            Spacer()
                .frame(height: floatingSelectorTopInset)
            
            // Centro: Feed Toggle
            FloatingGlassFeedToggle(selectedFeedType: $selectedFeedType)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isFeedHeaderHidden)
        .onChange(of: selectedFeedType) { newFeedType in
            // ✅ NUEVO: Guardar la preferencia del usuario
            UserDefaults.standard.selectedFeedType = newFeedType
            
            // ✅ Cambiar tipo de feed cuando se selecciona
            if let userId = Auth.auth().currentUser?.uid {
                viewModel.switchFeedType(to: newFeedType, userId: userId)
            }
            
            // ✅ NUEVO: Track analytics para preferencias
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pendingEchoes.count)
        .zIndex(998)
    }
    
    // ✅ Header moderno
    private var modernHeaderView: some View {
        HStack(spacing: 8) {
            // Sección de historias CON progreso de upload
                if isLoadingStories {
                    HStack(spacing: 10) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .tint(adaptiveColors.accent)
                                        .scaleEffect(0.7)
                                )
                        }
                        Spacer()
                    }
                    .padding(.leading, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // 🔥 NUEVO: Tu historia con progreso de upload si está subiendo
                            YourStoryCircleWithProgress(
                                hasStory: storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyUsers.first?.hasStory ?? false) : false,
                                storyCount: storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyUsers.first?.storyCount ?? 0) : 0,
                                storyAudiences: storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyUsers.first?.storyAudiences ?? []) : [],
                                colorScheme: colorScheme,
                                storyUploadService: storyUploadService
                            ) {
                                // ✅ LÓGICA SIMPLE Y CLARA
                                if let currentUserId = Auth.auth().currentUser?.uid,
                                   storyUsers.first?.hasStory == true && storyUsers.first?.userId == currentUserId {
                                    
                                    // 📖 Si tienes historia, mostrar tus historias
                                    selectedStoryUserId = currentUserId
                                    showSpecificUserStories = true

                                    
                                } else {
                                    
                                    // ➕ Si no tienes historia, crear nueva
                                    showCreatorView = true

                                    
                                }
                            }
                            
                            // Resto de historias (usuarios que sigues)
                            ForEach(storyUsers.dropFirst(), id: \.userId) { storyUser in
                                RealStoryCircle(
                                    userId: storyUser.userId,
                                    hasStory: storyUser.hasStory,
                                    hasUnseenStory: storyUser.hasUnseenStory,
                                    storyCount: storyUser.storyCount,
                                    storyViewedStatus: storyUser.storyViewedStatus,
                                    storyAudiences: storyUser.storyAudiences,
                                    isOwnStory: false,
                                    colorScheme: colorScheme
                                ) {
                                    
                    
                                    guard !storyUser.userId.isEmpty else {
                                        return
                                    }
                                    
                                    selectedStoryUserId = storyUser.userId
                                    showSpecificUserStories = true
                                }
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 0)
                    }
                }
                
                Spacer()
                
                // Botones integrados con espaciado natural
                HStack(spacing: 20) {
                    // 🌊 Echo History & Pending Indicator
                    if !pendingEchoes.isEmpty {
                        Menu {
                            Button(NSLocalizedString("feed.echo.actions.viewInvitations", comment: "View pending invitations")) {
                                if let firstPending = pendingEchoes.first, let echoId = firstPending.id {
                                    selectedPendingEchoId = echoId
                                    showPendingEchoInvitation = true
                                }
                            }
                            Button(NSLocalizedString("feed.echo.actions.viewHistory", comment: "View echo history")) {
                                showEchoHistory = true
                            }
                        } label: {
                            echoApertureIcon
                        }
                    } else {
                        Button(action: {
                            showEchoHistory = true
                        }) {
                            echoApertureIcon
                        }
                    }
                    
                    // ✅ NUEVO: Botón del mapa global

                    
                    ModernNotificationButton(
                        hasNotification: badgeService.unreadNotificationsCount > 0,
                        colorScheme: colorScheme,
                        action: {
                            
                            // ✅ Marcar como leídas y limpiar badge al abrir desde el icono
                            NotificationService.shared.markAllAsRead()
                            NotificationBadgeService.shared.clearNotificationBadge()
                            
                            showNotifications = true
                        }
                    )
                    
                    ModernMessageButton(
                        hasMessage: badgeService.unreadMessagesCount > 0,    // ✅ Badge aparece si > 0
                        messageCount: badgeService.unreadMessagesCount,      // ✅ Número real
                        colorScheme: colorScheme,
                        action: {
                            showMessages = true
                        }
                    )
                }
                .padding(.trailing, 12)
            }
            .padding(.top, 16)
            .padding(.bottom, 4)
            .background(
                Rectangle()
                    .fill(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea(edges: .top)
            )
    }

    private var echoApertureIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 36, height: 36)

            if !pendingEchoes.isEmpty {
                Text("\(pendingEchoes.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
                    .transition(.scale)
            }
        }
    }
    
    // ✅ Contenido del scroll
    private var scrollableContent: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    let screenHeight = UIScreen.main.bounds.height
                    let headerHeight = feedHeaderHeight
                    let progressBarHeight = uploadService.uploadingMoments.isEmpty ? 0.0 : 50.0
                    let segmentedToggleHeight = feedSelectorHeight
                    let tabbarHeight = 50.0
                    let availableHeight = screenHeight - headerHeight - progressBarHeight - segmentedToggleHeight - tabbarHeight - 60
                    
                    LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                        // ✅ Espacio para que el primer post empiece debajo del header
                        Spacer()
                            .frame(height: feedContentTopInset)
                        
                        ForEach(Array(viewModel.moments.enumerated()), id: \.element.feedViewIdentity) { index, moment in
                            VStack(spacing: max(15, screenHeight * 0.02)) {
                                
                                // ✅ Protección de screenshots para momentos privados
                                // Solo los momentos con audiencia "everyone" son visibles en capturas.
                                ScreenshotProtectedView(
                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                ) {
                                    ModernPostCardView(
                                        moment: moment,
                                        availableHeight: availableHeight,
                                        colorScheme: colorScheme,
                                        onComment: {
                                            selectedMoment = moment
                                        },
                                        onNearEnd: {
                                            if moment.id == viewModel.moments.last?.id,
                                               let userId = Auth.auth().currentUser?.uid {
                                                viewModel.loadMoreMoments(userId: userId)
                                            }
                                        },
                                        onHashtagTap: { hashtag in
                            
                                            selectedHashtag = "#\(hashtag)"
                                            showExploreWithHashtag = true
                                        },
                                        onLocationTap: { locationName, coordinate in
                                            DispatchQueue.main.async {
                                                self.selectedLocationName = locationName
                                                self.selectedLocationCoordinate = coordinate
                                                self.showingLocationMap = true
                                            }
                                        },
                                        // ✅ NUEVO: Callback para mostrar menú contextual global
                                        onContextMenu: { moment in
        
                                            selectedMomentForMenu = moment
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                showGlobalContextMenu = true
                                            }
                                        },
                                        onTagTap: { userId in
                                            // ✅ Tag Navigation
                                            selectedUserId = userId
                                            showUserProfile = true
                                        },
                                        onPeek: { imageURL, ratio, isPressing in
                                            // ✅ PREFETCHING POR INTENCIÓN (ESTRATEGIA 3)
                                            // Si el usuario empieza a presionar (Peek), cargamos la versión de alta resolución proactivamente
                                            if isPressing, let url = URL(string: imageURL) {
                                                KingfisherManager.shared.retrieveImage(with: url) { _ in }
                                            }
                                            
                                            // ✅ LONG PRESS PEEK (Visual)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                if isPressing {
                                                    peekImageURL = imageURL
                                                    peekAspectRatio = ratio
                                                    peekIsProtected = (moment.audience?.lowercased() ?? "") != "everyone"
                                                    isPeeking = true
                                                } else {
                                                    isPeeking = false
                                                    peekIsProtected = false
                                                }
                                            }
                                        }
                                    )
                                    .onAppear {
                                        // ✅ PREFETCHING DE LISTA (ESTRATEGIA 1)
                                        // Cuando un post aparece, precargamos las imágenes de los siguientes 5
                                        let nextIndex = index + 1
                                        let prefetchRange = nextIndex..<(nextIndex + 5)
                                        let urlsToPrefetch = viewModel.moments[safe: prefetchRange].compactMap { moment -> URL? in
                                            guard let firstMedia = moment.mediaItems?.first?.url else { return nil }
                                            return URL(string: firstMedia)
                                        }
                                        if !urlsToPrefetch.isEmpty {
                                            ImagePrefetchManager.shared.prefetch(urls: urlsToPrefetch)
                                        }
                                    }
                                    .environmentObject(firestoreService)
                                    .environmentObject(viewModel)
                                }

                                let adInterval = selectedFeedType == .forYou ? 3 : 5
                                if (index + 1) % adInterval == 0 && index < viewModel.moments.count - 1 {
                                    SmartNativeAdView()
                                        .onAppear {
                                        }
                                }
                            }
                        }
    
                        if viewModel.isLoadingMore {
                            ModernLoadingMoreView(colorScheme: colorScheme)
                                .padding(.vertical, 15)
                        }
                    }
                    .padding(.vertical, 15)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if value.translation.height < -40 && !isFeedHeaderHidden {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    isFeedHeaderHidden = true
                                }
                            } else if value.translation.height > 28 && isFeedHeaderHidden {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    isFeedHeaderHidden = false
                                }
                            }
                        }
                )
                
                // ✅ ESTADO VACÍO: Fuera del ScrollView para control total de la atmósfera
                if viewModel.moments.isEmpty && !viewModel.isLoading {
                    ModernEmptyFeedView(feedType: selectedFeedType)
                        .zIndex(10)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
            .refreshable {
                if let userId = Auth.auth().currentUser?.uid {
                    // ✅ OPTIMIZADO: Usar forceRefresh en lugar de refreshFeed
                    forceRefresh()
                    await refreshFeed(userId: userId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollFeedToTop"))) { _ in
                // ✅ NUEVO: Scroll al inicio y refrescar cuando se toca Home de nuevo
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(0, anchor: .top)
                }
                // Refrescar el feed
                if let userId = Auth.auth().currentUser?.uid {
                    forceRefresh()
                    Task {
                        await refreshFeed(userId: userId)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func startTimeUpdate() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            withAnimation {
                currentTime = Date()
            }
        }
    }
    
    // MARK: - Componentes de Stories (mantener igual)
    struct RealStoryCircle: View {
        let userId: String
        let hasStory: Bool
        let hasUnseenStory: Bool
        let storyCount: Int
        let storyViewedStatus: [Bool]
        let storyAudiences: [String?]
        let isOwnStory: Bool
        let colorScheme: ColorScheme
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                ZStack {
                    AsyncProfileImageView(userId: userId)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: hasUnseenStory,
                                storyViewedStatus: storyViewedStatus,
                                storyAudiences: storyAudiences,
                                isOwnStory: isOwnStory,
                                colorScheme: colorScheme,
                                ringSize: 50,
                                lineWidth: 3.0, // ✅ Grosor ligeramente mayor para Tier 1
                                hapticsEnabled: true
                            )
                        )
                }
                .frame(width: 56, height: 56) // ✅ Frame mayor para evitar cortes
                .padding(2) // ✅ Margen de seguridad
            }
        }
    }
    
    // ✅ NOTA: StorySegmentedRing y StorySegment ahora están en un archivo compartido
    // Glowsy/Views/story/StorySegmentedRing.swift
    
    /// ///
    //Progeso subida Stories
    ///
    struct YourStoryCircleWithProgress: View {
        let hasStory: Bool
        let storyCount: Int
        let storyAudiences: [String?]
        let colorScheme: ColorScheme
        @ObservedObject var storyUploadService: BackgroundStoryUploadService
        let action: () -> Void
        
        private var adaptiveColors: AdaptiveColors {
            AdaptiveColors(colorScheme: colorScheme)
        }
        
        var body: some View {
            Button(action: {
                // Si hay upload en progreso y falló, reintentar
                if let uploadingStory = storyUploadService.uploadingStory,
                   uploadingStory.status == .failed {
                    storyUploadService.retryUpload(uploadingStory)
                } else {
                    // ✅ SIMPLE: Siempre ejecutar la acción que se pasa
                    action()
                }
            }) {
                ZStack {
                    // Imagen de perfil del usuario actual
                    AsyncProfileImageView(userId: Auth.auth().currentUser?.uid ?? "")
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: false, // Tu propia historia siempre está vista
                                storyViewedStatus: Array(repeating: true, count: storyCount), // ✅ Todas las historias propias están "vistas"
                                storyAudiences: storyAudiences,
                                isOwnStory: true, // ✅ Es tu propia historia
                                colorScheme: colorScheme,
                                ringSize: 50,
                                lineWidth: 3.0, // ✅ Consistente con RealStoryCircle
                                hapticsEnabled: true
                            )
                        )
                    
                    // 🔥 PROGRESO DE UPLOAD si hay historia subiendo
                    if let uploadingStory = storyUploadService.uploadingStory {
                        Circle()
                            .trim(from: 0, to: uploadingStory.uploadProgress)
                            .stroke(
                                LinearGradient(
                                    colors: progressColors(for: uploadingStory.status),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: uploadingStory.uploadProgress)
                        
                        // Overlay de estado
                        Circle()
                            .fill((colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).opacity(0.4))
                            .frame(width: 50, height: 50)
                        
                        // Icono de estado
                        statusIcon(for: uploadingStory.status)
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .onChange(of: uploadingStory.status) { oldStatus, newStatus in
                                if newStatus == .completed {
                                    // ✅ Haptic Tier 1 al completar la subida
                                    StorySegmentedRing.triggerHaptic()
                                }
                            }
                            
                    }
                }
                .frame(width: 56, height: 56) // ✅ Frame mayor para evitar cortes
                .padding(2) // ✅ Margen de seguridad
            }
            .scaleEffect(storyUploadService.uploadingStory?.status == .failed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: storyUploadService.uploadingStory?.status)
        }
        
        private func progressColors(for status: UploadStatus) -> [Color] {
            switch status {
            case .uploading:
                return [.blue, .purple]
            case .processing:
                return [.orange, .yellow]
            case .completed, .moderated:
                return [.green, .mint]
            case .failed:
                return [.red, .pink]
            }
        }
        
        private func statusIcon(for status: UploadStatus) -> Image {
            switch status {
            case .uploading, .processing:
                return Image(systemName: "arrow.up")
            case .completed, .moderated:
                return Image(systemName: "checkmark")
            case .failed:
                return Image(systemName: "exclamationmark.triangle")
            }
        }
    }
    
    /// ///
    //Progeso subida Momentos
    ///
    private var uploadProgressBar: some View {
        Group {
            if !uploadService.uploadingMoments.isEmpty {
                VStack(spacing: 0) {
                    // Contenedor principal
                    ForEach(uploadService.uploadingMoments.prefix(3)) { uploadingMoment in
                        UploadProgressRow(uploadingMoment: uploadingMoment)
                            .environmentObject(uploadService)
                    }
                    
                    // Si hay más de 3, mostrar contador
                    if uploadService.uploadingMoments.count > 3 {
                        HStack {
                            Text("+ \(uploadService.uploadingMoments.count - 3) \(NSLocalizedString("feed.uploading.more", comment: "More uploading"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color(hex: "007AFF").opacity(0.3))
                        .frame(height: 2),
                    alignment: .bottom
                )
                .animation(.easeInOut(duration: 0.3), value: uploadService.uploadingMoments.count)
            }
        }
    }
    
    struct UploadProgressRow: View {
        @ObservedObject var uploadingMoment: UploadingMoment
        @EnvironmentObject var uploadService: BackgroundMomentUploadService
        @Environment(\.colorScheme) var colorScheme
        @State private var rotationAngle: Double = 0
        @State private var checkScale: CGFloat = 1.0
        
        var body: some View {
            HStack(spacing: 12) {
                // Thumbnail pequeño
                if let thumbnail = uploadingMoment.thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        )
                }
                
                // Contenido y progreso
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Texto del momento
                        Text(uploadingMoment.content.isEmpty ? NSLocalizedString("feed.uploading.newMoment", comment: "New moment text") : uploadingMoment.content)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Estado y acciones
                        uploadStatusView
                    }
                    
                    // Barra de progreso
                    if uploadingMoment.status == .uploading || uploadingMoment.status == .processing {
                        progressBarView
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(statusBorderColor, lineWidth: 0.5)
                        )
                    
                    if uploadingMoment.status == .completed || uploadingMoment.status == .moderated {
                        // Success Ping Animation
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                            .scaleEffect(checkScale == 1.0 ? 1.0 : 1.1)
                            .opacity(checkScale == 1.0 ? 0 : 1)
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        
        // MARK: - 🎯 Vista de estado
        // UploadProgressRow.swift - VERSIÓN iOS 17+ MODERNA

        private var uploadStatusView: some View {
            HStack(spacing: 6) {
                switch uploadingMoment.status {
                case .uploading:
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.blue)
                    
                    Text(String(format: NSLocalizedString("feed.uploading.progress", comment: "Upload progress"), Int(uploadingMoment.uploadProgress * 100)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                    
                case .processing:
                    // 🔥 VERSIÓN COMPATIBLE - Animación clásica
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                    
                    Text("feed.uploading.processing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    
                case .completed, .moderated:
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .scaleEffect(checkScale)
                        .onAppear {
                            hapticNotification(.success)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                checkScale = 1.4
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    checkScale = 1.0
                                }
                            }
                        }
                    
                    Text("feed.uploading.published")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                    
                case .failed:
                    Button(action: {
                        uploadService.retryUpload(uploadingMoment)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .symbolEffect(.pulse, value: uploadingMoment.status)
                            
                            Text("feed.uploading.retry")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        uploadService.cancelUpload(uploadingMoment)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        }
        
        // MARK: - 📊 Barra de progreso
        private var progressBarView: some View {
            VStack(spacing: 2) {
                // Barra de progreso
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Fondo de la barra
                        RoundedRectangle(cornerRadius: 2)
                            .fill((colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215")).opacity(0.1))
                            .frame(height: 3)
                        
                        // Progreso con Glow
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * uploadingMoment.uploadProgress, height: 3)
                            .shadow(color: (uploadingMoment.status == .uploading ? Color(hex: "007AFF") : Color.orange).opacity(0.5), radius: 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: uploadingMoment.uploadProgress)
                    }
                }
                .frame(height: 3)
                
                // Texto de estado detallado
                HStack {
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if uploadingMoment.mediaCount > 1 {
                        Text(String(format: NSLocalizedString("feed.uploading.files", comment: "Files count"), uploadingMoment.mediaCount))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        
        // MARK: - 🎨 Helpers de color y texto
        private var statusBackgroundColor: Color {
            switch uploadingMoment.status {
            case .uploading, .processing:
                return Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08)
            case .completed, .moderated:
                return Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08)
            case .failed:
                return Color.red.opacity(colorScheme == .dark ? 0.15 : 0.08)
            }
        }
        
        private var statusBorderColor: Color {
            switch uploadingMoment.status {
            case .uploading, .processing:
                return Color.white.opacity(0.15)
            case .completed, .moderated:
                return Color.green.opacity(0.3)
            case .failed:
                return Color.red.opacity(0.3)
            }
        }
        
        private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
        
        private func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }

        private var progressColor: LinearGradient {
            switch uploadingMoment.status {
            case .uploading:
                return LinearGradient(
                    colors: [Color(hex: "007AFF"), Color(hex: "00D2B4")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .processing:
                return LinearGradient(
                    colors: [.orange, .yellow],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            default:
                return LinearGradient(
                    colors: [.green],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        
        private var statusText: String {
            switch uploadingMoment.status {
            case .uploading:
                return NSLocalizedString("feed.uploading.uploading", comment: "Uploading files status")
            case .processing:
                return NSLocalizedString("feed.uploading.creating", comment: "Creating moment status")
            case .completed, .moderated:
                return NSLocalizedString("feed.uploading.available", comment: "Moment available status")
            case .failed:
                return uploadingMoment.errorMessage ?? NSLocalizedString("feed.uploading.error", comment: "Upload error status")
            }
        }
    }

    // MARK: - Funciones de carga
    private func loadInitialData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ NUEVO: Evitar recargas innecesarias
        if hasLoadedInitialData {

            return
        }
        
        // ✅ NUEVO: Limpiar cache si es necesario
        clearCacheIfNeeded()
        
        // ✅ NUEVO: Recuperar preferencia del usuario al cargar
        selectedFeedType = UserDefaults.standard.selectedFeedType
        
        // ✅ PERF: Cargar saved moments una sola vez para evitar checkIfSaved por cada card
        firestoreService.loadSavedMoments(userId: userId)

        
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    // ✅ Usar la preferencia guardada del usuario
                    await self.viewModel.fetchMoments(userId: userId, feedType: self.selectedFeedType)
                }
                group.addTask {
                    await self.viewModel.fetchUserData(userId: userId)
                }
                group.addTask {
                    await self.messagingViewModel.fetchConversations(for: userId)
                }
                group.addTask {
                    await self.loadStoryUsers(userId: userId)
                }
            }
            prefetchImages()
            
            // ✅ NUEVO: Marcar como cargado
            hasLoadedInitialData = true
        }
    }
    
    // ✅ NUEVO: Función para limpiar cache
    private func clearCacheIfNeeded() {
        let cacheAge = Date().timeIntervalSince(cachedStoriesTimestamp)
        if cacheAge > 600 { // 10 minutos

            cachedStories.removeAll()
            cachedStoriesTimestamp = Date()
        }
    }
    
    // ✅ NUEVO: Función para forzar refresh
    private func forceRefresh() {

        hasLoadedInitialData = false
        cachedStories.removeAll()
        cachedUnseenStories.removeAll()
        cachedStoriesTimestamp = Date()
        loadInitialData()
    }
    
    // ✅ OPTIMIZADO: loadStoryUsers con cache básico
    private func loadStoryUsers(userId: String) async {
        await withCheckedContinuation { continuation in
            isLoadingStories = true
            
            firestoreService.fetchMutedUserIds(userId: userId) { mutedUserIds in
                firestoreService.fetchFollowing(userId: userId) { result in
                    switch result {
                    case .success(let followingUsers):
                        let followingIds = followingUsers.map { $0.id }.filter { !mutedUserIds.contains($0) }
                    var allUserIds = [userId] // Empezar contigo
                    allUserIds.append(contentsOf: followingIds)
                    
                    // ✅ NUEVO: Verificar cache primero
                    let cacheAge = Date().timeIntervalSince(self.cachedStoriesTimestamp)
                    if cacheAge < 20 && !self.cachedStories.isEmpty { // 20 segundos para evitar anillos desfasados

                        var cachedEntries: [StoryUserState] = []
                        
                        // Agregar tu historia
                        let currentUserHasStory = self.cachedStories[userId] ?? false
                        let cachedOwnStories = currentUserHasStory ? LocalPersistenceService.shared.loadStories(userId: userId) : []
                        let ownStoryCount = cachedOwnStories.isEmpty ? (currentUserHasStory ? 1 : 0) : cachedOwnStories.count
                        let ownAudiences = cachedOwnStories.isEmpty ? (currentUserHasStory ? [nil] : []) : cachedOwnStories.map { $0.audience }
                        // Tus historias se consideran vistas por ti en el ring.
                        let ownViewedStatus = Array(repeating: true, count: ownStoryCount)
                        cachedEntries.append((
                            userId: userId,
                            hasStory: currentUserHasStory,
                            hasUnseenStory: false,
                            storyCount: ownStoryCount,
                            storyViewedStatus: ownViewedStatus,
                            storyAudiences: ownAudiences
                        ))
                        
                        // Agregar historias de otros desde cache
                        for followingId in followingIds {
                            if let hasStory = self.cachedStories[followingId], hasStory {
                                let hasUnseenStory = self.cachedUnseenStories[followingId] ?? true // Default a true si no está en cache
                                let cachedStories = LocalPersistenceService.shared.loadStories(userId: followingId)
                                let count = cachedStories.isEmpty ? 1 : cachedStories.count
                                let audiences = cachedStories.isEmpty ? [nil] : cachedStories.map { $0.audience }
                                // En cache no tenemos estado exacto por segmento; mantenemos aproximación uniforme.
                                let viewedStatus = Array(repeating: !hasUnseenStory, count: count)
                                cachedEntries.append((
                                    userId: followingId,
                                    hasStory: true,
                                    hasUnseenStory: hasUnseenStory,
                                    storyCount: count,
                                    storyViewedStatus: viewedStatus,
                                    storyAudiences: audiences
                                ))
                            }
                        }

                        let finalUsers = self.buildSortedStoryUsers(entries: cachedEntries, currentUserId: userId)
                        
                        self.storyUsers = finalUsers
                        
                        // ✅ Widget: Contar historias nuevas desde cache
                        let newStoriesCount = finalUsers.filter { $0.hasUnseenStory }.count
                        let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
                        widgetDefaults?.set(newStoriesCount, forKey: "widget_new_stories_count")
                        self.scheduleWidgetReload()
                        
                        self.isLoadingStories = false
                        continuation.resume()
                        return
                    }
                    
                    let finishLoad: ([StoryUserState]) -> Void = { finalUsers in
                        DispatchQueue.main.async {
                            self.cachedStoriesTimestamp = Date()
                            self.storyUsers = finalUsers

                            let newStoriesCount = finalUsers.filter { $0.hasUnseenStory }.count
                            let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
                            widgetDefaults?.set(newStoriesCount, forKey: "widget_new_stories_count")
                            self.scheduleWidgetReload()

                            self.isLoadingStories = false
                            continuation.resume()
                        }
                    }

                    self.firestoreService.fetchStorySummariesForUsers(userIds: allUserIds) { summaryResult in
                        let candidateUserIds: [String]
                        switch summaryResult {
                        case .success(let summaries):
                            candidateUserIds = allUserIds.filter {
                                self.shouldFetchDetailedStories(
                                    for: $0,
                                    currentUserId: userId,
                                    summaries: summaries
                                )
                            }
                        case .failure:
                            candidateUserIds = allUserIds
                        }

                        self.firestoreService.fetchActiveStoriesForUsers(userIds: candidateUserIds) { batchedResult in
                            switch batchedResult {
                            case .success(let storiesByUser):
                                self.loadStoryUsersFromBatchedStories(
                                    allUserIds: allUserIds,
                                    currentUserId: userId,
                                    storiesByUser: storiesByUser,
                                    completion: finishLoad
                                )
                            case .failure:
                                self.loadStoryUsersLegacy(
                                    allUserIds: allUserIds,
                                    currentUserId: userId,
                                    completion: finishLoad
                                )
                            }
                        }
                    }
                    
                    case .failure:
                        // ✅ CORREGIDO: Fallback también debe verificar tu historia
                        self.checkUserStories(userId: userId, currentUserId: userId) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                            DispatchQueue.main.async {
                                // Guardar en cache también en fallback
                                self.cachedStories[userId] = hasStory
                                self.cachedUnseenStories[userId] = hasUnseen
                                
                                self.storyUsers = [(userId: userId, hasStory: hasStory, hasUnseenStory: false, storyCount: storyCount, storyViewedStatus: viewedStatus, storyAudiences: audiences)]
                                self.isLoadingStories = false
                                continuation.resume()
                            }
                        }
                    }
                }
            }
    }
    }

    private func loadStoryUsersFromBatchedStories(
        allUserIds: [String],
        currentUserId: String,
        storiesByUser: [String: [Story]],
        completion: @escaping ([StoryUserState]) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.users.batched.sync")
        var entriesByUser: [String: StoryUserState] = [:]

        for userIdToCheck in allUserIds {
            let stories = storiesByUser[userIdToCheck] ?? []
            group.enter()
            evaluateVisibleStoriesForRing(userId: userIdToCheck, currentUserId: currentUserId, stories: stories) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                syncQueue.async {
                    let entry: StoryUserState = (
                        userId: userIdToCheck,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseen,
                        storyCount: storyCount,
                        storyViewedStatus: viewedStatus,
                        storyAudiences: audiences
                    )
                    entriesByUser[userIdToCheck] = entry
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let orderedEntries = syncQueue.sync {
                allUserIds.map { userId in
                    entriesByUser[userId] ?? (
                        userId: userId,
                        hasStory: false,
                        hasUnseenStory: false,
                        storyCount: 0,
                        storyViewedStatus: [],
                        storyAudiences: []
                    )
                }
            }
            for entry in orderedEntries {
                self.cachedStories[entry.userId] = entry.hasStory
                self.cachedUnseenStories[entry.userId] = entry.hasUnseenStory
            }
            completion(self.buildSortedStoryUsers(entries: orderedEntries, currentUserId: currentUserId))
        }
    }

    private func loadStoryUsersLegacy(
        allUserIds: [String],
        currentUserId: String,
        completion: @escaping ([StoryUserState]) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.users.legacy.sync")
        var entriesByUser: [String: StoryUserState] = [:]

        for userIdToCheck in allUserIds {
            group.enter()
            self.checkUserStories(userId: userIdToCheck, currentUserId: currentUserId) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                syncQueue.async {
                    let entry: StoryUserState = (
                        userId: userIdToCheck,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseen,
                        storyCount: storyCount,
                        storyViewedStatus: viewedStatus,
                        storyAudiences: audiences
                    )
                    entriesByUser[userIdToCheck] = entry
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let orderedEntries = syncQueue.sync {
                allUserIds.map { userId in
                    entriesByUser[userId] ?? (
                        userId: userId,
                        hasStory: false,
                        hasUnseenStory: false,
                        storyCount: 0,
                        storyViewedStatus: [],
                        storyAudiences: []
                    )
                }
            }
            for entry in orderedEntries {
                self.cachedStories[entry.userId] = entry.hasStory
                self.cachedUnseenStories[entry.userId] = entry.hasUnseenStory
            }
            completion(self.buildSortedStoryUsers(entries: orderedEntries, currentUserId: currentUserId))
        }
    }

    private func buildSortedStoryUsers(entries: [StoryUserState], currentUserId: String) -> [StoryUserState] {
        let currentUserEntry = entries.first(where: { $0.userId == currentUserId }) ?? (
            userId: currentUserId,
            hasStory: false,
            hasUnseenStory: false,
            storyCount: 0,
            storyViewedStatus: [],
            storyAudiences: []
        )

        let normalizedCurrentUserEntry: StoryUserState = (
            userId: currentUserEntry.userId,
            hasStory: currentUserEntry.hasStory,
            hasUnseenStory: false,
            storyCount: currentUserEntry.storyCount,
            storyViewedStatus: currentUserEntry.storyViewedStatus,
            storyAudiences: currentUserEntry.storyAudiences
        )

        var sortedOthers = entries.filter { $0.userId != currentUserId && $0.hasStory }

        let affinityManager = AffinityTracker.shared
        if let container = affinityManager.modelContainer {
            let context = SwiftData.ModelContext(container)
            let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
            let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
            let affinityScores = affinityManager.getScores(for: sortedOthers.map { $0.userId }, in: context)

            sortedOthers.sort { user1, user2 in
                if user1.hasUnseenStory && !user2.hasUnseenStory { return true }
                if user2.hasUnseenStory && !user1.hasUnseenStory { return false }

                var score1 = (affinityScores[user1.userId] ?? 0.0) * 1000
                var score2 = (affinityScores[user2.userId] ?? 0.0) * 1000

                if bestFriends.contains(user1.userId) {
                    score1 += 50000
                } else if mutuals.contains(user1.userId) {
                    score1 += 20000
                }

                if bestFriends.contains(user2.userId) {
                    score2 += 50000
                } else if mutuals.contains(user2.userId) {
                    score2 += 20000
                }

                return score1 > score2
            }
        } else {
            sortedOthers.sort { user1, user2 in
                if user1.hasUnseenStory && !user2.hasUnseenStory { return true }
                if user2.hasUnseenStory && !user1.hasUnseenStory { return false }
                return false
            }
        }

        var finalUsers: [StoryUserState] = [normalizedCurrentUserEntry]
        finalUsers.append(contentsOf: sortedOthers)
        return finalUsers
    }

    private func shouldFetchDetailedStories(
        for authorId: String,
        currentUserId: String,
        summaries: [String: StoryAuthorSummary]
    ) -> Bool {
        if authorId == currentUserId {
            return true
        }
        guard let summary = summaries[authorId] else {
            // Sin summary => fallback seguro (no ocultar historias por estado desconocido).
            return true
        }
        return !summary.shouldSkipDetailedFetch()
    }

    private func evaluateVisibleStoriesForRing(
        userId: String,
        currentUserId: String,
        stories: [Story],
        completion: @escaping (Bool, Bool, Int, [Bool], [String?]) -> Void
    ) {
        guard !stories.isEmpty else {
            completion(false, false, 0, [], [])
            return
        }

        StorySeenStateService.shared.fetchEffectiveLastSeen(
            viewerId: currentUserId,
            authorId: userId
        ) { effectiveLastSeenAt in
            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "story.visibility.sync.\(userId)")
            var visibleStories: [(story: Story, wasViewed: Bool)] = []
            var hasUnseenStory = false

            for story in stories {
                group.enter()
                let completionLock = NSLock()
                var didComplete = false

                func markCompleted() -> Bool {
                    completionLock.lock()
                    defer { completionLock.unlock() }
                    if didComplete { return false }
                    didComplete = true
                    return true
                }

                self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                    guard markCompleted() else { return }

                    if canView {
                        let supportsShortcut = StorySeenStateService.shared.supportsShortcut(forAudience: story.audience)
                        if supportsShortcut, let effectiveLastSeenAt = effectiveLastSeenAt, story.timestamp <= effectiveLastSeenAt {
                            syncQueue.async {
                                visibleStories.append((story: story, wasViewed: true))
                                group.leave()
                            }
                            return
                        }

                        if let storyId = story.id {
                            Firestore.firestore().collection("users").document(story.authorId)
                                .collection("stories").document(storyId)
                                .collection("viewers").document(currentUserId)
                                .getDocument { viewerDoc, _ in
                                    let wasViewed = viewerDoc?.exists == true
                                    if wasViewed, supportsShortcut {
                                        StorySeenStateService.shared.markSeen(
                                            viewerId: currentUserId,
                                            authorId: userId,
                                            timestamp: story.timestamp,
                                            syncRemote: true
                                        )
                                    }
                                    syncQueue.async {
                                        visibleStories.append((story: story, wasViewed: wasViewed))
                                        if !wasViewed {
                                            hasUnseenStory = true
                                        }
                                        group.leave()
                                    }
                                }
                        } else {
                            syncQueue.async {
                                let wasViewed = supportsShortcut && (effectiveLastSeenAt != nil)
                                visibleStories.append((story: story, wasViewed: wasViewed))
                                if !wasViewed {
                                    hasUnseenStory = true
                                }
                                group.leave()
                            }
                        }
                    } else {
                        group.leave()
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if markCompleted() {
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                let (sortedStories, unseenStory): ([(story: Story, wasViewed: Bool)], Bool) = syncQueue.sync {
                    let sorted = visibleStories.sorted { story1, story2 in
                        (story1.story.timestamp) < (story2.story.timestamp)
                    }
                    return (sorted, hasUnseenStory)
                }

                let storyCount = sortedStories.count
                let viewedStatus = sortedStories.map { $0.wasViewed }
                let audiences = sortedStories.map { $0.story.audience }
                let hasStory = storyCount > 0

                Task {
                    await StoryRingCacheService.shared.set(
                        viewerId: currentUserId,
                        authorId: userId,
                        snapshot: StoryRingSnapshot(
                            hasStory: hasStory,
                            hasUnseenStory: unseenStory,
                            storyCount: storyCount,
                            storyViewedStatus: viewedStatus,
                            storyAudiences: audiences
                        )
                    )
                }

                completion(hasStory, unseenStory, storyCount, viewedStatus, audiences)
            }
        }
    }

    // ✅ MEJORAR: checkUserStories con mejor logging y manejo de errores
    private func checkUserStories(userId: String, currentUserId: String, completion: @escaping (Bool, Bool, Int, [Bool], [String?]) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                
                if let error = error {

                    completion(false, false, 0, [], [])
                    return
                }
                guard let documents = snapshot?.documents, !documents.isEmpty else {

                    completion(false, false, 0, [], []) // No tiene historias
                    return
                }
                let stories = documents.compactMap { doc -> Story? in
                    do {
                        let story = try doc.data(as: Story.self)

                        return story
                    } catch {
    
                        return nil
                    }
                }
                
                guard !stories.isEmpty else {
    
                    completion(false, false, 0, [], [])
                    return
                }

                self.evaluateVisibleStoriesForRing(
                    userId: userId,
                    currentUserId: currentUserId,
                    stories: stories,
                    completion: completion
                )
            }
    }
    
    private func refreshFeed(userId: String) async {
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.viewModel.refreshMoments(userId: userId)
            }
            group.addTask {
                await self.notificationsViewModel.refreshNotifications()
            }
            group.addTask {
                await self.messagingViewModel.fetchConversations(for: userId)
            }
            group.addTask {
                await self.loadStoryUsers(userId: userId)
            }
        }
        prefetchImages()
    }
    
    // ✅ OPTIMIZADO: Prefetching mejorado
    private func prefetchImages() {
        let momentUrls = viewModel.moments
            .prefix(10) // ✅ AUMENTADO: De 3 a 10 imágenes
            .compactMap { $0.imagePath }
            .compactMap { URL(string: $0) }
        ImagePrefetchManager.shared.prefetch(urls: momentUrls)
    }
    
    private func scheduleWidgetReload(delay: TimeInterval = 2.0) {
        widgetReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - ✅ COMPONENTES MODERNOS

// ✅ Botón de stories moderno
struct ModernStoryButton: View {
    let colorScheme: ColorScheme
    let action: () -> Void
    @StateObject private var uploadProgressManager = StoryUploadProgressManager.shared
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Fondo más sutil - casi transparente como estilo nativo
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ?
                          Color(hex: "FAF9F6").opacity(0.05) :
                          Color(hex: "0B1215").opacity(0.03))
                    .frame(width: 36, height: 36)
                
                Image(systemName: uploadProgressManager.isUploading ? "arrow.up" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ?
                                   Color.white.opacity(0.9) :
                                   Color.black.opacity(0.8))
                
                if uploadProgressManager.isUploading {
                    // Progreso más discreto
                    Circle()
                        .stroke(adaptiveColors.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0, to: uploadProgressManager.progress)
                        .stroke(adaptiveColors.accent, lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: uploadProgressManager.progress)
                }
            }
        }
        .scaleEffect(uploadProgressManager.isUploading ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: uploadProgressManager.isUploading)
    }
}

// ✅ Botón de notificaciones integrado
struct ModernNotificationButton: View {
    let hasNotification: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Fondo rojo sutil cuando hay notificaciones
                if hasNotification {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 36, height: 36)
                }
                
                // ✅ CAMBIAR: Corazón rojo cuando hay notificaciones
                Image(systemName: hasNotification ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(hasNotification ?
                        .red :  // ✅ ROJO cuando hay notificaciones
                                     (colorScheme == .dark ?
                                      Color.white.opacity(0.9) :
                                        Color.black.opacity(0.8)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasNotification)
    }
}

// ✅ Botón de mensajes integrado
struct ModernMessageButton: View {
    let hasMessage: Bool
    let messageCount: Int // ✅ AGREGAR esta línea
    let colorScheme: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "paperplane")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(colorScheme == .dark ?
                                   Color.white.opacity(0.9) :
                                   Color.black.opacity(0.8))
                
                // ✅ CAMBIAR: Badge con número en lugar de punto
                if hasMessage && messageCount > 0 {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: messageCount > 9 ? 20 : 16, height: 16)
                        
                        Text("\(min(messageCount, 99))")
                            .font(.system(size: messageCount > 9 ? 10 : 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .offset(x: 10, y: -10)
                    .scaleEffect(hasMessage ? 1.0 : 0.1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasMessage)
                }
            }
        }
    }
}

// ✅ Loading moderno tipo "respiración" para más posts
struct ModernLoadingMoreView: View {
    let colorScheme: ColorScheme
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.6
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Círculo que "respira" con gradiente de Glowsy
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
                .scaleEffect(scale)
                .opacity(opacity)
                .animation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                    value: scale
                )
            
            Text("feed.loadingMore")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: adaptiveColors.shadowColor.opacity(0.3), radius: 6, x: 0, y: 3)
        .onAppear {
            // Iniciar animación de respiración
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.2
                opacity = 1.0
            }
        }
    }
}

// ✅ Estado vacío moderno


// ✅ ACTUALIZADO: ModernPostCardView con círculo de historia en el header
struct ModernPostCardView: View {
    let moment: Moment
    let availableHeight: CGFloat
    let colorScheme: ColorScheme
    let onComment: () -> Void
    let onNearEnd: () -> Void
    let onHashtagTap: (String) -> Void
    let onLocationTap: (String, CLLocationCoordinate2D?) -> Void
    let onContextMenu: (Moment) -> Void
    var onTagTap: ((String) -> Void)? = nil // ✅ Tag Navigation Callback
    var onPeek: ((String, CGFloat, Bool) -> Void)? = nil // ✅ PEEK: (imageURL, realRatio, isPressing)
    @EnvironmentObject private var firestoreService: FirestoreService
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var currentImageIndex = 0
    @State private var detectedAspectRatio: CGFloat
    @State private var isFollowing: Bool = false
    @State private var isSaved: Bool = false
    @State private var isFollowLoading: Bool = false
    @State private var isSaveLoading: Bool = false
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    @State private var showTags: Bool = false // ✅ NUEVO: Estado global para etiquetas en el post
    @State private var isImmersive: Bool = false // ✅ NUEVO: Modo inmersivo
    @State private var realAspectRatio: CGFloat = 1.0 // ✅ Ratio real sin cap (para long press reveal)
    
    // ✅ ACTUALIZADO: AspectRatioType mejorado con soporte para reels
    @State private var aspectRatioType: AspectRatioType = .square
    @State private var cachedCardHeight: CGFloat?
    @State private var lastCalculatedSize: CGSize = .zero
    @State private var isFirstAppear = true
    
    init(moment: Moment,
         availableHeight: CGFloat,
         colorScheme: ColorScheme,
         onComment: @escaping () -> Void,
         onNearEnd: @escaping () -> Void,
         onHashtagTap: @escaping (String) -> Void,
         onLocationTap: @escaping (String, CLLocationCoordinate2D?) -> Void,
         onContextMenu: @escaping (Moment) -> Void,
         onTagTap: ((String) -> Void)? = nil,
         onPeek: ((String, CGFloat, Bool) -> Void)? = nil) {
        
        self.moment = moment
        self.availableHeight = availableHeight
        self.colorScheme = colorScheme
        self.onComment = onComment
        self.onNearEnd = onNearEnd
        self.onHashtagTap = onHashtagTap
        self.onLocationTap = onLocationTap
        self.onContextMenu = onContextMenu
        self.onTagTap = onTagTap
        self.onPeek = onPeek
        _commentCount = State(initialValue: moment.commentCount)
        
        // ✅ CRÍTICO: Inicialización estática con metadatos SIEMPRE
        // Evitamos que el layout "baile" al cargar confiando en la DB
        if let ratioStr = moment.aspectRatio, !ratioStr.isEmpty {
            let ratio = ProcessedMedia.AspectRatio(from: ratioStr).value
            let safeRatio = (ratio > 0 && ratio.isFinite) ? ratio : 1.0
            
            // ✅ Guardar el ratio REAL para el long press reveal
            _realAspectRatio = State(initialValue: safeRatio)
            
            // ✅ REGLA INSTAGRAM: Todo contenido más vertical que 4:5 se cropea en el feed.
            // Vídeos se ven completos al hacer tap (Reels viewer).
            let displayRatio: CGFloat
            if safeRatio < 0.8 {
                displayRatio = 0.8
            } else {
                displayRatio = safeRatio
            }
            
            _detectedAspectRatio = State(initialValue: displayRatio)
            
            if displayRatio < 0.7 { _aspectRatioType = State(initialValue: .reels) }
            else if displayRatio < 0.9 { _aspectRatioType = State(initialValue: .portrait) }
            else if displayRatio < 1.3 { _aspectRatioType = State(initialValue: .square) }
            else { _aspectRatioType = State(initialValue: .landscape) }
        } else {
            _detectedAspectRatio = State(initialValue: 1.0)
            _realAspectRatio = State(initialValue: 1.0)
            _aspectRatioType = State(initialValue: .square)
        }
    }
    
    // ✅ Estados para el círculo de historia en el header
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    @State private var storyAudiences: [String?] = []
    @State private var isLoadingStory: Bool = false
    @State private var liveAuthorUsername: String = ""
    @State private var showStories = false
    @State private var showSpecificUserStories = false
    private let privacyService = PrivacyService()
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var displayAuthorUsername: String {
        let fallback = moment.username
        let live = liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }
    
    // ✅ MEJORADO: AspectRatioType con soporte completo para todos los formatos
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 400      // Para 1:1 (1080x1080)
            case .portrait: return 500    // Para 4:5 (1080x1350)
            case .landscape: return 300   // Para 16:9 - más compacto
            case .reels: return 600       // ✅ AJUSTADO: Para 9:16 (reels) - altura más razonable para el feed
            }
        }
        
        // ✅ NUEVO: Aspect ratios exactos basados en las dimensiones reales
        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0      // 1080÷1080 = 1.0
            case .portrait: return 0.8    // 1080÷1350 = 0.8
            case .landscape: return 1.78  // 16÷9 = 1.778
            case .reels: return 0.5625    // 9÷16 = 0.5625 (formato vertical de reels)
            }
        }
        
        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .landscape: return "16:9"
            case .reels: return "9:16"
            }
        }
    }

    private var mediaItems: [MediaItem] {
        // ✅ NUEVO: Usar el campo mediaItems del momento (múltiples archivos)
        if let mediaItems = moment.mediaItems, !mediaItems.isEmpty {
            return mediaItems
        }
        
        // ✅ FALLBACK: Para momentos legacy que solo tienen imagePath/videoUrl
        var items: [MediaItem] = []
        if let imagePath = moment.imagePath, !imagePath.isEmpty {
            items.append(MediaItem(type: .image, url: imagePath))
        }
        if let videoUrl = moment.videoUrl, !videoUrl.isEmpty {
            items.append(MediaItem(type: .video, url: videoUrl))
        }
        return items.isEmpty ? [MediaItem(type: .image, url: "")] : items
    }

    // ✅ MEJORADO: Cálculo de altura con validaciones completas
    private var cardHeight: CGFloat {
        let currentSize = CGSize(
            width: UIScreen.main.bounds.width - 16,
            height: availableHeight
        )
        
        // ✅ CACHEAR: Solo recalcular si el tamaño cambió significativamente
        if let cached = cachedCardHeight,
           abs(currentSize.width - lastCalculatedSize.width) < 1.0,
           abs(currentSize.height - lastCalculatedSize.height) < 1.0 {
            return cached
        }
        
        let newHeight = calculateCardHeight(for: currentSize)
        
        DispatchQueue.main.async {
            if self.cachedCardHeight != newHeight {
                self.cachedCardHeight = newHeight
                self.lastCalculatedSize = currentSize
            }
        }
        
        return newHeight
    }
    
    private func calculateCardHeight(for containerSize: CGSize) -> CGFloat {
        let maxWidth = containerSize.width
        guard maxWidth > 0 else { return 300 }
        
        let ratio = (detectedAspectRatio > 0 && detectedAspectRatio.isFinite) ? detectedAspectRatio : 1.0
        let idealHeight = maxWidth / ratio
        
        let maxAllowed = containerSize.height * 0.95
        return max(min(idealHeight, maxAllowed), 150)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header del post con círculo de historia
            postHeaderView
                .opacity(isImmersive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isImmersive)
            
            // Contenido principal
            ZStack(alignment: .bottom) {
                ZStack {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        showTags: $showTags, // ✅ PASAR binding
                        aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                        allMoments: feedViewModel.moments,
                        currentMoment: moment,
                        onTagTap: onTagTap, // ✅ Propagate to parent
                        isImmersive: $isImmersive // ✅ NUEVO: Faltaba este parámetro
                    )
                    .frame(height: max(cardHeight, 200))
                    .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 12 : 20))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isImmersive)
                    // ✅ NUEVO: Sistema de sombras multi-nivel (Efecto de profundidad premium)
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.12), radius: 15, x: 0, y: 10)
                    .shadow(color: colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .onAppear {
                        detectAspectRatio()
                    }
                    // ✅ NUEVO: Gesto para Modo Inmersivo
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onEnded { value in
                                // No hacemos nada en onEnded si queremos que sea momentáneo al soltar
                            }
                    )
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                        let currentItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : mediaItems.first
                        let shouldUseFullscreenPeek = mediaItems.count > 1 &&
                            currentItem?.type == .image &&
                            currentItem?.isHiddenByModeration != true

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isImmersive = isPressing
                            if isPressing {
                                HapticManager.shared.mediumImpact()
                                // ✅ PEEK: Comunicar imagen al FeedView para overlay
                                if let item = currentItem, item.type == .image, !item.isHiddenByModeration {
                                    let currentItemRatio = item.resolvedAspectRatioValue ?? realAspectRatio
                                    if currentItemRatio > 0,
                                       currentItemRatio.isFinite,
                                       (shouldUseFullscreenPeek || abs(currentItemRatio - detectedAspectRatio) > 0.035) {
                                        onPeek?(item.url, currentItemRatio, true)
                                    }
                                }
                            } else {
                                onPeek?("", 1.0, false)
                            }
                        }
                    }, perform: {})
                    
                    if mediaItems.count > 1 {
                        VStack {
                            HStack(spacing: 8) {
                                ForEach(0..<mediaItems.count, id: \.self) { index in
                                    Capsule()
                                        .fill(currentImageIndex == index ? getIndicatorColor(for: index) : Color.white.opacity(0.3))
                                        .frame(width: currentImageIndex == index ? 30 : 10, height: 6)
                                        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                }
                            }
                            .padding(.top, 20) // ✅ Más arriba para mejor visibilidad
                            Spacer()
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }
                    
                    let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
                    if let currentMediaItem, !currentMediaItem.isHiddenByModeration,
                       let tags = currentMediaItem.tags, !tags.isEmpty {
                        // Esquina inferior izquierda (encima del caption) - Estilo Glass
                        VStack {
                            Spacer()
                            HStack {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        showTags.toggle()
                                    }
                                }) {
                                    ZStack {
                                        // Background Glass
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 38, height: 38)
                                        
                                            .frame(width: 38, height: 38)
                                        
                                        // Icon tinted if active
                                        Image(systemName: showTags ? "person.fill" : "person.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(showTags ? Color(hex: "007AFF") : .white)
                                    }
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                                }
                                .padding(.leading, 12)
                                .padding(.bottom, moment.content.isEmpty ? 20 : 70) // Ajustar si hay texto
                                Spacer()
                            }
                        }
                        .zIndex(110)
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }
                    
                    // ✅ NUEVO: Indicador de aspect ratio (solo para debug si está habilitado)
                    if ProcessInfo.processInfo.environment["DEBUG_ASPECT_RATIO"] != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(aspectRatioType.displayName)")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .padding(.trailing, 20)
                                    .padding(.top, 20)
                            }
                            Spacer()
                        }
                    }
                    
                    // ✅ NUEVO: Gradiente protector para el texto (Cinematic feel)
                    VStack {
                        Spacer()
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.7)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120) // Altura suficiente para cubrir el caption
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .allowsHitTesting(false)
                    .opacity(isImmersive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isImmersive)

                    if !moment.content.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                ExpandableContentView(
                                    content: moment.content,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { hashtag in

                                        onHashtagTap(hashtag)
                                    }
                                )
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.trailing, 140) // ✅ Más espacio de seguridad
                            .padding(.bottom, 20)
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }
                }
                
                ModernActionButtons(
                    moment: moment,
                    isSaved: $isSaved,
                    isSaveLoading: $isSaveLoading,
                    commentCount: $commentCount,
                    onComment: onComment,
                    onSave: toggleSave,
                    onContextMenu: { onContextMenu(moment) }, // ✅ NUEVO
                    isImmersive: $isImmersive // ✅ NUEVO
                )
                .environmentObject(firestoreService)
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            if !hasLoadedInitialData {
                loadAllPostData()
                refreshAuthorUsername()
                hasLoadedInitialData = true
                
                // ✅ MARCAR que ya no es primera aparición
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFirstAppear = false
                }
            } else if liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                refreshAuthorUsername()
            }
            onNearEnd()
            
            // Solo para videos, notificar que está visible
            if mediaItems.first?.type == .video {

            }
        }
        .onChange(of: firestoreService.savedMomentIds) { _ in
            guard let currentUserId = Auth.auth().currentUser?.uid,
                  let momentId = moment.id,
                  firestoreService.hasLoadedSavedMoments(for: currentUserId) else { return }
            isSaved = firestoreService.savedMomentIds.contains(momentId)
        }
        .onChange(of: moment.authorId) { _ in
            liveAuthorUsername = ""
            refreshAuthorUsername()
        }

        .fullScreenCover(isPresented: $showSpecificUserStories) {
            StoriesView(startWithUserId: Binding(
                get: { moment.authorId },
                set: { _ in }
            ))
            .environmentObject(firestoreService)
            .onAppear {


            }
        }
    }
    
    // Header del post con círculo de historia
    private var postHeaderView: some View {
        HStack(spacing: 12) {
            Button(action: {
                if hasStory {
                    showSpecificUserStories = true
                } else {
                    // Si no tiene historia, ir al perfil
                    NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                }
            }) {
                ZStack {
                    AsyncProfileImageView(userId: moment.authorId)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: hasUnseenStory,
                                storyViewedStatus: storyViewedStatus,
                                storyAudiences: storyAudiences,
                                isOwnStory: false,
                                colorScheme: colorScheme,
                                ringSize: 44,
                                lineWidth: 2.5,
                                hapticsEnabled: false
                            )
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        if moment.authorId == Auth.auth().currentUser?.uid {
                            Button(action: {
                                // Navegar al perfil propio (Tab 4) o mostrar hoja
                                NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                            }) {
                                Text(displayAuthorUsername)
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(adaptiveColors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: {
                                // Navegar a perfil de otro usuario
                                NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                            }) {
                                Text(displayAuthorUsername)
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(adaptiveColors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        if moment.authorId == Auth.auth().currentUser?.uid {
                            // Para el usuario actual, verificar si está verificado
                            CurrentUserVerifiedBadge(size: 14)
                        } else {
                            // Para otros usuarios, verificar si están verificados
                            VerifiedBadgeView(userId: moment.authorId, size: 14)
                        }
                    }
                    
                    Text(moment.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(adaptiveColors.tertiary)
                }
                
                if let location = moment.location, !location.isEmpty {
                    Button(action: {
                        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedLocation.isEmpty else {
                            return
                        }
                        
                        onLocationTap(trimmedLocation, moment.locationCoordinate?.toCLLocationCoordinate2D)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(adaptiveColors.accent)
                            
                            Text(location)
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(adaptiveColors.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            if moment.authorId != Auth.auth().currentUser?.uid {
                ModernFollowButton(
                    isFollowing: isFollowing,
                    isLoading: isFollowLoading,
                    colorScheme: colorScheme,
                    action: toggleFollow
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onAppear {
            checkUserStories()
        }
    }
    
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        if moment.authorId == currentUserId {
            hasStory = false
            hasUnseenStory = false
            storyCount = 0
            storyViewedStatus = []
            storyAudiences = []
            isLoadingStory = false
            return
        }
        
        isLoadingStory = true
        
        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: moment.authorId,
            privacyService: privacyService,
            db: firestoreService.db
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
            self.isLoadingStory = false
        }
    }
    
    // ✅ NUEVO: Función para colores de indicadores multicolores
    private func getIndicatorColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "#5b2c6f"), // Púrpura
            Color(hex: "#007bff"), // Azul
            Color(hex: "#40dfcf"), // Turquesa
            Color(hex: "#ff6b6b"), // Rojo coral
            Color(hex: "#4ecdc4"), // Verde azulado
            Color(hex: "#45b7d1"), // Azul claro
            Color(hex: "#96ceb4"), // Verde menta
            Color(hex: "#feca57")  // Amarillo
        ]
        
        return colors[index % colors.count]
    }
    
    // ✅ MEJORADO: Función detectAspectRatio - SIEMPRE usar el aspect ratio guardado si está disponible
    private func detectAspectRatio() {
        // ✅ PRIMERO Y PRINCIPAL: Usar aspect ratio guardado en la base de datos (no recalcular)
        if let savedAspectRatio = moment.aspectRatio, !savedAspectRatio.isEmpty {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            let expectedRatioValue = aspectRatioFromDB.value
            
            // ✅ REGLA INSTAGRAM: Todo contenido más vertical que 4:5 se cropea
            let displayRatio: CGFloat
            if expectedRatioValue < 0.8 && expectedRatioValue > 0 {
                displayRatio = 0.8
            } else if expectedRatioValue > 0 && expectedRatioValue.isFinite {
                displayRatio = expectedRatioValue
            } else {
                displayRatio = 1.0
            }
            
            // Solo actualizar si el valor actual es diferente
            if detectedAspectRatio != displayRatio {
                DispatchQueue.main.async {
                    self.realAspectRatio = expectedRatioValue // ✅ Siempre guardar el real
                    self.detectedAspectRatio = displayRatio
                    self.cachedCardHeight = nil
                    
                    // Clasificar el tipo
                    if displayRatio < 0.7 { self.aspectRatioType = .reels }
                    else if displayRatio < 0.9 { self.aspectRatioType = .portrait }
                    else if displayRatio < 1.3 { self.aspectRatioType = .square }
                    else { self.aspectRatioType = .landscape }
                }
            }
            return
        }
        
        // ✅ SOLO FALLBACK: Si NO hay aspect ratio guardado, detectar una sola vez
        // Evitar detectar múltiples veces para el mismo momento
        guard detectedAspectRatio == 1.0 || detectedAspectRatio == 0 else {
            return // Ya se detectó
        }
        
        // ✅ FALLBACK: Si no hay aspect ratio guardado, detectar una sola vez
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {

            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.8 // Fallback a 4:5
                self.aspectRatioType = .portrait
                self.cachedCardHeight = nil // Invalidar cache
            }
            return
        }
        
        if firstItem.type == .image {

            KFImage(URL(string: firstItem.url))
                .onSuccess { result in
                    let imageSize = result.image.size
                    let ratio = imageSize.width / imageSize.height

                    
                    DispatchQueue.main.async {
                        // ✅ Validar ratio calculado
                        if ratio > 0 && ratio.isFinite {
                            self.detectedAspectRatio = ratio
                            self.classifyAspectRatio(ratio)
                        } else {
                            self.detectedAspectRatio = 1.0
                            self.aspectRatioType = .square
                        }
                    }
                }
                .onFailure { error in
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = 0.8 // Fallback a 4:5
                        self.aspectRatioType = .portrait
                    }
                }
        } else {
            // ✅ MEJORADO: Para videos, detectar si es vertical (reels) o horizontal (landscape)

            
            // Por defecto, asumir formato reels para videos (9:16)
            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.5625 // 9÷16 = 0.5625
                self.aspectRatioType = .reels
            }
            
            if let url = URL(string: firstItem.url) {
                let asset = AVAsset(url: url)
                Task {
                    do {
                        let track = try await asset.loadTracks(withMediaType: .video).first
                        if let track = track {
                            let size = try await track.load(.naturalSize)
                            let videoRatio = size.width / size.height
                            
                            DispatchQueue.main.async {
                                self.detectedAspectRatio = videoRatio
                                self.classifyAspectRatio(videoRatio)
                            }
                        }
                    } catch {

                    }
                }
            }
        }
    }
    
    // ✅ NUEVA: Función helper para clasificar aspect ratios
    private func classifyAspectRatio(_ ratio: CGFloat) {
        let tolerance: CGFloat = 0.05
        
        if abs(ratio - 1.0) < tolerance {
            // Square: ~1.0 (como 1080x1080)
            self.aspectRatioType = .square

        } else if abs(ratio - 0.8) < tolerance {
            // Portrait 4:5: ~0.8 (como 1080x1350)
            self.aspectRatioType = .portrait

        } else if abs(ratio - 0.5625) < tolerance {
            // Reels 9:16: ~0.5625 (como 1080x1920)
            self.aspectRatioType = .reels

        } else if ratio > 1.4 {
            // Landscape: > 1.4 (16:9 = 1.778)
            self.aspectRatioType = .landscape

        } else if ratio < 0.7 {
            // Muy vertical: usar como reels
            self.aspectRatioType = .reels

        } else {
            // Default entre ratios: usar square
            self.aspectRatioType = .square

        }
    }
    
    // Resto de funciones sin cambios
    private func loadAllPostData() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // ✅ PERF: Usar contador denormalizado del moment para evitar query por card
        commentCount = moment.commentCount
        
        feedViewModel.listenForCommentUpdates(momentId: momentId, authorId: moment.authorId)
        
        if moment.authorId != currentUserId {
            firestoreService.isFollowingCached(currentUserId: currentUserId, targetUserId: moment.authorId) { following in
                DispatchQueue.main.async {
                    self.isFollowing = following
                }
            }
        }
        
        if firestoreService.hasLoadedSavedMoments(for: currentUserId) {
            isSaved = firestoreService.savedMomentIds.contains(momentId)
        } else {
            firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { result in
                if case .success(let saved) = result {
                    DispatchQueue.main.async {
                        self.isSaved = saved
                    }
                }
            }
        }
    }

    private func refreshAuthorUsername() {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveAuthorUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines) == authorId else { return }
                self.liveAuthorUsername = fetchedUsername
            }
        }
    }
    
    private func loadCommentCount() {
        guard let momentId = moment.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ VALIDAR: Solo cargar comentarios si el usuario puede ver el momento
        firestoreService.canViewContent(currentUserId: currentUserId, targetUserId: moment.authorId) { result in
            switch result {
            case .success(let canView):
                guard canView else { return } // No cargar comentarios si no puede ver el momento
                
                // ✅ Solo cargar comentarios si tiene permisos
                self.firestoreService.db.collection("users").document(self.moment.authorId)
                    .collection("moments").document(momentId)
                    .collection("comments")
                    .getDocuments { snapshot, error in
                        if let error = error {
                            return
                        }
                        
                        DispatchQueue.main.async {
                            let newCount = snapshot?.documents.count ?? 0
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.commentCount = newCount
                            }
                        }
                    }
                    
            case .failure(_):
                // Si falla la verificación de permisos, no cargar comentarios
                return
            }
        }
    }
    
    private func toggleFollow() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ OPTIMISTIC UPDATE
        let previousState = isFollowing
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            self.isFollowing.toggle()
        }
        
        isFollowLoading = true
        
        if previousState {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if let error = error {
                        // Revert on error
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = true
                        }
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if let error = error {
                        // Revert on error
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = false
                        }
                    }
                }
            }
        }
    }
    
    private func toggleSave() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // ✅ OPTIMISTIC UPDATE
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            self.isSaved.toggle()
        }
        
        isSaveLoading = true
        
        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.isSaveLoading = false
                if let error = error {
                    // Revert on error
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
}
// ✅ COMPONENTES AUXILIARES (reusables)

// Enhanced Carousel View (mantener igual que antes)
struct EnhancedCarouselView: View {
    let mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    @Binding var showTags: Bool // ✅ NUEVO: Binding
    let aspectRatio: CGFloat
    let allMoments: [Moment] // ✅ NUEVO: Todos los momentos del feed
    let currentMoment: Moment // ✅ NUEVO: Momento actual
    var onTagTap: ((String) -> Void)? = nil // ✅ Tag Navigation
    @Binding var isImmersive: Bool // ✅ NUEVO
    
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                    MediaItemView(
                        item: item,
                        aspectRatio: aspectRatio,
                        prefersUnifiedCarouselFrame: mediaItems.count > 1,
                        allMoments: allMoments, // ✅ PASAR todos los momentos
                        currentMoment: currentMoment, // ✅ PASAR momento actual
                        showTags: $showTags, // ✅ PASAR binding
                        onTagTap: onTagTap, // ✅ Propagate
                        isImmersive: $isImmersive // ✅ NUEVO
                    )
                    .tag(index)
                    .frame(width: geometry.size.width)
                    .clipped()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 1.05))
                    ))
                    .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.4), value: currentIndex)
        }
    }
}

struct MediaItemView: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let prefersUnifiedCarouselFrame: Bool
    let allMoments: [Moment]
    let currentMoment: Moment
    @Binding var showTags: Bool // ✅ AHORA ES BINDING
    var onTagTap: ((String) -> Void)? = nil // ✅ Tag Navigation
    @Binding var isImmersive: Bool // ✅ NUEVO
    
    @State private var showReelsViewer = false
    @State private var isVisible = false
    @State private var loadedAspectRatio: CGFloat? = nil

    private var resolvedItemAspectRatio: CGFloat {
        if let loadedAspectRatio, loadedAspectRatio.isFinite, loadedAspectRatio > 0 {
            return loadedAspectRatio
        }
        guard let ratio = item.resolvedAspectRatioValue, ratio.isFinite, ratio > 0 else {
            return aspectRatio
        }
        return ratio
    }

    private var usesBlurredFitLayout: Bool {
        guard prefersUnifiedCarouselFrame else { return false }
        return MomentCarouselLayoutRules.presentationMode(
            for: resolvedItemAspectRatio,
            canvasAspectRatio: aspectRatio
        ) == .fitWithBlur
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack { // ✅ CAMBIADO: ZStack para que el overlay esté ENCIMA
                // ✅ SKELETON: Reserva el espacio exacto del ratio con cristal
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                if item.isHiddenByModeration {
                    ModeratedMediaItemView(item: item)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                } else if item.type == .image {
                    if usesBlurredFitLayout {
                        CarouselMediaBackdropView(item: item)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    Group {
                        if usesBlurredFitLayout {
                            KFImage(URL(string: item.url))
                                .placeholder { Color.clear }
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(UIScreen.main.scale)
                                .cacheOriginalImage()
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            KFImage(URL(string: item.url))
                                .placeholder { Color.clear }
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(UIScreen.main.scale)
                                .cacheOriginalImage()
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle()) // ✅ Asegurar área de tap
                    .simultaneousGesture( // ✅ USAR simultaneousGesture para mayor fiabilidad en TabView
                        TapGesture().onEnded {
                            if let tags = item.tags, !tags.isEmpty {
                                withAnimation(.spring()) {
                                    showTags.toggle()
                                }
                            }
                        }
                    )
                } else {
                    // ✅ VIDEOS: Con crop inteligente para el feed
                    CroppedVideoPlayer(
                        item: item,
                        aspectRatio: aspectRatio,
                        prefersUnifiedCarouselFrame: prefersUnifiedCarouselFrame,
                        currentMoment: currentMoment,
                        onTap: {
                            if let tags = item.tags, !tags.isEmpty {
                                withAnimation(.spring()) {
                                    showTags.toggle()
                                }
                            } else {
                                openReelsViewer()
                            }
                        },
                        isImmersive: $isImmersive // ✅ NUEVO
                    )
                }
                
                // ✅ Overlay de etiquetas
                if !item.isHiddenByModeration, let tags = item.tags, !tags.isEmpty {
                    PhotoTagOverlayView(tags: tags, isVisible: showTags, onTagTap: onTagTap)
                        .zIndex(20)
                }
            }
        }
        .clipped()
        .opacity(isVisible ? 1.0 : 0.8)
        .scaleEffect(isVisible ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 0.4), value: isVisible)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
        }
        .fullScreenCover(isPresented: $showReelsViewer) {
            ReelsViewer(
                videos: allMoments.videoMoments,
                startIndex: findVideoIndex()
            )
        }
    }
    
    private func openReelsViewer() {
        showReelsViewer = true
    }
    
    private func findVideoIndex() -> Int {
        let videoMoments = allMoments.videoMoments
        return videoMoments.firstIndex { $0.moment.id == currentMoment.id } ?? 0
    }
}

private struct CarouselMediaBackdropView: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            backdropContent
                .blur(radius: 30)
                .saturation(0.9)
                .overlay(Color.black.opacity(0.18))

            LinearGradient(
                colors: [.black.opacity(0.18), .clear, .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdropContent: some View {
        if item.type == .image {
            KFImage(URL(string: item.url))
                .placeholder { Color.black.opacity(0.2) }
                .resizable()
                .scaledToFill()
        } else if let thumbnailUrl = item.thumbnailUrl, !thumbnailUrl.isEmpty {
            KFImage(URL(string: thumbnailUrl))
                .placeholder { Color.black.opacity(0.2) }
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
}

private struct ModeratedMediaItemView: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .center) {
            moderatedBackground

            LinearGradient(
                colors: [.black.opacity(0.52), .black.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))

                Text(NSLocalizedString("mediaModeration.hidden.title", comment: "Hidden content title"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)

                Text(NSLocalizedString("mediaModeration.hidden.subtitle", comment: "Hidden content subtitle"))
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.78))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var moderatedBackground: some View {
        if item.type == .image {
            KFImage(URL(string: item.url))
                .placeholder { Color.black.opacity(0.28) }
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .saturation(0)
                .overlay(Color.black.opacity(0.18))
                .clipped()
        } else if let thumbnailUrl = item.thumbnailUrl, !thumbnailUrl.isEmpty {
            KFImage(URL(string: thumbnailUrl))
                .placeholder { Color.black.opacity(0.28) }
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .saturation(0)
                .overlay(Color.black.opacity(0.18))
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.4))
        }
    }
}

struct CroppedVideoPlayer: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let prefersUnifiedCarouselFrame: Bool
    let currentMoment: Moment
    let onTap: () -> Void
    @Binding var isImmersive: Bool // ✅ NUEVO
    
    @StateObject private var globalManager = GlobalVideoManager.shared
    @State private var isVisible = false
    @State private var isMuted = true // ✅ Estado para el botón de mute

    private var resolvedItemAspectRatio: CGFloat {
        guard let ratio = item.resolvedAspectRatioValue, ratio.isFinite, ratio > 0 else {
            return aspectRatio
        }
        return ratio
    }

    private var usesBlurredFitLayout: Bool {
        guard prefersUnifiedCarouselFrame else { return false }
        return MomentCarouselLayoutRules.presentationMode(
            for: resolvedItemAspectRatio,
            canvasAspectRatio: aspectRatio
        ) == .fitWithBlur
    }
    
    var body: some View {
        ZStack {
            if usesBlurredFitLayout {
                CarouselMediaBackdropView(item: item)

                ModernVideoPlayer(
                    url: item.url,
                    aspectRatio: resolvedItemAspectRatio,
                    videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                    hideMuteButton: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)

                VStack {
                    HStack {
                        Spacer()

                        if let duration = item.videoDuration ?? currentMoment.videoDuration {
                            Text(formatDuration(duration))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "0B1215").opacity(0.6))
                                .cornerRadius(6)
                                .padding(.trailing, 8)
                                .padding(.top, 8)
                        }
                    }

                    Spacer()
                }
                .opacity(isImmersive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isImmersive)
            } else if isReelsFormat {
                // ✅ REELS: Mostrar con mejor diseño nativo
                ZStack {
                    // Thumbnail del video si está disponible
                    if let thumbnailUrl = item.thumbnailUrl, !thumbnailUrl.isEmpty {
                        KFImage(URL(string: thumbnailUrl))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        // Video player como fallback
                        ModernVideoPlayer(
                            url: item.url,
                            aspectRatio: aspectRatio, // ✅ Mostrar ratio completo para reels
                            videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                            hideMuteButton: true // ✅ Ocultar botón de mute del player (usamos el nuestro arriba)
                        )
                        .onAppear {
                            // ✅ Actualizar estado de mute cuando aparece el player
                            let videoId = currentMoment.id ?? "video_\(UUID().uuidString)"
                            isMuted = globalManager.isMuted(videoId)
                        }
                        .onChange(of: globalManager.userHasEnabledSoundInSession) { hasSound in
                            // ✅ ESTILO INSTAGRAM: Actualizar estado cuando el usuario activa el sonido en la sesión
                            let videoId = currentMoment.id ?? "video_\(UUID().uuidString)"
                            isMuted = !hasSound || globalManager.isMuted(videoId)
                        }
                    }
                    
                    // ✅ OVERLAY con gradiente sutil nativo
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "0B1215").opacity(0.0),
                            Color(hex: "0B1215").opacity(0.3)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // ✅ OVERLAY invisible para capturar taps (en el fondo, zIndex bajo)
                    Button(action: {
                        onTap()
                    }) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .zIndex(1) // ✅ Overlay en el fondo
                    
                    // ✅ INDICADORES mejorados nativos (por encima del overlay)
                    VStack {
                        HStack {
                            // ✅ Badge "Reels" nativo (esquina superior izquierda)
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(NSLocalizedString("feed.reels.badge", comment: "Reels badge"))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.purple.opacity(0.8),
                                                Color.pink.opacity(0.8)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .padding(.leading, 12)
                            .padding(.top, 12)
                            
                            // ✅ Botón de mute (junto al badge) - por encima del overlay
                            Button(action: {
                                let videoId = currentMoment.id ?? "video_\(UUID().uuidString)"
                                globalManager.toggleMute(videoId)
                                isMuted = globalManager.isMuted(videoId)
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .padding(.leading, 8)
                            .padding(.top, 12)
                            
                            Spacer()
                            
                            // Duración del video (esquina superior derecha)
                            if let duration = item.videoDuration ?? currentMoment.videoDuration {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "0B1215").opacity(0.6))
                                    .cornerRadius(6)
                                    .padding(.trailing, 12)
                                    .padding(.top, 12)
                            }
                        }
                        
                        Spacer()
                        
                        // ✅ Indicador de expansión mejorado (centro abajo)
                        HStack {
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("feed.reels.tapToView", comment: "Tap to view reels"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "0B1215").opacity(0.5))
                            )
                            
                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                    .zIndex(100) // ✅ Asegurar que todos los controles estén por encima del overlay
                    .opacity(isImmersive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isImmersive)
                }
            } else {
                // ✅ VIDEOS HORIZONTALES: Mantener diseño actual
                ZStack {
                    ModernVideoPlayer(
                        url: item.url,
                        aspectRatio: feedDisplayRatio,
                        videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                        hideMuteButton: false // ✅ Mostrar botón de mute para videos horizontales
                    )
                    
                    // ✅ INDICADORES sutiles para videos horizontales
                    VStack {
                        HStack {
                            Spacer()
                            
                            if let duration = item.videoDuration ?? currentMoment.videoDuration {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "0B1215").opacity(0.6))
                                    .cornerRadius(6)
                                    .padding(.trailing, 8)
                                    .padding(.top, 8)
                            }
                        }
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(6)
                                .background(Color(hex: "0B1215").opacity(0.4))
                                .cornerRadius(6)
                                .padding(.trailing, 8)
                                .padding(.bottom, 8)
                        }
                    }
                    .opacity(isImmersive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isImmersive)
                }
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
    
    // ✅ MEJORADO: Detectar si es formato reels (9:16)
    private var isReelsFormat: Bool {
        aspectRatio < 0.7 || currentMoment.aspectRatio == "9:16"
    }
    
    // ✅ LÓGICA DE CROP: Solo para videos horizontales
    private var feedDisplayRatio: CGFloat {
        if aspectRatio < 0.7 { // Es video vertical (reels 9:16)
            return aspectRatio // ✅ Mostrar ratio completo para reels (no crop)
        }
        return aspectRatio // Otros formatos mantienen su ratio
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// Progress Circle (mantener igual que antes)
struct StoryProgressCircle: View {
    let progress: Double
    let isUploading: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: isUploading ?
                        [Color.blue, Color.purple] :
                        [Color.orange, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
    }
}

// ✅ SOLUCIONADO: Vista expandible con detección precisa de hashtags
struct ExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    
    private let maxLines = 2
    private let maxCharacters = 15
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ✅ MEJORADO: Usar AttributedText personalizado con tap gestures específicos
            if isExpanded {
                HashtagText(
                    content: content,
                    colorScheme: colorScheme,
                    onHashtagTap: onHashtagTap
                )
            } else {
                HashtagText(
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
                    HStack(spacing: 4) {
                        Text(isExpanded ? "feed.seeLess" : "feed.seeMore")
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(.white)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                }
                .scaleEffect(isExpanded ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isExpanded)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

struct HashtagText: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        // ✅ SOLUCIÓN FINAL: Usar Text con enlaces tappables
        Text(buildAttributedString())
            .font(.custom("Poppins-Regular", size: 14))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
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
        
        // Color base blanco para el degradado oscuro
        attributed.foregroundColor = .white
        
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

extension Range where Bound == String.Index {
    func toAttributedStringRange(in attributedString: AttributedString) -> Range<AttributedString.Index>? {
        guard let lowerBound = AttributedString.Index(self.lowerBound, within: attributedString),
              let upperBound = AttributedString.Index(self.upperBound, within: attributedString) else {
            return nil
        }
        return lowerBound..<upperBound
    }
}
// MARK: - FeedViewModel CORREGIDO - Versión que funciona

@MainActor
class FeedViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var userProfileImage: String?
    @Published var connections: [Connection] = []
    @Published var admirers: [Admirer] = []
    
    // Propiedades para el selector de feed
    @Published var currentFeedType: FeedType = .following
    @Published var forYouMoments: [Moment] = []
    @Published var followingMoments: [Moment] = []
    @Published var isPausedForUploads = false
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    private var lastDocument: DocumentSnapshot?
    private var userListener: ListenerRegistration?
    private var momentListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var pendingUpdates: [String: DispatchWorkItem] = [:]
    private let updateDebounceTime: TimeInterval = 0.3
    private var lastUpdateHashes: [String: Int] = [:]
    private var mutedUserIdsCache: Set<String> = []
    private var mutedUserIdsCacheTimestamp: Date = .distantPast
    private let mutedUserIdsCacheTTL: TimeInterval = 20
    
    // 🚀 Backend feed pagination state (per feed type)
    private var backendCursors: [FeedType: FeedCursor?] = [:]
    private var feedLoadedFromBackend: [FeedType: Bool] = [.following: false, .forYou: false]
    private var backendReachedEnd: [FeedType: Bool] = [.following: false, .forYou: false]
    
    // ✅ NUEVO: Queue para sincronización segura de arrays
    private let momentsQueue = DispatchQueue(label: "moments.sync", attributes: .concurrent)
    private let listenersQueue = DispatchQueue(label: "listeners.sync", attributes: .concurrent)

    deinit {
        performCleanup() // Usar la nueva función de cleanup
    }

    @MainActor
    func refreshMoments(userId: String) async {
        lastDocument = nil
        backendCursors.removeAll()
        feedLoadedFromBackend = [.following: false, .forYou: false]
        backendReachedEnd = [.following: false, .forYou: false]
        mutedUserIdsCache.removeAll()
        mutedUserIdsCacheTimestamp = .distantPast
        clearListeners()
        
        // ✅ OFFLINE: Al refrescar, mantenemos lo que hay hasta que llegue lo nuevo
        // No borramos las listas inmediatamente para evitar parpadeos
        
        fetchMoments(userId: userId, feedType: currentFeedType)
        
        // ✅ Esperar a que se complete la operación inicial
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
    }
    
    // MARK: - Caching Logic (Offline Support)
    
    private func getCacheKey(for type: FeedType) -> String {
        return "cached_feed_\(type == .following ? "following" : "foryou")"
    }
    
    private func saveFeedToCache(moments: [Moment], type: FeedType, sync: Bool = false) {
        // ✅ SwiftData: Guardar en DB local para experiencia offline
        Task { @MainActor in
            LocalPersistenceService.shared.saveFeedMoments(moments, sync: sync)
        }
    }
    
    private func loadFeedFromCache(type: FeedType) -> [Moment] {
        // ✅ SwiftData: Leer desde DB local (instantáneo)
        return LocalPersistenceService.shared.loadFeedMoments()
    }

    private func resolveMutedUserIds(viewerId: String, forceRefresh: Bool = false, completion: @escaping (Set<String>) -> Void) {
        guard !viewerId.isEmpty else {
            completion([])
            return
        }

        let cacheAge = Date().timeIntervalSince(mutedUserIdsCacheTimestamp)
        if !forceRefresh, cacheAge < mutedUserIdsCacheTTL {
            completion(mutedUserIdsCache)
            return
        }

        firestoreService.fetchMutedUserIds(userId: viewerId) { [weak self] mutedIds in
            Task { @MainActor in
                self?.mutedUserIdsCache = mutedIds
                self?.mutedUserIdsCacheTimestamp = Date()
                completion(mutedIds)
            }
        }
    }

    private func resolveMutedUserIdsAsync(viewerId: String, forceRefresh: Bool = false) async -> Set<String> {
        await withCheckedContinuation { continuation in
            resolveMutedUserIds(viewerId: viewerId, forceRefresh: forceRefresh) { mutedIds in
                continuation.resume(returning: mutedIds)
            }
        }
    }

    // MARK: - Main Functions
    
    func fetchMoments(userId: String, feedType: FeedType? = nil) {
        let targetFeedType = feedType ?? currentFeedType
        
        // ✅ Actualizar en main thread
        DispatchQueue.main.async {
            self.currentFeedType = targetFeedType
            self.isLoading = true
            self.errorMessage = nil
        }

        resolveMutedUserIds(viewerId: userId) { [weak self] mutedUserIds in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // ✅ OFFLINE: Cargar caché inmediatamente, respetando cuentas silenciadas.
                let cached = self.loadFeedFromCache(type: targetFeedType)
                let visibleCached = cached.filter { !mutedUserIds.contains($0.authorId) }
                if !visibleCached.isEmpty && self.moments.isEmpty {
                    self.moments = visibleCached

                    if targetFeedType == .following {
                        self.followingMoments = visibleCached
                    } else {
                        self.forYouMoments = visibleCached
                    }

                    let videoUrls = visibleCached.compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                    VideoPreloader.shared.preloadAssets(urls: videoUrls)
                }
            }
        }
        
        // Limpiar listeners anteriores
        clearListeners()
        
        switch targetFeedType {
        case .following:
            fetchFollowingMoments(userId: userId)
        case .forYou:
            fetchForYouMoments(userId: userId)
        }
    }
    

    
    func loadMoreMoments(userId: String) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        let feed = currentFeedType
        
        // 🚀 If initial load was from backend, keep using backend for pagination
        if feedLoadedFromBackend[feed] == true {
            // End of feed reached — nothing more to load
            if backendReachedEnd[feed] == true {
                isLoadingMore = false
                LogConfig.log("🚀 LoadMore: backend end-of-feed for \(feed)", category: "Feed")
                return
            }
            
            guard let cursor = backendCursors[feed] ?? nil else {
                // No cursor but not marked as end — treat as end
                backendReachedEnd[feed] = true
                isLoadingMore = false
                return
            }
            
            Task {
                let feedTypeStr = feed == .forYou ? "forYou" : "following"
                let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
                if let result = await BackendFeedService.shared.fetchFeedPage(
                    feedType: feedTypeStr,
                    cursor: cursor,
                    limit: 20
                ) {
                    let newMoments = result.moments
                        .filter { $0.isArchived != true }
                        .filter { !mutedUserIds.contains($0.authorId) }
                        .sorted { $0.timestamp > $1.timestamp }
                    let existingIds = Set(self.moments.map { $0.id })
                    let uniqueNew = newMoments.filter { !existingIds.contains($0.id) }
                    
                    await MainActor.run {
                        if let nextCursor = result.nextCursor {
                            self.backendCursors[feed] = nextCursor
                        } else {
                            self.backendCursors[feed] = nil
                            self.backendReachedEnd[feed] = true
                        }
                        
                        self.moments.append(contentsOf: uniqueNew)
                        
                        if feed == .following {
                            self.followingMoments.append(contentsOf: uniqueNew)
                        } else {
                            self.forYouMoments.append(contentsOf: uniqueNew)
                        }
                        
                        self.isLoadingMore = false
                        self.saveFeedToCache(moments: self.moments, type: feed, sync: false)
                        
                        let videoUrls = uniqueNew.compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                        VideoPreloader.shared.preloadAssets(urls: videoUrls)
                    }
                    LogConfig.log("🚀 LoadMore from BACKEND (+\(uniqueNew.count) moments)", category: "Feed")
                    return
                }
                
                // Backend loadMore failed — fall through to legacy
                LogConfig.log("🔄 LoadMore: backend failed, falling back to legacy", category: "Feed")
                await MainActor.run {
                    self.feedLoadedFromBackend[feed] = false
                    self.loadMoreMomentsLegacy(userId: userId)
                }
            }
            return
        }
        
        // Legacy loadMore
        loadMoreMomentsLegacy(userId: userId)
    }
    
    private func loadMoreMomentsLegacy(userId: String) {
        if currentFeedType == .following {
            firestoreService.fetchFollowing(userId: userId) { [weak self] result in
                switch result {
                case .success(let followingUsers):
                    let targetUserIds = followingUsers.map { $0.id }
                    
                    if targetUserIds.isEmpty {
                        DispatchQueue.main.async {
                            self?.isLoadingMore = false
                        }
                        return
                    }
                    
                    self?.fetchMoreMomentsFromUsers(userIds: targetUserIds, userId: userId, feedType: .following)
                case .failure(_):
                    DispatchQueue.main.async {
                        self?.isLoadingMore = false
                        self?.errorMessage = NSLocalizedString("feed.loading.moreContent", comment: "Error loading more content")
                    }
                }
            }
        } else if currentFeedType == .forYou {
            fetchMoreForYouMoments(userId: userId)
        }
    }
    
    func switchFeedType(to feedType: FeedType, userId: String) {
        currentFeedType = feedType
        clearListeners()
        
        switch feedType {
        case .following:
            if !followingMoments.isEmpty {
                moments = followingMoments
                setupListenersForMoments(followingMoments)
            } else {
                fetchMoments(userId: userId, feedType: feedType)
            }
        case .forYou:
            if !forYouMoments.isEmpty {
                moments = forYouMoments
                setupListenersForMoments(forYouMoments)
            } else {
                fetchMoments(userId: userId, feedType: feedType)
            }
        }
    }

    // MARK: - Private Functions
    
    private func fetchFollowingMoments(userId: String) {
        // 🚀 Backend-first: try Cloud Function, fallback to legacy
        Task {
            let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
            if let result = await BackendFeedService.shared.fetchFeedPage(feedType: "following", limit: 40) {
                // ✅ Backend success — moments already privacy-filtered server-side
                let moments = result.moments
                    .filter { $0.isArchived != true }
                    .filter { !mutedUserIds.contains($0.authorId) }
                    .sorted { $0.timestamp > $1.timestamp }
                
                // Apply affinity sorting (same as legacy)
                let finalMoments = self.applyAffinitySorting(moments: moments, feedType: .following)
                
                await MainActor.run {
                    self.isLoading = false
                    self.followingMoments = finalMoments
                    self.moments = finalMoments
                    self.feedLoadedFromBackend[.following] = true
                    if let nextCursor = result.nextCursor {
                        self.backendCursors[.following] = nextCursor
                        self.backendReachedEnd[.following] = false
                    } else {
                        self.backendCursors[.following] = nil
                        self.backendReachedEnd[.following] = true
                    }
                    self.saveFeedToCache(moments: finalMoments, type: .following, sync: true)
                    
                    let videoUrls = finalMoments.compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                    VideoPreloader.shared.preloadAssets(urls: videoUrls)
                }
                LogConfig.log("🚀 Feed loaded from BACKEND (\(finalMoments.count) moments)", category: "Feed")
                return
            }
            
            // ❌ Backend failed or circuit open — use legacy
            LogConfig.log("🔄 Feed: fallback to LEGACY", category: "Feed")
            await MainActor.run {
                self.feedLoadedFromBackend[.following] = false
                self.backendCursors[.following] = nil
                self.backendReachedEnd[.following] = false
            }
            self.fetchFollowingMomentsLegacy(userId: userId)
        }
    }
    
    /// Legacy feed: fetch from Firestore + client-side privacy filter
    private func fetchFollowingMomentsLegacy(userId: String) {
        firestoreService.fetchFollowing(userId: userId) { [weak self] result in
            switch result {
            case .success(let followingUsers):
                let targetUserIds = followingUsers.map { $0.id }
                
                if targetUserIds.isEmpty {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.followingMoments = []
                        self?.moments = []
                    }
                } else {
                    self?.fetchMomentsFromUsers(userIds: targetUserIds, userId: userId, feedType: .following)
                }
                
            case .failure(_):
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.followingMoments = []
                    self?.moments = []
                    self?.errorMessage = NSLocalizedString("feed.loading.content", comment: "Error loading content")
                }
            }
        }
    }


    private func fetchForYouMoments(userId: String) {
        // 🚀 Backend-first: try Cloud Function, fallback to legacy
        Task {
            let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
            if let result = await BackendFeedService.shared.fetchFeedPage(feedType: "forYou", limit: 60) {
                let moments = result.moments
                    .filter { $0.isArchived != true }
                    .filter { !mutedUserIds.contains($0.authorId) }
                    .sorted { $0.timestamp > $1.timestamp }
                let finalMoments = self.applyAffinitySorting(moments: moments, feedType: .forYou)
                
                await MainActor.run {
                    self.isLoading = false
                    self.forYouMoments = finalMoments
                    self.moments = finalMoments
                    self.feedLoadedFromBackend[.forYou] = true
                    if let nextCursor = result.nextCursor {
                        self.backendCursors[.forYou] = nextCursor
                        self.backendReachedEnd[.forYou] = false
                    } else {
                        self.backendCursors[.forYou] = nil
                        self.backendReachedEnd[.forYou] = true
                    }
                    self.saveFeedToCache(moments: finalMoments, type: .forYou, sync: true)
                    
                    let videoUrls = finalMoments.compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                    VideoPreloader.shared.preloadAssets(urls: videoUrls)
                }
                LogConfig.log("🚀 ForYou feed loaded from BACKEND (\(finalMoments.count) moments)", category: "Feed")
                return
            }
            
            LogConfig.log("🔄 ForYou feed: fallback to LEGACY", category: "Feed")
            await MainActor.run {
                self.feedLoadedFromBackend[.forYou] = false
                self.backendCursors[.forYou] = nil
                self.backendReachedEnd[.forYou] = false
            }
            self.fetchForYouMomentsLegacy(userId: userId)
        }
    }
    
    /// Legacy forYou: fetch from multiple sources + client-side privacy filter
    private func fetchForYouMomentsLegacy(userId: String) {
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let user):
                let interests = user.interests
                let group = DispatchGroup()
                var allUserIds: Set<String> = []
                
                // Incluir tus propios momentos
                allUserIds.insert(userId)
                
                // Usuarios que sigues
                group.enter()
                self?.firestoreService.fetchFollowing(userId: userId) { result in
                    if case .success(let followingUsers) = result {
                        let someFollowing = Set(followingUsers.prefix(10).map { $0.id })
                        allUserIds.formUnion(someFollowing)
                    }
                    group.leave()
                }
                
                // Usuarios con intereses similares
                group.enter()
                self?.firestoreService.fetchUsersWithSharedInterests(
                    interests: interests,
                    excludingUserId: userId
                ) { result in
                    if case .success(let users) = result {
                        let userIds = Set(users.prefix(15).map { $0.id })
                        allUserIds.formUnion(userIds)
                    }
                    group.leave()
                }
                
                // Usuarios sugeridos
                group.enter()
                self?.firestoreService.fetchSuggestedUsers { result in
                    if case .success(let suggestedUsers) = result {
                        let suggestedIds = Set(suggestedUsers.prefix(20).map { $0.id })
                        allUserIds.formUnion(suggestedIds)
                    }
                    group.leave()
                }
                
                // Usuarios populares
                group.enter()
                self?.fetchPopularUsers(excludingUserId: userId) { popularUsers in
                    let popularIds = Set(popularUsers.prefix(25).map { $0.id })
                    allUserIds.formUnion(popularIds)
                    group.leave()
                }
                
                // Usuarios aleatorios
                group.enter()
                self?.fetchRandomUsers(excludingUserId: userId) { randomUsers in
                    let randomIds = Set(randomUsers.prefix(15).map { $0.id })
                    allUserIds.formUnion(randomIds)
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    let finalUserIds = Array(allUserIds)
                    
                    if finalUserIds.isEmpty {
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            self?.forYouMoments = []
                            self?.moments = []
                        }
                        return
                    }
                    
                    self?.fetchMomentsFromUsers(userIds: finalUserIds, userId: userId, feedType: .forYou)
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Apply affinity-based sorting: bestFriends + mutuals boost + SwiftData scores + randomness
    private func applyAffinitySorting(moments: [Moment], feedType: FeedType) -> [Moment] {
        let affinityManager = AffinityTracker.shared
        
        guard let container = affinityManager.modelContainer else {
            // Fallback: chronological + shuffled for forYou
            return feedType == .forYou
                ? Array(moments.shuffled().prefix(60))
                : Array(moments.prefix(40))
        }
        
        let context = SwiftData.ModelContext(container)
        let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
        let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
        let affinityScores = affinityManager.getScores(for: moments.map { $0.authorId }, in: context)
        
        let scoredMoments = moments.map { moment -> (moment: Moment, score: Double) in
            let baseScore = moment.timestamp.timeIntervalSince1970
            var additionalScore = 0.0
            
            let affinityScore = affinityScores[moment.authorId] ?? 0.0
            additionalScore += (affinityScore * 1000)
            additionalScore += Double.random(in: 0...5000)
            
            if bestFriends.contains(moment.authorId) {
                additionalScore += 50000
            } else if mutuals.contains(moment.authorId) {
                additionalScore += 20000
            }
            
            return (moment: moment, score: baseScore + additionalScore)
        }
        
        let sorted = scoredMoments.sorted { $0.score > $1.score }.map { $0.moment }
        return feedType == .forYou ? Array(sorted.prefix(60)) : Array(sorted.prefix(40))
    }
    
    private func fetchMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let limitPerUser = feedType == .forYou ? 8 : 12
        let totalLimit = feedType == .forYou ? 120 : 80

        firestoreService.fetchMomentsFromUsers(
            userIds: userIds,
            perUserLimit: limitPerUser,
            totalLimit: totalLimit
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fetchedMoments):
                let sortedMoments = fetchedMoments.sorted { $0.timestamp > $1.timestamp }
            
            // ✅ EXPERIMENTAL AFFINITY SORTING
            let affinityManager = AffinityTracker.shared
            var finalMoments: [Moment]
            
            // Try to get the model container so we can query local scores
            if let container = affinityManager.modelContainer {
                let context = SwiftData.ModelContext(container)
                let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
                let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
                let affinityScores = affinityManager.getScores(for: sortedMoments.map { $0.authorId }, in: context)
                
                let scoredMoments = sortedMoments.map { moment -> (moment: Moment, score: Double) in
                    let baseScore = moment.timestamp.timeIntervalSince1970
                    var additionalScore = 0.0
                    
                    let affinityScore = affinityScores[moment.authorId] ?? 0.0
                    // Add a scaled version of the affinity score
                    additionalScore += (affinityScore * 1000)
                    
                    // Mezcla para que no sea siempre el mismo feed
                    let randomFactor = Double.random(in: 0...5000) 
                    additionalScore += randomFactor
                    
                    if bestFriends.contains(moment.authorId) {
                        additionalScore += 50000 // Big boost for best friends
                    } else if mutuals.contains(moment.authorId) {
                        additionalScore += 20000 // Boost for mutuals
                    }
                    
                    return (moment: moment, score: baseScore + additionalScore)
                }
                // Sort by the new mixed score
                let finalSortedMoments = scoredMoments.sorted { $0.score > $1.score }.map { $0.moment }
                
                finalMoments = feedType == .forYou ?
                    Array(finalSortedMoments.prefix(60)) :
                    Array(finalSortedMoments.prefix(40))
            } else {
                // Fallback to chronological + randomized if SwiftData is not available
                finalMoments = feedType == .forYou ?
                    Array(sortedMoments.shuffled().prefix(60)) :
                    Array(sortedMoments.prefix(40))
            }
            // Aplicar filtros de privacidad y actualizar UI
                self.filterMomentsForPrivacy(viewerId: userId, moments: finalMoments) { filteredMoments in
                DispatchQueue.main.async {
                        self.isLoading = false
                    
                    switch feedType {
                    case .following:
                            self.followingMoments = filteredMoments
                    case .forYou:
                            self.forYouMoments = filteredMoments
                    }
                    
                        self.moments = filteredMoments
                    
                    // ✅ OFFLINE: Guardar en caché para la próxima vez
                    // Como es el fetch inicial, usamos sync: true para limpiar momentos borrados
                        self.saveFeedToCache(moments: filteredMoments, type: feedType, sync: true)
                    
                    // ✅ INSTANT PLAYBACK: Preload videos
                    let videoUrls = filteredMoments
                        .compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                    VideoPreloader.shared.preloadAssets(urls: videoUrls)
                }
            }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func fetchMoreMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let limitPerUser = feedType == .forYou ? 8 : 12
        let totalLimit = feedType == .forYou ? 120 : 80
        let existingMomentIds = Set(moments.compactMap { $0.id })

        firestoreService.fetchMomentsFromUsers(
            userIds: userIds,
            perUserLimit: limitPerUser,
            totalLimit: totalLimit
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fetchedMoments):
                let filteredNewMoments = fetchedMoments.filter { moment in
                    guard let momentId = moment.id else { return false }
                    return !existingMomentIds.contains(momentId)
                }
                let sortedNewMoments = filteredNewMoments.sorted { $0.timestamp > $1.timestamp }
            
            // ✅ EXPERIMENTAL AFFINITY SORTING - load more
            let affinityManager = AffinityTracker.shared
            var finalSortedNewMoments: [Moment]
            
            if let container = affinityManager.modelContainer {
                let context = SwiftData.ModelContext(container)
                let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
                let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
                let affinityScores = affinityManager.getScores(for: sortedNewMoments.map { $0.authorId }, in: context)
                
                let scoredMoments = sortedNewMoments.map { moment -> (moment: Moment, score: Double) in
                    let baseScore = moment.timestamp.timeIntervalSince1970
                    var additionalScore = 0.0
                    
                    let affinityScore = affinityScores[moment.authorId] ?? 0.0
                    additionalScore += (affinityScore * 1000)
                    
                    // Mezcla para contenido de scrolling infinito
                    let randomFactor = Double.random(in: 0...5000) 
                    additionalScore += randomFactor
                    
                    if bestFriends.contains(moment.authorId) {
                        additionalScore += 50000
                    } else if mutuals.contains(moment.authorId) {
                        additionalScore += 20000
                    }
                    
                    return (moment: moment, score: baseScore + additionalScore)
                }
                
                finalSortedNewMoments = scoredMoments.sorted { $0.score > $1.score }.map { $0.moment }
            } else {
                // Fallback
                finalSortedNewMoments = sortedNewMoments.shuffled()
            }
                self.filterMomentsForPrivacy(viewerId: userId, moments: finalSortedNewMoments) { filteredMoments in
                DispatchQueue.main.async {
                        self.isLoadingMore = false
                    
                    if feedType == .forYou {
                            self.forYouMoments.append(contentsOf: filteredMoments)
                            self.moments.append(contentsOf: filteredMoments)
                    } else {
                            self.followingMoments.append(contentsOf: filteredMoments)
                            self.moments.append(contentsOf: filteredMoments)
                    }
                    
                    // ✅ INSTANT PLAYBACK: Preload videos
                    let videoUrls = filteredMoments
                        .compactMap { $0.mediaItems?.first(where: { $0.type == .video })?.url }
                    VideoPreloader.shared.preloadAssets(urls: videoUrls)
                }
            }
            case .failure:
                DispatchQueue.main.async {
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    private func fetchMoreForYouMoments(userId: String) {
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let user):
                let interests = user.interests
                let group = DispatchGroup()
                var allUserIds: Set<String> = []
                allUserIds.insert(userId)
                
                group.enter()
                self?.firestoreService.fetchUsersWithSharedInterests(
                    interests: interests,
                    excludingUserId: userId
                ) { result in
                    if case .success(let users) = result {
                        let userIds = Set(users.prefix(10).map { $0.id })
                        allUserIds.formUnion(userIds)
                    }
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    let finalUserIds = Array(allUserIds)
                    self?.fetchMoreMomentsFromUsers(userIds: finalUserIds, userId: userId, feedType: .forYou)
                }
                
            case .failure(_):
                DispatchQueue.main.async {
                    self?.isLoadingMore = false
                }
            }
        }
    }
    
    private func fetchRandomUsers(excludingUserId: String, completion: @escaping ([AppUser]) -> Void) {
        firestoreService.db.collection("users")
            .whereField("isActive", isEqualTo: true)
            .limit(to: 30)
            .getDocuments { snapshot, error in
                guard error == nil, let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != excludingUserId ? user : nil
                    } catch {
                        return nil
                    }
                }
                
                completion(users.shuffled())
            }
    }
    
    private func fetchPopularUsers(excludingUserId: String, completion: @escaping ([AppUser]) -> Void) {
        firestoreService.db.collection("users")
            .limit(to: 15)
            .getDocuments { snapshot, error in
                guard error == nil, let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != excludingUserId ? user : nil
                    } catch {
                        return nil
                    }
                }
                
                completion(users)
            }
    }
    
    // MARK: - Privacy Filter
    
    private func filterMomentsForPrivacy(viewerId: String, moments: [Moment], completion: @escaping ([Moment]) -> Void) {
         guard !viewerId.isEmpty, !moments.isEmpty else {
             completion([])
             return
         }
         
         let batchSize = 10
         var filteredMoments: [Moment] = []
         let cacheLock = NSLock()
         var decisionCache: [String: Bool] = [:]
         var inFlightDecisions: [String: [(Bool) -> Void]] = [:]

         func evaluateMomentAccess(_ moment: Moment, completion: @escaping (Bool) -> Void) {
             // Fast paths: no need to hit Firestore for these.
             if moment.authorId == viewerId {
                 completion(true)
                 return
             }

             if moment.taggedUsers?.contains(viewerId) == true {
                 completion(true)
                 return
             }

             let cacheKey = privacyDecisionCacheKey(for: moment, viewerId: viewerId)
             var shouldStartRequest = false

             cacheLock.lock()
             if let cached = decisionCache[cacheKey] {
                 cacheLock.unlock()
                 completion(cached)
                 return
             }

             if inFlightDecisions[cacheKey] != nil {
                 inFlightDecisions[cacheKey]?.append(completion)
                 cacheLock.unlock()
                 return
             }

             inFlightDecisions[cacheKey] = [completion]
             shouldStartRequest = true
             cacheLock.unlock()

             guard shouldStartRequest else { return }

             let requestLock = NSLock()
             var didComplete = false

             func resolveRequest(_ canView: Bool) {
                 var callbacks: [(Bool) -> Void] = []

                 cacheLock.lock()
                 decisionCache[cacheKey] = canView
                 callbacks = inFlightDecisions[cacheKey] ?? []
                 inFlightDecisions[cacheKey] = nil
                 cacheLock.unlock()

                 callbacks.forEach { $0(canView) }
             }

             privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                 requestLock.lock()
                 if didComplete {
                     requestLock.unlock()
                     return
                 }
                 didComplete = true
                 requestLock.unlock()
                 resolveRequest(canView)
             }

             DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                 requestLock.lock()
                 if didComplete {
                     requestLock.unlock()
                     return
                 }
                 didComplete = true
                 requestLock.unlock()
                 resolveRequest(false) // Fail closed on timeout.
             }
         }
         
         func processBatch(startIndex: Int) {
             let endIndex = min(startIndex + batchSize, moments.count)
             let batch = Array(moments[startIndex..<endIndex])
             
             let group = DispatchGroup()
             var visibleMomentIds = Set<String>()
             let syncQueue = DispatchQueue(label: "batch.results.sync")
             
             for moment in batch {
                 guard let momentId = moment.id, !momentId.isEmpty else { continue }
                 
                 group.enter()

                 evaluateMomentAccess(moment) { canView in
                     if canView {
                         syncQueue.sync {
                             visibleMomentIds.insert(momentId)
                         }
                     }
                     group.leave()
                 }
             }
             
             group.notify(queue: .main) {
                 let orderedBatchResults = batch.filter { moment in
                     guard let id = moment.id else { return false }
                     return visibleMomentIds.contains(id)
                 }
                 filteredMoments.append(contentsOf: orderedBatchResults)
                 
                 if endIndex < moments.count {
                     processBatch(startIndex: endIndex)
                 } else {
                     completion(filteredMoments)
                 }
             }
         }
         
         processBatch(startIndex: 0)
     }

    private func privacyDecisionCacheKey(for moment: Moment, viewerId: String) -> String {
        let audience = moment.audience ?? "everyone"
        let base = "\(viewerId)|\(moment.authorId)|\(audience)"

        switch audience {
        case "custom":
            return "\(base)|moment:\(moment.id ?? "missing")"
        case "customList":
            if let customListId = moment.customListId, !customListId.isEmpty {
                return "\(base)|list:\(customListId)"
            }
            return "\(base)|moment:\(moment.id ?? "missing")"
        default:
            return base
        }
    }

    // MARK: - Listeners
    nonisolated private func clearListeners() {
        // ✅ MEJORADO: Limpieza thread-safe
        listenersQueue.async(flags: .barrier) {
            // Cancelar todos los updates pendientes
            self.pendingUpdates.values.forEach { $0.cancel() }
            self.pendingUpdates.removeAll()
            self.lastUpdateHashes.removeAll()
            
            // Remover listeners de forma segura
            self.momentListeners.values.forEach { $0.remove() }
            self.momentListeners.removeAll()
            self.commentListeners.values.forEach { $0.remove() }
            self.commentListeners.removeAll()
        }
    }
    
    private func setupListenersForMoments(_ moments: [Moment]) {
        // ✅ MEJORADO: Setup de listeners de forma segura
        DispatchQueue.global(qos: .userInitiated).async {
            for moment in moments {
                if let momentId = moment.id {
                    self.listenForCommentUpdates(momentId: momentId, authorId: moment.authorId)
                }
            }
        }
    }
    
    func listenForCommentUpdates(momentId: String, authorId: String) {
        // ✅ MEJORADO: Protección contra listeners duplicados
        listenersQueue.async(flags: .barrier) {
            if self.commentListeners[momentId] != nil || self.momentListeners[momentId] != nil {
                return
            }
        }

        // ✅ VALIDAR: Solo crear listener si el usuario puede ver el momento
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ DECLARAR commentListener en el scope correcto
        var commentListener: ListenerRegistration?
        
        firestoreService.canViewContent(currentUserId: currentUserId, targetUserId: authorId) { [weak self] result in
            switch result {
            case .success(let canView):
                guard canView else { return } // No crear listener si no puede ver el momento
                
                // ✅ Solo crear listener si tiene permisos
                commentListener = self?.firestoreService.db.collection("users").document(authorId)
                    .collection("moments").document(momentId)
                    .collection("comments")
                    .addSnapshotListener { snapshot, error in
                        guard error == nil else { return }
                        
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("CommentAdded"),
                                object: momentId
                            )
                        }
                    }
                
                // ✅ Guardar el listener solo si se creó correctamente
                if let listener = commentListener {
                    self?.listenersQueue.async(flags: .barrier) {
                        self?.commentListeners[momentId] = listener
                    }
                }
                
            case .failure(_):
                // Si falla la verificación de permisos, no crear listener
                return
            }
        }
        
        // 🔥 LISTENER ARREGLADO: Con debounce y comparación inteligente
        listenersQueue.async(flags: .barrier) {
            if self.momentListeners[momentId] == nil {
                let momentListener = self.firestoreService.db.collection("users").document(authorId)
                .collection("moments").document(momentId)
                .addSnapshotListener { [weak self] document, error in
                    guard let self = self,
                          let document = document,
                          document.exists,
                          error == nil else {
                        return
                    }
                    
                    // ✅ NUEVO: Pausa durante uploads para evitar conflictos
                    if self.isPausedForUploads {
                        return
                    }
                    
                    do {
                        // ✅ MEJORADO: Verificación segura de documentID
                        let documentID = document.documentID
                        guard !documentID.isEmpty else {
                            return
                        }
                        
                        var updatedMoment = try document.data(as: Moment.self)
                        updatedMoment.id = documentID

                        // Si se archiva en tiempo real, retirarlo inmediatamente del feed.
                        if updatedMoment.isArchived == true {
                            DispatchQueue.main.async {
                                self.moments.removeAll { $0.id == momentId }
                                self.followingMoments.removeAll { $0.id == momentId }
                                self.forYouMoments.removeAll { $0.id == momentId }
                                self.saveFeedToCache(moments: self.followingMoments, type: .following, sync: false)
                                self.saveFeedToCache(moments: self.forYouMoments, type: .forYou, sync: false)
                            }
                            return
                        }
                        
                        // ✅ NUEVO: Solo actualizar si hay cambios significativos
                        guard self.shouldUpdateMoment(momentId: momentId, newMoment: updatedMoment) else {
                            return
                        }
                        
                        // ✅ NUEVO: Debounce para agrupar múltiples updates
                        self.debouncedUpdateMoment(momentId: momentId, updatedMoment: updatedMoment)
                        
                    } catch {
                    }
                }
            
            self.momentListeners[momentId] = momentListener
        }
        }
    }
    
    private func shouldUpdateMoment(momentId: String, newMoment: Moment) -> Bool {
        // Buscar momento actual
        guard let currentIndex = moments.firstIndex(where: { $0.id == momentId }) else {
            return true // Es nuevo, siempre actualizar
        }
        
        let currentMoment = moments[currentIndex]
        
        // ✅ Generar hash de propiedades importantes para comparar
        let newHash = generateMomentHash(moment: newMoment)
        let currentHash = lastUpdateHashes[momentId] ?? 0
        
        // Solo actualizar si el hash cambió
        if newHash != currentHash {
            lastUpdateHashes[momentId] = newHash
            return true
        }
        
        return false
    }
    
    // ✅ NUEVA FUNCIÓN: Generar hash de propiedades importantes
    private func generateMomentHash(moment: Moment) -> Int {
        var hasher = Hasher()
        
        // ✅ Usar tu sistema de reactions en lugar de likes
        hasher.combine(moment.reactions.count) // Número total de reactions
        
        // ✅ Hash de cada tipo de reaction y su count
        for (reactionType, userIds) in moment.reactions.sorted(by: { $0.key < $1.key }) {
            hasher.combine(reactionType)
            hasher.combine(userIds.count) // Solo el count, no los IDs específicos
        }
        
        hasher.combine(moment.commentCount) // Tu campo commentCount
        hasher.combine(moment.content)
        hasher.combine(moment.timestamp.timeIntervalSince1970)
        
        // ✅ Incluir propiedades que podrían cambiar y afectar la UI
        hasher.combine(moment.imagePath)
        hasher.combine(moment.videoUrl)
        hasher.combine(moment.aspectRatio)
        
        // ✅ NO incluir: authorId, username, profileImagePath (no cambian)
        // ✅ NO incluir: taggedUsers, location, audience (no cambian después de crear)
        
        return hasher.finalize()
    }
    
    // ✅ MEJORADO: Update con debounce thread-safe
    private func debouncedUpdateMoment(momentId: String, updatedMoment: Moment) {
        listenersQueue.async(flags: .barrier) {
            // Cancelar update pendiente si existe
            self.pendingUpdates[momentId]?.cancel()
            
            // Crear nuevo update con delay
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.moments.firstIndex(where: { $0.id == momentId }) {
                        self.moments[index] = updatedMoment
                        
                        // Actualizar caché correspondiente sin trigger adicional
                        self.updateMomentInCache(momentId: momentId, updatedMoment: updatedMoment)
                    }
                    
                    // Limpiar trabajo completado de forma segura
                    self.listenersQueue.async(flags: .barrier) {
                        self.pendingUpdates.removeValue(forKey: momentId)
                    }
                }
            }
            
            self.pendingUpdates[momentId] = workItem
            
            // Ejecutar después del debounce time
            DispatchQueue.main.asyncAfter(deadline: .now() + self.updateDebounceTime, execute: workItem)
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Actualizar caché sin trigger re-renders adicionales
    private func updateMomentInCache(momentId: String, updatedMoment: Moment) {
        if currentFeedType == .following {
            if let cacheIndex = followingMoments.firstIndex(where: { $0.id == momentId }) {
                followingMoments[cacheIndex] = updatedMoment
            }
        } else {
            if let cacheIndex = forYouMoments.firstIndex(where: { $0.id == momentId }) {
                forYouMoments[cacheIndex] = updatedMoment
            }
        }
    }
    
    // ✅ MEJORADO: Pausar listeners durante uploads
    func pauseListenersForUpload() {
        isPausedForUploads = true
        
        // Auto-resume después de 10 segundos (safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.resumeListenersAfterUpload()
        }
    }
    
    // ✅ MEJORADO: Reanudar listeners después de upload
    func resumeListenersAfterUpload() {
        isPausedForUploads = false
    }
    
    // ✅ NUEVO: Función de cleanup mejorada para deinit
    nonisolated private func performCleanup() {
        listenersQueue.async(flags: .barrier) {
            // Cancelar todos los updates pendientes
            self.pendingUpdates.values.forEach { $0.cancel() }
            self.pendingUpdates.removeAll()
            self.lastUpdateHashes.removeAll()
            
            // Remover listeners
            self.momentListeners.values.forEach { $0.remove() }
            self.momentListeners.removeAll()
            self.commentListeners.values.forEach { $0.remove() }
            self.commentListeners.removeAll()
            
            // Remover user listener
            self.userListener?.remove()
            self.userListener = nil
        }
    }
    
    // MARK: - User Data
    
    func fetchUserData(userId: String) {
        userListener?.remove()
        userListener = firestoreService.db.collection("users").document(userId)
            .addSnapshotListener { document, error in
                guard let data = document?.data(), error == nil else { return }
                
                DispatchQueue.main.async {
                    self.userProfileImage = data["profileImagePath"] as? String
                }
            }
    }

    func fetchConnections(userId: String) {
        firestoreService.fetchConnections(userId: userId) { result in
            if case .success(let connections) = result {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // ✅ NUEVO: Remover listener específico (Lazy Loading)
    func removeCommentListener(momentId: String) {
        listenersQueue.async(flags: .barrier) {
            if let listener = self.commentListeners[momentId] {
                listener.remove()
                self.commentListeners.removeValue(forKey: momentId)
            }
        }
    }
        
    func fetchAdmirers(userId: String) {
        firestoreService.fetchAdmirers(userId: userId) { result in
            if case .success(let admirers) = result {
                DispatchQueue.main.async {
                    self.admirers = admirers
                }
            }
        }
    }
    
    // MARK: - Stories (if needed)
    
    func filterStoriesForVisibility(viewerId: String, stories: [Story], completion: @escaping ([Story]) -> Void) {
        let group = DispatchGroup()
        var filteredStories: [Story] = []
        let syncQueue = DispatchQueue(label: "story.filter.sync")
        
        for story in stories {
            group.enter()
            
            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canSee in
                if canSee {
                    syncQueue.async {
                        filteredStories.append(story)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let orderedFilteredStories = stories.filter { originalStory in
                filteredStories.contains { $0.id == originalStory.id }
            }
            completion(orderedFilteredStories)
        }
    }
}

struct MomentDetailFromNotificationView: View {
    let momentId: String
    let userId: String  // ✅ Ahora required
    @Binding var isPresented: Bool
    @State private var moment: Moment?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                LoadingMomentView()
            } else if let errorMessage = errorMessage {
                ErrorMomentView(message: errorMessage) {
                    isPresented = false
                }
            } else if let moment = moment {
                MomentDetailView(moment: moment)
            } else {
                ErrorMomentView(message: "Momento no encontrado") {
                    isPresented = false
                }
            }
        }
        .onAppear {
            loadMoment()
        }
    }
    
    private func loadMoment() {
        // ✅ USAR TU MÉTODO EXISTENTE
        FirestoreService().fetchMoment(momentId: momentId, userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loadedMoment):
                    moment = loadedMoment
                case .failure(let error):
                    errorMessage = "No se pudo cargar el momento"
                }
            }
        }
    }
}

struct LoadingMomentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
                    .scaleEffect(1.5)
                
                Text("feed.loadingMoment")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
            }
        }
    }
}

struct ErrorMomentView: View {
    let message: String
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                
                Text(message)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Button("Cerrar") {
                    onClose()
                }
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.red)
                .clipShape(Capsule())
            }
            .padding(40)
        }
    }
}



// MARK: - Extensions

extension FeedViewModel {
    func resetFeedPreferences() {
        UserDefaults.standard.removeObject(forKey: "selectedFeedType")
    }
    
    func trackFeedUsage() {
        let currentPreference = UserDefaults.standard.selectedFeedType
    }
}


extension Array {
    subscript(safe range: Range<Index>) -> ArraySlice<Element> {
        let start = Swift.max(range.lowerBound, startIndex)
        let end = Swift.min(range.upperBound, endIndex)
        return self[start..<end]
    }
}
