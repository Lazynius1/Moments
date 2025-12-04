import SwiftUI


@main
struct GlowsyApp: App {
    // AppDelegate adaptado para Android en Skip
    @StateObject var ephemeralCleanupManager = EphemeralCleanupManager()
    @StateObject var cacheManager = CacheManager.shared
    @State var showSplash = true

    // Agregar una propiedad para almacenar el listener de autenticación
    @State var authListenerHandle: AuthStateDidChangeListenerHandle?
    @State var didPostLaunchInit = false

    init() {
        FirebaseApp.configure()

        // Android: Firestore settings will be configured natively
        // Skip will transpile this to use Android Firebase SDK
        /*
        let settings = FirestoreSettings()
        // ✅ LÍMITE FIREBASE: 100MB máximo para cache persistente
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB max para Firebase
        )
        Firestore.firestore().settings = settings
        */

        // AdMob y caches se inicializan después del primer frame
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreenView()
                        .onAppear {
                            // Permisos de ubicación pospuestos hasta uso real
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showSplash = false
                                }
                            }
                        }
                } else {
                    TabBarView()
                        .environmentObject(ephemeralCleanupManager)
                        .environmentObject(MessageRequestService())
                        .onAppear {
                            
                            // Post-launch initializations (una sola vez)
                            if !didPostLaunchInit {
                                didPostLaunchInit = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    // Inicializar AdMob tras primer frame
                                    AdMobConfiguration.shared.initialize()
                                    
                                    // Configurar caches con tamaños más moderados
                                    let memoryCapacity = 20 * 1024 * 1024
                                    let diskCapacity = 150 * 1024 * 1024  // ✅ AJUSTADO: 150MB (más conservador)
                                    let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "imageCache")
                                    URLCache.shared = cache
                                    
                                    // Kingfisher no disponible en Android - usando URLCache en su lugar
                                    // URLCache ya configurado arriba
                                }
                            }
                            
                            // ✅ Configurar listener de autenticación
                            authListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
                                if user != nil {
                                    // Usuario logueado - configurar badge service
                                    NotificationBadgeService.shared.setupListeners()
                                } else {
                                    // Usuario deslogueado - limpiar todo
                                    NotificationBadgeService.shared.cleanup()
                                }
                            }
                        }
                        .onDisappear {
                            // ✅ Limpiar el listener de autenticación cuando la escena desaparezca
                            if let handle = authListenerHandle {
                                Auth.auth().removeStateDidChangeListener(handle)
                            }
                        }
                        // UIApplication notifications no disponibles en Android
                        // Se manejarán a través de lifecycle de Android
                        // .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        //     AnalyticsService.shared.applicationDidBecomeActive()
                        // }
                        // .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        //     AnalyticsService.shared.applicationWillResignActive()
                        // }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMoment"))) { notification in
                            if let momentId = notification.object as? String {
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToProfile"))) { notification in
                            if let userId = notification.object as? String {
                                // En lugar de mostrar sheet, enviar a TabBarView para manejar
                                NotificationCenter.default.post(name: NSNotification.Name("ShowUserProfile"), object: userId)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConversation"))) { notification in
                            if let conversationId = notification.object as? String {
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToStoryChain"))) { notification in
                            if let userInfo = notification.userInfo,
                               let chainId = userInfo["chainId"] as? String,
                               let chainTitle = userInfo["chainTitle"] as? String {
                                // Enviar a TabBarView para manejar la navegación a Story Chain
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("ShowStoryChain"), 
                                    object: nil,
                                    userInfo: ["chainId": chainId, "chainTitle": chainTitle]
                                )
                            }
                        }

                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }
}
