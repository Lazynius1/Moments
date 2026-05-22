import Foundation
import GoogleMobileAds
import SwiftUI
import AppTrackingTransparency
import AdSupport
import UserMessagingPlatform

// MARK: - AdMob Configuration
@MainActor
class AdMobConfiguration: NSObject {
    static let shared = AdMobConfiguration()

    // IDs de AdMob
    static let appId = "ca-app-pub-7805678909278568~7091658934" // App ID real de Moments
    static let nativeAdUnitId = "ca-app-pub-7805678909278568/9925436334" // ID real de Moments

    // Para testing (usar si el usuario lo solicita)
    static let testNativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"

    private var preloadedNativeAd: NativeAd?
    private(set) var isInitialized = false
    
    // 🔍 Modo Diagnóstico: Si está en true, usará IDs de prueba de Google en el iPhone real
    // Cámbialo a true para verificar si tu código funciona con los IDs genéricos de Google
    static let isDiagnosticMode = false

    private override init() {
        super.init()
    }

    func initialize() {
        // Verificar el App ID cargado desde Info.plist (Silencioso en prod)
        if Bundle.main.infoDictionary?["GADApplicationIdentifier"] as? String == nil {
            print("⚠️ AdMob: GADApplicationIdentifier NO DETECTADO en Info.plist")
        }
        
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isInitialized = true
            }
        }
    }
    
    /// Inicia el flujo de consentimiento (UMP -> ATT)
    /// Se debe llamar cuando el usuario acepta la pantalla de intro
    func startConsentFlow(completion: @escaping () -> Void) {
        // Marcar como presentado para que no vuelva a salir en esta sesión
        Self.hasPresentedConsentFlow = true
        // Persistir que ya se inició el flujo para futuras sesiones
        UserDefaults.standard.set(true, forKey: "hasSeenPrivacyConsent")
        
        requestGDPRConsent { [weak self] _ in
            // Al terminar UMP, pedimos ATT
            self?.requestATTAuthorization()
            completion()
        }
    }
    
    // Flag para evitar múltiples presentaciones en la misma sesión
    private static var hasPresentedConsentFlow = false
    
    /// Determina si se debe mostrar el flujo de consentimiento (Intro screen)
    var shouldShowConsentFlow: Bool {
        // Si ya se presentó en esta sesión, no volver a mostrar
        if Self.hasPresentedConsentFlow { return false }
        
        // Si ya se presentó en sesiones anteriores (persistencia), no volver a mostrar
        if UserDefaults.standard.bool(forKey: "hasSeenPrivacyConsent") { return false }
        
        // Mostrar si NO se ha determinado el ATT o UMP status es desconocido
        if #available(iOS 14, *) {
            let attStatus = ATTrackingManager.trackingAuthorizationStatus
            let umpStatus = UserMessagingPlatform.ConsentInformation.shared.consentStatus
            
            // Si ATT no está determinado, mostrar flow
            if attStatus == .notDetermined {
                return true
            }
            // Si UMP es desconocido o requerido, y no tenemos ATT claro
            if umpStatus == .unknown || umpStatus == .required {
                 return true
            }
        }
        return false
    }
    
    // MARK: - GDPR Consent (UMP)
    
    private func requestGDPRConsent(completion: @escaping (Bool) -> Void) {
        let parameters = UserMessagingPlatform.RequestParameters()
        
        // Para testing en dispositivos reales de desarrollo
        #if DEBUG
        let debugSettings = UserMessagingPlatform.DebugSettings()
        debugSettings.testDeviceIdentifiers = ["1060a23e10e3c616610d4d25ea574f47"]
        // debugSettings.geography = .EEA // Descomenta para simular EU
        parameters.debugSettings = debugSettings
        #endif
        
        // Paso 1: Actualizar información de consentimiento
        UserMessagingPlatform.ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            if let error = error {
                print("❌ UMP Error: \(error.localizedDescription)")
                // En caso de error, intentar cargar anuncios de todos modos
                completion(true)
                return
            }
            
            // Paso 2: Mostrar formulario si es necesario
            Task { @MainActor [weak self] in
                self?.loadAndShowConsentFormIfRequired(completion: completion)
            }
        }
    }
    
    private func loadAndShowConsentFormIfRequired(completion: @escaping (Bool) -> Void) {
        guard let topVC = UIApplication.shared.topViewController() else {
            print("⚠️ UMP: No se encontró topViewController para mostrar formulario")
            completion(UserMessagingPlatform.ConsentInformation.shared.canRequestAds)
            return
        }
        
        UserMessagingPlatform.ConsentForm.loadAndPresentIfRequired(from: topVC) { error in
            if let error = error {
                print("❌ UMP Form Error: \(error.localizedDescription)")
            }
            
            let canRequestAds = UserMessagingPlatform.ConsentInformation.shared.canRequestAds
            completion(canRequestAds)
        }
    }
    
    /// Permite al usuario cambiar sus preferencias de consentimiento
    func showPrivacyOptionsForm() {
        guard UserMessagingPlatform.ConsentInformation.shared.privacyOptionsRequirementStatus == .required else {
            print("ℹ️ UMP: No se requiere formulario de opciones de privacidad")
            return
        }
        
        guard let topVC = UIApplication.shared.topViewController() else {
            print("⚠️ UMP: No se encontró topViewController para mostrar opciones de privacidad")
            return
        }
        
        UserMessagingPlatform.ConsentForm.presentPrivacyOptionsForm(from: topVC) { error in
            if let error = error {
                print("❌ UMP: Error al mostrar opciones de privacidad: \(error.localizedDescription)")
            }
        }
    }

    private func configureRequestConfiguration() {
        // Configuración de producción - sin dispositivos de test
    }

    static func getNativeAdUnitId() -> String {
        if isDiagnosticMode {
            return testNativeAdUnitId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nativeAdUnitId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - App Tracking Transparency (ATT)

    func requestATTAuthorization() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    // Track ATT decision in analytics
                    self.trackATTDecision(status: status)
                    
                    switch status {
                    case .authorized:
                        self.configureAdPersonalization(enabled: true)
                    default:
                        self.configureAdPersonalization(enabled: false)
                    }
                }
            }
        } else {
            configureAdPersonalization(enabled: false)
        }
    }
    
    private func trackATTDecision(status: ATTrackingManager.AuthorizationStatus) {
        let statusString: String
        switch status {
        case .authorized:
            statusString = "authorized"
        case .denied:
            statusString = "denied"
        case .restricted:
            statusString = "restricted"
        case .notDetermined:
            statusString = "notDetermined"
        @unknown default:
            statusString = "unknown"
        }
        
        // Track in analytics
        
        // Also save to UserDefaults for quick access
        UserDefaults.standard.set(statusString, forKey: "attAuthorizationStatus")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "attDecisionTimestamp")
    }
    
    private func configureAdPersonalization(enabled: Bool) {
        if !enabled {
            configureNonPersonalizedAds()
        }
    }
    
    private func configureNonPersonalizedAds() {
        // Configurar para anuncios no personalizados cuando el usuario rechaza tracking
        // AdMob automáticamente sirve anuncios contextuales en lugar de personalizados
    }
    
    func getAdPersonalizationStatus() -> (isPersonalized: Bool, reason: String) {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            let hasSeen = UserDefaults.standard.bool(forKey: "hasSeenATTPreAlert")
            
            switch status {
            case .authorized:
                return (true, "Usuario autorizó seguimiento")
            case .denied:
                return (false, "Usuario denegó seguimiento")
            case .restricted:
                return (false, "Seguimiento restringido")
            case .notDetermined:
                return (hasSeen ? false : true, hasSeen ? "Alerta vista pero no decidida" : "Usuario no ha decidido aún")
            @unknown default:
                return (false, "Estado desconocido")
            }
        } else {
            return (false, "iOS anterior a 14.5")
        }
    }
    
    func getATTDecisionInfo() -> (status: String, timestamp: Date?, hasDecided: Bool) {
        let status = UserDefaults.standard.string(forKey: "attAuthorizationStatus") ?? "notDetermined"
        let timestamp = UserDefaults.standard.double(forKey: "attDecisionTimestamp")
        let decisionDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        
        return (
            status: status,
            timestamp: decisionDate,
            hasDecided: status != "notDetermined"
        )
    }

    // MARK: - Preload Functions

    func preloadNativeAd() {
        guard isInitialized else {
            print("⏳ AdMob: Ignorando precarga (SDK no inicializado)")
            return
        }
        let adUnitID = AdMobConfiguration.getNativeAdUnitId().trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .any
        
        guard let rootViewController = UIApplication.shared.topViewController() else {
            print("⚠️ AdMob: No se pudo obtener rootViewController para precarga")
            return
        }
        
        let adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: [mediaOptions]
        )
        
        let request = createAdRequest()
        adLoader.delegate = self
        adLoader.load(request)
    }

    func setPreloadedNativeAd(_ ad: NativeAd) {
        self.preloadedNativeAd = ad
    }

    func getPreloadedNativeAd() -> NativeAd? {
        return preloadedNativeAd
    }

    func clearPreloadedNativeAd() {
        preloadedNativeAd = nil
    }

    func createNativeAdOptions() -> NativeAdMediaAdLoaderOptions {
        let options = NativeAdMediaAdLoaderOptions()
        options.mediaAspectRatio = .any
        
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status != .authorized {
                // Configuraciones no personalizadas
            }
        }
        
        return options
    }
    
    func createAdRequest() -> GoogleMobileAds.Request {
        let request = GoogleMobileAds.Request()
        
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status != .authorized {
                // Configurar para anuncios no personalizados
                // AdMob automáticamente detecta el estado de ATT y sirve anuncios contextuales
            }
        }
        
        return request
    }
}

