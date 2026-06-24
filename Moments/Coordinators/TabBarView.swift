import SwiftUI
import FirebaseAuth

private struct EchoInvitationRoute: Identifiable {
    let echoId: String

    var id: String { echoId }
}

private struct NovaTabGlyph: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        NovaBrandIcon(size: size, color: color)
    }
}

// MARK: - Tab Selection Type (iOS 26+)
// Using an enum allows mixing Tab(value:) with Tab(role: .search, value:)
@available(iOS 26.0, *)
enum AppTab: Hashable {
    case home
    case nova
    case create
    case explore
    case profile
}

struct TabBarView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var exploreViewModel = ExploreViewModel()
    @StateObject private var navigationService = NotificationNavigationService.shared
    @StateObject private var firestoreService = FirestoreService.shared
    @State private var selectedTab: Int = 0
    @State private var previousSelectedTab: Int = 0
    @State private var showCreatorView: Bool = false
    @State private var isCreatingStory: Bool = false
    @State private var openCreatorInStoryMode: Bool = false
    @State private var hasPreloadedExplore: Bool = false
    @State private var showEchoInvitation: Bool = false
    @State private var pendingEchoId: String = ""
    @State private var echoInvitationRoute: EchoInvitationRoute?
    @State private var showEchoViewer: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Group {
                if shouldShowMainApp {
                    if #available(iOS 26.0, *) {
                        ModernTabView(
                            selectedTab: $selectedTab,
                            previousSelectedTab: $previousSelectedTab,
                            showCreatorView: $showCreatorView,
                            isCreatingStory: $isCreatingStory,
                            openCreatorInStoryMode: $openCreatorInStoryMode,
                            hasPreloadedExplore: $hasPreloadedExplore,
                            showEchoInvitation: $showEchoInvitation,
                            pendingEchoId: $pendingEchoId,
                            showEchoViewer: $showEchoViewer,
                            exploreViewModel: exploreViewModel,
                            authService: authService,
                            navigationService: navigationService,
                            onEchoInvitationRoute: { echoId in
                                echoInvitationRoute = EchoInvitationRoute(echoId: echoId)
                            }
                        )
                        .overlay(alignment: .top) {
                            InAppBannerView()
                        }
                    } else {
                        legacyTabView
                            .overlay(alignment: .top) {
                                InAppBannerView()
                            }
                    }
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
            .id(authRootIdentity)

            if let route = echoInvitationRoute {
                EchoInvitationView(
                    echoId: route.echoId,
                    onDismiss: {
                        echoInvitationRoute = nil
                        showEchoInvitation = false
                        pendingEchoId = ""
                    },
                    onAccept: { echoId in
                        pendingEchoId = echoId
                        showEchoViewer = true
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1000)
            }
        }
        .offlineBannerOverlay()
        .onAppear {
            if shouldShowMainApp {
                InAppNotificationService.shared.startListing()
            }
        }
        .onChange(of: authRootIdentity) { _, _ in
            if shouldShowMainApp {
                InAppNotificationService.shared.startListing()
            } else {
                InAppNotificationService.shared.stopListening()
            }
        }
        .onOpenURL { url in
            IncognitoModeService.shared.handlePendingAppGroupActionIfNeeded()
            // ✅ Manejar deep links desde el widget y QR (Lógica extraída)
            handleDeepLink(url)
        }
    }

    private var shouldShowMainApp: Bool {
        authService.isLoggedIn && authService.authState == .authenticated
    }

    private var authRootIdentity: String {
        let userId = authService.currentFirebaseUser?.uid ?? "guest"

        switch authService.authState {
        case .loading:
            return "loading-\(userId)"
        case .verifyingAccount:
            return "verifying-\(userId)"
        case .authenticated:
            return "authenticated-\(userId)"
        case .deactivated:
            return "deactivated-\(userId)"
        case .suspended(let reason, let expiresAt):
            return "suspended-\(userId)-\(reason ?? "none")-\(expiresAt?.timeIntervalSince1970 ?? 0)"
        case .unauthenticated:
            return "unauthenticated"
        }
    }
    

