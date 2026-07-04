import SwiftUI

/// Imita `ModernLocationMomentRow`: tarjeta de 180pt con overlay de avatar + nombre en la esquina.
struct LocationMomentCardSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var overlaySurfaceColor: Color {
        Color.white.opacity(0.22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfaceColor)

                HStack(spacing: 8) {
                    Circle()
                        .fill(overlaySurfaceColor)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(overlaySurfaceColor)
                            .frame(width: 90, height: 10)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(overlaySurfaceColor)
                            .frame(width: 50, height: 8)
                    }

                    Spacer()
                }
                .padding(12)
            }
            .frame(height: 180)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(surfaceColor)
                .frame(width: 200, height: 12)
                .padding(.horizontal, 12)
                .padding(.top, 10)
        }
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }
}
