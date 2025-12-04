import SwiftUI

// MARK: - Main View
struct CreatingProfileView: View {
    @StateObject var viewModel = CreatingProfileViewModel()
    @State var isVisible = false
    var onAnimationComplete: (() -> Void)? // ✅ NUEVO: Closure para notificar cuando la animación ha terminado
    
    var body: some View {
        ZStack {
            // Animated Background
            AnimatedBackgroundView()
            
            // Main Content
            VStack(spacing: 50) {
                Spacer()
                
                // Logo Section
                LogoView()
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                
                // Loading Card
                LoadingCardView(viewModel: viewModel)
                    .offset(y: isVisible ? 0 : 50)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                
                // Floating Dots
                FloatingDotsView()
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.4), value: isVisible)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
            viewModel.startAnimation()
            
            // ✅ MEJORADO: Tiempo mínimo GARANTIZADO de 6 segundos para ver toda la animación
            let minimumDuration: TimeInterval = 6.0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + minimumDuration) {
                onAnimationComplete?()
            }
        }
    }
}

// MARK: - Animated Background
struct AnimatedBackgroundView: View {
    @State var animateGradient = false
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: animateGradient)
            
            // Floating orbs
            ForEach(0..<3, id: \.self) { index in
                FloatingOrbView(index: index)
            }
        }
        .onAppear {
            animateGradient = true
        }
    }
}

// MARK: - Floating Orb
struct FloatingOrbView: View {
    let index: Int
    @State var offset = CGPoint(x: 0, y: 0)
    @State var scale: CGFloat = 1.0
    
    private var orbColor: Color {
        switch index {
        case 0: return Color.blue.opacity(0.3)
        case 1: return Color.purple.opacity(0.3)
        default: return Color.pink.opacity(0.3)
        }
    }
    
    var body: some View {
        Circle()
            .fill(orbColor)
            .frame(width: 200, height: 200)
            .blur(radius: 40)
            .scaleEffect(scale)
            .offset(x: offset.x, y: offset.y)
            .animation(
                .easeInOut(duration: Double.random(in: 3...6))
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.5),
                value: offset
            )
            .animation(
                .easeInOut(duration: Double.random(in: 2...4))
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.3),
                value: scale
            )
            .onAppear {
                let randomX = CGFloat.random(in: -100...100)
                let randomY = CGFloat.random(in: -150...150)
                offset = CGPoint(x: randomX, y: randomY)
                scale = CGFloat.random(in: 0.8...1.2)
            }
    }
}

// MARK: - Logo View
struct LogoView: View {
    @State var glowIntensity: Double = 0.5
    
    var body: some View {
        VStack(spacing: 24) {
            Image("LoginLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150)
                .shadow(color: .white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
                .shadow(color: .blue.opacity(0.5), radius: 25, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }
}

// MARK: - Loading Card
struct LoadingCardView: View {
    @ObservedObject var viewModel: CreatingProfileViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            // Enhanced Spinner
            EnhancedSpinnerView(progress: viewModel.progress)
            
            // Text Section
            VStack(spacing: 16) {
                Text(NSLocalizedString("creatingProfile.title", comment: "Creating your account"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Text(viewModel.currentStepText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.currentStep)
            }
            
            // Enhanced Progress Bar
            EnhancedProgressBarView(
                currentStep: viewModel.currentStep,
                totalSteps: viewModel.steps.count
            )
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .background(
            ZStack {
                // Glass morphism effect
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.1),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                
                // Border gradient
                RoundedRectangle(cornerRadius: 32)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
        .shadow(color: .blue.opacity(0.1), radius: 50, x: 0, y: 25)
    }
}

// MARK: - Enhanced Spinner
struct EnhancedSpinnerView: View {
    let progress: CGFloat
    @State var rotationAngle: Double = 0
    @State var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 8)
                .frame(width: 100, height: 100)
            
            // Progress ring with enhanced gradient
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.25, green: 0.35, blue: 0.82),
                            Color(red: 0.78, green: 0.31, blue: 0.75),
                            Color(red: 1.0, green: 0.8, blue: 0.44),
                            Color(red: 0.25, green: 0.35, blue: 0.82)
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: progress)
            
            // Center icon with particles effect
            ZStack {
                // Particle rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        .frame(width: CGFloat(30 + index * 15), height: CGFloat(30 + index * 15))
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: pulseScale
                        )
                }
                
                // Main icon
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .shadow(color: .white.opacity(0.5), radius: 5, x: 0, y: 0)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
        }
    }
}

// MARK: - Enhanced Progress Bar
struct EnhancedProgressBarView: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= currentStep ?
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 6)
                        .shadow(
                            color: index <= currentStep ? .blue.opacity(0.5) : .clear,
                            radius: 4,
                            x: 0,
                            y: 0
                        )
                        .scaleEffect(index == currentStep ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
                }
            }
            .frame(maxWidth: 240)
            
            Text("\(currentStep + 1) de \(totalSteps)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Floating Dots
struct FloatingDotsView: View {
    @State var animationPhase: [Bool] = [false, false, false]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            center: .center,
                            startRadius: 1,
                            endRadius: 6
                        )
                    )
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase[index] ? 1.5 : 0.8)
                    .opacity(animationPhase[index] ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animationPhase[index]
                    )
            }
        }
        .onAppear {
            for index in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                    animationPhase[index] = true
                }
            }
        }
    }
}

// MARK: - View Model
class CreatingProfileViewModel: ObservableObject {
    @Published var progress: CGFloat = 0.0
    @Published var currentStep = 0
    
    let steps = [
        "Verificando datos...",
        "Creando tu perfil...",
        "Subiendo imagen...",
        "Configurando preferencias...",
        "¡Completado! 🎉"
    ]
    
    var currentStepText: String {
        steps[currentStep]
    }
    
    func startAnimation() {
        // ✅ MEJORADO: Animación más rápida (2.5 segundos) para completar todos los pasos
        let stepDuration = 2.5 / Double(steps.count)
        
        for i in 0..<steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    self.currentStep = i
                    self.progress = CGFloat(i + 1) / CGFloat(self.steps.count)
                }
                
            }
        }
    }
}

// MARK: - Preview
struct CreatingProfileView_Previews: PreviewProvider {
    static var previews: some View {
        CreatingProfileView()
    }
}