// MARK: - Modern Tab View (iOS 26+ — owns @State modernTab: AppTab)
@available(iOS 26.0, *)
struct ModernTabView: View {
    @Binding var selectedTab: Int
    @Binding var previousSelectedTab: Int
    @Binding var showCreatorView: Bool
    @Binding var isCreatingStory: Bool
    @Binding var openCreatorInStoryMode: Bool
    @Binding var hasPreloadedExplore: Bool
    @Binding var showEchoInvitation: Bool
    @Binding var pendingEchoId: String
    @Binding var showEchoViewer: Bool
    @ObservedObject var exploreViewModel: ExploreViewModel
    @ObservedObject var authService: AuthService
    @ObservedObject var navigationService: NotificationNavigationService
    var onEchoInvitationRoute: (String) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    // This struct owns modernTab so @available is not needed on a stored property
    @State private var modernTab: AppTab = .home

    private var tabIconActiveColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }

    private var tabIconInactiveColor: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(hex: "0B1215").opacity(0.62)
    }

    var body: some View {
        TabView(selection: Binding(
            get: { modernTab },
            set: { newTab in
                if newTab == .create {
                    HapticManager.shared.mediumImpact()
                    showCreatorView = true
                    isCreatingStory = true
                } else if newTab == .home && modernTab == .home {
                    HapticManager.shared.lightImpact()
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollFeedToTop"), object: nil)
                } else {
                    HapticManager.shared.selection()
                    modernTab = newTab
                    selectedTab = appTabToInt(newTab)
                    previousSelectedTab = selectedTab
                }
            }
        )) {
            Tab(NSLocalizedString("tabBar.home", comment: ""), systemImage: "house", value: AppTab.home) {
                NavigationStack {
                    FeedView(showCreatorView: $showCreatorView)
                }
                .environmentObject(authService)
            }
            Tab(NSLocalizedString("tabBar.nova", comment: ""), image: "NovaTabIcon", value: AppTab.nova) {
                NovaView()
            }
            Tab("", systemImage: "camera.aperture", value: AppTab.create) {
                Color.clear
            }
            // ✨ Native search tab: expands on tap, minimizes on scroll down with tab bar
            Tab(value: AppTab.explore, role: .search) {
                ExploreView()
                    .environmentObject(exploreViewModel)
            }
            Tab(NSLocalizedString("tabBar.profile", comment: ""), systemImage: "person", value: AppTab.profile) {
                NavigationStack {
                    ProfileView(selectedTab: $selectedTab)
                }
            }
        }
        .tabViewStyle(.automatic)
        .tint(.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
        // TabView nativo solo admite ShapeStyle en toolbarBackground (no View).
        // Tinte canvas alineado al chrome; el glass completo está en legacy CustomTabBar.
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(MomentsChromeGlass.canvasTint(for: colorScheme), for: .tabBar)
        .environmentObject(authService)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showCreatorView) {
            CreatorView(
                isCreatingStory: $isCreatingStory,
                showCreatorView: $showCreatorView,
                initialSticker: nil,
                openInStoryMode: openCreatorInStoryMode
            )
            .onDisappear { openCreatorInStoryMode = false }
        }
        .setupTabBarHandlers(
            selectedTab: $selectedTab,
            previousSelectedTab: $previousSelectedTab,
            showCreatorView: $showCreatorView,
            isCreatingStory: $isCreatingStory,
            openCreatorInStoryMode: $openCreatorInStoryMode,
            hasPreloadedExplore: $hasPreloadedExplore,
            showEchoInvitation: $showEchoInvitation,
            pendingEchoId: $pendingEchoId,
            showEchoViewer: $showEchoViewer,
            exploreViewModel: exploreViewModel,
            navigationService: navigationService,
            onEchoInvitationRoute: onEchoInvitationRoute
        )
        // Keep modernTab in sync when navigationService changes selectedTab
        .onChange(of: selectedTab) { _, newInt in
            modernTab = intToAppTab(newInt)
        }
    }

    private func appTabToInt(_ tab: AppTab) -> Int {
        switch tab {
        case .home:    return 0
        case .nova:    return 1
        case .create:  return 2
        case .explore: return 3
        case .profile: return 4
        }
    }

    private func intToAppTab(_ int: Int) -> AppTab {
        switch int {
        case 0: return .home
        case 1: return .nova
        case 2: return .create
        case 3: return .explore
        case 4: return .profile
        default: return .home
        }
    }
}
    // MARK: - Legacy Tab View (iOS < 26)
    private var legacyTabView: some View {
        ZStack {
            // Contenido principal que se extiende detrás del TabBar
            ZStack {
                switch selectedTab {
                case 0:
                    NavigationStack {
                        FeedView(showCreatorView: $showCreatorView)
                    }
                case 1:
                    NovaView()
                case 2:
                    Color.clear
                case 3:
                    ExploreView()
                        .environmentObject(exploreViewModel)
                case 4:
                    NavigationStack {
                        ProfileView(selectedTab: $selectedTab)
                    }
                default:
                    FeedView(showCreatorView: $showCreatorView)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // TabBar según Human Interface Guidelines de Apple
            // - Ubicada en el borde inferior
            // - Translúcida
            // - Misma altura en todas las orientaciones
            VStack {
                Spacer()
                
                CustomTabBar(selectedTab: $selectedTab, showCreatorView: $showCreatorView, previousSelectedTab: $previousSelectedTab)
                    .frame(height: 49) // Altura estándar según HIG
                    .background {
                        MomentsTabBarChromeBackground()
                    }
            }
        }
        .environmentObject(authService)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .setupTabBarHandlers(
            selectedTab: $selectedTab,
            previousSelectedTab: $previousSelectedTab,
            showCreatorView: $showCreatorView,
            isCreatingStory: $isCreatingStory,
            openCreatorInStoryMode: $openCreatorInStoryMode,
            hasPreloadedExplore: $hasPreloadedExplore,
            showEchoInvitation: $showEchoInvitation,
            pendingEchoId: $pendingEchoId,
            showEchoViewer: $showEchoViewer,
            exploreViewModel: exploreViewModel,
            navigationService: navigationService,
            onEchoInvitationRoute: { echoId in
                echoInvitationRoute = EchoInvitationRoute(echoId: echoId)
            }
        )
    }

    // ✅ NUEVO: Manejador de Deep Links extraído para evitar errores de compilador
    private func handleDeepLink(_ url: URL) {
        // ✅ 1. Manejar esquemas personalizados (moments:// o glowsy://)
        if let scheme = url.scheme, (scheme == "moments" || scheme == "glowsy") {
            handleCustomScheme(url)
            return
        }
        
        // ✅ 2. Manejar Universal Links (https://moments.app o https://momentsapp.app)
        if let scheme = url.scheme, scheme == "https", let host = url.host {
            let normalizedHost = host.lowercased()
            let supportedHosts: Set<String> = [
                "moments.app",
                "www.moments.app",
                "momentsapp.app",
                "www.momentsapp.app"
            ]
            
            if supportedHosts.contains(normalizedHost) {
                handleUniversalLink(url)
                return
            }
        }
    }
    
    private func handleCustomScheme(_ url: URL) {
        let host = url.host
        let path = url.path
        
        if host == "moment", url.pathComponents.count > 1 {
            // glowsy://moment/ID
            let momentId = url.pathComponents[1]
            AppRouter.shared.navigate(to: .moment(id: momentId, authorId: ""))
        } else if host == "story", path == "/create" {
            // Abrir creator en modo historia
            openCreatorInStoryMode = true
            showCreatorView = true
            isCreatingStory = true
        } else if url.host == "profile" {
            // Manejo de perfiles
            if url.path == "/visits" {
                // Abrir perfil propio y mostrar visitas
                selectedTab = 4
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    AppRouter.shared.navigate(to: .showProfileVisits)
                }
            } else if url.pathComponents.count > 1 {
                // Es un perfil de usuario: glowsy://profile/username
                let username = url.lastPathComponent
                
                // Resolver ID de usuario y navegar
                firestoreService.fetchUserByUsername(username) { result in
                    switch result {
                    case .success(let user):
                        DispatchQueue.main.async {
                            AppRouter.shared.navigate(to: .showUserProfile(userId: user.id))
                        }
                    case .failure(let error):
                        AppLog.debug("Error resolving username from deep link: \(error.localizedDescription)")
                    }
                }
            }
        } else if url.host == "messages" {
            // Abrir mensajes
            AppRouter.shared.navigate(to: .showMessages)
        } else if url.host == "notifications" {
            // Abrir notificaciones
            AppRouter.shared.navigate(to: .showNotifications)
        } else if host == "stories" {
            // Abrir feed y mostrar historias
            AppRouter.shared.navigate(to: .showStories)
        } else if host == "incognito", path == "/pause" {
            IncognitoModeService.shared.pauseFromLiveActivity()
        }
    }
    
    private func handleUniversalLink(_ url: URL) {
        let pathComponents = url.pathComponents
        
        // Formato esperado: https://moments.app/moment/ID o https://momentsapp.app/moment/ID
        if pathComponents.count >= 3 && pathComponents[1] == "moment" {
            let momentId = pathComponents[2]
            
            // Navegar al momento
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppRouter.shared.navigate(to: .moment(id: momentId, authorId: ""))
            }
        }
    }
}

