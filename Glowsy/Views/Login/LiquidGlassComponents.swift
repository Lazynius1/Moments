import SwiftUI

// MARK: - Liquid Aurora Background
struct LiquidAuroraBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1) // Deep dark base
                .ignoresSafeArea()
            
            // Fluid blobs
            Circle()
                .fill(LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 450, height: 450)
                .blur(radius: 80)
                .offset(x: animate ? -100 : 100, y: animate ? -150 : 150)
            
            Circle()
                .fill(LinearGradient(colors: [.purple.opacity(0.3), .pink.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 400)
                .blur(radius: 70)
                .offset(x: animate ? 150 : -150, y: animate ? 100 : -100)
            
            // Grainy texture overlay for a "liquid paper" feel
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Liquid Glass Text Field
struct LiquidGlassTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isError: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: UITextAutocapitalizationType = .none
    @State private var isFocused = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.4))
                .frame(width: 24)
            
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                TextField("", text: $text)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .autocapitalization(autocapitalization)
                    .keyboardType(keyboardType)
                    .onTapGesture { isFocused = true }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .opacity(0.1)
                
                RoundedRectangle(cornerRadius: 30)
                    .stroke(
                        isError ?
                        LinearGradient(
                            colors: [.red.opacity(0.5), .red.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isError ? 1.0 : 0.5
                    )
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .padding(.horizontal, 8)
    }
}

// MARK: - Liquid Glass Secure Field
struct LiquidGlassSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool
    @State private var isFocused = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.4))
                .frame(width: 24)
            
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                if isVisible {
                    TextField("", text: $text)
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                } else {
                    SecureField("", text: $text)
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                }
            }
            
            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .opacity(0.1)
                
                RoundedRectangle(cornerRadius: 30)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .padding(.horizontal, 8)
        .onTapGesture { isFocused = true }
    }
}
// MARK: - Liquid Glass Card
struct LiquidGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    
    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                ZStack {
                    // Enhanced glass morphism effect
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    // Enhanced border gradient
                    RoundedRectangle(cornerRadius: cornerRadius)
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
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
            )
    }
}

// MARK: - Liquid Glass Button
struct LiquidGlassButton: View {
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
    }
    
    let title: String
    let icon: String?
    let action: () -> Void
    var style: ButtonStyle = .primary
    var isLoading: Bool = false
    var gradientColors: [Color] = [.blue, .purple]
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(backgroundView)
        .disabled(isLoading)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .white
        case .destructive: return .white.opacity(0.9)
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: gradientColors.first?.opacity(0.3) ?? .blue, radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
            
        case .secondary:
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isPressed ? 0.15 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
        case .destructive:
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(isPressed ? 0.3 : 0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
        }
    }
}
