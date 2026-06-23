import SwiftUI

struct ChatBuzzShakeEffect: GeometryEffect {
    var progress: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let remaining = max(0, 1 - progress)
        let x = sin(progress * .pi * 20) * amplitude * remaining
        let y = cos(progress * .pi * 14) * amplitude * 0.38 * remaining
        let rotation = sin(progress * .pi * 16) * 0.022 * remaining
        var transform = CGAffineTransform(translationX: x, y: y)
        transform = transform.rotated(by: rotation)
        return ProjectionTransform(transform)
    }
}

struct ChatBuzzToast: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    private var shape: Capsule {
        Capsule(style: .continuous)
    }

    var body: some View {
        HStack(spacing: 9) {
            AttachmentIconView(
                icon: .buzz,
                size: AttachmentIconMetrics.buzzToast,
                style: colorScheme == .dark ? .white : .black
            )

            Text(text)
                .font(.custom("Poppins-SemiBold", size: 13))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .momentsChromeGlass(in: shape, interactive: false)
        .clipShape(shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }
}

struct ChatBuzzTimelineEventRow: View {
    let text: String
    let isOutgoing: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var shape: Capsule {
        Capsule(style: .continuous)
    }

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                AttachmentIconView(
                    icon: .buzz,
                    size: AttachmentIconMetrics.buzzTimelineEvent,
                    style: colorScheme == .dark ? .white : .black
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.red, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Text(text)
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .momentsChromeGlass(in: shape, interactive: false)
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(colorScheme == .dark ? 0.4 : 0.25),
                                Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.08),
                                Color.clear
                            ],
                            startPoint: isOutgoing ? .leading : .trailing,
                            endPoint: isOutgoing ? .trailing : .leading
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.16 : 0.05), radius: 8, x: 0, y: 3)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ChatBuzzWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let width = rect.width
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY + 5))
        path.addCurve(
            to: CGPoint(x: width * 0.34, y: midY - 2),
            control1: CGPoint(x: width * 0.12, y: midY - 8),
            control2: CGPoint(x: width * 0.22, y: midY - 1)
        )
        path.addLine(to: CGPoint(x: width * 0.44, y: midY - 2))
        path.addCurve(
            to: CGPoint(x: width * 0.52, y: midY + 4),
            control1: CGPoint(x: width * 0.47, y: midY + 12),
            control2: CGPoint(x: width * 0.49, y: midY - 10)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.62, y: midY + 1),
            control1: CGPoint(x: width * 0.56, y: midY + 16),
            control2: CGPoint(x: width * 0.56, y: midY - 15)
        )
        path.addCurve(
            to: CGPoint(x: width, y: midY + 3),
            control1: CGPoint(x: width * 0.74, y: midY + 11),
            control2: CGPoint(x: width * 0.86, y: midY + 7)
        )
        return path
    }
}
