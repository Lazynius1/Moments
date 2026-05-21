import GoogleMobileAds

// MARK: - AdMob Aspect Ratios Configuration FINAL SIMPLE
extension AdMobConfiguration {
    
    enum AdAspectRatioContext {
        case stories    // 9:16 - Historias a pantalla completa
        case feed       // 4:5 - Posts en feed
        case banner     // 320x50 - Banners estándar
        
        var nativeAdOptions: NativeAdMediaAdLoaderOptions {
            let options = NativeAdMediaAdLoaderOptions()
            
            switch self {
            case .stories:
                // ✅ 9:16 - Formato vertical para historias
                options.mediaAspectRatio = .portrait
                
            case .feed:
                // ✅ Portrait - Para que se vea vertical como los posts del feed
                options.mediaAspectRatio = .portrait
                
            case .banner:
                // ✅ Horizontal - Para banners
                options.mediaAspectRatio = .landscape
            }
            
            return options
        }
    }
    
    /// ✅ ELIMINAMOS createStoriesAdOptions() problemático
    /// En su lugar, usar directamente en StoryNativeAdManager:
    /// let mediaOptions = NativeAdMediaAdLoaderOptions()
    /// mediaOptions.mediaAspectRatio = .portrait
    
    /// Crear opciones básicas (mantener compatibilidad con feed)
    static func createNativeAdOptions() -> NativeAdMediaAdLoaderOptions {
        return AdAspectRatioContext.feed.nativeAdOptions
    }
}

// MARK: - Documentación de Aspect Ratios
/*
 📱 ASPECT RATIOS DE LA APP MOMENTS:
 
 ✅ Stories (9:16):
    - Historias a pantalla completa
    - Formato vertical  Stories
    - AdMob: .portrait
 
 ✅ Feed Posts (4:5):
    - Posts principales en el feed
    - Formato vertical pero menos estirado
    - AdMob: .any (deja que AdMob elija)
 
 ✅ Feed Landscape (16:9):
    - Videos horizontales en feed
    - AdMob: .landscape
 
 📝 NOTA: AdMob .portrait no significa exactamente 9:16,
 pero es la opción más cercana para contenido vertical tipo Stories.
 AdMob optimizará el formato según el contenido disponible.
*/
