import SwiftUI

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.5
    @State private var orbRotation: Double = 0
    @State private var glowIntensity: Double = 0.3
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Enhanced background similar to LoginView
            // Shared Liquid Aurora Background
            LiquidAuroraBackground()
            
            VStack {
                Spacer()
                
                // Logo principal con animaciones
                ZStack {
                    // Glow effect de fondo
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 50,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .scaleEffect(pulseScale)
                        .blur(radius: 30)
                    
                    // Logo principal
                    Image("LoginLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                        .shadow(color: .white.opacity(glowIntensity), radius: 20, x: 0, y: 0)
                        .shadow(color: .blue.opacity(0.5), radius: 40, x: 0, y: 0)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                
                Spacer()
                
                // Texto "Moments" removido - solo se muestra el logo
                
                Spacer()
                
                // Loading indicator optimizado
                VStack(spacing: 20) {
                    MomentsLoader()
                    
                    Text("splash.loading")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .opacity(logoOpacity)
                }
                .padding(.bottom, 80)
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Animación del logo principal
        withAnimation(.easeInOut(duration: 1.0)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Glow pulsante
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowIntensity = 1.0
            pulseScale = 1.1
        }
        
        // Rotación del orbe
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            orbRotation = 360
        }
    }
}



// MARK: - Moments Loader
struct MomentsLoader: View {
    @State private var progress: CGFloat = 0.0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                .frame(width: 40, height: 40)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.white, .blue.opacity(0.8), .purple.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            // Animación de progreso
            withAnimation(.easeInOut(duration: 2.5)) {
                progress = 1.0
            }
            
            // Rotación suave
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Alternative Minimal Splash (más simple)
struct MinimalSplashScreenView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // Background simple
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Logo simple
                Image("LoginLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .foregroundColor(.white)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                
                // Texto "Moments" removido - solo se muestra el logo
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - Preview
struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SplashScreenView()
            MinimalSplashScreenView()
        }
    }
}
