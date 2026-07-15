import SwiftUI

// MARK: - Main View
struct CreatingProfileView: View {
    @StateObject private var viewModel = CreatingProfileViewModel()
    @State private var isVisible = false
    var onAnimationComplete: (() -> Void)? // ✅ NUEVO: Closure para notificar cuando la animación ha terminado
    
    var body: some View {
        ZStack {
            // Animated Background
            LiquidAuroraBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                LogoView()
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding, value: isVisible), value: isVisible)
                
                CreatingProfileStatusView(viewModel: viewModel)
                    .offset(y: isVisible ? 0 : 24)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.2), value: isVisible), value: isVisible)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
            viewModel.startAnimation()
            
            let minimumDuration: TimeInterval = 2.8
            
            DispatchQueue.main.asyncAfter(deadline: .now() + minimumDuration) {
                onAnimationComplete?()
            }
        }
    }
}



// MARK: - Logo View
struct LogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Image(colorScheme == .dark ? "LoginLogo" : "whatsnew")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 118, height: 118)
            .shadow(color: AuthColors.primary(colorScheme).opacity(0.08), radius: 12, x: 0, y: 0)
    }
}

// MARK: - Creating Profile Status
struct CreatingProfileStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: CreatingProfileViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("creatingProfile.title", comment: "Creating your account"))
                .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                .foregroundStyle(AuthColors.primary(colorScheme))
            
            Text(viewModel.currentStepText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.64))
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.85, dampingFraction: 0.86), value: viewModel.currentStep)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }
}

// MARK: - View Model
class CreatingProfileViewModel: ObservableObject {
    @Published var currentStep = 0
    private let completionEmoji = ["😊", "💛", "✨", "🫶", "😌"].randomElement() ?? "😊"
    
    private let stepKeys = [
        "creatingProfile.step.verifying",
        "creatingProfile.step.creating",
        "creatingProfile.step.uploading",
        "creatingProfile.step.configuring",
        "creatingProfile.step.completed"
    ]
    
    var currentStepText: String {
        let text = NSLocalizedString(stepKeys[currentStep], comment: "Creating profile step")
        return currentStep == stepKeys.count - 1 ? "\(text) \(completionEmoji)" : text
    }

    func startAnimation() {
        let stepDuration = 2.8 / Double(stepKeys.count)
        
        for i in 0..<stepKeys.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    self.currentStep = i
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
