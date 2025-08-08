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
    @State private var hasPreloadedExplore: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if authService.isLoggedIn {
            VStack(spacing: 0) {
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

                CustomTabBar(selectedTab: $selectedTab)
                    .background(
                        (colorScheme == .dark ?
                         Color.black.opacity(0.95) :
                         Color.white.opacity(0.95))
                            .edgesIgnoringSafeArea(.bottom)
                            .blur(radius: 10)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                        Color.gray.opacity(0.3) :
                                        Color.gray.opacity(0.2)
                                    ),
                                alignment: .top
                            )
                    )
            }
            .environmentObject(authService)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                self.previousSelectedTab = self.selectedTab
                if let userId = Auth.auth().currentUser?.uid {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !hasPreloadedExplore {
                            exploreViewModel.fetchMomentsByInterestsWithTrending()
                            hasPreloadedExplore = true
                            print("🚀 Explore pre-cargado en background")
                        }
                    }
                }
                
                // ✅ Actualizar FCM token al aparecer la app principal
                FCMTokenService.shared.updateFCMToken()
            }
            .onChange(of: selectedTab) { newSelection in
                if newSelection == 3 && !hasPreloadedExplore {
                    exploreViewModel.fetchMomentsByInterestsWithTrending()
                    hasPreloadedExplore = true
                    print("🚀 Explore cargado al hacer tap")
                }
                
                if newSelection == 2 {
                    self.showCreatorView = true
                    self.isCreatingStory = true
                    DispatchQueue.main.async {
                        self.selectedTab = self.previousSelectedTab
                    }
                } else {
                    self.previousSelectedTab = newSelection
                }
            }
            // ✅ Manejar navegación desde notificaciones
            .onChange(of: navigationService.pendingNavigation) { navigation in
                handlePendingNavigation(navigation)
            }
            // ✅ Manejar navegación desde stickers de mención
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfile"))) { notification in
                if let userId = notification.object as? String {
                    print("🔔 Navegación desde sticker de mención a usuario: \(userId)")
                    navigationService.pendingNavigation = .profile(userId)
                }
            }
            // ✅ Manejar navegación directa a perfil
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfile"))) { notification in
                if let userId = notification.object as? String {
                    print("🔔 Mostrando perfil de usuario: \(userId)")
                    selectedTab = 0 // Ir al feed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: userId)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCreatorView) {
                CreatorView(isCreatingStory: $isCreatingStory, showCreatorView: $showCreatorView, initialSticker: nil)
            }
        } else {
            LoginView()
                .environmentObject(authService)
        }
    }
    
    // ✅ SIMPLIFICADO: Función para manejar navegación desde notificaciones
    private func handlePendingNavigation(_ navigation: NotificationNavigationService.PendingNavigation?) {
        guard let navigation = navigation else { return }
        
        print("🔔 Procesando navegación pendiente: \(navigation.description)")
        
        switch navigation {
        case .moment(let momentId):
            print("🔔 Navegando a momento: \(momentId)")
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToMoment"), object: momentId)
            
        case .profile(let userId):
            print("🔔 Navegando a perfil: \(userId)")
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToProfile"), object: userId)
            
        case .conversation(let conversationId):
            print("🔔 Navegando a conversación: \(conversationId)")
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToConversation"), object: conversationId)
            
        case .story(let storyId):
            print("🔔 Navegando a historia: \(storyId)")
            selectedTab = 0
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToStory"), object: storyId)
            
        case .followRequests(let requestId):
            print("🔔 Navegando a solicitudes de seguimiento: \(requestId)")
            selectedTab = 4
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToFollowRequests"), object: requestId)
            
        case .notifications(let filter):
            print("🔔 Navegando a notificaciones con filtro: \(filter ?? "ninguno")")
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

// MARK: - Custom Tab Bar Adaptativo (sin cambios)
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) var colorScheme
    
    private var activeColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var inactiveColor: Color {
        colorScheme == .dark ? .gray : .gray
    }
    
    private var gradientColors: [Color] {
        colorScheme == .dark ?
        [Color(hex: "6B73FF"), Color(hex: "9B59B6")] :
        [Color(hex: "007AFF"), Color(hex: "5856D6")]
    }
    
    var body: some View {
        HStack {
            TabBarItem(
                icon: "house",
                title: "Home",
                isSelected: selectedTab == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 0
            }
            
            TabBarItem(
                icon: "star",
                title: "Nova",
                isSelected: selectedTab == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 1
            }
            
            Button(action: {
                selectedTab = 2
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 50, height: 36)
                        .shadow(
                            color: gradientColors[0].opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                    
                    Image(systemName: "plus")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            
            TabBarItem(
                icon: "magnifyingglass",
                title: "Explorar",
                isSelected: selectedTab == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 3
            }
            
            TabBarItem(
                icon: "person",
                title: "Perfil",
                isSelected: selectedTab == 4,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                selectedTab = 4
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Tab Bar Item Adaptativo (sin cambios)
struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let activeColor: Color
    let inactiveColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? activeColor : inactiveColor)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? activeColor : inactiveColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .opacity(isSelected ? 1.0 : 0.7)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
