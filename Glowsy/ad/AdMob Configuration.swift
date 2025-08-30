import Foundation
import GoogleMobileAds
import SwiftUI
import AppTrackingTransparency // Importar el framework para ATT
import AdSupport // Necesario para acceder al IDFA

// MARK: - AdMob Configuration
class AdMobConfiguration: NSObject { // Heredar de NSObject para GADAdLoaderDelegate
    static let shared = AdMobConfiguration()

    // IDs de AdMob
    static let appId = "ca-app-pub-7805678909278568~7091658934" // ✅ App ID real de Glowsy
    static let nativeAdUnitId = "ca-app-pub-7805678909278568/9925436334"

    // Para testing (usar en desarrollo) - DESACTIVADO PARA PRODUCCIÓN
    // static let testNativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"

    // ✅ CORREGIDO: Variable de instancia en lugar de static
    private var preloadedNativeAd: NativeAd?

    private override init() {
        super.init()
    }

    func initialize() {
        // ✅ NUEVA API: MobileAds.shared.start() en lugar de GADMobileAds
        MobileAds.shared.start { status in
        }

        // Configurar solicitudes de consentimiento si es necesario
        configureRequestConfiguration()
    }

    private func configureRequestConfiguration() {
        // ✅ NUEVA API: MobileAds.shared.requestConfiguration
        let requestConfiguration = MobileAds.shared.requestConfiguration

        // Ejemplo: configurar para testing - DESACTIVADO PARA PRODUCCIÓN
        // #if DEBUG
        // requestConfiguration.testDeviceIdentifiers = ["b75dd22029c3da38e5f235d014e906c9937689a8b9e510a98ce4e76ad3cf40bd"] // Reemplaza con tu ID de dispositivo de prueba
        // #endif

        // Aquí puedes añadir más configuraciones si es necesario, como para SKAdNetwork
        // MobileAds.shared.requestConfiguration.skAdNetworkConfigurations = ...
    }

    // Función para obtener el ID correcto según el entorno - SIEMPRE PRODUCCIÓN
    static func getNativeAdUnitId() -> String {
        // #if DEBUG
        // return testNativeAdUnitId
        // #else
        return nativeAdUnitId
        // #endif
    }

    // MARK: - App Tracking Transparency (ATT)

    /// Solicita el permiso de seguimiento al usuario.
    func requestATTAuthorization() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized:
                        // Configurar anuncios personalizados
                        self.configureAdPersonalization(enabled: true)
                    case .denied:
                        // Configurar anuncios no personalizados
                        self.configureAdPersonalization(enabled: false)
                    case .notDetermined:
                        // Configuración por defecto
                        self.configureAdPersonalization(enabled: false)
                    case .restricted:
                        // Configurar anuncios no personalizados
                        self.configureAdPersonalization(enabled: false)
                    @unknown default:
                        // Configuración por defecto
                        self.configureAdPersonalization(enabled: false)
                    }
                }
            }
        } else {
            // Manejar versiones anteriores de iOS si es necesario
            // Configuración por defecto para versiones anteriores
            configureAdPersonalization(enabled: false)
        }
    }
    
    /// Configura la personalización de anuncios según el consentimiento del usuario
    private func configureAdPersonalization(enabled: Bool) {
        if enabled {
            // Usuario aceptó seguimiento - anuncios personalizados
            // Las opciones por defecto de Google ya incluyen personalización
        } else {
            // Usuario no aceptó seguimiento - anuncios no personalizados
            // Configurar opciones para anuncios menos personalizados
            configureNonPersonalizedAds()
        }
    }
    
    /// Configura opciones para anuncios no personalizados
    private func configureNonPersonalizedAds() {
        // Nota: En iOS, las opciones de no personalización se manejan principalmente
        // a través del consentimiento de ATT, pero podemos configurar algunas opciones adicionales
    }
    
    /// Obtiene el estado actual de personalización de anuncios
    func getAdPersonalizationStatus() -> (isPersonalized: Bool, reason: String) {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            let userDeclined = UserDefaults.standard.bool(forKey: "userDeclinedATTAlert")
            
            switch status {
            case .authorized:
                if userDeclined {
                    return (false, "Usuario rechazó la alerta de consentimiento")
                } else {
                    return (true, "Usuario autorizó seguimiento")
                }
            case .denied:
                return (false, "Usuario denegó seguimiento")
            case .restricted:
                return (false, "Seguimiento restringido")
            case .notDetermined:
                if userDeclined {
                    return (false, "Usuario rechazó la alerta de consentimiento")
                } else {
                    return (true, "Usuario no ha decidido aún")
                }
            @unknown default:
                return (false, "Estado desconocido")
            }
        } else {
            return (false, "iOS anterior a 14.5")
        }
    }

    // MARK: - ✅ FUNCIONES DE PRECARGA CORREGIDAS

    /// ✅ MEJORADA: Función de precarga con mejor logging
    func preloadNativeAd() {
        
        let adUnitID = AdMobConfiguration.getNativeAdUnitId()
        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .any // Usar .any como funciona en el feed
        
        let adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [mediaOptions]
        )
        
        let request = GoogleMobileAds.Request()
        
        // Usar el delegate existente de AdMobConfiguration
        adLoader.delegate = self
        adLoader.load(request)
        
    }

    /// ✅ CORREGIDA: Función que faltaba
    func setPreloadedNativeAd(_ ad: NativeAd) {
        self.preloadedNativeAd = ad
    }

    /// Retorna el anuncio nativo precargado si está disponible.
    func getPreloadedNativeAd() -> NativeAd? {
        let ad = preloadedNativeAd
        return ad
    }

    /// Limpia el anuncio nativo precargado.
    func clearPreloadedNativeAd() {
        preloadedNativeAd = nil
    }

    private func createNativeAdOptions() -> NativeAdMediaAdLoaderOptions {
        let options = NativeAdMediaAdLoaderOptions()
        options.mediaAspectRatio = .landscape
        
        // Configurar opciones según el consentimiento del usuario
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            let userDeclined = UserDefaults.standard.bool(forKey: "userDeclinedATTAlert")
            
            if status == .denied || userDeclined {
                // Usuario no aceptó seguimiento - configurar para anuncios menos personalizados
                // En iOS, esto se maneja principalmente a través del consentimiento ATT
                // pero podemos configurar algunas opciones adicionales si es necesario
            } else {
                // Usuario aceptó seguimiento o no ha decidido - anuncios personalizados
            }
        }
        
        return options
    }
}

