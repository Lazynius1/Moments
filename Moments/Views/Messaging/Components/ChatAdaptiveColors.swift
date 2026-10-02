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

    var messageBubbleStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
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
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func linear(_ channel: CGFloat) -> Double {
        let value = Double(channel)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    return luminance > 0.179 ? .black : .white
}
