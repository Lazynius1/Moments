import SwiftUI

// MARK: - Chat bubble chroma

private struct ChatOutgoingBubbleColorKey: EnvironmentKey {
    static let defaultValue = Color(hex: "3F6F8F")
}

extension EnvironmentValues {
    var chatOutgoingBubbleColor: Color {
        get { self[ChatOutgoingBubbleColorKey.self] }
        set { self[ChatOutgoingBubbleColorKey.self] = newValue }
    }
}

private struct ChatFloatingTextColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// Color de los textos sueltos sobre el fondo (citas, "Editado", horas) cuando hay
    /// fondo personalizado; `nil` con el fondo por defecto.
    var chatFloatingTextColor: Color? {
        get { self[ChatFloatingTextColorKey.self] }
        set { self[ChatFloatingTextColorKey.self] = newValue }
    }
}

/// Legibilidad de textos sueltos sobre fondos personalizados: más opacos
/// y con sombra suave; con el fondo por defecto se mantiene `fallback`.
private struct ChatFloatingTextModifier: ViewModifier {
    let fallback: Color
    @Environment(\.chatFloatingTextColor) private var floatingTextColor

    func body(content: Content) -> some View {
        if let floatingTextColor {
            content
                .foregroundStyle(floatingTextColor.opacity(0.9))
                .shadow(color: (floatingTextColor == .white ? Color.black : Color.white).opacity(0.45), radius: 2, x: 0, y: 0.5)
        } else {
            content.foregroundStyle(fallback)
        }
    }
}

extension View {
    func chatFloatingText(_ fallback: Color) -> some View {
        modifier(ChatFloatingTextModifier(fallback: fallback))
    }
}

private struct ChatCardIsOutgoingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Tarjeta compartida dentro de un mensaje propio: su panel adopta
    /// `chatOutgoingBubbleColor` (la media queda intacta).
    var chatCardIsOutgoing: Bool {
        get { self[ChatCardIsOutgoingKey.self] }
        set { self[ChatCardIsOutgoingKey.self] = newValue }
    }
}

extension View {
    /// Borde con el color del chat para tarjetas propias solo de imagen (historia, reel):
    /// la media no se tiñe. `nil` no dibuja nada.
    @ViewBuilder
    func chatOutgoingCardBorder(_ color: Color?, cornerRadius: CGFloat, lineWidth: CGFloat = 2) -> some View {
        if let color {
            overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: lineWidth)
            )
        } else {
            self
        }
    }
}

private struct ChatMessageRowFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    /// Frame global de la fila; lo publica `ChatMessageRowChrome` para layout.
    var chatMessageRowFrame: CGRect {
        get { self[ChatMessageRowFrameKey.self] }
        set { self[ChatMessageRowFrameKey.self] = newValue }
    }
}

private struct ChatMessageBubbleFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

private struct ChatMessageBubbleCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    /// Frame global de la burbuja; lo publica `ChatMessageBubbleChrome`.
    var chatMessageBubbleFrame: CGRect {
        get { self[ChatMessageBubbleFrameKey.self] }
        set { self[ChatMessageBubbleFrameKey.self] = newValue }
    }

    var chatMessageBubbleCornerRadius: CGFloat {
        get { self[ChatMessageBubbleCornerRadiusKey.self] }
        set { self[ChatMessageBubbleCornerRadiusKey.self] = newValue }
    }
}

// MARK: - Colores adaptativos mejorados para ChatView
extension AdaptiveColors {
    // MARK: - Colores específicos para chat mejorados
    var chatInputBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215").opacity(0.78) : Color(hex: "FAF9F6").opacity(0.94)
    }

    var chatNavigationBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215").opacity(0.78) : Color(hex: "FAF9F6").opacity(0.94)
    }

    var searchBarStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)
    }

    var mediaIconColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    var recordingIndicator: Color {
        colorScheme == .dark ? .white : .black
    }

    // MARK: - Colores para mensajes mejorados
    var messageBubbleBackground: Color {
        // Solid surfaces keep text readable over personal chat wallpapers.
        colorScheme == .dark ? Color(hex: "2C3235") : Color(hex: "E9E9E6")
    }

    /// Borde casi imperceptible: en claro el relleno ya contrasta con el fondo.
    var messageBubbleStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.clear
    }

    /// Borde fino de miniaturas de foto/vídeo.
    var mediaBubbleStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var messageTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var timestampColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    var dateHeaderColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }

    var typingIndicatorColor: Color {
        // Contraste sobre `messageBubbleBackground` (no glass).
        colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.42)
    }

    var replyBarBackground: Color {
        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.1) : Color(hex: "0B1215").opacity(0.05)
    }

    var replyBarText: Color {
        colorScheme == .dark ? .white : .black
    }

    var replyBarSecondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
    }

    // MARK: - Accent Colors
    var userAccentColor: Color {
        Color(hex: "3F6F8F")
    }

    var accentColorRed: Color {
        Color(hex: "FF3B30")
    }

    var receivedAccentColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2)
    }

    // MARK: - Gradientes específicos para chat actualizados
    var chatBackground: [Color] {
        colorScheme == .dark ? [
            Color(hex: "0B1215"),
            Color(hex: "0B1215"),
            Color(hex: "0B1215")
        ] : [
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6")
        ]
    }

    var messagingBackground: [Color] {
        colorScheme == .dark ? [
            userAccentColor.opacity(0.3),
            Color.blue.opacity(0.2),
            Color(hex: "0B1215")
        ] : [
            userAccentColor.opacity(0.1),
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6")
        ]
    }
}

