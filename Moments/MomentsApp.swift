import SwiftUI
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth // Añadir este import
import GoogleMobileAds

private extension Foundation.Notification.Name {
    static let incognitoLiveActivityPauseRequested = Foundation.Notification.Name("incognitoLiveActivityPauseRequested")
}

@main
struct MomentsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var ephemeralCleanupManager = EphemeralCleanupManager()
    @StateObject private var cacheManager = CacheManager.shared
    @StateObject private var offlineSyncService = OfflineSyncService.shared
    @StateObject private var incognitoModeService = IncognitoModeService.shared
    // Instancia estable: evita recrear el servicio (y su listener de Auth) en cada re-render.
    @StateObject private var messageRequestService = MessageRequestService()
    @State private var showSplash = true
    @State private var showWhatsNew = false
    @AppStorage("lastVersionPrompted") private var lastVersionPrompted: String = "1.0.0"
    @AppStorage("lastAppOpenSyncAt") private var lastAppOpenSyncAt: Double = 0

    // Agregar una propiedad para almacenar el listener de autenticación
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?
    @State private var didPostLaunchInit = false

    init() {
        AppCheck.setAppCheckProviderFactory(MomentsAppCheckProviderFactory())
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
                TabBarView()
                    .environment(AppRouter.shared)
                    .environmentObject(ephemeralCleanupManager)
                    .environmentObject(messageRequestService)
                    .onAppear {

                        // Post-launch initializations (una sola vez)
                        if !didPostLaunchInit {
                            didPostLaunchInit = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                // Inicializar AdMob tras primer frame
                                AdMobConfiguration.shared.initialize()
                                OfflineSyncService.shared.enableAutomaticSync()

                                // Bootstrap del seguimiento de tiempo (Time Spent / Daily Limit)
                                // diferido tras el primer frame para no penalizar el arranque.
                                _ = TimeSpentManager.shared

                                Task {
                                    await BackgroundMomentUploadService.shared.cleanupStaleUploadActivities()
                                    await BackgroundStoryUploadService.shared.cleanupStaleUploadActivities()
                                }

                                // Nota: la configuración de cachés de imágenes (Kingfisher/URLCache)
                                // se hace ahora en AppDelegate.didFinishLaunching, antes del primer frame.

                                // ✅ SwiftData: Limpiar datos locales antiguos (>7 días) — fuera del path crítico.
                                Task.detached(priority: .utility) {
                                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                                    await MainActor.run {
                                        LocalPersistenceService.shared.cleanupOldData()
                                    }
                                    ChatCacheStore.runMaintenance()

                                    if Auth.auth().currentUser != nil {
                                        await MessageIngestService.shared.drainPendingQueue()
                                        await MainActor.run {
                                            MessageCatchUpService.shared.syncRecent(
                                                conversations: LocalPersistenceService.shared.loadConversations()
                                            )
                                        }
                                    }

                                    // Configure AffinityTracker with the shared SwiftData container
                                    await MainActor.run {
                                        if let container = LocalPersistenceService.shared.container {
                                            AffinityTracker.shared.setup(container: container)
                                            AffinityTracker.shared.applyTimeDecayIfNeeded()
                                            AffinityTracker.shared.cleanupVeryLowAffinities()
                                        }
                                    }
                                }
                            }
                        }

                        // ✅ Reanudar sesión de ubicación en vivo si la app se reabrió con una activa
                        LiveLocationSharingService.shared.restoreIfNeeded()

                        // ✅ Configurar listener de autenticación
                        authListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
                            if user != nil {
                                // Usuario logueado - configurar badge service
                                NotificationBadgeService.shared.setupListeners()
                                syncLastAppOpenIfNeeded(force: true)
                                IncognitoModeService.shared.loadState()
                                Task { @MainActor in
                                    await MessageIngestService.shared.drainPendingQueue()
                                }
                            } else {
                                // Usuario deslogueado - limpiar todo
                                NotificationBadgeService.shared.cleanup()
                                IncognitoModeService.shared.resetForSignedOutUser()
                                LiveLocationSharingService.shared.handleUserSignedOut()
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

                        // ✅ Reanudar ubicación en vivo tras volver del background/relaunch
                        LiveLocationSharingService.shared.restoreIfNeeded()

                        syncLastAppOpenIfNeeded()
                        IncognitoModeService.shared.refresh()
                        IncognitoModeService.shared.handlePendingAppGroupActionIfNeeded()

                        Task { @MainActor in
                            ChatCacheStore.runMaintenance()
                            await MessageIngestService.shared.drainPendingQueue()
                            MessageCatchUpService.shared.syncRecent(
                                conversations: LocalPersistenceService.shared.loadConversations()
                            )
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .incognitoLiveActivityPauseRequested)) { _ in
                        IncognitoModeService.shared.pauseFromLiveActivity()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToProfile"))) { notification in
                        if let userId = notification.object as? String {
                            AppRouter.shared.navigate(to: .showUserProfile(userId: userId))
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

                if incognitoModeService.isActive {
                    IncognitoGlobalOverlay(service: incognitoModeService)
                        .transition(.opacity)
                        .zIndex(1600)
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
