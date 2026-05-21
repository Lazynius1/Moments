import SwiftUI

enum AuthColors {
    static func primary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
    }

    static func secondary(_ colorScheme: ColorScheme, opacity: Double = 0.68) -> Color {
        primary(colorScheme).opacity(opacity)
    }

    static func subtle(_ colorScheme: ColorScheme, opacity: Double = 0.12) -> Color {
        primary(colorScheme).opacity(opacity)
    }
}

// MARK: - Liquid Aurora Background
struct LiquidAuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false

    private var baseColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var ambientOpacity: Double {
        colorScheme == .dark ? 0.08 : 0.045
    }
    
    var body: some View {
        ZStack {
            baseColor
                .ignoresSafeArea()
            
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(ambientOpacity))
                .frame(width: 450, height: 450)
                .blur(radius: 90)
                .offset(x: animate ? -100 : 100, y: animate ? -150 : 150)
            
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(ambientOpacity))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: animate ? 150 : -150, y: animate ? 100 : -100)
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
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isError: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: UITextAutocapitalizationType = .none
    @State private var isFocused = false

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    private var secondaryText: Color {
        primaryText.opacity(colorScheme == .dark ? 0.42 : 0.52)
    }

    private var focusedIcon: Color {
        primaryText.opacity(isFocused ? 0.95 : (colorScheme == .dark ? 0.46 : 0.48))
    }

    private var strokeColor: Color {
        if isError {
            return .red.opacity(0.55)
        }
        return primaryText.opacity(isFocused ? 0.28 : (colorScheme == .dark ? 0.1 : 0.12))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(focusedIcon)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(secondaryText)
                }

                TextField("", text: $text)
                    .foregroundColor(primaryText)
                    .font(.system(size: 15))
                    .autocapitalization(autocapitalization)
                    .keyboardType(keyboardType)
                    .onTapGesture { isFocused = true }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            Color.clear
                .liquidGlass(in: Capsule(), interactive: true)
        }
        .overlay {
            Capsule()
                .stroke(strokeColor, lineWidth: isError ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .padding(.horizontal, 8)
        .accessibilityLabel(Text(placeholder))
    }
}

// MARK: - Liquid Glass Secure Field
struct LiquidGlassSecureField: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool
    @State private var isFocused = false

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    private var secondaryText: Color {
        primaryText.opacity(colorScheme == .dark ? 0.42 : 0.52)
    }

    private var focusedIcon: Color {
        primaryText.opacity(isFocused ? 0.95 : (colorScheme == .dark ? 0.46 : 0.48))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(focusedIcon)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(secondaryText)
                }

                if isVisible {
                    TextField("", text: $text)
                        .foregroundColor(primaryText)
                        .font(.system(size: 15))
                } else {
                    SecureField("", text: $text)
                        .foregroundColor(primaryText)
                        .font(.system(size: 15))
                }
            }

            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundColor(focusedIcon)
            }
            .accessibilityLabel(Text(isVisible ? "login.password.hide" : "login.password.show"))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            Color.clear
                .liquidGlass(in: Capsule(), interactive: true)
        }
        .overlay {
            Capsule()
                .stroke(primaryText.opacity(isFocused ? 0.28 : (colorScheme == .dark ? 0.1 : 0.12)), lineWidth: 0.6)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .padding(.horizontal, 8)
        .onTapGesture { isFocused = true }
        .accessibilityLabel(Text(placeholder))
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
            .background {
                Color.clear
                    .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
            }
    }
}

// MARK: - Liquid Glass Button
struct LiquidGlassButton: View {
    @Environment(\.colorScheme) private var colorScheme

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
                        .progressViewStyle(CircularProgressViewStyle(tint: AuthColors.primary(colorScheme)))
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
        case .primary: return AuthColors.primary(colorScheme)
        case .secondary: return AuthColors.primary(colorScheme)
        case .destructive: return .red.opacity(colorScheme == .dark ? 0.9 : 0.95)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuthColors.subtle(colorScheme, opacity: isPressed ? 0.14 : 0.08))
                        .allowsHitTesting(false)
                }

        case .secondary:
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AuthColors.subtle(colorScheme, opacity: 0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }

        case .destructive:
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red.opacity(isPressed ? 0.18 : 0.1))
                        .allowsHitTesting(false)
                }
        }
    }
}
