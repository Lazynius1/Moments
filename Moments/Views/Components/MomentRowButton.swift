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
        MomentsPressButtonStyle(scale: 0.98, pressedOpacity: 0.88, haptic: .none)
            .makeBody(configuration: configuration)
    }
}

extension View {
    func momentRowInteraction(action: @escaping () -> Void) -> some View {
        MomentRowButton(action: action) {
            self
        }
    }
}
