import SwiftUI

// MARK: - Efecto de Halo Inteligente Reutilizable (Apple Intelligence Style)
struct IntelligentGlow: View {
    var isFocused: Bool
    var cornerRadius: CGFloat
    var colors: [Color]

    private var shouldAnimate: Bool {
        isFocused && !MotionPolicy.reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !shouldAnimate)) { timeline in
            let rotation = shouldAnimate
                ? (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3) * 360
                : 0

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors + [colors[0]]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: isFocused ? 6 : 0
                    )
                    .blur(radius: isFocused ? 12 : 0)
                    .opacity(isFocused ? 0.6 : 0)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors + [colors[0]]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: isFocused ? 3.5 : 0
                    )
                    .blur(radius: isFocused ? 4 : 0)
                    .opacity(isFocused ? 0.9 : 0)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.8),
                                colors[0].opacity(0.5),
                                .white.opacity(0.8),
                                colors[1 % colors.count].opacity(0.5),
                                .white.opacity(0.8)
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: isFocused ? 1.5 : 0
                    )
                    .opacity(isFocused ? 1.0 : 0)
            }
        }
    }
}

