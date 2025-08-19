// ✅ NUEVO: Sistema de colores adaptativos
struct AdaptiveColors {
    let colorScheme: ColorScheme
    
    // Colores principales
    var primary: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var secondary: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }
    
    var tertiary: Color {
        colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.8)
    }
    
    // Colores de acento
    var accent: Color {
        Color(hex: "00A896")
    }
    
    var accentSecondary: Color {
        colorScheme == .dark ? Color(hex: "00A896").opacity(0.3) : Color(hex: "00A896").opacity(0.6)
    }
    
    // Colores de fondo
    var cardBackground: Material {
        .ultraThinMaterial
    }
    
    var overlayStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)] :
        [Color.black.opacity(0.1), Color(hex: "00A896").opacity(0.4)]
    }
    
    // Colores para botones
    var buttonStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)] :
        [Color.black.opacity(0.2), Color(hex: "00A896").opacity(0.5)]
    }
    
    var buttonGradient: [Color] {
        colorScheme == .dark ?
        [Color(hex: "00A896"), Color.white.opacity(0.8)] :
        [Color(hex: "00A896"), Color.black.opacity(0.7)]
    }
    
    // Sombras
    var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.1) : .black.opacity(0.15)
    }
}

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

struct FeedView: View {
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
    private let privacyService = PrivacyService()
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var showStories = false
    @State private var showingComments = false
    @State private var selectedMoment: Moment?
    @Binding var showCreatorView: Bool
    @State private var currentTime = Date()
    @Environment(\.colorScheme) var colorScheme
    @State private var storyUsers: [(userId: String, hasStory: Bool, hasUnseenStory: Bool)] = []
    @State private var isLoadingStories = true
    @State private var selectedFeedType: FeedType = UserDefaults.standard.selectedFeedType
    @State private var showingLocationMap = false
    @State private var selectedLocationName: String = ""
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    // ✅ NUEVO: Cache básico para optimización
    @State private var cachedStories: [String: Bool] = [:]
    @State private var cachedStoriesTimestamp: Date = Date()
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
    @State private var targetConversationId: String? = nil
    @State private var targetMomentId: String? = nil
    @State private var showMomentDetail = false
    @State private var targetMomentUserId: String? = nil
    

    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                modernBackgroundView
                    .ignoresSafeArea()
                mainContent
                
                if showGlobalContextMenu, let moment = selectedMomentForMenu {
                    ModernContextMenuOverlay(
                        moment: moment,
                        isPresented: $showGlobalContextMenu,
                        showShareSheet: $showShareSheet,
                        onEdit: {
                            editedContent = moment.content
                            showEditSheet = true

                        },
                        onDelete: {
                            showDeleteAlert = true

                        },
                        onShare: {
                            if privacyService.canShareMoment(moment) {
                                showShareSheet = true
                                // Share sheet abierto
                            } else {
                                // No se puede compartir momento privado
                            }
                        },
                        onReport: {
                            showReportSheet = true

                        },
                        onCopyLink: {
                            if let momentId = moment.id {
                                UIPasteboard.general.string = "https://moments.app/moment/\(momentId)"

                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
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
            }
        }
        .navigationBarHidden(true)
        
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
        
        .onAppear {
            AnalyticsService.shared.trackScreenView("FeedView")
            AnalyticsService.shared.trackFeatureUsage("feed")
            loadInitialData()
            startTimeUpdate()
            
            setupServiceConnections()
            
            // ✅ Solicitar permiso de notificaciones al cargar el feed (solo si no se ha decidido aún)
            requestNotificationPermissionIfNeeded()
            
            // ✅ SETUP DE LISTENERS
            badgeService.setupListeners()
            
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
        .onDisappear {
            // cleanupListeners() // ❌ ELIMINAR

        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView(onNotificationsCleared: {

                // ✅ No es necesario actualizar hasUnreadNotifications localmente
                // badgeService.clearAppBadge() // ❌ No llamar aquí, NotificationsView ya lo maneja
                NotificationCenter.default.post(
                    name: NSNotification.Name("NotificationsCleared"),
                    object: nil
                )
            })
        }
        .sheet(isPresented: $showMessages) {
            MessagingView(targetConversationId: $targetConversationId)
                .environmentObject(messagingViewModel)
                .environmentObject(firestoreService)
        }
        .fullScreenCover(isPresented: $showSpecificUserStories) {
            StoriesView(startWithUserId: $selectedStoryUserId)
                .environmentObject(firestoreService)
        }
        .fullScreenCover(isPresented: $showStories) {
            StoriesView()
                .environmentObject(firestoreService)
        }
        .sheet(isPresented: $showingComments, onDismiss: {
            selectedMoment = nil
        }) {
            if let moment = selectedMoment {
                ModernCommentsView(moment: moment)
                    .environmentObject(firestoreService)
            }
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .fullScreenCover(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: selectedLocationName.isEmpty ? "Ubicación" : selectedLocationName,
                coordinate: selectedLocationCoordinate,
                isPresented: $showingLocationMap
            )
        }
        .onChange(of: showingLocationMap) { isShowing in
            if isShowing {
                // ✅ El onChange es crucial para el funcionamiento, pero sin prints
            }
        }


        .fullScreenCover(isPresented: $showMomentDetail) {
            if let momentId = targetMomentId, let userId = targetMomentUserId {
                MomentDetailFromNotificationView(
                    momentId: momentId,
                    userId: userId,
                    isPresented: $showMomentDetail
                )
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
        .alert("Eliminar momento", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Eliminar", role: .destructive) {
                if let moment = selectedMomentForMenu {
                    deleteMoment(moment: moment)
                }
            }
        } message: {
                            Text("feed.delete.confirm")
        }
        .sheet(isPresented: $showReportSheet) {
            if let moment = selectedMomentForMenu {
                ReportBottomSheet(moment: moment)
            }
        }
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
        .onChange(of: showingComments) { newValue in
            if !newValue {
                selectedMoment = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfileInFeed"))) { notification in
            if let userId = notification.object as? String, !userId.isEmpty {
                selectedUserId = userId
                showUserProfile = true
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
    }
    
    private func setupServiceConnections() {
        // Conectar UploadService con FeedViewModel
        uploadService.setFeedViewModel(viewModel)

    }
    
    // ✅ Nuevo: Solicitud de permisos de notificaciones desde el Feed en primera carga
    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
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
                // Negro más intenso y elegante
                Color(hex: "0A0A0A")
                    .ignoresSafeArea()
            } else {
                // ✅ NUEVO: Fondo claro elegante
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
                .ignoresSafeArea()
            }
        }
    }
    
    private var mainContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                modernHeaderView
                
                // 🔥 NUEVO: Barra de progreso de uploads
                uploadProgressBar
                
                // ✅ MODIFICADO: Selector de feed con guardado de preferencias
                SegmentedFeedToggle(selectedFeedType: $selectedFeedType)
                    .padding(.vertical, 8)
                    .onChange(of: selectedFeedType) { newFeedType in
                        // ✅ NUEVO: Guardar la preferencia del usuario
                        UserDefaults.standard.selectedFeedType = newFeedType
                        
                        // ✅ Cambiar tipo de feed cuando se selecciona
                        if let userId = Auth.auth().currentUser?.uid {
                            viewModel.switchFeedType(to: newFeedType, userId: userId)
                        }
                        
                        // ✅ NUEVO: Track analytics para preferencias
                        AnalyticsService.shared.trackFeatureUsage("feed_type_changed_to_\(newFeedType.rawValue)")
                    }
                
                scrollableContent
            }
        }
    }
    
