import UIKit

extension UIApplication {
    private static let fallbackSize = CGSize(width: 393, height: 852)
    private static let metricsLock = NSLock()
    private static var cachedWindowSize = fallbackSize
    private static var cachedDisplayScale: CGFloat = 3

    /// Ventana clave de la escena activa. Reemplazo de `UIScreen.main` para obtener
    /// tamaños/insets respetando multi-ventana (iPad, Mirroring, pantallas dinámicas).
    /// `connectedScenes` es UIKit: solo en el hilo principal. SwiftUI AsyncRenderer
    /// evalúa geometría en background y no puede tocar esto.
    var activeKeyWindow: UIWindow? {
        guard Thread.isMainThread else { return nil }
        let window = resolveKeyWindow()
        rememberMetrics(from: window)
        return window
    }

    /// Tamaño de la ventana activa; fallback canónico si aún no hay ventana.
    var activeWindowSize: CGSize {
        if Thread.isMainThread {
            rememberMetrics(from: resolveKeyWindow())
        }
        return Self.readCachedSize()
    }

    /// Escala de la pantalla de la ventana activa (vía window scene, no `UIScreen.main`).
    /// Para vistas SwiftUI prefiérase `@Environment(\.displayScale)`; esto es para
    /// contextos sin entorno (métodos, clases no-vista).
    var activeDisplayScale: CGFloat {
        if Thread.isMainThread {
            rememberMetrics(from: resolveKeyWindow())
        }
        return Self.readCachedScale()
    }

    private func resolveKeyWindow() -> UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    }

    private func rememberMetrics(from window: UIWindow?) {
        let size = window?.bounds.size
        let scale = window?.windowScene?.screen.scale
        Self.metricsLock.lock()
        if let size, size.width > 0, size.height > 0 {
            Self.cachedWindowSize = size
        }
        if let scale, scale > 0 {
            Self.cachedDisplayScale = scale
        }
        Self.metricsLock.unlock()
    }

    private static func readCachedSize() -> CGSize {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return cachedWindowSize
    }

    private static func readCachedScale() -> CGFloat {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return cachedDisplayScale
    }
}
