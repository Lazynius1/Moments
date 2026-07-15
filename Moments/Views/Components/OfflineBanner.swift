import SwiftUI

struct OfflineBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    let onRetry: () -> Void
    
    // ✅ Estado local para auto-ocultación (TRUE por defecto para que avise al entrar)
    @State private var isVisible = true
    
    var body: some View {
        Group {
            if !networkMonitor.isConnected {
                // Animación de entrada/salida
                if isVisible {
                HStack(spacing: 12) {
                    // ✅ Icono con círculo traslúcido (Match exacto Mockup)
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    
                    Text("network.offline.title")
                        .font(.system(size: legacyPoppinsSize(17), weight: .semibold)) // Más cuerpo al texto
                        .foregroundStyle(.primary)
                        .padding(.trailing, 12) // Margen derecho para balancear la cápsula
                }
                .padding(.leading, 8)   // Menos padding a la izquierda (el círculo ya tiene su espacio)
                .padding(.vertical, 8)
                .background(
                        // ✅ ESTILO MOCKUP PURO: Solo Blur + Glow
                        ZStack {
                            // SIN FONDO NEGRO (Solo el blur material)
                            
                            // Glow interno rojo suave
                            RadialGradient(
                                gradient: Gradient(colors: [Color.red.opacity(0.2), Color.clear]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                            
                            // Blur real
                            BlurView(style: .systemUltraThinMaterial)
                        }
                    )
                    .clipShape(Capsule())
                    // Borde de cristal
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    // ✅ Glow ambiente
                    .shadow(color: Color.red.opacity(0.35), radius: 40, x: 0, y: 20)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        // ✅ Auto-ocultar después de 4 segundos
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                isVisible = false
                            }
                        }
                    }
                    .onTapGesture {
                        onRetry()
                    }
                } else {
                    // Botón discreto para recuperar el banner si sigue offline
                    Button(action: {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            isVisible = true
                        }
                    }) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .transition(MotionPolicy.Transition.enterPop)
                    .padding(.top, 4)
                }
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, connected in
            if !connected {
                // Si se pierde la conexión, mostrar banner siempre
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                    isVisible = true
                }
            }
        }
    }
}

struct SlowConnectionBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    @State private var isVisible = true
    
    var body: some View {
        Group {
            if networkMonitor.isSlowConnection {
                if isVisible {
                    HStack(spacing: 12) {
                        // ✅ Icono con círculo traslúcido
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "tortoise.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.yellow)
                        }
                        
                        Text("network.slow.title")
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer(minLength: 12)
                        
                        Button(action: {
                            withAnimation { isVisible = false }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                                .padding(8)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            // SIN FONDO NEGRO
                            
                            RadialGradient(
                                gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.clear]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                            
                            BlurView(style: .systemUltraThinMaterial)
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.orange.opacity(0.35), radius: 40, x: 0, y: 20)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation { isVisible = false }
                        }
                    }
                }
            }
        }
        .onChange(of: networkMonitor.isSlowConnection) { _, slow in
            if slow {
                withAnimation { isVisible = true }
            }
        }
    }
}



#Preview {
    ZStack {
        Color.blue
        VStack {
            OfflineBanner(networkMonitor: NetworkMonitor.shared) {}
            SlowConnectionBanner(networkMonitor: NetworkMonitor.shared)
        }
    }
}
