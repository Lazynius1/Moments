import SwiftUI

struct MomentsEmptyStateAppearModifier: ViewModifier {
    var appearedOffsetY: CGFloat = 0
    var initialOffsetY: CGFloat = 14

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .offset(y: appeared ? appearedOffsetY : initialOffsetY)
            .opacity(appeared ? 1 : 0)
            .animation(
                MotionPolicy.animation(
                    MotionPolicy.Spring.onboarding.delay(0.08),
                    value: appeared
                ),
                value: appeared
            )
            .onAppear {
                appeared = true
            }
    }
}

extension View {
    func momentsEmptyStateAppear(
        appearedOffsetY: CGFloat = 0,
        initialOffsetY: CGFloat = 14
    ) -> some View {
        modifier(
            MomentsEmptyStateAppearModifier(
                appearedOffsetY: appearedOffsetY,
                initialOffsetY: initialOffsetY
            )
        )
    }
}
