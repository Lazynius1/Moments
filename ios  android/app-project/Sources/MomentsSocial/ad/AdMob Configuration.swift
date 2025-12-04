import Foundation
import SwiftUI

// MARK: - AdMob Configuration
class AdMobConfiguration: NSObject {
    static let shared = AdMobConfiguration()

    // IDs de AdMob
    static let appId = "ca-app-pub-7805678909278568~7091658934"
    static let nativeAdUnitId = "ca-app-pub-7805678909278568/9925436334"

    private var preloadedNativeAd: NativeAd?

    private override init() {
        super.init()
    }

    func initialize() {
        // AdMob initialization handled by Skip bridge to Android
        // Skip will transpile this to MobileAds.initialize(context)
        #if SKIP
        // Android initialization happens natively
        #else
        // iOS initialization - already handled in original code
        #endif
        configureRequestConfiguration()
    }

    private func configureRequestConfiguration() {
        // Configuration handled natively per platform
    }

    static func getNativeAdUnitId() -> String {
        return nativeAdUnitId
    }

    // MARK: - App Tracking Transparency (ATT) - iOS only
    
    func requestATTAuthorization() {
        // Android doesn't use ATT - privacy handled through Play Services
        // iOS implementation handled natively
        #if SKIP
        // Android: No ATT needed
        #else
        // iOS: Request ATT if available
        #endif
    }
    
    func getAdPersonalizationStatus() -> (isPersonalized: Bool, reason: String) {
        // Default to personalized - actual status handled natively
        return (true, "Default personalization")
    }
    
    // MARK: - Preload Native Ad
    
    func preloadNativeAd(completion: @escaping (Bool) -> Void) {
        let adUnitID = AdMobConfiguration.getNativeAdUnitId()
        let adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [createNativeAdOptions()]
        )
        
        let request = createAdRequest()
        
        // Create temporary delegate to handle preload
        let delegate = PreloadDelegate { [weak self] nativeAd in
            self?.preloadedNativeAd = nativeAd
            completion(true)
        } onError: {
            completion(false)
        }
        
        adLoader.delegate = delegate
        adLoader.load(request)
    }
    
    func getPreloadedNativeAd() -> NativeAd? {
        return preloadedNativeAd
    }
    
    func setPreloadedNativeAd(_ ad: NativeAd?) {
        self.preloadedNativeAd = ad
    }
    
    func clearPreloadedNativeAd() {
        preloadedNativeAd = nil
    }
    
    // MARK: - Ad Request Helpers
    
    func createAdRequest() -> AdRequest {
        return AdRequest()
    }
    
    func createNativeAdOptions() -> NativeAdMediaAdLoaderOptions {
        let options = NativeAdMediaAdLoaderOptions()
        options.mediaAspectRatio = .any
        return options
    }
    
    // MARK: - Analytics Integration
    
    func trackAdEvent(_ event: String, details: [String: Any] = [:]) {
        AnalyticsService.shared.trackInteraction("ad_\(event)", details: details)
    }
}

// MARK: - Preload Delegate Helper
private class PreloadDelegate: NSObject, NativeAdLoaderDelegate {
    let onSuccess: (NativeAd) -> Void
    let onError: () -> Void
    
    init(onSuccess: @escaping (NativeAd) -> Void, onError: @escaping () -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        onError()
    }
    
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        onSuccess(nativeAd)
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

        // Check for preloaded ad first
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