    // ✅ Header moderno
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
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
                    .padding(.leading, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // 🔥 NUEVO: Tu historia con progreso de upload si está subiendo
                            YourStoryCircleWithProgress(
                                hasStory: storyUsers.first?.userId == Auth.auth().currentUser?.uid ? (storyUsers.first?.hasStory ?? false) : false,
                                colorScheme: colorScheme,
                                storyUploadService: storyUploadService
                            ) {
                                // ✅ LÓGICA SIMPLE Y CLARA
                                if let currentUserId = Auth.auth().currentUser?.uid,
                                   storyUsers.first?.hasStory == true && storyUsers.first?.userId == currentUserId {
                                    
                                    // 📖 Si tienes historia, mostrar tus historias
                                    AnalyticsService.shared.trackInteraction("own_story_tapped")
                                    selectedStoryUserId = currentUserId
                                    showSpecificUserStories = true

                                    
                                } else {
                                    
                                    // ➕ Si no tienes historia, crear nueva
                                    AnalyticsService.shared.trackInteraction("create_story_tapped")
                                    showCreatorView = true

                                    
                                }
                            }
                            
                            // Resto de historias (usuarios que sigues)
                            ForEach(storyUsers.dropFirst(), id: \.userId) { storyUser in
                                RealStoryCircle(
                                    userId: storyUser.userId,
                                    hasStory: storyUser.hasStory,
                                    hasUnseenStory: storyUser.hasUnseenStory,
                                    isOwnStory: false, // Ya no es tu historia
                                    colorScheme: colorScheme
                                ) {
                                    AnalyticsService.shared.trackInteraction("stories_button_tapped")
                                    AnalyticsService.shared.trackFeatureUsage("stories")
                                    
                    
                                    guard !storyUser.userId.isEmpty else {
                                        return
                                    }
                                    
                                    selectedStoryUserId = storyUser.userId
                                    showSpecificUserStories = true
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 0)
                    }
                }
                
                Spacer()
                
