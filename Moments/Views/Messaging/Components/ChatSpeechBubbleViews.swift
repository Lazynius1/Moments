import SwiftUI
import UIKit

// MARK: - Group position

/// Posición de un mensaje dentro de una ráfaga del mismo remitente.
enum ChatMessageGroupPosition {
    case single
    case first
    case middle
    case last
}

// MARK: - Speech bubble shape

/// Burbuja redondeada. Las esquinas del lado del emisor se "unen"
/// (radio pequeño) entre mensajes consecutivos para dar el efecto de grupo.
struct ChatBubbleShape: Shape {
    enum Side {
        case leading
        case trailing
    }

    let side: Side
    var position: ChatMessageGroupPosition = .single
    var cornerRadius: CGFloat = 17
    var joinedRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let j = joinedRadius

        let topPinned = !(position == .first || position == .single)
        let bottomPinned = !(position == .last || position == .single)

        let shape: UnevenRoundedRectangle
        switch side {
        case .leading:
            shape = UnevenRoundedRectangle(
                topLeadingRadius: topPinned ? j : r,
                bottomLeadingRadius: bottomPinned ? j : r,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
        case .trailing:
            shape = UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: bottomPinned ? j : r,
                topTrailingRadius: topPinned ? j : r,
                style: .continuous
            )
        }
        return shape.path(in: rect)
    }
}

// MARK: - Text bubble metrics

/// Valores de referencia al tamaño de texto por defecto; escalan con Dynamic Type.
enum ChatTextBubbleMetrics {
    static let horizontalPadding: CGFloat = 15
    static let verticalPadding: CGFloat = 10
    static let lineSpacing: CGFloat = 2
    static let cornerRadius: CGFloat = 20
    static let joinedRadius: CGFloat = 4
    /// Fracción del ancho de pantalla que puede ocupar una burbuja.
    static let maxWidthScreenFraction: CGFloat = 0.78
}

/// Fuente de mensaje: ~15pt por defecto, escalada con Ajustes → Tamaño del texto.
enum ChatMessageFont {
    static var bubble: Font {
        Font(
            UIFontMetrics(forTextStyle: .body).scaledFont(
                for: UIFont.systemFont(ofSize: 15, weight: .regular)
            )
        )
    }
}

// MARK: - Text bubble

struct ChatTextBubbleView: View {
    let text: String
    let isOutgoing: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    let reactions: [String: [String]]?
    let onReaction: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chatOutgoingBubbleColor) private var chatOutgoingBubbleColor
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = ChatTextBubbleMetrics.horizontalPadding
    @ScaledMetric(relativeTo: .body) private var verticalPadding = ChatTextBubbleMetrics.verticalPadding
    @ScaledMetric(relativeTo: .body) private var lineSpacing = ChatTextBubbleMetrics.lineSpacing
    @ScaledMetric(relativeTo: .body) private var cornerRadius = ChatTextBubbleMetrics.cornerRadius
    @ScaledMetric(relativeTo: .body) private var joinedRadius = ChatTextBubbleMetrics.joinedRadius

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var maxBubbleWidth: CGFloat {
        UIScreen.main.bounds.width * ChatTextBubbleMetrics.maxWidthScreenFraction
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            side: isOutgoing ? .trailing : .leading,
            position: groupPosition,
            cornerRadius: cornerRadius,
            joinedRadius: joinedRadius
        )
    }

    private var bubbleFill: Color {
        isOutgoing ? chatOutgoingBubbleColor : adaptiveColors.messageBubbleBackground
    }

    private var textColor: Color {
        isOutgoing ? .white : adaptiveColors.messageTextColor
    }

    private var hasReactions: Bool {
        reactions.map { !$0.isEmpty } ?? false
    }

    var body: some View {
        Text(text)
            .font(ChatMessageFont.bubble)
            .lineSpacing(lineSpacing)
            .foregroundColor(textColor)
            .multilineTextAlignment(isOutgoing ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .padding(
                MessageReactionMetrics.bubbleContentInsets(
                    isOutgoing: isOutgoing,
                    compact: true,
                    hasReactions: hasReactions
                )
            )
            .background(bubbleFill, in: bubbleShape)
            .overlay(
                bubbleShape
                    .stroke(
                        isOutgoing ? Color.clear : adaptiveColors.messageBubbleStroke,
                        lineWidth: 0.5
                    )
            )
            .messageReactionOverlay(
                isOutgoing: isOutgoing,
                reactions: reactions,
                compact: true,
                onTap: onReaction
            )
            .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
    }
}

// MARK: - Corner avatar for incoming messages

enum ChatIncomingMessageLayout {
    static let gutterAvatarSize: CGFloat = 26
    static let gutterGap: CGFloat = 6

    /// Sangría izquierda total que reserva la columna del avatar.
    static var gutterInset: CGFloat { gutterAvatarSize + gutterGap }
}

struct ChatIncomingAvatarButton: View {
    let otherUserId: String?
    let isUnavailable: Bool
    let size: CGFloat
    var expandTapTarget: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if isUnavailable {
                    ProfileUnavailableAvatar(size: size)
                } else {
                    GlassmorphicAvatar(userId: otherUserId ?? "")
                        .frame(width: size, height: size)
                }
            }
            .frame(
                width: expandTapTarget ? max(size, 44) : size,
                height: expandTapTarget ? max(size, 44) : size
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Columna izquierda fija para mensajes entrantes: muestra el avatar solo en el
/// último mensaje de la ráfaga; en el resto deja un hueco del mismo ancho para
/// mantener todos los mensajes alineados al mismo borde izquierdo.
struct ChatIncomingAvatarGutter: View {
    let showAvatar: Bool
    let otherUserId: String?
    let isUnavailable: Bool
    let onTap: () -> Void

    var body: some View {
        Group {
            if showAvatar {
                ChatIncomingAvatarButton(
                    otherUserId: otherUserId,
                    isUnavailable: isUnavailable,
                    size: ChatIncomingMessageLayout.gutterAvatarSize,
                    expandTapTarget: false,
                    onTap: onTap
                )
            } else {
                Color.clear.frame(width: ChatIncomingMessageLayout.gutterAvatarSize, height: 1)
            }
        }
        .frame(width: ChatIncomingMessageLayout.gutterAvatarSize)
        .padding(.trailing, ChatIncomingMessageLayout.gutterGap)
    }
}
