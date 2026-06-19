import SwiftUI

// MARK: - Group position

/// Posición de un mensaje dentro de una ráfaga del mismo remitente (estilo Instagram).
enum ChatMessageGroupPosition {
    case single
    case first
    case middle
    case last
}

// MARK: - Speech bubble shape

/// Burbuja redondeada estilo Instagram. Las esquinas del lado del emisor se "unen"
/// (radio pequeño) entre mensajes consecutivos para dar el efecto de grupo.
struct ChatBubbleShape: Shape {
    enum Side {
        case leading
        case trailing
    }

    let side: Side
    var position: ChatMessageGroupPosition = .single
    var cornerRadius: CGFloat = 20
    var joinedRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let j = joinedRadius

        // Radio de cada esquina del lado del emisor según posición en el grupo.
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

// MARK: - Text bubble

struct ChatTextBubbleView: View {
    let text: String
    let isOutgoing: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    let reactions: [String: [String]]?
    let onReaction: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(side: isOutgoing ? .trailing : .leading, position: groupPosition)
    }

    private var bubbleFill: Color {
        isOutgoing ? adaptiveColors.userAccentColor : adaptiveColors.messageBubbleBackground
    }

    private var textColor: Color {
        isOutgoing ? .white : adaptiveColors.messageTextColor
    }

    var body: some View {
        Text(text)
            .font(.custom("Poppins-Regular", size: 15))
            .foregroundColor(textColor)
            .multilineTextAlignment(isOutgoing ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: isOutgoing ? .trailing : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleFill, in: bubbleShape)
            .overlay(
                bubbleShape
                    .stroke(
                        isOutgoing ? Color.clear : adaptiveColors.messageBubbleStroke,
                        lineWidth: 0.5
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
            .messageReactionOverlay(
                isOutgoing: isOutgoing,
                reactions: reactions,
                compact: true,
                onTap: onReaction
            )
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
