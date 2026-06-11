import SwiftUI

struct FeedPostSkeletonView: View {
    let colorScheme: ColorScheme

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(surfaceColor)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surfaceColor)
                        .frame(width: 120, height: 10)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surfaceColor)
                        .frame(width: 72, height: 8)
                }

                Spacer(minLength: 0)
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surfaceColor)
                .frame(height: 360)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(surfaceColor)
                .frame(maxWidth: .infinity)
                .frame(height: 10)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(surfaceColor)
                .frame(width: 180, height: 10)
        }
        .padding(.horizontal, 16)
        .shimmering(active: true)
    }
}

private struct FeedSkeletonShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0.55 + (sin(phase) * 0.15) : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
    }
}

private extension View {
    func shimmering(active: Bool) -> some View {
        modifier(FeedSkeletonShimmerModifier(active: active))
    }
}
