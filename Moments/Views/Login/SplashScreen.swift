import SwiftUI

struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onComplete: (() -> Void)? = nil
    @State private var logoScale: CGFloat = 1.0
    @State private var logoOpacity: Double = 1.0
    @State private var backgroundOpacity: Double = 1.0
    @State private var didStart = false
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            Image(colorScheme == .dark ? "SplashLogoDark" : "SplashLogoLight")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 156, height: 156)
                .shadow(color: AuthColors.primary(colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.08), radius: 18, x: 0, y: 0)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        guard !didStart else { return }
        didStart = true
        
        if reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    logoOpacity = 0.0
                    backgroundOpacity = 0.0
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
                onComplete?()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            withAnimation(.easeInOut(duration: 0.22)) {
                logoScale = 0.84
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.04) {
            withAnimation(.easeInOut(duration: 0.34)) {
                logoScale = 26.0
                logoOpacity = 0.0
                backgroundOpacity = 0.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.44) {
            onComplete?()
        }
    }
}

// MARK: - Alternative Minimal Splash (más simple)
struct MinimalSplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            LiquidAuroraBackground()
            
            Image(colorScheme == .dark ? "SplashLogoDark" : "SplashLogoLight")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 138, height: 138)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
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
