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
    /// Frame global de la fila; lo publica `ChatMessageRowChrome` para long-press y menú.
    var chatMessageRowFrame: CGRect {
        get { self[ChatMessageRowFrameKey.self] }
        set { self[ChatMessageRowFrameKey.self] = newValue }
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
        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.14) : Color(hex: "0B1215").opacity(0.07)
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
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
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
