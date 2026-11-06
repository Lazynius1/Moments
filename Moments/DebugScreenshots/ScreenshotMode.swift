#if DEBUG
import Foundation
import UIKit

/// Modo captura para la App Store: UI real con datos de demostración,
/// sin sesión y sin acceso a Firebase de producción. Solo existe en Debug.
/// Se activa con el argumento de lanzamiento `-MomentsScreenshotMode <pantalla>`.
enum ScreenshotMode {
    enum Screen: String, CaseIterable, Identifiable {
        case feed
        case aiLabel
        case storyViewer
        case hiddenLayers
        case chat
        case chatInbox
        case echo
        case map
        case privacy
        case appIcons
        case nova

        var id: String { rawValue }
    }

    static let screen: Screen? = UserDefaults.standard
        .string(forKey: "MomentsScreenshotMode")
        .flatMap(Screen.init(rawValue:))

    static var isActive: Bool { screen != nil }

    /// Usuario propio de la demo (no existe en Auth).
    static let meId = "ss_me"

    /// Idioma con el que se resolvió el bundle (`-AppleLanguages`).
    static let lang: String = Bundle.main.preferredLocalizations.first ?? "en"

    /// Historia que abre el visor (`-MomentsScreenshotStoryIndex`, por defecto la segunda).
    static var storyIndex: Int {
        // Desde la línea de comandos llega como texto: `integer(forKey:)` lo convierte.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "MomentsScreenshotStoryIndex") == nil
            ? 1
            : defaults.integer(forKey: "MomentsScreenshotStoryIndex")
    }

    private static var didBootstrap = false

    /// Prepara imágenes, caché local de Firestore y preferencias. Llamar tras `ScreenshotSandbox.configure()`.
    @MainActor
    static func bootstrap() {
        guard isActive, !didBootstrap else { return }
        didBootstrap = true

        ScreenshotURLProtocol.install()
        ScreenshotImages.prefillCache()
        ScreenshotFirestoreSeeder.seed()

        for user in ScreenshotFixtures.allUsers {
            UserCacheService.shared.cacheUser(user)
        }

        // Sin aura de incógnito heredada de sesiones anteriores del simulador.
        IncognitoModeService.shared.resetForSignedOutUser()

        prepareDefaults()
    }

    private static func prepareDefaults() {
        let defaults = UserDefaults.standard

        // Capas ocultas: dos reveladas y una pendiente (clave sin sesión = "anonymous").
        let moment = ScreenshotFixtures.hiddenLayersMoment
        let layers = ScreenshotFixtures.hiddenLayers(for: moment.id ?? "")
        for (index, layer) in layers.enumerated() {
            let key = "hiddenLayerSeen:anonymous:\(moment.id ?? "unknown"):\(layer.id)"
            if index < 2 {
                defaults.set(true, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        // La historia con rasca debe aparecer sin revelar.
        for story in ScreenshotFixtures.stories {
            defaults.removeObject(forKey: "reveal_revealed_\(story.id ?? "")")
        }

        // Mapa centrado en Barcelona.
        defaults.set([
            "lat": ScreenshotFixtures.barcelona.latitude,
            "lon": ScreenshotFixtures.barcelona.longitude,
            "latDelta": 0.07,
            "lonDelta": 0.07
        ], forKey: "discoverMap.lastRegion")
    }
}
#endif
