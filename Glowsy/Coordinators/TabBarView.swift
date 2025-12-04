import SwiftUI
import FirebaseAuth

struct TabBarView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var exploreViewModel = ExploreViewModel()
    @StateObject private var navigationService = NotificationNavigationService.shared
    @State private var selectedTab: Int = 0
    @State private var previousSelectedTab: Int = 0
    @State private var showCreatorView: Bool = false
    @State private var isCreatingStory: Bool = false
    @State private var openCreatorInStoryMode: Bool = false // ✅ Para abrir desde widget en modo historia
    @State private var hasPreloadedExplore: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if authService.isLoggedIn {
                if #available(iOS 26.0, *) {
                    // Nueva API iOS 26 con efecto Liquid Glass y gota de agua nativo
                    modernTabView
                } else {
                    // Implementación legacy para versiones anteriores
                    legacyTabView
                }
            } else {
                LoginView()
                    .environmentObject(authService)
            }
        }
        .onOpenURL { url in
            // ✅ Manejar deep links desde el widget
            guard url.scheme == "moments" else { return }
            
            if url.host == "story", url.path == "/create" {
                // Abrir creator en modo historia
                openCreatorInStoryMode = true
                showCreatorView = true
                isCreatingStory = true
            } else if url.host == "profile", url.path == "/visits" {
                // Abrir perfil y mostrar visitas
                selectedTab = 4
                // ✅ Delay para asegurar que ProfileView esté cargado antes de mostrar el sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowProfileVisits"), object: nil)
                }
            } else if url.host == "messages" {
                // Abrir mensajes
                NotificationCenter.default.post(name: NSNotification.Name("ShowMessages"), object: nil)
            } else if url.host == "notifications" {
                // Abrir notificaciones
                NotificationCenter.default.post(name: NSNotification.Name("ShowNotifications"), object: nil)
            } else if url.host == "stories" {
                // Abrir feed y mostrar historias
                selectedTab = 0
                NotificationCenter.default.post(name: NSNotification.Name("ShowStories"), object: nil)
            }
        }
    }
    
    // MARK: - Modern Tab View (iOS 26+ con Liquid Glass)
    @available(iOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 2 {
                    // Si se selecciona el tab de crear, abrir CreatorView
                    showCreatorView = true
                    isCreatingStory = true
                    // Mantener el tab anterior seleccionado visualmente
                    selectedTab = previousSelectedTab
                } else if newValue == 0 && selectedTab == 0 {
                    // ✅ NUEVO: Si se toca Home cuando ya está seleccionado, scroll al inicio y refrescar
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollFeedToTop"), object: nil)
                } else {
                    selectedTab = newValue
                    previousSelectedTab = newValue
                }
            }
        )) {
            // Tab 0: Feed
            Tab(NSLocalizedString("tabBar.home", comment: "Home tab title"), systemImage: "house", value: 0) {
                FeedView(showCreatorView: $showCreatorView)
                    .environmentObject(authService)
            }
            
            // Tab 1: Nova
            Tab(NSLocalizedString("tabBar.nova", comment: "Nova tab title"), systemImage: "star", value: 1) {
                GeminiView()
            }
            
            // Tab 2: Create (abre CreatorView)
            Tab("", systemImage: "camera.fill", value: 2) {
                Color.clear
            }
            
            // Tab 3: Explore
            Tab(NSLocalizedString("tabBar.explore", comment: "Explore tab title"), systemImage: "magnifyingglass", value: 3) {
                ExploreView()
                    .environmentObject(exploreViewModel)
            }
            
            // Tab 4: Profile
            Tab(NSLocalizedString("tabBar.profile", comment: "Profile tab title"), systemImage: "person", value: 4) {
                ProfileView(selectedTab: $selectedTab)
            }
        }
        .tabViewStyle(.automatic)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(authService)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showCreatorView) {
            CreatorView(
                isCreatingStory: $isCreatingStory,
                showCreatorView: $showCreatorView,
                initialSticker: nil,
                openInStoryMode: openCreatorInStoryMode
            )
            .onDisappear {
                // ✅ Resetear el flag cuando se cierra el creator
                openCreatorInStoryMode = false
            }
        }
        .setupTabBarHandlers(
            selectedTab: $selectedTab,
            previousSelectedTab: $previousSelectedTab,
            showCreatorView: $showCreatorView,
            isCreatingStory: $isCreatingStory,
            openCreatorInStoryMode: $openCreatorInStoryMode,
            hasPreloadedExplore: $hasPreloadedExplore,
            exploreViewModel: exploreViewModel,
            navigationService: navigationService
        )
    }
    
    // MARK: - Legacy Tab View (iOS < 26)
    private var legacyTabView: some View {
        ZStack {
            // Contenido principal que se extiende detrás del TabBar
            ZStack {
                switch selectedTab {
                case 0:
                    FeedView(showCreatorView: $showCreatorView)
                case 1:
                    GeminiView()
                case 2:
                    Color.clear
                case 3:
                    ExploreView()
                        .environmentObject(exploreViewModel)
                case 4:
                    ProfileView(selectedTab: $selectedTab)
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
                    .background(
                        // Material translúcido según HIG
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .edgesIgnoringSafeArea(.bottom)
                            .overlay(
                                // Borde superior sutil
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                        Color.white.opacity(0.1) :
                                        Color.black.opacity(0.1)
                                    ),
                                alignment: .top
                            )
                    )
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
            exploreViewModel: exploreViewModel,
            navigationService: navigationService
        )
    }
    
    // ✅ SIMPLIFICADO: Función para manejar navegación desde notificaciones
    private func handlePendingNavigation(_ navigation: NotificationNavigationService.PendingNavigation?) {
        guard let navigation = navigation else { return }
        
        switch navigation {
        case .moment(let momentId):
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToMoment"), object: momentId)
            
        case .profile(let userId):
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToProfile"), object: userId)
            
        case .conversation(let conversationId):
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToConversation"), object: conversationId)
            
        case .story(let storyId):
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToStory"), object: storyId)
            
        case .storyChain(let chainId, let chainTitle):
            selectedTab = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToStoryChain"), 
                object: nil,
                userInfo: ["chainId": chainId, "chainTitle": chainTitle]
            )
            
        case .followRequests(let requestId):
            selectedTab = 4
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToFollowRequests"), object: requestId)
            
        case .notifications(let filter):
            selectedTab = 4
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToNotifications"), object: filter)
        }
        
        // ✅ Limpiar navegación pendiente
        navigationService.clearPendingNavigation()
        
        // ✅ Analytics para tracking de navegación desde notificaciones
        AnalyticsService.shared.trackInteraction(
            "notification_navigation",
            details: [
                "type": navigation.category,
                "source": "push_notification"
            ]
        )
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
        colorScheme == .dark ? .white : .black
    }
    
    private var inactiveColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
    }
    
    private var gradientColors: [Color] {
        colorScheme == .dark ?
        [Color(hex: "6B73FF"), Color(hex: "9B59B6")] :
        [Color(hex: "007AFF"), Color(hex: "5856D6")]
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Tab 0: Home
            TabBarItem(
                icon: "house",
                title: NSLocalizedString("tabBar.home", comment: "Home tab title"),
                isSelected: selectedTab == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                if selectedTab == 0 {
                    // ✅ NUEVO: Si ya está en Home, scroll al inicio y refrescar
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollFeedToTop"), object: nil)
                } else {
                    selectedTab = 0
                }
            }
            
            // Tab 1: Nova
            TabBarItem(
                icon: "star",
                title: NSLocalizedString("tabBar.nova", comment: "Nova tab title"),
                isSelected: selectedTab == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 1
            }
            
            // Botón central de crear integrado en la tab bar
            CreateButton(
                showCreatorView: $showCreatorView,
                selectedTab: $selectedTab,
                previousSelectedTab: $previousSelectedTab
            )
            .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            
            // Tab 3: Explore
            TabBarItem(
                icon: "magnifyingglass",
                title: NSLocalizedString("tabBar.explore", comment: "Explore tab title"),
                isSelected: selectedTab == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 3
            }
            
            // Tab 4: Profile
            TabBarItem(
                icon: "person",
                title: NSLocalizedString("tabBar.profile", comment: "Profile tab title"),
                isSelected: selectedTab == 4,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icono: tamaño estándar según HIG
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? activeColor : inactiveColor)
                    .symbolVariant(isSelected ? .fill : .none)
                
                // Etiqueta: siempre visible según HIG
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? activeColor : inactiveColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) // Área de toque completa según HIG
        }
        .buttonStyle(PlainButtonStyle()) // Estilo plano para mejor control
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
        exploreViewModel: ExploreViewModel,
        navigationService: NotificationNavigationService
    ) -> some View {
        self
            .onAppear {
                previousSelectedTab.wrappedValue = selectedTab.wrappedValue
                if let userId = Auth.auth().currentUser?.uid {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !hasPreloadedExplore.wrappedValue {
                            exploreViewModel.fetchMomentsByInterestsWithTrending()
                            hasPreloadedExplore.wrappedValue = true
                        }
                    }
                }
                
                FCMTokenService.shared.updateFCMToken()
            }
            .onChange(of: selectedTab.wrappedValue) { newSelection in
                if newSelection == 3 && !hasPreloadedExplore.wrappedValue {
                    exploreViewModel.fetchMomentsByInterestsWithTrending()
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
            .onChange(of: navigationService.pendingNavigation) { navigation in
                if let navigation = navigation {
                    switch navigation {
                    case .moment(let momentId):
                        selectedTab.wrappedValue = 0
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToMoment"), object: momentId)
                        
                    case .profile(let userId):
                        selectedTab.wrappedValue = 0
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToProfile"), object: userId)
                        
                    case .conversation(let conversationId):
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToConversation"), object: conversationId)
                        
                    case .story(let storyId):
                        selectedTab.wrappedValue = 0
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToStory"), object: storyId)
                        
                    case .storyChain(let chainId, let chainTitle):
                        selectedTab.wrappedValue = 0
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToStoryChain"), 
                            object: nil,
                            userInfo: ["chainId": chainId, "chainTitle": chainTitle]
                        )
                        
                    case .followRequests(let requestId):
                        selectedTab.wrappedValue = 4
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToFollowRequests"), object: requestId)
                        
                    case .notifications(let filter):
                        selectedTab.wrappedValue = 4
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToNotifications"), object: filter)
                    }
                    
                    navigationService.clearPendingNavigation()
                    
                    AnalyticsService.shared.trackInteraction(
                        "notification_navigation",
                        details: [
                            "type": navigation.category,
                            "source": "push_notification"
                        ]
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfile"))) { notification in
                if let userId = notification.object as? String {
                    navigationService.pendingNavigation = .profile(userId)
                }
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
