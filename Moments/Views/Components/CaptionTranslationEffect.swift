import SwiftUI

/// A text-masked light sweep while waiting, followed by a soft reveal.
struct CaptionTranslationEffect: ViewModifier {
    let isTranslating: Bool
    let text: String
    var revealProgress: Double = 1
    var showingTranslation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isTranslating && !reduceMotion ? 0.64 : 1)
            .overlay {
                if isTranslating && !reduceMotion {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                            let progress = timeline.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1.8) / 1.8
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.95), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: geometry.size.width * (progress * 1.75 - 0.65))
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .opacity(revealProgress)
            .blur(radius: reduceMotion || !showingTranslation ? 0 : (1 - revealProgress) * 2.5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isTranslating)
    }
}
