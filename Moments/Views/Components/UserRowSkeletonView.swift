import SwiftUI

/// Fila avatar + nombre + control final, imitando filas de usuario tipo
/// `SelectableBestFriendRow` / resultados de búsqueda de personas a etiquetar.
struct UserRowSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme
    var avatarSize: CGFloat = 40

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(surfaceColor)
                .frame(width: avatarSize, height: avatarSize)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(surfaceColor)
                .frame(width: 120, height: 14)

            Spacer()

            Circle()
                .fill(surfaceColor)
                .frame(width: 24, height: 24)
        }
        .padding(.vertical, 8)
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }
}

/// Lista vertical de N filas de usuario en estado de carga.
struct UserRowSkeletonList: View {
    var rows: Int = 5
    var avatarSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                UserRowSkeletonView(avatarSize: avatarSize)
            }
        }
    }
}
