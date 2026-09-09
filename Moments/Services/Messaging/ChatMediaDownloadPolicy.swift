import Foundation

/// Política fija de media de chat (estilo Instagram): si hay red se descarga.
/// El tope y la retención no son preferencias de usuario.
enum ChatMediaDownloadPolicy {
    static let maxMediaBytes: Int64 = 1_610_612_736 // 1.5 GB
    static let retentionDays: Int = 30

    /// Cache hits se sirven siempre. Esto decide si se baja de red el fichero completo.
    static func shouldDownloadAutomatically(force: Bool = false) -> Bool {
        if force { return true }
        return NetworkMonitor.shared.isConnected
    }

    /// Miniaturas de preview (~KB): blur real antes del tap.
    static func shouldDownloadThumbnailPreview(force: Bool = false) -> Bool {
        if force { return true }
        return NetworkMonitor.shared.isConnected
    }
}
