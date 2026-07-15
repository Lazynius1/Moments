import UIKit

extension UIApplication {
    /// Ventana clave de la escena activa. Reemplazo de `UIScreen.main` para obtener
    /// tamaños/insets respetando multi-ventana (iPad, Mirroring, pantallas dinámicas).
    var activeKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    }

    /// Tamaño de la ventana activa; fallback canónico si aún no hay ventana.
    var activeWindowSize: CGSize {
        activeKeyWindow?.bounds.size ?? CGSize(width: 393, height: 852)
    }

    /// Escala de la pantalla de la ventana activa (vía window scene, no `UIScreen.main`).
    /// Para vistas SwiftUI prefiérase `@Environment(\.displayScale)`; esto es para
    /// contextos sin entorno (métodos, clases no-vista).
    var activeDisplayScale: CGFloat {
        activeKeyWindow?.windowScene?.screen.scale ?? 3
    }
}
