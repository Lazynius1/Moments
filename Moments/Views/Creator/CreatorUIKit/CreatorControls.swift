import SwiftUI
import UIKit

@ViewBuilder
func ToolIconButton(icon: String, action: @escaping () -> Void) -> some View {
    Button(action: {
        HapticManager.shared.lightImpact()
        action()
    }) {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}
