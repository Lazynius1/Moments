
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
    @StateObject private var notificationGate = PermissionPrimerGate(.notifications)
    @State private var didScheduleNotificationPrompt = false
    @State private var showNotifications = false
    @State private var showNova = false
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
    @Namespace private var profileZoomNamespace
    @Namespace private var storyZoomNamespace
    // 🔗 STORY CHAINS: Variables para navegación
    @State private var showStoryChain = false
    @State private var selectedChainId: String = ""
    @State private var selectedChainTitle: String = ""
    @State private var hasLoadedInitialData = false
    // ✅ NUEVO: Mapa global
    @State private var hasUnreadMessages: Bool = false
    @State private var selectedStoryRoute: StoryUserPresentationRoute?
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
    @State private var storyRingPreviewSelection: FeedStoryRingPreviewSelection?
    @State private var postProfilePreviewSelection: FeedPostProfilePreviewSelection?
    @State private var hiddenPostPreviewMomentId: String?
    
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
    @State private var timeUpdateTimer: Timer?

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
                        if let errorMessage = viewModel.errorMessage {
                            AppErrorBanner(message: errorMessage) {
                                forceRefresh()
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(viewModel.errorMessage != nil)
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

            FeedStoryRingPreviewOverlay(
                selection: $storyRingPreviewSelection,
                colorScheme: colorScheme,
                onOpenStory: { userId, storyId, elapsed in
                    openStoryViewer(for: userId, startStoryId: storyId, startElapsed: elapsed)
                },
                onOpenProfile: openUserProfile,
                onMuted: { userId in
                    storyRingCoordinator.removeMutedUser(userId)
                }
            )
            .ignoresSafeArea()
            .zIndex(1600)

            FeedPostProfilePreviewOverlay(
                selection: $postProfilePreviewSelection,
                colorScheme: colorScheme,
                messagingViewModel: messagingViewModel,
                onOpenProfile: openUserProfile,
                onPresentedChange: { presented in
                    if !presented {
                        hiddenPostPreviewMomentId = nil
                    }
                }
            )
            .ignoresSafeArea()
            .zIndex(1601)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .permissionPrimerGate(notificationGate)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
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

                // Precalentar pipeline de vídeo fuera del primer scroll a un reel.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    FeedVideoPipelineWarmer.prewarmIfNeeded()
                }
            }
        .onDisappear {
            // Liberar recursos al salir del feed para evitar fugas y trabajo en background.
            timeUpdateTimer?.invalidate()
            timeUpdateTimer = nil
            pendingEchoesListener?.remove()
            pendingEchoesListener = nil
            viewModel.shutdown()
        }
        .feedNotificationRouting(
            showNotifications: $showNotifications,
            showCreatorView: $showCreatorView,
            showExplore: $showExplore,
            showMomentDetail: $showMomentDetail,
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
                    selectedStoryRoute = StoryUserPresentationRoute(userId: authorId)
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
            showNova: $showNova,
            selectedStoryRoute: $selectedStoryRoute,
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
            profileZoomNamespace: profileZoomNamespace,
            storyZoomNamespace: storyZoomNamespace,
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
        openStoryViewer(for: userId, startStoryId: nil, startElapsed: 0)
    }

    private func openStoryViewer(for userId: String, startStoryId: String?, startElapsed: TimeInterval) {
        guard !userId.isEmpty else { return }
        syncStoryRingNavigationOrder()
        selectedStoryRoute = StoryUserPresentationRoute(
            userId: userId,
            startStoryId: startStoryId,
            startElapsed: startElapsed
        )
    }
    
    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    UIApplication.shared.registerForRemoteNotifications()
                case .notDetermined:
                    guard !didScheduleNotificationPrompt else { return }
                    didScheduleNotificationPrompt = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                        notificationGate.requestAccess {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    // 🌊 ECHOES: Configurar listener para invitaciones pendientes
    private func setupPendingEchoesListener() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        pendingEchoesListener = EchoService.shared.fetchPendingEchoes(userId: userId) { echoes in
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
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
                onOpenUserProfile: openUserProfile,
                onAuthorAvatarLongPress: { userId, momentId, frame in
                    hiddenPostPreviewMomentId = momentId
                    postProfilePreviewSelection = FeedPostProfilePreviewSelection(
                        userId: userId,
                        momentId: momentId,
                        anchorFrame: frame
                    )
                },
                hiddenMomentId: hiddenPostPreviewMomentId,
                profileZoomNamespace: profileZoomNamespace
            )
                .ignoresSafeArea(edges: .top)
            
            FeedHeaderBar(
                showCreatorView: $showCreatorView,
                showNotifications: $showNotifications,
                showNova: $showNova,
                showEchoHistory: $showEchoHistory,
                showPendingEchoInvitation: $showPendingEchoInvitation,
                selectedPendingEchoId: $selectedPendingEchoId,
                pendingEchoInvitationRoute: $pendingEchoInvitationRoute,
                storyRingCoordinator: storyRingCoordinator,
                storyUploadService: storyUploadService,
                badgeService: badgeService,
                colorScheme: colorScheme,
                pendingEchoes: pendingEchoes,
                storyZoomNamespace: storyZoomNamespace,
                onOpenStory: openStoryViewer,
                onPreviewStory: { userId, frame in
                    storyRingPreviewSelection = FeedStoryRingPreviewSelection(
                        userId: userId,
                        anchorFrame: frame
                    )
                }
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
        // Evita acumular timers si onAppear se dispara más de una vez.
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
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
            // Re-armar el listener del usuario que se liberó en onDisappear (shutdown).
            // Los listeners de comentarios se re-arman solos vía cambios de visibilidad.
            viewModel.fetchUserData(userId: userId)
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
        FeedVideoPipelineWarmer.prewarmIfNeeded()
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
