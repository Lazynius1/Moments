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

struct TextSegment: Identifiable {
    let id = UUID()
    let text: String
    let isSpoiler: Bool
}

private struct ChatSearchHighlightTermKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct ChatSearchActiveMessageIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var chatSearchHighlightTerm: String {
        get { self[ChatSearchHighlightTermKey.self] }
        set { self[ChatSearchHighlightTermKey.self] = newValue }
    }

    var chatSearchActiveMessageId: String? {
        get { self[ChatSearchActiveMessageIdKey.self] }
        set { self[ChatSearchActiveMessageIdKey.self] = newValue }
    }
}

struct ChatTextBubbleView: View {
    let text: String
    let isOutgoing: Bool
    var messageId: String? = nil
    var groupPosition: ChatMessageGroupPosition = .single
    let reactions: [String: [String]]?
    var isStarred: Bool = false
    var repliedMessage: EnhancedMessage? = nil
    var otherParticipantName: String = ""
    var onReplyTap: (() -> Void)? = nil
    let onReaction: (String) -> Void

    @State private var revealSpoilers = false
    @Environment(\.chatSearchHighlightTerm) private var searchHighlightTerm
    @Environment(\.chatSearchActiveMessageId) private var activeSearchMessageId
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

    private var hasReply: Bool {
        repliedMessage != nil
    }

    private var hasLink: Bool {
        ChatLinkOpener.firstURL(in: text) != nil
    }

    /// La burbuja se coloca según el remitente, pero su contenido siempre se lee
    /// desde el inicio de línea, igual que en Mensajes y el resto de mensajería.
    private var stackAlignment: HorizontalAlignment {
        .leading
    }

    private var textAlignment: TextAlignment {
        .leading
    }

    private var contentFrameAlignment: Alignment {
        .leading
    }

    private func parseSegments(_ input: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        let parts = input.components(separatedBy: "||")
        for (index, part) in parts.enumerated() {
            let isSpoiler = index % 2 != 0
            if !part.isEmpty {
                segments.append(TextSegment(text: part, isSpoiler: isSpoiler))
            }
        }
        return segments
    }

    private var linkColor: Color {
        isOutgoing ? Color.white.opacity(0.92) : .blue
    }

    private var formattedAttributedString: AttributedString {
        var combined = AttributedString("")
        let segments = parseSegments(text)
        for segment in segments {
            var segmentAttr: AttributedString
            if let parsed = try? AttributedString(markdown: segment.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                segmentAttr = parsed
            } else {
                segmentAttr = AttributedString(segment.text)
            }

            if segment.isSpoiler {
                if !revealSpoilers {
                    segmentAttr.foregroundColor = .clear
                    // Display as solid block
                    segmentAttr.backgroundColor = textColor.opacity(0.85)
                } else {
                    segmentAttr.foregroundColor = textColor
                    segmentAttr.backgroundColor = textColor.opacity(0.12)
                    ChatLinkOpener.applyDetectedLinks(
                        to: &segmentAttr,
                        in: segment.text,
                        linkColor: linkColor
                    )
                }
            } else {
                segmentAttr.foregroundColor = textColor
                ChatLinkOpener.applyDetectedLinks(
                    to: &segmentAttr,
                    in: segment.text,
                    linkColor: linkColor
                )
            }
            combined.append(segmentAttr)
        }
        applySearchHighlight(to: &combined)
        return combined
    }

    private var searchHighlightBackground: Color {
        Color(red: 1.0, green: 0.82, blue: 0.25).opacity(isActiveSearchMatch ? 0.92 : 0.45)
    }

    private var isActiveSearchMatch: Bool {
        guard let messageId, let activeSearchMessageId else { return false }
        return messageId == activeSearchMessageId
    }

    private func applySearchHighlight(to attributed: inout AttributedString) {
        let term = searchHighlightTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !(hasSpoilers && !revealSpoilers) else { return }

        let plain = String(attributed.characters)
        guard !plain.isEmpty else { return }

        var searchStart = plain.startIndex
        while searchStart < plain.endIndex,
              let found = plain.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<plain.endIndex
              ) {
            let lowerOffset = plain.distance(from: plain.startIndex, to: found.lowerBound)
            let upperOffset = plain.distance(from: plain.startIndex, to: found.upperBound)
            let attrLower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
            let attrUpper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
            attributed[attrLower..<attrUpper].backgroundColor = searchHighlightBackground
            attributed[attrLower..<attrUpper].foregroundColor = isActiveSearchMatch ? .black : nil
            searchStart = found.upperBound > searchStart ? found.upperBound : plain.index(after: searchStart)
        }
    }

    private var hasSpoilers: Bool {
        parseSegments(text).contains(where: \.isSpoiler)
    }

    var body: some View {
        textContent
            .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
    }

    private var textContent: some View {
        Group {
            if hasSpoilers {
                bubbleText
                    .onTapGesture {
                        if UIAccessibility.isReduceMotionEnabled {
                            revealSpoilers.toggle()
                        } else {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                revealSpoilers.toggle()
                            }
                        }
                    }
                    .accessibilityHint(Text(NSLocalizedString("chat.a11y.spoilerHint", comment: "Hidden spoiler hint")))
                    .accessibilityAddTraits(.isButton)
            } else {
                bubbleText
            }
        }
    }

    private var messageText: some View {
        Text(formattedAttributedString)
            .font(ChatMessageFont.bubble)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                ChatLinkOpener.open(url)
                return .handled
            })
    }

    private var bubbleText: some View {
        VStack(alignment: stackAlignment, spacing: 6) {
            if let repliedMessage {
                EmbeddedReplyView(
                    repliedMessage: repliedMessage,
                    isOutgoingBubble: isOutgoing,
                    otherParticipantName: otherParticipantName,
                    onTap: onReplyTap
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let linkURL = ChatLinkOpener.firstURL(in: text) {
                LinkPreviewCard(url: linkURL, embedded: true, isOutgoing: isOutgoing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            messageText
                .frame(
                    maxWidth: (hasReply || hasLink) ? .infinity : nil,
                    alignment: contentFrameAlignment
                )
                .padding(.horizontal, hasReply ? 4 : 0)
        }
            .padding(.horizontal, hasReply ? 6 : horizontalPadding)
            .padding(.top, hasReply ? 6 : verticalPadding)
            .padding(.bottom, hasReply ? 8 : verticalPadding)
            .padding(
                MessageReactionMetrics.bubbleContentInsets(
                    isOutgoing: isOutgoing,
                    compact: true,
                    hasReactions: hasReactions,
                    hasStar: isStarred
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
                isStarred: isStarred,
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
