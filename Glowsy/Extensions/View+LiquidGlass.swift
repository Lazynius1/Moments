import SwiftUI

// MARK: - Liquid Glass helper
// Aplica .glassEffect() nativo en iOS 26+ y .ultraThinMaterial como fallback en iOS 17.6+
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(shape)
        }
    }
}
