import Foundation
import GoogleMobileAds
import SwiftUI
import AppTrackingTransparency
import AdSupport

// MARK: - AdMob Configuration
class AdMobConfiguration: NSObject {
    static let shared = AdMobConfiguration()

    // IDs de AdMob
    static let appId = "ca-app-pub-7805678909278568~7091658934" // ✅ App ID real de Glowsy
    static let nativeAdUnitId = "ca-app-pub-7805678909278568/9925436334"

    // Para testing (usar en desarrollo) - DESACTIVADO PARA PRODUCCIÓN
    // static let testNativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"

    private var preloadedNativeAd: NativeAd?

    private override init() {
        super.init()
    }

    func initialize() {
        MobileAds.shared.start { status in
        }
        configureRequestConfiguration()
    }

    private func configureRequestConfiguration() {
        let requestConfiguration = MobileAds.shared.requestConfiguration

        // Ejemplo: configurar para testing - DESACTIVADO PARA PRODUCCIÓN
        // #if DEBUG
        // requestConfiguration.testDeviceIdentifiers = ["1a116ffb808808d4257e0cc3d44d4d1f"]
        // #endif
    }

    static func getNativeAdUnitId() -> String {
        return nativeAdUnitId
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
        AnalyticsService.shared.trackInteraction("att_decision", details: [
            "status": statusString,
            "timestamp": Date().timeIntervalSince1970
        ])
        
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
        let adUnitID = AdMobConfiguration.getNativeAdUnitId()
        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .any
        
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow })?.rootViewController else {
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

extension AdMobConfiguration: AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        DispatchQueue.main.async {
            self.preloadedNativeAd = nil
        }
    }
}

extension AdMobConfiguration: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        DispatchQueue.main.async {
            self.preloadedNativeAd = nativeAd
        }
    }
}

// MARK: - Native Ad Manager
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

        if let preloadedAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
            self.nativeAd = preloadedAd
            self.isLoading = false
            self.hasError = false
            AdMobConfiguration.shared.clearPreloadedNativeAd()
            return
        }

        isLoading = true
        hasError = false

        let adUnitID = AdMobConfiguration.getNativeAdUnitId()

        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [AdMobConfiguration.shared.createNativeAdOptions()]
        )

        adLoader?.delegate = self

        let request = AdMobConfiguration.shared.createAdRequest()
        adLoader?.load(request)
    }
}

extension NativeAdManager: AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.hasError = true
        }
    }
}

extension NativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        DispatchQueue.main.async {
            self.nativeAd = nativeAd
            self.isLoading = false
            self.hasError = false
        }
    }
}

// MARK: - Plus Ad Manager
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
