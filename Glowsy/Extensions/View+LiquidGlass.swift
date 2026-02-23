import SwiftUI

// MARK: - Liquid Glass helper
// Aplica .glassEffect() nativo en iOS 26+ y .ultraThinMaterial como fallback en iOS 17.6+
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(shape)
        }
    }
}