// MARK: - Custom Tab Bar según Human Interface Guidelines
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatorView: Bool
    @Binding var previousSelectedTab: Int
    @Environment(\.colorScheme) var colorScheme
    
    // Colores según HIG: activo usa el color del sistema, inactivo con opacidad
    private var activeColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }
    
    private var inactiveColor: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(hex: "0B1215").opacity(0.62)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Tab 0: Home
            TabBarItem(
                icon: "house",
                title: NSLocalizedString("tabBar.home", comment: "Home tab title"),
                isSelected: selectedTab == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                usesSystemIcon: true
            ) {
                if selectedTab == 0 {
                    // ✅ NUEVO: Si ya está en Home, scroll al inicio y refrescar
                    HapticManager.shared.lightImpact()
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollFeedToTop"), object: nil)
                } else {
                    HapticManager.shared.selection()
                    selectedTab = 0
                }
            }
            
            // Tab 1: Nova
            TabBarItem(
                icon: "NovaTabIcon",
                title: NSLocalizedString("tabBar.nova", comment: "Nova tab title"),
                isSelected: selectedTab == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                usesSystemIcon: false
            ) {
                HapticManager.shared.selection()
                selectedTab = 1
            }
            
            // Botón central de crear integrado en la tab bar
            CreateButton(
                showCreatorView: $showCreatorView,
                selectedTab: $selectedTab,
                previousSelectedTab: $previousSelectedTab
            )
            .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: selectedTab), value: selectedTab)
            
            // Tab 3: Explore
            TabBarItem(
                icon: "magnifyingglass",
                title: NSLocalizedString("tabBar.explore", comment: "Explore tab title"),
                isSelected: selectedTab == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                usesSystemIcon: true
            ) {
                HapticManager.shared.selection()
                selectedTab = 3
            }
            
            // Tab 4: Profile
            TabBarItem(
                icon: "person",
                title: NSLocalizedString("tabBar.profile", comment: "Profile tab title"),
                isSelected: selectedTab == 4,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                usesSystemIcon: true
            ) {
                HapticManager.shared.selection()
                selectedTab = 4
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8) // Padding vertical según HIG
    }
}

