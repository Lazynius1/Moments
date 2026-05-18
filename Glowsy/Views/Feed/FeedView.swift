
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

private struct FeedProfileSheetRoute: Identifiable {
    let userId: String

    var id: String { userId }
}

private struct FeedEchoInvitationRoute: Identifiable {
    let echoId: String

    var id: String { echoId }
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
    @State private var selectedUserId: String = ""
    @State private var selectedProfileRoute: FeedProfileSheetRoute?
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
    @State private var isManualRefreshing = false
    
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
    @State private var pendingEchoInvitationRoute: FeedEchoInvitationRoute?
    @State private var pendingEchoesListener: ListenerRegistration?
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var feedHeaderHeight: CGFloat { 88 }
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
                    .allowsHitTesting(!networkMonitor.isConnected || networkMonitor.isSlowConnection)
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

            if let route = pendingEchoInvitationRoute {
                EchoInvitationView(
                    echoId: route.echoId,
                    onDismiss: {
                        pendingEchoInvitationRoute = nil
                        showPendingEchoInvitation = false
                        selectedPendingEchoId = ""
                    },
                    onAccept: { echoId in
                        NotificationNavigationService.shared.pendingNavigation = .echo(echoId)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2100)
            }
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
                        onSave: { payload in
                            updateMoment(moment: moment, payload: payload)
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
                openUserProfile(userId)
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
            .sheet(item: $selectedProfileRoute, onDismiss: {
                selectedUserId = ""
                selectedProfileRoute = nil
            }) {
                UserProfileView(userId: $0.userId)
                    .id($0.userId)
            }
            // 🌊 ECHOES: Sheet para invitación pendiente
            // 🌊 ECHOES: Sheet para historial
            .sheet(isPresented: $showEchoHistory) {
                EchoHistoryView()
                    .presentationDetents([.medium, .large])
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
    private func updateMoment(moment: Moment, payload: EditMomentPayload) {
        guard let momentId = moment.id else { return }
        
        firestoreService.updateMomentDetails(
            userId: moment.authorId,
            momentId: momentId,
            content: payload.content,
            audience: payload.audience.rawValue,
            customListId: payload.customListId,
            customViewers: payload.customViewers,
            taggedUsers: payload.taggedUsers,
            location: payload.locationName.isEmpty ? nil : payload.locationName,
            locationCoordinate: payload.locationCoordinate.map {
                Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            mediaItems: payload.mediaItems
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

            if isManualRefreshing {
                FeedRefreshIndicator(colorScheme: colorScheme)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
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

    private func openUserProfile(_ userId: String) {
        let trimmedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else { return }

        if trimmedUserId == Auth.auth().currentUser?.uid {
            selectedUserId = ""
            selectedProfileRoute = nil
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToOwnProfileTab"), object: nil)
            return
        }

        selectedUserId = trimmedUserId
        selectedProfileRoute = FeedProfileSheetRoute(userId: trimmedUserId)
    }

    private struct FeedRefreshIndicator: View {
        let colorScheme: ColorScheme

        var body: some View {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                    .scaleEffect(0.72)

                Text("feed.refreshing")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.74) : .black.opacity(0.62))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule(), interactive: false)
        }
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
                                    fallbackUsername: "",
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
                        .padding(.trailing, 4)
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
                                    pendingEchoInvitationRoute = FeedEchoInvitationRoute(echoId: echoId)
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
                                            openUserProfile(userId)
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
                                        if nextIndex < viewModel.moments.count {
                                            let endIndex = min(nextIndex + 5, viewModel.moments.count)
                                            let urlsToPrefetch = viewModel.moments[nextIndex..<endIndex].compactMap { moment -> URL? in
                                                guard let firstMedia = moment.mediaItems?.first?.url else { return nil }
                                                return URL(string: firstMedia)
                                            }
                                            if !urlsToPrefetch.isEmpty {
                                                ImagePrefetchManager.shared.prefetch(urls: urlsToPrefetch)
                                            }
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
                    await performManualRefresh(userId: userId)
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
                        await performManualRefresh(userId: userId)
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
        let fallbackUsername: String
        let hasStory: Bool
        let hasUnseenStory: Bool
        let storyCount: Int
        let storyViewedStatus: [Bool]
        let storyAudiences: [String?]
        let isOwnStory: Bool
        let colorScheme: ColorScheme
        let action: () -> Void
        
        var body: some View {
            VStack(spacing: 3) {
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
                .buttonStyle(.plain)

                LiveUsernameContent(userId: userId, fallbackUsername: fallbackUsername) { username in
                    Text(username)
                        .font(.custom("Poppins-Medium", size: 10))
                        .foregroundColor(Color.primary.opacity(0.76))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.75)
                        .frame(width: 64)
                }
            }
            .frame(width: 64)
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

        private var labelText: String {
            NSLocalizedString("stories.yourStory", comment: "Your story label")
        }
        
        var body: some View {
            VStack(spacing: 3) {
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
                .buttonStyle(.plain)

                Text(labelText)
                    .font(.custom("Poppins-Medium", size: 10))
                    .foregroundColor(Color.primary.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 64)
            }
            .frame(width: 64)
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
    private func loadStoryUsers(userId: String, allowInstantCache: Bool = true) async {
        await withCheckedContinuation { continuation in
            isLoadingStories = true

            if allowInstantCache {
                let cachedStoryUsers = self.loadCachedStoryUsers(userId: userId)
                if !cachedStoryUsers.isEmpty {
                    self.storyUsers = cachedStoryUsers
                    self.isLoadingStories = false
                }
            }

            guard NetworkMonitor.shared.isConnected else {
                self.isLoadingStories = false
                continuation.resume()
                return
            }
            
            firestoreService.fetchMutedUserIds(userId: userId) { mutedUserIds in
                firestoreService.fetchFollowing(userId: userId) { result in
                    switch result {
                    case .success(let followingUsers):
                        let followingIds = followingUsers.map { $0.id }.filter { !mutedUserIds.contains($0) }
                    var allUserIds = [userId] // Empezar contigo
                    allUserIds.append(contentsOf: followingIds)
                    
                    // ✅ NUEVO: Verificar cache primero
                    let cacheAge = Date().timeIntervalSince(self.cachedStoriesTimestamp)
                    if allowInstantCache && cacheAge < 20 && !self.cachedStories.isEmpty { // 20 segundos para evitar anillos desfasados

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

    private func loadCachedStoryUsers(userId: String) -> [StoryUserState] {
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        let candidateIds = [userId] + cachedConnections.following.map { $0.id }
        var entries: [StoryUserState] = []

        for candidateId in candidateIds {
            let stories = LocalPersistenceService.shared.loadStories(userId: candidateId)
            let hasStory = !stories.isEmpty

            if candidateId != userId && !hasStory {
                continue
            }

            entries.append((
                userId: candidateId,
                hasStory: hasStory,
                hasUnseenStory: candidateId == userId ? false : hasStory,
                storyCount: stories.count,
                storyViewedStatus: Array(repeating: candidateId == userId, count: stories.count),
                storyAudiences: stories.map { $0.audience }
            ))
        }

        return buildSortedStoryUsers(entries: entries, currentUserId: userId)
    }

    @MainActor
    private func performManualRefresh(userId: String) async {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isManualRefreshing = true
        }

        await refreshFeed(userId: userId)

        try? await Task.sleep(nanoseconds: 250_000_000)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isManualRefreshing = false
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
                await self.loadStoryUsers(userId: userId, allowInstantCache: false)
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



extension Array {
    subscript(safe range: Range<Index>) -> ArraySlice<Element> {
        let start = Swift.max(range.lowerBound, startIndex)
        let end = Swift.min(range.upperBound, endIndex)
        guard start <= end else { return self[endIndex..<endIndex] }
        return self[start..<end]
    }
}
