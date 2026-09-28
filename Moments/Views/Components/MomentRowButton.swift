import SwiftUI

struct MomentRowButton<Content: View>: View {
    let action: () -> Void
    let content: Content
    var feedback: MomentRowButtonStyle.Feedback = .press
    
    init(
        feedback: MomentRowButtonStyle.Feedback = .press,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.action = action
        self.content = content()
        self.feedback = feedback
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            content
        }
        .buttonStyle(MomentRowButtonStyle(feedback: feedback))
    }
}


struct MomentRowButtonStyle: ButtonStyle {
    enum Feedback {
        case press
        case menu
    }

    var feedback: Feedback = .press

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch feedback {
        case .press:
            MomentsPressButtonStyle(scale: 0.98, pressedOpacity: 0.88, haptic: .none)
                .makeBody(configuration: configuration)
        case .menu:
            // No llamar `MomentsMenuRowButtonStyle().makeBody` aquí:
            // ese camino no instala el Environment del ButtonStyle.
            MomentsMenuRowButtonLabel(configuration: configuration)
        }
    }
}

struct MomentsMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MomentsMenuRowButtonLabel(configuration: configuration)
    }
}

/// Cuerpo del estilo menu como `View` real para que `@Environment` se resuelva.
private struct MomentsMenuRowButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == MomentsMenuRowButtonStyle {
    static var momentsMenuRow: MomentsMenuRowButtonStyle { .init() }
}

extension View {
    func momentRowInteraction(action: @escaping () -> Void) -> some View {
        MomentRowButton(action: action) {
            self
        }
    }
}