// MARK: - Tab Bar Item según Human Interface Guidelines
struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let activeColor: Color
    let inactiveColor: Color
    let usesSystemIcon: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icono: tamaño estándar según HIG
                Group {
                    if usesSystemIcon {
                        Image(systemName: icon)
                            .symbolVariant(isSelected ? .fill : .none)
                            .foregroundColor(isSelected ? activeColor : inactiveColor)
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    } else {
                        NovaTabGlyph(
                            size: 22,
                            color: isSelected ? activeColor : inactiveColor
                        )
                    }
                }
                
                // Etiqueta: siempre visible según HIG
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? activeColor : inactiveColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) // Área de toque completa según HIG
        }
        .buttonStyle(.momentsPress(haptic: .none))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Create Button (Botón central personalizado)
struct CreateButton: View {
    @Binding var showCreatorView: Bool
    @Binding var selectedTab: Int
    @Binding var previousSelectedTab: Int
    @Environment(\.colorScheme) var colorScheme
    
    private var gradientColors: [Color] {
        colorScheme == .dark ?
        [Color(hex: "6B73FF"), Color(hex: "9B59B6")] :
        [Color(hex: "007AFF"), Color(hex: "5856D6")]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            showCreatorView = true
            DispatchQueue.main.async {
                selectedTab = previousSelectedTab
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 32)
                    .shadow(
                        color: gradientColors[0].opacity(0.3),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
                
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.momentsPress(scale: 0.92, haptic: .none))
        .accessibilityLabel(Text("tabBar.create"))
    }
}

