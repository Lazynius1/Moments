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
    @StateObject private var offlineSyncService = OfflineSyncService.shared
    @State private var showSplash = true
    @State private var showWhatsNew = false
    @AppStorage("lastVersionPrompted") private var lastVersionPrompted: String = "1.0.0"
    @AppStorage("lastAppOpenSyncAt") private var lastAppOpenSyncAt: Double = 0

    // Agregar una propiedad para almacenar el listener de autenticación
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?
    @State private var didPostLaunchInit = false

    init() {
        FirebaseApp.configure()

        // Bootstrap global time tracking so Time Spent and Daily Limit work
        // without requiring the user to open the Time Spent screens first.
        _ = TimeSpentManager.shared

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
                                OfflineSyncService.shared.enableAutomaticSync()

                                Task {
                                    await BackgroundMomentUploadService.shared.cleanupStaleUploadActivities()
                                    await BackgroundStoryUploadService.shared.cleanupStaleUploadActivities()
                                }

                                // Configurar caches con tamaños más moderados
                                let memoryCapacity = 20 * 1024 * 1024
                                let diskCapacity = 500 * 1024 * 1024  // ✅ AJUSTADO: 500MB (Estándar moderno)
                                let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "imageCache")
                                URLCache.shared = cache

                                let kingfisherCache = KingfisherManager.shared.cache
                                kingfisherCache.memoryStorage.config.totalCostLimit = 20 * 1024 * 1024
                                kingfisherCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024  // ✅ AJUSTADO: 500MB (Estándar moderno)
                                kingfisherCache.diskStorage.config.expiration = StorageExpiration.days(7)  // ✅ ALINEADO CON SWIFTDATA: 7 días de persistencia

                                // ✅ SwiftData: Limpiar datos locales antiguos (>7 días)
                                Task { @MainActor in
                                    LocalPersistenceService.shared.cleanupOldData()

                                    // Configure AffinityTracker with the shared SwiftData container
                                    if let container = LocalPersistenceService.shared.container {
                                        AffinityTracker.shared.setup(container: container)
                                        AffinityTracker.shared.applyTimeDecayIfNeeded()
                                        AffinityTracker.shared.cleanupVeryLowAffinities()
                                    }
                                }
                            }
                        }

                        // ✅ Configurar listener de autenticación
                        authListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
                            if user != nil {
                                // Usuario logueado - configurar badge service
                                NotificationBadgeService.shared.setupListeners()
                                syncLastAppOpenIfNeeded(force: true)
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
                        // ✅ NUEVO: Marcar mensajes pendientes como entregados (respaldo si notificación no llegó)
                        ChatService.shared.markAllPendingMessagesAsDelivered()

                        // ✅ WIDGET FIX: Forzar actualización del widget al abrir la app
                        NotificationBadgeService.shared.refreshAllCounts()
                        syncLastAppOpenIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
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

                if showSplash {
                    SplashScreenView {
                        showSplash = false
                        checkVersion()
                    }
                    .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func checkVersion() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.9.0"

        if lastVersionPrompted != currentVersion {
            // Esperar un poco para que la transición del splash termine
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showWhatsNew = true
                lastVersionPrompted = currentVersion
            }
        }
    }

    private func syncLastAppOpenIfNeeded(force: Bool = false) {
        guard Auth.auth().currentUser != nil else { return }

        let now = Date().timeIntervalSince1970
        let minimumInterval: TimeInterval = 15 * 60
        guard force || (now - lastAppOpenSyncAt) >= minimumInterval else { return }

        lastAppOpenSyncAt = now
        FirestoreService.shared.updateLastAppOpenAt()
    }
}
