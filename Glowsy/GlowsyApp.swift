import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth // Añadir este import
import Kingfisher
import GoogleMobileAds

@main
struct GlowsyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var ephemeralCleanupManager = EphemeralCleanupManager()
    @StateObject private var cacheManager = CacheManager.shared
    @State private var showSplash = true

    // Agregar una propiedad para almacenar el listener de autenticación
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?
    @State private var didPostLaunchInit = false

    init() {
        FirebaseApp.configure()

        let settings = FirestoreSettings()
        // ✅ LÍMITE FIREBASE: 100MB máximo para cache persistente
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB max para Firebase
        )
        Firestore.firestore().settings = settings

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
                                    
                                    let kingfisherCache = KingfisherManager.shared.cache
                                    kingfisherCache.memoryStorage.config.totalCostLimit = 20 * 1024 * 1024
                                    kingfisherCache.diskStorage.config.sizeLimit = 150 * 1024 * 1024  // ✅ AJUSTADO: 150MB (más conservador)
                                    kingfisherCache.diskStorage.config.expiration = StorageExpiration.days(1)  // ✅ MÁS AGRESIVO: 1 día en lugar de 3
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
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            AnalyticsService.shared.applicationDidBecomeActive()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                            AnalyticsService.shared.applicationWillResignActive()
                        }
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

                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }
}