// MARK: - Extension para handlers compartidos
extension View {
    func setupTabBarHandlers(
        selectedTab: Binding<Int>,
        previousSelectedTab: Binding<Int>,
        showCreatorView: Binding<Bool>,
        isCreatingStory: Binding<Bool>,
        openCreatorInStoryMode: Binding<Bool>,
        hasPreloadedExplore: Binding<Bool>,
        showEchoInvitation: Binding<Bool>,
        pendingEchoId: Binding<String>,
        showEchoViewer: Binding<Bool>,
        exploreViewModel: ExploreViewModel,
        navigationService: NotificationNavigationService,
        onEchoInvitationRoute: @escaping (String) -> Void = { _ in }
    ) -> some View {
        let appRouter = AppRouter.shared
        return self
            .onAppear {
                previousSelectedTab.wrappedValue = selectedTab.wrappedValue
                if (Auth.auth().currentUser?.uid) != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !hasPreloadedExplore.wrappedValue {
                            exploreViewModel.fetchMomentsByInterests()
                            hasPreloadedExplore.wrappedValue = true
                        }
                    }
                }
                
                FCMTokenService.shared.updateFCMToken()
            }
            .onChange(of: selectedTab.wrappedValue) { _, newSelection in
                if newSelection == 3 && !hasPreloadedExplore.wrappedValue {
                    exploreViewModel.fetchMomentsByInterests()
                    hasPreloadedExplore.wrappedValue = true
                }
                
                if newSelection == 2 {
                    showCreatorView.wrappedValue = true
                    isCreatingStory.wrappedValue = true
                    DispatchQueue.main.async {
                        selectedTab.wrappedValue = previousSelectedTab.wrappedValue
                    }
                } else {
                    previousSelectedTab.wrappedValue = newSelection
                }
            }
            .onChange(of: appRouter.pending) { _, pending in
                guard pending != nil else { return }
                appRouter.dispatchPending(
                    using: AppRouterTabBarContext(
                        selectedTab: selectedTab,
                        showCreatorView: showCreatorView,
                        pendingEchoId: pendingEchoId,
                        showEchoInvitation: showEchoInvitation,
                        showEchoViewer: showEchoViewer,
                        onEchoInvitationRoute: onEchoInvitationRoute
                    )
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfile"))) { notification in
                if let userId = notification.object as? String {
                    appRouter.navigate(to: .profile(userId: userId))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToOwnProfileTab"))) { _ in
                selectedTab.wrappedValue = 4
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfile"))) { notification in
                if let userId = notification.object as? String {
                    selectedTab.wrappedValue = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: userId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowStoryChain"))) { notification in
                if let userInfo = notification.userInfo,
                   let chainId = userInfo["chainId"] as? String,
                   let chainTitle = userInfo["chainTitle"] as? String {
                    selectedTab.wrappedValue = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToStoryChainInFeed"),
                            object: nil,
                            userInfo: ["chainId": chainId, "chainTitle": chainTitle]
                        )
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReturnToFeedAfterMomentPublish"))) { _ in
                previousSelectedTab.wrappedValue = 0
                selectedTab.wrappedValue = 0
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCreatorForChain"))) { notification in
                if let userInfo = notification.userInfo,
                   let chainId = userInfo["chainId"] as? String,
                   let chainTitle = userInfo["chainTitle"] as? String,
                   let chainPosition = userInfo["chainPosition"] as? Int {
                    showCreatorView.wrappedValue = true
                    isCreatingStory.wrappedValue = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SetContentType"),
                            object: nil,
                            userInfo: ["contentType": "story"]
                        )
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SetChainContext"),
                            object: nil,
                            userInfo: [
                                "chainId": chainId,
                                "chainTitle": chainTitle,
                                "chainPosition": chainPosition
                            ]
                        )
                    }
                }
            }
            .fullScreenCover(isPresented: showCreatorView) {
                CreatorView(
                    isCreatingStory: isCreatingStory,
                    showCreatorView: showCreatorView,
                    initialSticker: nil,
                    openInStoryMode: openCreatorInStoryMode.wrappedValue
                )
                .onDisappear {
                    // ✅ Resetear el flag cuando se cierra el creator
                    openCreatorInStoryMode.wrappedValue = false
                }
            }
            .fullScreenCover(isPresented: showEchoViewer) {
                if !pendingEchoId.wrappedValue.isEmpty {
                    EchoViewerUI(echoId: pendingEchoId.wrappedValue)
                }
            }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TabBarView()
                .environmentObject(AuthService())
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            TabBarView()
                .environmentObject(AuthService())
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            }
    }
}