// MARK: - ✅ DELEGATES CORREGIDOS PARA PRECARGA
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

// MARK: - Native Ad Manager (SIN CAMBIOS)
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

        // Intentar usar un anuncio precargado si está disponible
        if let preloadedAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
            self.nativeAd = preloadedAd
            self.isLoading = false
            self.hasError = false
            AdMobConfiguration.shared.clearPreloadedNativeAd() // Limpiar después de usar
            return
        }

        isLoading = true
        hasError = false

        let adUnitID = AdMobConfiguration.getNativeAdUnitId()

        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [createNativeAdOptions()]
        )

        adLoader?.delegate = self

        let request = GoogleMobileAds.Request()
        adLoader?.load(request)

    }

    private func createNativeAdOptions() -> NativeAdMediaAdLoaderOptions {
        let options = NativeAdMediaAdLoaderOptions()
        options.mediaAspectRatio = .landscape
        return options
    }
}

// MARK: - AdLoaderDelegate para NativeAdManager
extension NativeAdManager: AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.hasError = true
        }
    }
}

// MARK: - NativeAdLoaderDelegate para NativeAdManager
extension NativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        DispatchQueue.main.async {
            self.nativeAd = nativeAd
            self.isLoading = false
            self.hasError = false
        }
    }
}

// MARK: - Plus Ad Manager (SIN CAMBIOS)
class PlusAdManager: ObservableObject {
    @Published var shouldShowAds = true
    @Published var isPlus = false

    private var authService: AuthService?

    init(authService: AuthService? = nil) {
        self.authService = authService
        updateAdDisplayStatus()
    }

    /// Actualiza el estado de visualización de anuncios
    func updateAdDisplayStatus() {
        guard let authService = authService,
              let currentUser = authService.currentUser else {
            // Si no hay usuario, mostrar anuncios
            shouldShowAds = true
            isPlus = false
            return
        }

        // Verificar si el usuario es Plus y tiene suscripción activa
        let hasActivePlus = currentUser.isPlusSubscriber &&
                           currentUser.hasActivePlusSubscription

        isPlus = hasActivePlus
        shouldShowAds = !hasActivePlus

    }

    /// Función para usar cuando el estado del usuario cambie
    func refreshAdStatus() {
        updateAdDisplayStatus()
    }
}