                // Botones integrados con espaciado natural
                HStack(spacing: 20) {
                    ModernStoryButton(colorScheme: colorScheme) {
                        AnalyticsService.shared.trackInteraction("stories_button_tapped")
                        AnalyticsService.shared.trackFeatureUsage("stories")
                        showStories = true
                    }
                    
                    // ✅ NUEVO: Botón del mapa global

                    
                    ModernNotificationButton(
                        hasNotification: badgeService.unreadNotificationsCount > 0,
                        colorScheme: colorScheme,
                        action: {
                            AnalyticsService.shared.trackInteraction("notifications_button_tapped")
                            AnalyticsService.shared.trackFeatureUsage("notifications")
                            showNotifications = true
                        }
                    )
                    
                    ModernMessageButton(
                        hasMessage: badgeService.unreadMessagesCount > 0,    // ✅ Badge aparece si > 0
                        messageCount: badgeService.unreadMessagesCount,      // ✅ Número real
                        colorScheme: colorScheme,
                        action: {
                            AnalyticsService.shared.trackInteraction("messages_button_tapped")
                            AnalyticsService.shared.trackFeatureUsage("messages")
                            showMessages = true
                        }
                    )
                }
                .padding(.trailing, 20)
            }
            .padding(.vertical, 16)
            .background(
                Group {
                    if colorScheme == .dark {
                        // Negro más intenso y elegante
                        Color(hex: "0A0A0A")
                    } else {
                        // Mismo fondo que el Feed en modo claro
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
            .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
        }
    }
    
    // ✅ Contenido del scroll
    private var scrollableContent: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: max(15, geometry.size.height * 0.02)) {
                        ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                            VStack(spacing: max(15, geometry.size.height * 0.02)) {
                                let headerHeight = 100.0
                                let progressBarHeight = uploadService.uploadingMoments.isEmpty ? 0.0 : 50.0
                                let segmentedToggleHeight = 35.0
                                let availableHeight = geometry.size.height - headerHeight - progressBarHeight - segmentedToggleHeight - 10

                                ModernPostCardView(
                                    moment: moment,
                                    availableHeight: availableHeight,
                                    colorScheme: colorScheme,
                                    onComment: {
                                        selectedMoment = moment
                                        showingComments = true
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
                                    }
                                )
                                .id(index)
                                .environmentObject(firestoreService)
                                .environmentObject(viewModel)

                                let adInterval = selectedFeedType == .forYou ? 3 : 5
                                if (index + 1) % adInterval == 0 && index < viewModel.moments.count - 1 {
                                    SmartNativeAdView()
                                        .onAppear {
                                            AnalyticsService.shared.trackFeatureUsage("native_ad_shown")

                                        }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ModernLoadingMoreView(colorScheme: colorScheme)
                                .padding(.vertical, 15)
                        }

                        if viewModel.moments.isEmpty && !viewModel.isLoading {
                            ModernEmptyFeedView(feedType: selectedFeedType, colorScheme: colorScheme)
                                .padding(.vertical, 50)
                        }
                    }
                    .padding(.vertical, 15)
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
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
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
        let isOwnStory: Bool
        let colorScheme: ColorScheme  // ✅ AGREGAR esta línea
        let action: () -> Void
        
        var body: some View {

            Button(action: action) {
                ZStack {
                    AsyncProfileImageView(userId: userId)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 1)
                        )

                }
            }
        }
        
        private var storyRingGradient: LinearGradient {
            if hasUnseenStory {
                // ✅ HISTORIA NO VISTA: Tu gradiente único blue → purple → pink
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
    }
    
    /// ///
    //Progeso subida Stories
    ///
    struct YourStoryCircleWithProgress: View {
        let hasStory: Bool
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
                            Circle()
                                .stroke(baseStoryRingGradient, lineWidth: hasStory ? 2.5 : 1)
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
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 50, height: 50)
                        
                        // Icono de estado
                        statusIcon(for: uploadingStory.status)
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            
                    }
                    // ❌ QUITADO: Plus button eliminado completamente
                }
            }
            .scaleEffect(storyUploadService.uploadingStory?.status == .failed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: storyUploadService.uploadingStory?.status)
        }
        
        // MARK: - Helper functions (igual que antes)
        private var baseStoryRingGradient: LinearGradient {
            if hasStory {
                // ✅ TU HISTORIA: Mismo gradiente que usas para otros (tu identidad visual)
                return LinearGradient(
                    colors: [Color.blue, Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // ✅ NO TIENES HISTORIA: Sin anillo (transparente)
                return LinearGradient(
                    colors: [Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
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
                        .fill(Color(hex: "00A896").opacity(0.3))
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
                        Text(uploadingMoment.content.isEmpty ? "Nuevo momento" : uploadingMoment.content)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusBackgroundColor)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
                    
                case .completed:
                    // 🔥 VERSIÓN SIMPLE - Sin symbolEffect
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .scaleEffect(checkScale)
                        .onAppear {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                checkScale = 1.2
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    checkScale = 1.0
                                }
                            }
                        }
                    
                    Text("feed.uploading.published")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                    
                case .moderated:
                    // 🔥 MISMA ANIMACIÓN pero usuario no sabe
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .scaleEffect(checkScale)
                        .onAppear {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                checkScale = 1.2
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    checkScale = 1.0
                                }
                            }
                        }
                    
                    Text("feed.uploading.published") // 🤫 Usuario no sabe que fue moderado
                        .font(.system(size: 11, weight: .medium))
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
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        
                        // Progreso
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * uploadingMoment.uploadProgress, height: 4)
                            .animation(.easeInOut(duration: 0.3), value: uploadingMoment.uploadProgress)
                    }
                }
                .frame(height: 4)
                
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
        
        private var progressColor: LinearGradient {
            switch uploadingMoment.status {
            case .uploading:
                return LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .processing:
                return LinearGradient(
                    colors: [.orange, .orange.opacity(0.8)],
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
                return "Subiendo archivos..."
            case .processing:
                return "Creando momento..."
            case .completed, .moderated:
                return "¡Tu momento ya está disponible!"
            case .failed:
                return uploadingMoment.errorMessage ?? "Error al subir"
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
        cachedStoriesTimestamp = Date()
        loadInitialData()
    }
    
    // ✅ OPTIMIZADO: loadStoryUsers con cache básico
    private func loadStoryUsers(userId: String) async {
        await withCheckedContinuation { continuation in
            isLoadingStories = true
            
            firestoreService.fetchFollowing(userId: userId) { result in
                switch result {
                case .success(let followingUsers):
                    let followingIds = followingUsers.map { $0.id }
                    var allUserIds = [userId] // Empezar contigo
                    allUserIds.append(contentsOf: followingIds)
                    
                    // ✅ NUEVO: Verificar cache primero
                    let cacheAge = Date().timeIntervalSince(self.cachedStoriesTimestamp)
                    if cacheAge < 300 && !self.cachedStories.isEmpty { // 5 minutos

                        var finalUsers: [(userId: String, hasStory: Bool, hasUnseenStory: Bool)] = []
                        
                        // Agregar tu historia
                        let currentUserHasStory = self.cachedStories[userId] ?? false
                        finalUsers.append((userId: userId, hasStory: currentUserHasStory, hasUnseenStory: false))
                        
                        // Agregar historias de otros desde cache
                        for followingId in followingIds {
                            if let hasStory = self.cachedStories[followingId], hasStory {
                                finalUsers.append((userId: followingId, hasStory: true, hasUnseenStory: true))
                            }
                        }
                        
                        self.storyUsers = finalUsers
                        self.isLoadingStories = false
                        continuation.resume()
                        return
                    }
                    
                    let group = DispatchGroup()
                    var usersWithStories: [(userId: String, hasStory: Bool, hasUnseenStory: Bool)] = []
                    var currentUserHasStory = false // ✅ NUEVO: Track tu historia por separado
                    let syncQueue = DispatchQueue(label: "story.users.sync")
                    
                    for userIdToCheck in allUserIds {
                        group.enter()
                        self.checkUserStories(userId: userIdToCheck, currentUserId: userId) { hasStory, hasUnseen in
                            syncQueue.async {
                                // ✅ NUEVO: Guardar en cache
                                self.cachedStories[userIdToCheck] = hasStory
                                
                                if userIdToCheck == userId {
                                    // ✅ NUEVO: Tu historia va por separado
                                    currentUserHasStory = hasStory
                                } else if hasStory {
                                    // ✅ CORREGIDO: Solo historias de OTROS usuarios
                                    usersWithStories.append((
                                        userId: userIdToCheck,
                                        hasStory: hasStory,
                                        hasUnseenStory: hasUnseen
                                    ))
                                }
                                group.leave()
                            }
                        }
                    }
                    
                    group.notify(queue: .main) {
                        // ✅ NUEVO: Construir array final correctamente
                        var finalUsers: [(userId: String, hasStory: Bool, hasUnseenStory: Bool)] = []
                        
                        // 1. Agregar TU historia SIEMPRE (primera posición)
                        finalUsers.append((userId: userId, hasStory: currentUserHasStory, hasUnseenStory: false))
                        
                        // 2. Agregar historias de otros (ordenadas por no vistas primero)
                        let sortedOthers = usersWithStories.sorted { user1, user2 in
                            if user1.hasUnseenStory && !user2.hasUnseenStory { return true }
                            if user2.hasUnseenStory && !user1.hasUnseenStory { return false }
                            return false
                        }
                        finalUsers.append(contentsOf: sortedOthers)
                        

                        
                        // ✅ NUEVO: Actualizar timestamp del cache
                        self.cachedStoriesTimestamp = Date()
                        self.storyUsers = finalUsers
                        self.isLoadingStories = false
                        continuation.resume()
                    }
                    
                case .failure(let error):

                    
                    // ✅ CORREGIDO: Fallback también debe verificar tu historia
                    self.checkUserStories(userId: userId, currentUserId: userId) { hasStory, hasUnseen in
                        DispatchQueue.main.async {
                            self.storyUsers = [(userId: userId, hasStory: hasStory, hasUnseenStory: false)]
                            self.isLoadingStories = false
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    // ✅ MEJORAR: checkUserStories con mejor logging y manejo de errores
    private func checkUserStories(userId: String, currentUserId: String, completion: @escaping (Bool, Bool) -> Void) {

        
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                
                if let error = error {

                    completion(false, false)
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {

                    completion(false, false) // No tiene historias
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
    
                    completion(false, false)
                    return
                }
                
                let group = DispatchGroup()
                var isAnyStoryVisible = false
                var hasUnseenStory = false
                let syncQueue = DispatchQueue(label: "story.visibility.check")

                for story in stories {
                    group.enter()

                    
                    // ✅ MEJORADO: Agregar timeout y mejor manejo de errores
                    var hasCompleted = false
                    let completionQueue = DispatchQueue(label: "story.completion.control")
                    
                    // Usar el servicio de privacidad para la verificación completa
                    self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                        completionQueue.async {
                            if !hasCompleted {
                                hasCompleted = true
                                

                                
                                if canView {
                                    syncQueue.async {
                                        isAnyStoryVisible = true
                                    }
                                    
                                    // Si la historia es visible, comprobar si no ha sido vista
                                    if let storyId = story.id {
                                        group.enter() // Agregar un enter más para la verificación de viewers
                                        
                                        Firestore.firestore().collection("users").document(story.authorId)
                                            .collection("stories").document(storyId)
                                            .collection("viewers").document(currentUserId)
                                            .getDocument { viewerDoc, _ in
                                                let wasViewed = viewerDoc?.exists == true
                                                
                                                if !wasViewed {
                                                    syncQueue.async {
                                                        hasUnseenStory = true
                                                    }
                                                }
                                                group.leave()
                                            }
                                    }
                                }
                                
                                group.leave()
                            }
                        }
                    }
                    
                    // ✅ NUEVO: Timeout de seguridad para evitar que se cuelgue
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        completionQueue.async {
                            if !hasCompleted {
                                hasCompleted = true

                                group.leave()
                            }
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    // Solo completar con 'true' si al menos una historia fue visible
                    completion(isAnyStoryVisible, hasUnseenStory)
                }
            }
    }
    
    private func refreshFeed(userId: String) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.viewModel.refreshMoments(userId: userId)
            }
            group.addTask {
                await self.notificationsViewModel.fetchNotifications()
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
        let prefetcher = ImagePrefetcher(urls: momentUrls) { skipped, failed, completed in

        }
        prefetcher.start()
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
                // Fondo más sutil - casi transparente como Instagram
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ?
                          Color.white.opacity(0.05) :
                          Color.black.opacity(0.03))
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

// ✅ Loading moderno para más posts
struct ModernLoadingMoreView: View {
    let colorScheme: ColorScheme  // ✅ AGREGAR parámetro
    @State private var rotationAngle: Double = 0
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.buttonStroke,  // ✅ CAMBIAR
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: adaptiveColors.buttonGradient,  // ✅ CAMBIAR
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
            }
            
                            Text("feed.loadingMore")
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(adaptiveColors.secondary)  // ✅ CAMBIAR esta línea
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())

        .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)  // ✅ CAMBIAR
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// ✅ Estado vacío moderno
struct ModernEmptyFeedView: View {
    let feedType: FeedType
    let colorScheme: ColorScheme  // ✅ AGREGAR parámetro
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.buttonStroke,  // ✅ CAMBIAR
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: feedType.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: adaptiveColors.buttonGradient,  // ✅ CAMBIAR
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(adaptiveColors.primary)  // ✅ CAMBIAR esta línea
                
                Text(emptyDescription)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(adaptiveColors.tertiary)  // ✅ CAMBIAR esta línea
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyTitle: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.title", comment: "Empty following feed title")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.title", comment: "Empty for you feed title")
        }
    }
    
    private var emptyDescription: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.description", comment: "Empty following feed description")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.description", comment: "Empty for you feed description")
        }
    }
}


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
    @EnvironmentObject private var firestoreService: FirestoreService
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var currentImageIndex = 0
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var isFollowing: Bool = false
    @State private var isSaved: Bool = false
    @State private var isFollowLoading: Bool = false
    @State private var isSaveLoading: Bool = false
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    
    // ✅ ACTUALIZADO: AspectRatioType mejorado con soporte para reels
    @State private var aspectRatioType: AspectRatioType = .square
    @State private var cachedCardHeight: CGFloat?
    @State private var lastCalculatedSize: CGSize = .zero
    @State private var isFirstAppear = true
    
    // ✅ Estados para el círculo de historia en el header
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    @State private var isLoadingStory: Bool = false
    @State private var showStories = false
    @State private var showSpecificUserStories = false
    private let privacyService = PrivacyService()
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    // ✅ MEJORADO: AspectRatioType con soporte completo para todos los formatos
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 400      // Para 1:1 (1080x1080)
            case .portrait: return 500    // Para 4:5 (1080x1350)
            case .landscape: return 300   // Para 16:9 - más compacto
            case .reels: return 800       // ✅ NUEVO: Para 9:16 (reels/stories) - más alto
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
            width: UIScreen.main.bounds.width - 30,
            height: availableHeight
        )
        
        // ✅ CACHEAR: Solo recalcular si el tamaño cambió significativamente
        if let cached = cachedCardHeight,
           abs(currentSize.width - lastCalculatedSize.width) < 1.0,
           abs(currentSize.height - lastCalculatedSize.height) < 1.0 {
            return cached
        }
        
        // ✅ RECALCULAR solo cuando sea necesario
        let newHeight = calculateCardHeight(for: currentSize)
        
        // ✅ GUARDAR en cache (sin trigger re-render)
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
        
        // ✅ Validar que maxWidth sea positivo
        guard maxWidth > 0 else {

            return 300 // Fallback seguro
        }
        
        // ✅ Validar aspect ratio detectado
        let aspectRatio: CGFloat
        if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
            aspectRatio = detectedAspectRatio
        } else {
            aspectRatio = aspectRatioType.exactRatio
        }
        
        // ✅ Calcular altura ideal basada en el aspect ratio
        let idealHeight = maxWidth / aspectRatio
        
        // ✅ Validar que la altura calculada sea válida
        guard idealHeight > 0 && idealHeight.isFinite else {

            return aspectRatioType.maxHeight // Usar altura máxima como fallback
        }
        
        // ✅ Aplicar límites seguros
        let maxAllowedHeight = min(aspectRatioType.maxHeight, containerSize.height)
        let finalHeight = min(idealHeight, maxAllowedHeight)
        
        // ✅ Validación final - asegurar altura mínima
        let safeHeight = max(finalHeight, 200) // Mínimo 200pt
        
        // ✅ SOLO LOGEAR EN PRIMERA CARGA (no en cada recálculo)
        if isFirstAppear {
    
        }
        
        return safeHeight
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header del post con círculo de historia
            postHeaderView
            
            // Contenido principal
            ZStack(alignment: .bottom) {
                ZStack {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                        allMoments: feedViewModel.moments,
                        currentMoment: moment
                    )
                    .frame(height: max(cardHeight, 200))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
                    .onAppear {
                        detectAspectRatio()
                    }
                    
                    // ✅ NUEVO: Botón simple de menú contextual (sin overlay local)
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {

                                onContextMenu(moment) // ✅ Llamar al callback del FeedView
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.4), Color.gray.opacity(0.3)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                    
                    if mediaItems.count > 1 {
                        VStack {
                            HStack(spacing: 8) {
                                ForEach(0..<mediaItems.count, id: \.self) { index in
                                    Capsule()
                                        .fill(currentImageIndex == index ? Color.white : Color.white.opacity(0.5))
                                        .frame(width: currentImageIndex == index ? 25 : 8, height: 4)
                                        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                }
                            }
                            .padding(.top, 60) // ✅ Espacio para evitar solapamiento con el botón de menú
                            Spacer()
                        }
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
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                ModernActionButtons(
                    moment: moment,
                    isSaved: $isSaved,
                    isSaveLoading: $isSaveLoading,
                    commentCount: $commentCount,
                    onComment: onComment,
                    onSave: toggleSave
                )
                .environmentObject(firestoreService)
            }
            .padding(.horizontal, 15)
        }
        .onAppear {
            if !hasLoadedInitialData {
                loadAllPostData()
                hasLoadedInitialData = true
                
                // ✅ MARCAR que ya no es primera aparición
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFirstAppear = false
                }
            }
            onNearEnd()
            
            // Solo para videos, notificar que está visible
            if mediaItems.first?.type == .video {

            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // ✅ INVALIDAR cache cuando cambia orientación
            DispatchQueue.main.async {
                cachedCardHeight = nil
                lastCalculatedSize = .zero
            }
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
                    AnalyticsService.shared.trackInteraction("post_header_story_tapped")
                    showSpecificUserStories = true
                }
            }) {
                ZStack {
                    AsyncProfileImageView(userId: moment.authorId)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 0)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        if moment.authorId == Auth.auth().currentUser?.uid {
                            NavigationLink(destination: ProfileView(selectedTab: .constant(4))) {
                                Text("\(moment.username)")
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(adaptiveColors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            NavigationLink(destination: UserProfileView(userId: moment.authorId)) {
                                Text("\(moment.username)")
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
                    
                    Text(timeAgo(from: moment.timestamp))
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear {
            checkUserStories()
        }
    }
    
    private var storyRingGradient: LinearGradient {
        if hasUnseenStory {
            return LinearGradient(
                colors: [Color.purple, Color.pink, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasStory {
            return LinearGradient(
                colors: colorScheme == .dark ?
                [Color.gray.opacity(0.5), Color.gray.opacity(0.7)] :
                [Color.gray.opacity(0.6), Color.gray.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.clear, Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        if moment.authorId == currentUserId {
            hasStory = false
            hasUnseenStory = false
            isLoadingStory = false
            return
        }
        
        isLoadingStory = true
        
        firestoreService.db.collection("users").document(moment.authorId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                
                if let error = error {

                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                        self.isLoadingStory = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                        self.isLoadingStory = false
                    }
                    return
                }

                let stories = documents.compactMap { try? $0.data(as: Story.self) }
                
                let group = DispatchGroup()
                var isAnyStoryVisible = false
                var hasUnseenStory = false
                let syncQueue = DispatchQueue(label: "post.story.visibility.check")

                for story in stories {
                    group.enter()
                    privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                        if canView {
                            syncQueue.async {
                                isAnyStoryVisible = true
                                if let storyId = story.id {
                                    Firestore.firestore().collection("users").document(story.authorId)
                                        .collection("stories").document(storyId)
                                        .collection("viewers").document(currentUserId)
                                        .getDocument { viewerDoc, _ in
                                            if viewerDoc?.exists != true {
                                                hasUnseenStory = true
                                            }
                                            group.leave()
                                        }
                                } else {
                                    group.leave()
                                }
                            }
                        } else {
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    DispatchQueue.main.async {
                        self.hasStory = isAnyStoryVisible
                        self.hasUnseenStory = hasUnseenStory
                        self.isLoadingStory = false

                    }
                }
            }
    }
    
    // ✅ MEJORADO: Función detectAspectRatio con mejor clasificación
    private func detectAspectRatio() {
        // ✅ Evitar detectar múltiples veces para el mismo momento
        guard detectedAspectRatio == 1.0 || detectedAspectRatio == 0 else {
            return // Ya se detectó
        }
        
        // ✅ PRIMERO: Intentar usar aspect ratio guardado en el momento
        if let savedAspectRatio = moment.aspectRatio {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            
            DispatchQueue.main.async {
                // ✅ Validar que el valor sea finito y positivo
                let ratioValue = aspectRatioFromDB.value
                if ratioValue > 0 && ratioValue.isFinite {
                    self.detectedAspectRatio = ratioValue
                    
                    // ✅ INVALIDAR cache para recalcular con nuevo ratio
                    self.cachedCardHeight = nil
                } else {

                    self.detectedAspectRatio = 1.0 // Fallback a square
                }
                
                // Clasificar el tipo con ratios exactos
                switch aspectRatioFromDB {
                case .landscape:
                    self.aspectRatioType = .landscape

                case .portrait:
                    self.aspectRatioType = .portrait

                case .square:
                    self.aspectRatioType = .square

                case .nineBySixteen:
                    self.aspectRatioType = .reels

                }
            }
            return
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
        
        print("🔄 Cargando datos para momento: \(momentId)")
        
        feedViewModel.listenForCommentUpdates(momentId: momentId, authorId: moment.authorId)
        loadCommentCount()
        
        if moment.authorId != currentUserId {
            firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: moment.authorId) { following in
                DispatchQueue.main.async {
                    self.isFollowing = following
                }
            }
        }
        
        firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { result in
            switch result {
            case .success(let saved):
                DispatchQueue.main.async {
                    self.isSaved = saved
                }
            case .failure(let error):
                print("Error checking save status: \(error)")
            }
        }
    }
    
    private func loadCommentCount() {
        guard let momentId = moment.id else { return }
        
        firestoreService.db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error cargando comentarios: \(error)")
                    return
                }
                
                DispatchQueue.main.async {
                    let newCount = snapshot?.documents.count ?? 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.commentCount = newCount
                    }
                }
            }
    }
    
    private func toggleFollow() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isFollowLoading = true
        
        if isFollowing {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = false
                        }
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = true
                        }
                    }
                }
            }
        }
    }
    
    private func toggleSave() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        isSaveLoading = true
        
        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.isSaveLoading = false
                if let error = error {
                    print("Error toggling save: \(error)")
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// ✅ ACTUALIZADO: ModernActionButtons con sistema de reactions
struct ModernActionButtons: View {
    let moment: Moment
    @Binding var isSaved: Bool
    @Binding var isSaveLoading: Bool
    @Binding var commentCount: Int
    let onComment: () -> Void
    let onSave: () -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            
            VStack(spacing: 12) {
                // ✅ REACCIONES: Siempre mostrar el botón, pero controlar el contador
                EpicReactionButton(moment: moment, showCount: !moment.hideLikeCounts)
                    .environmentObject(firestoreService)
                
                // ✅ COMENTARIOS: Solo mostrar si están habilitados
                if !moment.disableComments {
                    Button(action: onComment) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: commentCount > 0 ?
                                                    [Color.blue.opacity(0.6), Color.purple.opacity(0.6)] :
                                                    [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                
                                Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: commentCount > 0 ?
                                            [Color.blue, Color.purple] :
                                            [Color.white.opacity(0.8), Color(hex: "00A896")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            if commentCount > 0 {
                                Text("\(commentCount)")
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }

                    .scaleEffect(commentCount > 0 ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: commentCount)
                }
                
                // ✅ GUARDAR: Solo mostrar si está permitido compartir
                if moment.allowSharing {
                    Button(action: onSave) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: isSaved ?
                                                [Color.yellow.opacity(0.6), Color.orange.opacity(0.6)] :
                                                [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            
                            if isSaveLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .tint(Color(hex: "00A896"))
                            } else {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: isSaved ?
                                            [Color.yellow, Color.orange] :
                                            [Color.white.opacity(0.8), Color(hex: "00A896")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                    }
                    .scaleEffect(isSaved ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSaved)
                    .disabled(isSaveLoading)
                }
                
                // ✅ NUEVO: Mensaje informativo si todas las interacciones están deshabilitadas
                if moment.disableComments && moment.hideLikeCounts && !moment.allowSharing {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text("feed.noInteractions")
                            .font(.custom("Poppins-Regular", size: 10))
                            .foregroundColor(.gray.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommentAdded"))) { notification in
            if let momentId = notification.object as? String, momentId == moment.id {
                // Los comentarios se actualizan automáticamente via listeners en FeedViewModel
            }
        }
    }
}

// ✅ MANTENER: ModernFollowButton (igual que antes)
struct ModernFollowButton: View {
    let isFollowing: Bool
    let isLoading: Bool
    let colorScheme: ColorScheme  // ✅ AGREGAR parámetro
    let action: () -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(colorScheme == .dark ? .white : .white)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                
                Text(isFollowing ? "feed.following" : "feed.follow")
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(.white)  // El texto del botón siempre blanco porque el fondo es de color
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: isFollowing ?
                            [Color.gray.opacity(0.6), Color.gray.opacity(0.8)] :
                            [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],  // ✅ CAMBIAR
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                            [Color.white.opacity(0.3), Color.white.opacity(0.1)] :
                            [Color.white.opacity(0.5), Color.white.opacity(0.2)],  // ✅ CAMBIAR
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: adaptiveColors.accent.opacity(0.3), radius: 4, x: 0, y: 2)  // ✅ CAMBIAR
        }
        .disabled(isLoading)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLoading)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFollowing)
    }
}
// ✅ COMPONENTES AUXILIARES (reusables)

// Enhanced Carousel View (mantener igual que antes)
struct EnhancedCarouselView: View {
    let mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    let aspectRatio: CGFloat
    let allMoments: [Moment] // ✅ NUEVO: Todos los momentos del feed
    let currentMoment: Moment // ✅ NUEVO: Momento actual
    
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, item in
                    MediaItemView(
                        item: item,
                        aspectRatio: aspectRatio,
                        allMoments: allMoments, // ✅ PASAR todos los momentos
                        currentMoment: currentMoment // ✅ PASAR momento actual
                    )
                    .tag(index)
                    .frame(width: geometry.size.width)
                    .clipped()
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
    }
}

