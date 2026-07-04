import SwiftUI

extension View {
    func shimmer(isAnimating: Bool) -> some View {
        modifier(ShimmerModifier(isAnimating: isAnimating))
    }
}

struct ShimmerModifier: ViewModifier {
    let isAnimating: Bool
    @State private var isPulsing = false

    private var animates: Bool {
        isAnimating && !MotionPolicy.reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .overlay(pulseOverlay)
            .onAppear {
                guard animates else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    @ViewBuilder
    private var pulseOverlay: some View {
        if animates {
            Color.white
                .opacity(isPulsing ? 0.22 : 0.04)
                .allowsHitTesting(false)
        }
    }
}
