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
    @State private var showSplash = true

    // Agregar una propiedad para almacenar el listener de autenticación
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?

    init() {
        FirebaseApp.configure()
        print("Firebase inicializado")

        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        print("Firestore configurado con cacheSettings: \(settings.cacheSettings)")

        AdMobConfiguration.shared.initialize()

        let memoryCapacity = 100 * 1024 * 1024
        let diskCapacity = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "imageCache")
        URLCache.shared = cache
        print("URLCache configurado: \(memoryCapacity / 1024 / 1024) MB en memoria, \(diskCapacity / 1024 / 1024) MB en disco")

        let kingfisherCache = KingfisherManager.shared.cache
        kingfisherCache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        kingfisherCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        kingfisherCache.diskStorage.config.expiration = StorageExpiration.date(Date().addingTimeInterval(7 * 24 * 60 * 60))
        print("Kingfisher configurado: 100 MB en memoria, 500 MB en disco, caducidad de 7 días")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreenView()
                        .onAppear {
                            LocationUtilities.shared.requestLocationPermission()
                            RealLoginActivityService.shared.requestLocationPermission()
                            print("🚀 Servicios inicializados durante SplashScreen")
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                } else {
                    TabBarView()
                        .environmentObject(ephemeralCleanupManager)
                        .onAppear {
                            print("🚀 Sistema de limpieza de mensajes efímeros iniciado")
                            print("📍 Servicios de ubicación configurados")
                            
                            // ✅ Configurar listener de autenticación
                            authListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
                                if user != nil {
                                    // Usuario logueado - configurar badge service
                                    NotificationBadgeService.shared.setupListeners()
                                    print("🔔 Auth: Usuario logueado, configurando NotificationBadgeService")
                                } else {
                                    // Usuario deslogueado - limpiar todo
                                    NotificationBadgeService.shared.cleanup()
                                    print("🧹 Auth: Usuario deslogueado, limpiando NotificationBadgeService")
                                }
                            }
                        }
                        .onDisappear {
                            // ✅ Limpiar el listener de autenticación cuando la escena desaparezca
                            if let handle = authListenerHandle {
                                Auth.auth().removeStateDidChangeListener(handle)
                                print("🧹 Auth: Listener de autenticación removido")
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            AnalyticsService.shared.applicationDidBecomeActive()
                            print("📊 Sesión de analytics iniciada")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                            AnalyticsService.shared.applicationWillResignActive()
                            print("📊 Sesión de analytics finalizada")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMoment"))) { notification in
                            if let momentId = notification.object as? String {
                                print("🔔 Navegar a momento desde notificación: \(momentId)")
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToProfile"))) { notification in
                            if let userId = notification.object as? String {
                                print("🔔 Navegar a perfil desde notificación: \(userId)")
                                // En lugar de mostrar sheet, enviar a TabBarView para manejar
                                NotificationCenter.default.post(name: NSNotification.Name("ShowUserProfile"), object: userId)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConversation"))) { notification in
                            if let conversationId = notification.object as? String {
                                print("🔔 Navegar a conversación desde notificación: \(conversationId)")
                            }
                        }

                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }
}
