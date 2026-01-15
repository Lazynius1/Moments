import SwiftUI

// MARK: - Efecto de Halo Inteligente Reutilizable (Apple Intelligence Style)
struct IntelligentGlow: View {
    @State private var rotation: Double = 0
    var isFocused: Bool
    var cornerRadius: CGFloat
    var colors: [Color]
    
    var body: some View {
        ZStack {
            // Capa 1: Resplandor exterior (Blur amplio)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors[0]]),
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: isFocused ? 6 : 0
                )
                .blur(radius: isFocused ? 12 : 0)
                .opacity(isFocused ? 0.6 : 0)
            
            // Capa 2: Halo medio (Más definido)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors[0]]),
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: isFocused ? 3.5 : 0
                )
                .blur(radius: isFocused ? 4 : 0)
                .opacity(isFocused ? 0.9 : 0)
            
            // Capa 3: Línea de energía (Núcleo brillante)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.8),
                            colors[0].opacity(0.5),
                            .white.opacity(0.8),
                            colors[1 % colors.count].opacity(0.5),
                            .white.opacity(0.8)
                        ]),
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: isFocused ? 1.5 : 0
                )
                .opacity(isFocused ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

