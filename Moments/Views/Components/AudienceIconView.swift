import SwiftUI

enum AudienceIdentityTint {
    static func bestFriends(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "3A9A72") : Color(hex: "185C45")
    }
}

enum AudienceIconMetrics {
    /// Filas (Settings, visibilidad). SF Symbol ~19pt en slot 28pt.
    static let row: CGFloat = 22
    /// Creator / caption.
    static let creatorRow: CGFloat = 22
    /// Grid del sheet (Only Me, etc.).
    static let gridCard: CGFloat = 30
    /// Grid: Everyone / Mutuals / BFF / Personalizado / Listas.
    static let gridCardEmphasis: CGFloat = 34
    /// Cápsula en editor de historia.
    static let storyCapsule: CGFloat = 20
    /// Barra inferior de historia propia (alineado con StoryActivityEmptyIcon 36×36).
    static let storyBottomBar: CGFloat = 34
    /// Resumen en actividad de historia.
    static let storyActivity: CGFloat = 17
    /// Miniatura en grids de actividad / perfil (solo icono, sin cápsula).
    static let activityGridThumbnail: CGFloat = 15
}

struct AudienceIconView: View {
    let audience: ContentAudience
    let size: CGFloat
    let tintColor: Color

    init(
        audience: ContentAudience,
        size: CGFloat,
        tintColor: Color? = nil,
        colorScheme: ColorScheme? = nil
    ) {
        self.audience = audience
        self.size = size

        if let tintColor {
            self.tintColor = tintColor
        } else if audience == .bestFriends {
            self.tintColor = AudienceIdentityTint.bestFriends(colorScheme ?? .light)
        } else if let colorScheme {
            self.tintColor = colorScheme == .dark ? .white : .black
        } else {
            self.tintColor = .primary
        }
    }

    var body: some View {
        Image(audience.assetName)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(tintColor)
            .accessibilityHidden(true)
    }
}

/// Icono de audiencia discreto para overlays en grids (sin texto ni cápsula).
struct ActivityGridAudienceIcon: View {
    let audience: ContentAudience
    var size: CGFloat = AudienceIconMetrics.activityGridThumbnail
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AudienceIconView(
            audience: audience,
            size: size,
            tintColor: audience == .bestFriends ? AudienceIdentityTint.bestFriends(colorScheme) : .white
        )
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        .allowsHitTesting(false)
    }
}
