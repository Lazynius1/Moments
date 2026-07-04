import SwiftUI

struct ProfileHeaderSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                Circle()
                    .fill(surfaceColor)
                    .frame(width: 96, height: 96)

                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(surfaceColor)
                                .frame(width: 34, height: 16)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(surfaceColor)
                                .frame(width: 48, height: 10)
                        }
                        .frame(maxWidth: .infinity)
                        if index < 2 {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(width: 200, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(surfaceColor)
                .frame(height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }
}

struct ProfileMomentsGridSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Misma mezcla hero/tall/unit que un grid real con contenido variado,
    // en vez de una cuadrícula uniforme que no anticipa el layout final.
    private let tileKinds: [BentoTileKind] = [.hero, .unit, .unit, .unit, .tall, .unit, .unit, .unit, .unit]

    private func surfaceColor(for index: Int) -> Color {
        let base = colorScheme == .dark ? Color.white : Color.black
        return base.opacity(index.isMultiple(of: 3) ? 0.10 : 0.06)
    }

    var body: some View {
        GeometryReader { geometry in
            ProfileBentoLayout {
                ForEach(Array(tileKinds.enumerated()), id: \.offset) { index, kind in
                    Rectangle()
                        .fill(surfaceColor(for: index))
                        .bentoTileKind(kind)
                }
            }
            .frame(width: geometry.size.width, alignment: .topLeading)
        }
        .frame(height: gridHeight)
        .shimmer(isAnimating: true)
        .accessibilityHidden(true)
    }

    private var gridHeight: CGFloat {
        ProfileMomentsGridMetrics.bentoHeight(tileKinds: tileKinds)
    }
}
