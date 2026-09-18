import SwiftUI
import UIKit

@ViewBuilder
func ToolIconButton(icon: String, action: @escaping () -> Void) -> some View {
    ToolIconButtonView(icon: icon, action: action)
}

private struct ToolIconButtonView: View {
    let icon: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(ink.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .clipShape(Circle())
        }
    }
}
