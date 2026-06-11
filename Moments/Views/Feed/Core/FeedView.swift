
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

struct FeedView: View {
    @EnvironmentObject var authService: AuthService
    @State private var viewModel = FeedViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @StateObject private var messagingViewModel = MessagingViewModel()
    @StateObject private var firestoreService = FirestoreService.shared
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
    @State private var suspendedMomentForComments: Moment? = nil
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
    @State private var storyRingNavigationUserIds: [String] = []
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

            FloatingMomentUploadOverlay(topInset: isFeedHeaderHidden ? 18 : feedHeaderHeight + 12)
                .environmentObject(uploadService)
                .zIndex(1200)
            
            FeedFloatingSelector(
                selectedFeedType: $selectedFeedType,
                isManualRefreshing: $isManualRefreshing,
                viewModel: viewModel,
                colorScheme: colorScheme,
                floatingSelectorTopInset: floatingSelectorTopInset,
                isFeedHeaderHidden: isFeedHeaderHidden,
                pendingEchoesCount: pendingEchoes.count
            )
            
                .overlay(
                    VStack(spacing: 8) {
                        SlowConnectionBanner(networkMonitor: networkMonitor)
                        if let errorMessage = viewModel.errorMessage {
                            AppErrorBanner(message: errorMessage) {
                                forceRefresh()
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(!networkMonitor.isConnected || networkMonitor.isSlowConnection)
                    , alignment: .top
                )
            
            FeedOverlaysSection(
                isPeeking: $isPeeking,
                peekImageURL: $peekImageURL,
                peekAspectRatio: $peekAspectRatio,
                peekIsProtected: $peekIsProtected,
                showGlobalContextMenu: $showGlobalContextMenu,
                showShareSheet: $showShareSheet,
                showEditSheet: $showEditSheet,
                showDeleteAlert: $showDeleteAlert,
                editedContent: $editedContent,
                selectedMomentForMenu: $selectedMomentForMenu,
                pendingEchoInvitationRoute: $pendingEchoInvitationRoute,
                showPendingEchoInvitation: $showPendingEchoInvitation,
                selectedPendingEchoId: $selectedPendingEchoId,
                notificationSummaryService: notificationSummaryService,
                badgeService: badgeService,
                colorScheme: colorScheme
            )
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
            onOpenStory: { _, authorId in
                syncStoryRingNavigationOrder()
                if let authorId, !authorId.isEmpty {
                    selectedStoryUserId = authorId
                    showSpecificUserStories = true
                } else {
                    showStories = true
                }
            },
            onOpenStoryChain: { chainId, chainTitle in
                selectedChainId = chainId
                selectedChainTitle = chainTitle
                showStoryChain = true
            }
        )
        .onChange(of: showingLocationMap) { _, isShowing in
            if isShowing {
                // ✅ El onChange es crucial para el funcionamiento, pero sin prints
            }
        }
        .onChange(of: selectedProfileRoute) { _, newRoute in
            if newRoute == nil, let suspended = suspendedMomentForComments {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedMoment = suspended
                    suspendedMomentForComments = nil
                }
            }
        }

        .onChange(of: badgeService.unreadNotificationsCount) { _, count in

        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.forceFeedRefresh)) { _ in
            guard let userId = Auth.auth().currentUser?.uid else { return }
            Task {
                await performManualRefresh(userId: userId)
                await OfflineSyncService.shared.retryFromUserAction()
                if NetworkMonitor.shared.isConnected {
                    HapticManager.shared.notification(.success)
                } else {
                    HapticManager.shared.notification(.warning)
                }
            }
        }
        .environmentObject(firestoreService)
        .feedPresentations(
            showNotifications: $showNotifications,
            showMessages: $showMessages,
            showSpecificUserStories: $showSpecificUserStories,
            selectedStoryUserId: $selectedStoryUserId,
            storyRingNavigationUserIds: $storyRingNavigationUserIds,
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

    private func syncStoryRingNavigationOrder() {
        storyRingNavigationUserIds = storyRingCoordinator.ringNavigationUserIds
    }

    private func openStoryViewer(for userId: String) {
        guard !userId.isEmpty else { return }
        syncStoryRingNavigationOrder()
        selectedStoryUserId = userId
        showSpecificUserStories = true
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
            mentionedUsers: payload.mentionedUsers,
            location: payload.locationName.isEmpty ? nil : payload.locationName,
            locationCoordinate: payload.locationCoordinate.map {
                Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            mediaItems: payload.mediaItems
        ) { error in
            if error != nil {
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
                
                if error != nil {
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
        AdaptiveColors(colorScheme: colorScheme).surfaceBackground
            .ignoresSafeArea()
    }
    
    private var mainContent: some View {
        ZStack(alignment: .top) {
            FeedListSection(
                viewModel: viewModel,
                isFeedHeaderHidden: $isFeedHeaderHidden,
                selectedMoment: $selectedMoment,
                selectedFeedType: $selectedFeedType,
                selectedHashtag: $selectedHashtag,
                showExploreWithHashtag: $showExploreWithHashtag,
                selectedLocationName: $selectedLocationName,
                selectedLocationCoordinate: $selectedLocationCoordinate,
                showingLocationMap: $showingLocationMap,
                showGlobalContextMenu: $showGlobalContextMenu,
                selectedMomentForMenu: $selectedMomentForMenu,
                peekImageURL: $peekImageURL,
                peekAspectRatio: $peekAspectRatio,
                isPeeking: $isPeeking,
                peekIsProtected: $peekIsProtected,
                colorScheme: colorScheme,
                feedContentTopInset: feedContentTopInset,
                feedHeaderHeight: feedHeaderHeight,
                feedSelectorHeight: feedSelectorHeight,
                onForceRefresh: forceRefresh,
                onManualRefresh: performManualRefresh,
                onOpenUserProfile: openUserProfile
            )
                .ignoresSafeArea(edges: .top)
            
            FeedHeaderBar(
                showCreatorView: $showCreatorView,
                showNotifications: $showNotifications,
                showMessages: $showMessages,
                showEchoHistory: $showEchoHistory,
                showPendingEchoInvitation: $showPendingEchoInvitation,
                selectedPendingEchoId: $selectedPendingEchoId,
                pendingEchoInvitationRoute: $pendingEchoInvitationRoute,
                storyRingCoordinator: storyRingCoordinator,
                storyUploadService: storyUploadService,
                badgeService: badgeService,
                colorScheme: colorScheme,
                pendingEchoes: pendingEchoes,
                onOpenStory: openStoryViewer
            )
            .offset(y: isFeedHeaderHidden ? -(feedHeaderHeight + 20) : 0)
            .opacity(isFeedHeaderHidden ? 0 : 1)
            .allowsHitTesting(!isFeedHeaderHidden)
            .padding(.top, -8)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isFeedHeaderHidden), value: isFeedHeaderHidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openUserProfile(_ userId: String) {
        let trimmedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else { return }

        if trimmedUserId == Auth.auth().currentUser?.uid {
            if selectedMoment != nil {
                selectedMoment = nil
            }
            selectedUserId = ""
            selectedProfileRoute = nil
            LegacyNavigationBridge.ownProfileTab()
            return
        }

        selectedUserId = trimmedUserId

        if let currentMoment = selectedMoment {
            suspendedMomentForComments = currentMoment
            selectedMoment = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                selectedProfileRoute = FeedProfileSheetRoute(userId: trimmedUserId)
            }
        } else {
            selectedProfileRoute = FeedProfileSheetRoute(userId: trimmedUserId)
        }
    }
    
    private func startTimeUpdate() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            withAnimation {
                currentTime = Date()
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
        let moments = Array(viewModel.moments.prefix(12))
        VideoMomentsIndex.shared.rebuild(from: viewModel.moments)

        let momentUrls = moments
            .compactMap { $0.imagePath }
            .compactMap { URL(string: $0) }
        ImagePrefetchManager.shared.prefetch(urls: momentUrls)

        let videoURLs = VideoPlaybackSelector.shared.preloadURLStrings(from: moments, maxMoments: 6)
        if !videoURLs.isEmpty {
            VideoPreloader.shared.preloadAssets(urls: videoURLs)
        }
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
