import SwiftUI

enum AuthFormMetrics {
    static let maxFormContentWidth: CGFloat = 340

    /// Márgenes laterales: mismo aire en Pro y Pro Max; el Pro no debe quedar más estrecho.
    static func screenHorizontalInset(for containerWidth: CGFloat) -> CGFloat {
        if containerWidth >= 420 {
            return 24
        }
        if containerWidth >= 375 {
            return 24
        }
        return 20
    }

    static var defaultScreenHorizontalInset: CGFloat {
        screenHorizontalInset(for: UIApplication.shared.activeWindowSize.width)
    }

    static func responsiveFieldHeight(for screenHeight: CGFloat) -> CGFloat {
        if screenHeight < 670 { // iPhone SE (667)
            return 38
        } else if screenHeight < 850 { // Standard iPhone (e.g. 15 Pro, 852)
            return 42
        } else { // Pro Max / Plus (896+)
            return 44
        }
    }

    static func responsiveButtonHeight(for screenHeight: CGFloat) -> CGFloat {
        // Mínimo 44pt en todos los dispositivos (HIG: target táctil y botón de Apple)
        if screenHeight < 850 {
            return 44
        } else {
            return 46
        }
    }

    static var fieldHeight: CGFloat {
        responsiveFieldHeight(for: UIApplication.shared.activeWindowSize.height)
    }

    static var buttonHeight: CGFloat {
        responsiveButtonHeight(for: UIApplication.shared.activeWindowSize.height)
    }

    static let registerLogoHeight: CGFloat = 112
    static let onboardingLogoHeight: CGFloat = 72
    static let onboardingFieldSpacing: CGFloat = 24
    static let onboardingSectionSpacing: CGFloat = 28
    static let onboardingTopPadding: CGFloat = 12
    static let onboardingTitleToFieldsSpacing: CGFloat = 36
    static let profilePhotoSize: CGFloat = 96
    static let onboardingPreviewPhotoSize: CGFloat = 88