// Pick the stronger black/white contrast for dark and pastel outgoing colors.
func chatBubbleTextColor(for color: Color) -> Color {
    chatRelativeLuminance(color) > 0.179 ? .black : .white
}

// MARK: - Acento del chat legible

/// Componentes sRGB (0…1) de un color estático.
private func chatRGBComponents(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func clamp(_ value: CGFloat) -> Double { min(max(Double(value), 0), 1) }
    return (clamp(r), clamp(g), clamp(b), clamp(a))
}

private func chatRelativeLuminance(r: Double, g: Double, b: Double) -> Double {
    func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

/// Luminancia relativa WCAG (0 = negro, 1 = blanco).
func chatRelativeLuminance(_ color: Color) -> Double {
    let c = chatRGBComponents(color)
    return chatRelativeLuminance(r: c.r, g: c.g, b: c.b)
}

/// Contraste WCAG entre dos luminancias (1…21).
private func chatContrastRatio(_ l1: Double, _ l2: Double) -> Double {
    (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

/// Color de burbuja del chat usado como acento sobre otra superficie (p. ej. la burbuja recibida).
///
/// Conserva tono y saturación (HSL) y solo mueve la luminosidad, en pasos de 3 %:
/// oscurece sobre fondos claros y aclara sobre fondos oscuros hasta un contraste
/// WCAG ≥ `minimumContrast` (3:1, mínimo para iconos y texto destacado; los enlaces
/// van además subrayados). Si ya contrasta lo devuelve intacto: el 3F6F8F por defecto
/// no cambia en modo claro y solo se aclara un poco en oscuro.
func chatAccentColor(_ accent: Color, readableOn background: Color, minimumContrast: Double = 3) -> Color {
    let backgroundLuminance = chatRelativeLuminance(background)
    let c = chatRGBComponents(accent)
    guard chatContrastRatio(chatRelativeLuminance(r: c.r, g: c.g, b: c.b), backgroundLuminance) < minimumContrast else {
        return accent
    }

    // RGB → HSL
    let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b), delta = maxC - minC
    var lightness = (maxC + minC) / 2
    let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    var hue: Double = 0
    if delta != 0 {
        if maxC == c.r { hue = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == c.g { hue = (c.b - c.r) / delta + 2 }
        else { hue = (c.r - c.g) / delta + 4 }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    // HSL → RGB
    func rgb(_ l: Double) -> (Double, Double, Double) {
        let chroma = (1 - abs(2 * l - 1)) * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - chroma / 2
        let base: (Double, Double, Double)
        switch hue {
        case ..<60: base = (chroma, x, 0)
        case ..<120: base = (x, chroma, 0)
        case ..<180: base = (0, chroma, x)
        case ..<240: base = (0, x, chroma)
        case ..<300: base = (x, 0, chroma)
        default: base = (chroma, 0, x)
        }
        return (min(max(base.0 + m, 0), 1), min(max(base.1 + m, 0), 1), min(max(base.2 + m, 0), 1))
    }

    let darken = backgroundLuminance > 0.179
    var adjusted = rgb(lightness)
    while darken ? lightness > 0 : lightness < 1 {
        lightness = darken ? max(0, lightness - 0.03) : min(1, lightness + 0.03)
        adjusted = rgb(lightness)
        let luminance = chatRelativeLuminance(r: adjusted.0, g: adjusted.1, b: adjusted.2)
        if chatContrastRatio(luminance, backgroundLuminance) >= minimumContrast { break }
    }
    return Color(.sRGB, red: adjusted.0, green: adjusted.1, blue: adjusted.2, opacity: c.a)
}

extension AdaptiveColors {
    /// Color de burbuja del chat como acento legible sobre la burbuja recibida
    /// (enlaces, menciones, play y onda de las notas de voz recibidas…).
    func receivedAccent(from chatColor: Color) -> Color {
        chatAccentColor(chatColor, readableOn: messageBubbleBackground)
    }

    /// Fondo neutro de las tarjetas recibidas (momento, perfil, ubicación).
    var chatCardBackground: Color {
        colorScheme == .dark ? Color(hex: "151C1D") : Color(hex: "E8EEF0")
    }
}