extension AdMobConfiguration: @preconcurrency AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ AdMob: Error al precargar anuncio nativo: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.preloadedNativeAd = nil
        }
    }
}

extension AdMobConfiguration: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor [weak self] in
            self?.preloadedNativeAd = nativeAd
        }
    }
}

// MARK: - Native Ad Manager
@MainActor
class NativeAdManager: NSObject, ObservableObject {
    @Published var nativeAd: NativeAd?
    @Published var isLoading = false
    @Published var hasError = false

    private var adLoader: AdLoader?

    override init() {
        super.init()
    }

    func loadAd() {
        guard !isLoading else { return }
        
        guard AdMobConfiguration.shared.isInitialized else {
            print("⏳ AdMob: Reintentando carga en 1s (SDK no inicializado)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.loadAd()
            }
            return
        }

        if let preloadedAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
            self.nativeAd = preloadedAd
            self.isLoading = false
            self.hasError = false
            AdMobConfiguration.shared.clearPreloadedNativeAd()
            return
        }

        isLoading = true
        hasError = false
        nativeAd = nil

        let adUnitID = AdMobConfiguration.getNativeAdUnitId().trimmingCharacters(in: .whitespacesAndNewlines)
        let rootVC = UIApplication.shared.topViewController()
        
        print("📡 AdMob: Cargando anuncio nativo...")
        print("   - Ad Unit ID: \(adUnitID)")
        print("   - Root VC: \(rootVC != nil ? String(describing: type(of: rootVC!)) : "NIL")")
        print("   - Bundle ID: \(Bundle.main.bundleIdentifier ?? "NIL")")
        print("   - Modo Diagnóstico: \(AdMobConfiguration.isDiagnosticMode)")

        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [AdMobConfiguration.shared.createNativeAdOptions()]
        )

        adLoader?.delegate = self

        let request = AdMobConfiguration.shared.createAdRequest()
        adLoader?.load(request)
    }
}

extension NativeAdManager: @preconcurrency AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ AdMob: Error al cargar anuncio nativo: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.isLoading = false
            self?.hasError = true
        }
    }
}

extension NativeAdManager: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor [weak self] in
            self?.nativeAd = nativeAd
            self?.isLoading = false
            self?.hasError = false
        }
    }
}

// MARK: - Plus Ad Manager
@MainActor
class PlusAdManager: ObservableObject {
    @Published var shouldShowAds = true
    @Published var isPlus = false

    private var authService: AuthService?

    init(authService: AuthService? = nil) {
        self.authService = authService
        updateAdDisplayStatus()
    }

    func updateAdDisplayStatus() {
        guard let authService = authService,
              let currentUser = authService.currentUser else {
            shouldShowAds = true
            isPlus = false
            return
        }

        let hasActivePlus = currentUser.isPlusSubscriber && currentUser.hasActivePlusSubscription

        isPlus = hasActivePlus
        shouldShowAds = !hasActivePlus
    }

    func refreshAdStatus() {
        updateAdDisplayStatus()
    }
}

// MARK: - UIApplication Extension
extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
