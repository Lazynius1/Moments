import SwiftUI

enum EchoesIconMetrics {
    /// Fila de categoría en actividad (slot 36pt; alineado con reacciones ~22pt).
    static let categoryRow: CGFloat = 28
    /// Barra superior del feed (heart/paperplane ~22pt; icono custom un poco más grande para igualar peso visual).
    static let feedToolbar: CGFloat = 32
    /// Empty state de Echoes en actividad (sin círculo).
    static let emptyState: CGFloat = 96
    /// Miniatura en fila de echo (slot 56pt).
    static let rowThumbnail: CGFloat = 36
    /// Avatar fallback en filas de actividad.
    static let rowAvatar: CGFloat = 18
    /// Empty state historial de echoes (sheet desde el feed).
    static let historyEmpty: CGFloat = 92
    /// Celda en historial.
    static let historyRow: CGFloat = 32
    /// Cabecera del sheet de invitación.
    static let invitation: CGFloat = 40
    /// Espera en visor de echo (sin círculo).
    static let viewerLoading: CGFloat = 56
}

struct EchoesIconView: View {
    let size: CGFloat
    private let tintColor: Color
    private let gradient: LinearGradient?

    init(size: CGFloat, tintColor: Color = .primary) {
        self.size = size
        self.tintColor = tintColor
        self.gradient = nil
    }

    init(size: CGFloat, gradient: LinearGradient) {
        self.size = size
        self.tintColor = .primary
        self.gradient = gradient
    }

    var body: some View {
        let image = Image("EchoesIcon")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)

        if let gradient {
            image.foregroundStyle(gradient)
        } else {
            image.foregroundStyle(tintColor)
        }
    }
}

extension EchoesIconView {
    static var echoesBrandGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var echoesBrandGradientHorizontal: LinearGradient {
        LinearGradient(
            colors: [.orange, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
