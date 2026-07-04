import SwiftUI

/// Imita el chrome del `StoryViewerScreen` (barras de progreso segmentadas + header de autor)
/// mientras se resuelve la lista de stories a mostrar.
struct StoryViewerSkeletonView: View {
    var segmentCount: Int = 3

    private let surfaceColor = Color.white.opacity(0.16)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<segmentCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(surfaceColor)
                        .frame(height: 2.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HStack(spacing: 10) {
                Circle()
                    .fill(surfaceColor)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(surfaceColor)
                        .frame(width: 96, height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(surfaceColor)
                        .frame(width: 60, height: 9)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
        }
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }
}
