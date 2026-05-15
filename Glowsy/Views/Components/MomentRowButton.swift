import SwiftUI

struct MomentRowButton<Content: View>: View {
    let action: () -> Void
    let content: Content
    
    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            content
        }
        .buttonStyle(MomentRowButtonStyle())
    }
}


struct MomentRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension View {
    func momentRowInteraction(action: @escaping () -> Void) -> some View {
        MomentRowButton(action: action) {
            self
        }
    }
}
