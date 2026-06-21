import Foundation
import os

/// Logging ligero para hot-paths. En Release se compila a no-op para evitar
/// el coste de I/O de `print` en rutas calientes (arranque, scroll, red).
///
/// Uso: `AppLog.debug("mensaje")`. Para errores que sí quieras conservar en
/// Release usa `AppLog.error(...)`, que va a `os.Logger`.
enum AppLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Moments",
        category: "app"
    )

    /// Solo se emite en builds DEBUG. No-op en Release.
    @inlinable
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    /// Errores relevantes que se conservan también en Release (vía os.Logger).
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
