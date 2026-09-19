import SwiftUI
import UIKit

private struct MomentsViewportSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 393, height: 852)
}

private struct MomentsDivisionRegionsKey: EnvironmentKey {
    static let defaultValue: [CGRect] = []
}

extension EnvironmentValues {
    /// Tamaño de la escena que contiene la vista. Cambia en tiempo real cuando
    /// la ventana se redimensiona o el iPhone Duo cambia de configuración.
    var momentsViewportSize: CGSize {
        get { self[MomentsViewportSizeKey.self] }
        set { self[MomentsViewportSizeKey.self] = newValue }
    }


    /// Regiones físicas activas que dividen la escena (por ejemplo, el pliegue
    /// de Duo), expresadas en coordenadas locales de la raíz.
    var momentsDivisionRegions: [CGRect] {
        get { self[MomentsDivisionRegionsKey.self] }
        set { self[MomentsDivisionRegionsKey.self] = newValue }
    }
}

private struct MomentsViewportMetricsModifier: ViewModifier {
    @State private var viewportSize = MomentsViewportSizeKey.defaultValue
    @State private var divisionRegions: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                guard size.width > 0, size.height > 0 else { return }
                viewportSize = size
            }
            .onGeometryChange(for: [CGRect].self) { proxy in
                if #available(iOS 27.1, *) {
                    return proxy.reservedRegions(kind: .division)
                        .filter(\.isActive)
                        .map(\.frame)
                }
                return []
            } action: { regions in
                divisionRegions = regions
            }
            .environment(\.momentsViewportSize, viewportSize)
            .environment(\.momentsDivisionRegions, divisionRegions)
    }
}

extension View {
    /// Instala métricas propias de esta escena en la raíz de Moments.
    func momentsViewportMetrics() -> some View {
        modifier(MomentsViewportMetricsModifier())
    }

    /// Desplaza localmente un control crítico si una división física lo corta.
    func momentsAvoidsActiveDivision(padding: CGFloat = 10) -> some View {
        modifier(MomentsDivisionAvoidanceModifier(padding: padding))
    }
}

private struct MomentsDivisionAvoidanceModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.momentsViewportSize) private var viewportSize
    @Environment(\.momentsDivisionRegions) private var divisionRegions
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .offset(x: horizontalDisplacement)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                frame = newFrame
            }
    }

    private var horizontalDisplacement: CGFloat {
        guard let division = divisionRegions.first(where: {
            $0.height > $0.width && frame.intersects($0.insetBy(dx: -padding, dy: 0))
        }) else { return 0 }

        let moveLeading = division.minX - padding - frame.maxX
        let moveTrailing = division.maxX + padding - frame.minX
        let leadingFits = frame.minX + moveLeading >= 0
        let trailingFits = frame.maxX + moveTrailing <= viewportSize.width

        if leadingFits && trailingFits {
            return abs(moveLeading) <= abs(moveTrailing) ? moveLeading : moveTrailing
        }
        if leadingFits { return moveLeading }
        if trailingFits { return moveTrailing }
        return 0
    }
}

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