    static let iconFontSize: CGFloat = 15
    static let fieldFontSize: CGFloat = 15
    static let buttonFontSize: CGFloat = 15
    static let fieldHorizontalPadding: CGFloat = 16
    static let iconSlotWidth: CGFloat = 20
    static let fieldCornerRadius: CGFloat = 14
    static let buttonCornerRadius: CGFloat = 14
}

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

    private let fieldHeight = AuthFormMetrics.fieldHeight
    private let fieldHorizontalPadding = AuthFormMetrics.fieldHorizontalPadding
    private let iconSlotWidth = AuthFormMetrics.iconSlotWidth
    @ScaledMetric(relativeTo: .body) private var iconFontSize = AuthFormMetrics.iconFontSize
    @ScaledMetric(relativeTo: .body) private var fieldFontSize = AuthFormMetrics.fieldFontSize

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

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AuthFormMetrics.fieldCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconFontSize).weight(.medium))
                .foregroundStyle(focusedIcon)
                .frame(width: iconSlotWidth)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: fieldFontSize))
                        .foregroundStyle(secondaryText)
                }

                TextField("", text: $text)
                    .foregroundStyle(primaryText)
                    .font(.system(size: fieldFontSize))
                    .autocapitalization(autocapitalization)
                    .keyboardType(keyboardType)
                    .onTapGesture { isFocused = true }
            }
        }
        .padding(.horizontal, fieldHorizontalPadding)
        .frame(minHeight: fieldHeight)
        .background {
            Color.clear
                .liquidGlass(in: fieldShape, interactive: true)
        }
        .overlay {
            fieldShape
                .stroke(strokeColor, lineWidth: isError ? 1 : 0.5)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
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

    private let fieldHeight = AuthFormMetrics.fieldHeight
    private let fieldHorizontalPadding = AuthFormMetrics.fieldHorizontalPadding
    private let iconSlotWidth = AuthFormMetrics.iconSlotWidth
    @ScaledMetric(relativeTo: .body) private var iconFontSize = AuthFormMetrics.iconFontSize
    @ScaledMetric(relativeTo: .body) private var fieldFontSize = AuthFormMetrics.fieldFontSize

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    private var secondaryText: Color {
        primaryText.opacity(colorScheme == .dark ? 0.42 : 0.52)
    }

    private var focusedIcon: Color {
        primaryText.opacity(isFocused ? 0.95 : (colorScheme == .dark ? 0.46 : 0.48))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AuthFormMetrics.fieldCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconFontSize).weight(.medium))
                .foregroundStyle(focusedIcon)
                .frame(width: iconSlotWidth)

            ZStack(alignment: .trailing) {
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: fieldFontSize))
                            .foregroundStyle(secondaryText)
                    }

                    if isVisible {
                        TextField("", text: $text)
                            .foregroundStyle(primaryText)
                            .font(.system(size: fieldFontSize))
                            .autocapitalization(.none)
                            .onTapGesture { isFocused = true }
                    } else {
                        SecureField("", text: $text)
                            .foregroundStyle(primaryText)
                            .font(.system(size: fieldFontSize))
                            .autocapitalization(.none)
                            .onTapGesture { isFocused = true }
                    }
                }

                Button(action: {
                    isVisible.toggle()
                }) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(primaryText.opacity(0.48))
                        .padding(.trailing, 4)
                }
            }
        }
        .padding(.horizontal, fieldHorizontalPadding)
        .frame(minHeight: fieldHeight)
        .background {
            Color.clear
                .liquidGlass(in: fieldShape, interactive: true)
        }
        .overlay {
            fieldShape
                .stroke(primaryText.opacity(isFocused ? 0.28 : (colorScheme == .dark ? 0.1 : 0.12)), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
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
                    .font(.system(size: AuthFormMetrics.buttonFontSize, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AuthFormMetrics.buttonHeight)
        }
        .background(backgroundView)
        .disabled(isLoading)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isPressed), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            isPressed = pressing
        })
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
                .liquidGlass(in: RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
                        .fill(AuthColors.subtle(colorScheme, opacity: isPressed ? 0.14 : 0.08))
                        .allowsHitTesting(false)
                }

        case .secondary:
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
                        .stroke(AuthColors.subtle(colorScheme, opacity: 0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }

        case .destructive:
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous), interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
                        .fill(Color.red.opacity(isPressed ? 0.18 : 0.1))
                        .allowsHitTesting(false)
                }
        }
    }
}

// MARK: - Layout auth (login / registro sobre el fondo, sin caja contenedora)
private struct AuthScreenContentWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        let screenWidth = UIApplication.shared.activeWindowSize.width
        let margin: CGFloat
        if screenWidth < 380 {
            margin = 20
        } else if screenWidth < 390 {
            margin = 28
        } else if screenWidth < 500 {
            margin = 36
        } else {
            margin = 40
        }
        return content
            .frame(maxWidth: screenWidth >= 500 ? 400 : .infinity)
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Ancho fluido con márgenes adaptativos; tope 400pt en pantallas anchas (iPad).
    func authScreenContentWidth() -> some View {
        modifier(AuthScreenContentWidthModifier())
    }

    func authScreenHorizontalPadding() -> some View {
        let screenWidth = UIApplication.shared.activeWindowSize.width
        let margin: CGFloat
        if screenWidth < 380 {
            margin = 20
        } else if screenWidth < 390 {
            margin = 28
        } else if screenWidth < 500 {
            margin = 36
        } else {
            margin = 40
        }
        return padding(.horizontal, margin)
    }
}

struct AuthRegistrationPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    private let buttonHeight = AuthFormMetrics.buttonHeight
    @ScaledMetric(relativeTo: .body) private var buttonFontSize = AuthFormMetrics.buttonFontSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AuthColors.primary(colorScheme)))
                        .scaleEffect(0.75)
                } else {
                    Text(title)
                        .font(.system(size: buttonFontSize).weight(.semibold))
                        .foregroundStyle(AuthColors.primary(colorScheme))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: buttonHeight)
        }
        .background {
            Color.clear
                .momentsChromeGlass(
                    in: RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous),
                    interactive: isEnabled
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
                .fill(AuthColors.subtle(colorScheme, opacity: isEnabled ? 0.1 : 0.02))
                .allowsHitTesting(false)
        }
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .scaleEffect(isLoading ? 0.97 : 1)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}
