
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

private extension Moment {
    var feedViewIdentity: String {
        if let id, !id.isEmpty {
            return "\(authorId)_\(id)"
        }
        return "\(authorId)_\(timestamp.timeIntervalSince1970)_\(content.prefix(24))"
    }
}

struct FeedView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @StateObject private var messagingViewModel = MessagingViewModel()
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var storyRingCoordinator = FeedStoryRingCoordinator()
    @StateObject private var storyViewModel = StoryViewModel()
    @StateObject private var uploadService = BackgroundMomentUploadService.shared
    @StateObject private var storyUploadService = BackgroundStoryUploadService.shared
    @StateObject private var adManager = NativeAdManager()
    @StateObject private var notificationSummaryService = NotificationSummaryService.shared
    @ObservedObject private var badgeService = NotificationBadgeService.shared // ✅ NUEVO
    @StateObject private var navigationService = NotificationNavigationService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared // ✅ NUEVO: NetworkMonitor
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var showStories = false
    @State private var selectedMoment: Moment?
    @Binding var showCreatorView: Bool
    @State private var currentTime = Date()
    @Environment(\.colorScheme) var colorScheme
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
                
                storyRingCoordinator.prefetchTopStoryUsers(
                    excluding: Auth.auth().currentUser?.uid,
                    firestoreService: firestoreService
                )
                
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
        .onDisappear {
            // cleanupListeners() // ❌ ELIMINAR
        }
        .feedNotificationRouting(
            showMessages: $showMessages,
            showNotifications: $showNotifications,
            showCreatorView: $showCreatorView,
            showExplore: $showExplore,
            showMomentDetail: $showMomentDetail,
            targetConversationId: $targetConversationId,
            targetMomentId: $targetMomentId,
            targetMomentUserId: $targetMomentUserId,
            notificationSummaryService: notificationSummaryService,
            badgeService: badgeService,
            navigationService: navigationService,
            storyRingCoordinator: storyRingCoordinator,
            firestoreService: firestoreService,
            onOpenUserProfile: openUserProfile,
            onOpenStoryChain: { chainId, chainTitle in
                selectedChainId = chainId
                selectedChainTitle = chainTitle
                showStoryChain = true
            }
        )
        .onChange(of: showingLocationMap) { isShowing in
            if isShowing {
                // ✅ El onChange es crucial para el funcionamiento, pero sin prints
            }
        }

        .onChange(of: badgeService.unreadNotificationsCount) { count in

        }
        .environmentObject(firestoreService)
        .feedPresentations(
            showNotifications: $showNotifications,
            showMessages: $showMessages,
            showSpecificUserStories: $showSpecificUserStories,
            selectedStoryUserId: $selectedStoryUserId,
            showStories: $showStories,
            selectedMoment: $selectedMoment,
            showExploreWithHashtag: $showExploreWithHashtag,
            selectedHashtag: $selectedHashtag,
            showExplore: $showExplore,
            showingLocationMap: $showingLocationMap,
            selectedLocationName: $selectedLocationName,
            selectedLocationCoordinate: $selectedLocationCoordinate,
            showMomentDetail: $showMomentDetail,
            targetMomentId: $targetMomentId,
            targetMomentUserId: $targetMomentUserId,
            showEditSheet: $showEditSheet,
            showDeleteAlert: $showDeleteAlert,
            selectedMomentForMenu: $selectedMomentForMenu,
            selectedProfileRoute: $selectedProfileRoute,
            selectedUserId: $selectedUserId,
            showEchoHistory: $showEchoHistory,
            targetConversationId: $targetConversationId,
            messagingViewModel: messagingViewModel,
            firestoreService: firestoreService,
            updateMoment: updateMoment,
            deleteMoment: deleteMoment
        )
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
                if storyRingCoordinator.isLoadingStories {
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
                                hasStory: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyRingCoordinator.storyUsers.first?.hasStory ?? false) : false,
                                storyCount: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyRingCoordinator.storyUsers.first?.storyCount ?? 0) : 0,
                                storyAudiences: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyRingCoordinator.storyUsers.first?.storyAudiences ?? []) : [],
                                colorScheme: colorScheme,
                                storyUploadService: storyUploadService
                            ) {
                                // ✅ LÓGICA SIMPLE Y CLARA
                                if let currentUserId = Auth.auth().currentUser?.uid,
                                   storyRingCoordinator.storyUsers.first?.hasStory == true && storyRingCoordinator.storyUsers.first?.userId == currentUserId {
                                    
                                    // 📖 Si tienes historia, mostrar tus historias
                                    selectedStoryUserId = currentUserId
                                    showSpecificUserStories = true

                                    
                                } else {
                                    
                                    // ➕ Si no tienes historia, crear nueva
                                    showCreatorView = true

                                    
                                }
                            }
                            
                            // Resto de historias (usuarios que sigues)
                            ForEach(storyRingCoordinator.storyUsers.dropFirst(), id: \.userId) { storyUser in
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
        storyRingCoordinator.clearCacheIfNeeded()
        
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
                    await self.storyRingCoordinator.loadStoryUsers(userId: userId, firestoreService: self.firestoreService)
                }
            }
            prefetchImages()
            
            // ✅ NUEVO: Marcar como cargado
            hasLoadedInitialData = true
        }
    }
    
    // ✅ NUEVO: Función para forzar refresh
    private func forceRefresh() {

        hasLoadedInitialData = false
        storyRingCoordinator.resetCache()
        loadInitialData()
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
                await self.storyRingCoordinator.loadStoryUsers(
                    userId: userId,
                    allowInstantCache: false,
                    firestoreService: self.firestoreService
                )
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
}



extension Array {
    subscript(safe range: Range<Index>) -> ArraySlice<Element> {
        let start = Swift.max(range.lowerBound, startIndex)
        let end = Swift.min(range.upperBound, endIndex)
        guard start <= end else { return self[endIndex..<endIndex] }
        return self[start..<end]
    }
}
