import SwiftUI

/// Imita `InlineCommentRow`/`EnhancedModernCommentRow`: avatar + línea de usuario + 1-2 líneas de texto.
struct CommentRowSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme
    var textLineCount: Int = 2

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(surfaceColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(width: 84, height: 11)

                ForEach(0..<textLineCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surfaceColor)
                        .frame(width: index == textLineCount - 1 ? 140 : nil, height: 12)
                }
            }
        }
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }
}

/// Lista vertical de N filas de comentario en estado de carga.
struct CommentRowSkeletonList: View {
    var rows: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<rows, id: \.self) { _ in
                CommentRowSkeletonView()
            }
        }
    }
}