struct MediaItemView: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let allMoments: [Moment]
    let currentMoment: Moment
    
    @State private var showReelsViewer = false
    
    var body: some View {
        Group {
            if item.type == .image {
                // Imágenes igual que antes
                KFImage(URL(string: item.url))
                    .placeholder {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay(ProgressView().tint(Color(hex: "00A896")))
                            .aspectRatio(aspectRatio, contentMode: .fit)
                    }
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fill)
                    .clipped()
            } else {
                // ✅ VIDEOS: Con crop inteligente para el feed
                CroppedVideoPlayer(
                    item: item,
                    aspectRatio: aspectRatio,
                    currentMoment: currentMoment,
                    onTap: { openReelsViewer() }
                )
            }
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

struct CroppedVideoPlayer: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let currentMoment: Moment
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            // ✅ VIDEO que se reproduce en el feed CON CROP
            ModernVideoPlayer(
                url: item.url,
                aspectRatio: feedDisplayRatio, // ✅ Usar ratio croppado para el feed
                videoId: currentMoment.id ?? "video_\(UUID().uuidString)"
            )
            
            // ✅ OVERLAY invisible para capturar taps
            Button(action: onTap) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // ✅ INDICADORES sutiles
            VStack {
                HStack {
                    Spacer()
                    
                    // Duración del video
                    if let duration = currentMoment.videoDuration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                }
                
                Spacer()
                
                // Indicador sutil de expansión
                HStack {
                    Spacer()
                    
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                }
            }
        }
    }
    
    // ✅ LÓGICA DE CROP: Si es 9:16, mostrar como 4:5 en el feed
    private var feedDisplayRatio: CGFloat {
        if aspectRatio < 0.7 { // Es video vertical (reels 9:16)
            return 0.8 // Mostrar como 4:5 en el feed (crop)
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
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
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
            .shadow(color: colorScheme == .dark ? .black.opacity(0.8) : .white.opacity(0.8), radius: 3, x: 0, y: 1)
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
        attributed.foregroundColor = colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.9)
        
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
    
    // ✅ NUEVO: Queue para sincronización segura de arrays
    private let momentsQueue = DispatchQueue(label: "moments.sync", attributes: .concurrent)
    private let listenersQueue = DispatchQueue(label: "listeners.sync", attributes: .concurrent)

    deinit {
        performCleanup() // Usar la nueva función de cleanup
        print("🗑️ FeedViewModel destruido")
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
        
        // Limpiar listeners anteriores
        clearListeners()
        
        switch targetFeedType {
        case .following:
            fetchFollowingMoments(userId: userId)
        case .forYou:
            fetchForYouMoments(userId: userId)
        }
    }
    
    @MainActor
    func refreshMoments(userId: String) async {
        lastDocument = nil
        clearListeners()
        
        switch currentFeedType {
        case .following:
            followingMoments = []
        case .forYou:
            forYouMoments = []
        }
        
        fetchMoments(userId: userId, feedType: currentFeedType)
        
        // ✅ Esperar a que se complete la operación inicial
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
    }
    
    func loadMoreMoments(userId: String) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
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
                case .failure:
                    DispatchQueue.main.async {
                        self?.isLoadingMore = false
                        self?.errorMessage = "Error cargando más contenido"
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
                
            case .failure:
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.followingMoments = []
                    self?.moments = []
                    self?.errorMessage = "Error cargando contenido"
                }
            }
        }
    }
    
    private func fetchForYouMoments(userId: String) {
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
    
    private func fetchMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let group = DispatchGroup()
        var allMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "moments.fetch.sync")
        let limitPerUser = feedType == .forYou ? 8 : 12
        
        for targetUserId in userIds {
            group.enter()
            
            firestoreService.fetchMoments(for: targetUserId) { result in
                defer { group.leave() }
                
                if case .success(let moments) = result {
                    let limitedMoments = Array(moments.prefix(limitPerUser))
                    
                    self.momentsQueue.async(flags: .barrier) {
                        allMoments.append(contentsOf: limitedMoments)
                    }
                    
                    // Configurar listeners
                    for moment in limitedMoments {
                        if let momentId = moment.id {
                            self.listenForCommentUpdates(momentId: momentId, authorId: targetUserId)
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            let sortedMoments = self.momentsQueue.sync {
                allMoments.sorted { $0.timestamp > $1.timestamp }
            }
            
            let finalMoments = feedType == .forYou ?
                Array(sortedMoments.shuffled().prefix(60)) :
                Array(sortedMoments.prefix(40))
            
            // Aplicar filtros de privacidad
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
                }
            }
        }
    }
    
    private func fetchMoreMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let group = DispatchGroup()
        var newMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "moments.more.sync")
        let limitPerUser = feedType == .forYou ? 8 : 12
        let existingMomentIds = Set(moments.compactMap { $0.id })
        
        for targetUserId in userIds {
            group.enter()
            
            firestoreService.fetchMoments(for: targetUserId) { result in
                defer { group.leave() }
                
                if case .success(let moments) = result {
                    let filteredMoments = moments.filter { moment in
                        guard let momentId = moment.id else { return false }
                        return !existingMomentIds.contains(momentId)
                    }
                    
                    let limitedMoments = Array(filteredMoments.prefix(limitPerUser))
                    
                    self.momentsQueue.async(flags: .barrier) {
                        newMoments.append(contentsOf: limitedMoments)
                    }
                    
                    // Configurar listeners
                    for moment in limitedMoments {
                        if let momentId = moment.id {
                            self.listenForCommentUpdates(momentId: momentId, authorId: targetUserId)
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            let sortedNewMoments = self.momentsQueue.sync {
                newMoments.sorted { $0.timestamp > $1.timestamp }
            }
            
            self.filterMomentsForPrivacy(viewerId: userId, moments: sortedNewMoments) { filteredMoments in
                DispatchQueue.main.async {
                    self.isLoadingMore = false
                    
                    if feedType == .forYou {
                        let shuffledMoments = filteredMoments.shuffled()
                        self.forYouMoments.append(contentsOf: shuffledMoments)
                        self.moments.append(contentsOf: shuffledMoments)
                    } else {
                        self.followingMoments.append(contentsOf: filteredMoments)
                        self.moments.append(contentsOf: filteredMoments)
                    }
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
                
            case .failure:
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
        
        func processBatch(startIndex: Int) {
            let endIndex = min(startIndex + batchSize, moments.count)
            let batch = Array(moments[startIndex..<endIndex])
            
            let group = DispatchGroup()
            var batchResults: [Moment] = []
            let syncQueue = DispatchQueue(label: "batch.results.sync")
            
            for moment in batch {
                guard let momentId = moment.id, !momentId.isEmpty else { continue }
                
                group.enter()
                
                var hasCompleted = false
                let completionQueue = DispatchQueue(label: "completion.control")
                
                privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                    completionQueue.async {
                        if !hasCompleted {
                            hasCompleted = true
                            
                            if canView {
                                syncQueue.sync {
                                    batchResults.append(moment)
                                }
                            }
                            
                            group.leave()
                        }
                    }
                }
                
                // ✅ MEJORADO: Timeout de seguridad con DispatchWorkItem
                let timeoutWorkItem = DispatchWorkItem {
                    completionQueue.async {
                        if !hasCompleted {
                            hasCompleted = true
                            group.leave()
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeoutWorkItem)
            }
            
            group.notify(queue: .main) {
                filteredMoments.append(contentsOf: batchResults)
                
                if endIndex < moments.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        processBatch(startIndex: endIndex)
                    }
                } else {
                    completion(filteredMoments)
                }
            }
        }
        
        processBatch(startIndex: 0)
    }
    
    // MARK: - Listeners
    private func clearListeners() {
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

        // Listener para comentarios (mantener igual)
        let commentListener = firestoreService.db.collection("users").document(authorId)
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
        
        listenersQueue.async(flags: .barrier) {
            self.commentListeners[momentId] = commentListener
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
                        print("❌ Error en listener o documento no existe: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    // ✅ NUEVO: Pausa durante uploads para evitar conflictos
                    if self.isPausedForUploads {
                        print("⏸️ Listener pausado durante upload para: \(momentId)")
                        return
                    }
                    
                    do {
                        // ✅ MEJORADO: Verificación segura de documentID
                        let documentID = document.documentID
                        guard !documentID.isEmpty else {
                            print("❌ Document ID está vacío para momento")
                            return
                        }
                        
                        var updatedMoment = try document.data(as: Moment.self)
                        updatedMoment.id = documentID
                        
                        // ✅ NUEVO: Solo actualizar si hay cambios significativos
                        guard self.shouldUpdateMoment(momentId: momentId, newMoment: updatedMoment) else {
                            print("🔄 Sin cambios significativos para: \(momentId)")
                            return
                        }
                        
                        // ✅ NUEVO: Debounce para agrupar múltiples updates
                        self.debouncedUpdateMoment(momentId: momentId, updatedMoment: updatedMoment)
                        
                    } catch {
                        print("❌ Error decodificando momento \(momentId): \(error)")
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
            print("✅ Cambio detectado en momento \(momentId): hash \(currentHash) → \(newHash)")
            return true
        }
        
        print("🔄 Sin cambios en momento \(momentId) (hash: \(newHash))")
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
        print("⏸️ Pausando listeners durante upload")
        isPausedForUploads = true
        
        // Auto-resume después de 10 segundos (safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.resumeListenersAfterUpload()
        }
    }
    
    // ✅ MEJORADO: Reanudar listeners después de upload
    func resumeListenersAfterUpload() {
        print("▶️ Reanudando listeners después de upload")
        isPausedForUploads = false
    }
    
    // ✅ NUEVO: Función de cleanup mejorada para deinit
    private func performCleanup() {
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
                    self.connections = connections
                }
            }
        }
        
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
        // AnalyticsService.shared.trackFeatureUsage("feed_preference_\(currentPreference.rawValue)")
    }
}
