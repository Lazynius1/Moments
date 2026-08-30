import SwiftUI
import FirebaseAuth
import Kingfisher

enum ChatComposerContextMode: Equatable {
    case reply
    case edit
}

struct ChatComposerContextPanel: View {
    let replyingTo: EnhancedMessage?
    let editingMessage: EnhancedMessage?
    let otherParticipantName: String
    let onCancelReply: () -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        if let editingMessage {
            ChatComposerReplyHeader(
                message: editingMessage,
                otherParticipantName: otherParticipantName,
                mode: .edit,
                onCancel: onCancelEdit
            )
        } else if let replyingTo {
            ChatComposerReplyHeader(
                message: replyingTo,
                otherParticipantName: otherParticipantName,
                mode: .reply,
                onCancel: onCancelReply
            )
        }
    }
}

struct ChatComposerReplyHeader: View {
    let message: EnhancedMessage
    let otherParticipantName: String
    let mode: ChatComposerContextMode
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme

    /// Debe coincidir con `GlassmorphicInputBar.inputFieldShape`.
    private static let fieldCornerRadius: CGFloat = 22

    private var composerReplyHeaderTopShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.fieldCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.fieldCornerRadius,
            style: .continuous
        )
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var isVanishProtected: Bool {
        message.isVanishModeMessage == true
    }

    private var accentColor: Color {
        if mode == .edit {
            return adaptiveColors.userAccentColor
        }
        return message.senderId == currentUserId
            ? adaptiveColors.userAccentColor
            : adaptiveColors.receivedAccentColor
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(hex: "151C1D") : Color(hex: "E8EEF0")
    }

    var body: some View {
        Group {
            if isVanishProtected {
                ScreenshotProtectedView(isProtected: true, cornerRadius: Self.fieldCornerRadius) {
                    replyBarContent
                }
            } else {
                replyBarContent
            }
        }
    }

    private var replyBarContent: some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                if mode == .edit {
                    Text("chat.editing.title")
                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        .foregroundStyle(accentColor)
                } else {
                    Text(message.senderId == currentUserId ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                Text(message.preview)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !message.isViewOnce,
               let mediaUrl = message.replyPreviewThumbnailURL,
               let url = URL(string: mediaUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.62))
                    .frame(width: 28, height: 28)
                    .background(
                        colorScheme == .dark
                            ? Color.white.opacity(0.09)
                            : Color.black.opacity(0.08),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.cancel"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(surfaceColor, in: composerReplyHeaderTopShape)
        .clipShape(composerReplyHeaderTopShape)
    }
}

struct GlassmorphicReplyPreview: View {
    let message: EnhancedMessage
    let isParentMessageFromCurrentUser: Bool
    let otherParticipantName: String
    let onTap: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var isVanishProtected: Bool {
        message.isVanishModeMessage == true
    }

    var body: some View {
        Group {
            if isVanishProtected {
                ScreenshotProtectedView(isProtected: true, cornerRadius: 10) {
                    replyPreviewButton
                }
            } else {
                replyPreviewButton
            }
        }
    }

    private var replyPreviewButton: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 0) {
                Capsule()
                    .fill(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                    .frame(width: 2.5)
                    .padding(.vertical, 6)
                    .padding(.leading, 1)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.senderId == currentUserId ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                            .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                            .foregroundStyle(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)

                        Text(message.preview)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    if !message.isViewOnce, let mediaUrl = message.replyPreviewThumbnailURL, let url = URL(string: mediaUrl) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(adaptiveColors.messageBubbleBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(minWidth: 120, maxWidth: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(adaptiveColors.messageBubbleStroke.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Cita de respuesta apilada encima de la burbuja: etiqueta «Respondiste a…/… respondió»
/// + fragmento atenuado del mensaje citado, alineado al lado del autor.
struct StackedReplyQuote: View {
    let repliedMessage: EnhancedMessage
    /// La fila (la respuesta) la escribe el usuario actual.
    let isOutgoingRow: Bool
    let otherParticipantName: String
    let onTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }
    private var repliedToSelf: Bool { repliedMessage.senderId == currentUserId }
    private var isVanishProtected: Bool { repliedMessage.isVanishModeMessage == true }

    private var captionText: String {
        if isOutgoingRow {
            let name = repliedToSelf
                ? NSLocalizedString("chat.reply.you", comment: "")
                : otherParticipantName
            return String(format: NSLocalizedString("chat.reply.youRepliedTo", comment: ""), name)
        }
        return String(format: NSLocalizedString("chat.reply.repliedTo", comment: ""), otherParticipantName)
    }

    var body: some View {
        Group {
            if isVanishProtected {
                ScreenshotProtectedView(isProtected: true, cornerRadius: 13) { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            onTap?()
        }) {
            VStack(alignment: isOutgoingRow ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 9))
                    Text(captionText)
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.5))
                .padding(.horizontal, 6)

                quoteSnippet
            }
            .frame(maxWidth: 240, alignment: isOutgoingRow ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(captionText), \(repliedMessage.preview)")
        .accessibilityAddTraits(.isButton)
    }

    private var quoteSnippet: some View {
        HStack(spacing: 7) {
            if !repliedMessage.isViewOnce, let mediaUrl = repliedMessage.replyPreviewThumbnailURL, let url = URL(string: mediaUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(repliedMessage.preview)
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.65))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(adaptiveColors.messageBubbleBackground.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(adaptiveColors.messageBubbleStroke.opacity(0.4), lineWidth: 0.5)
        )
    }
}

/// Reply citado EMBEBIDO dentro de la burbuja: barra de color,
/// fondo tintado, llena el ancho de la burbuja y queda pegado encima del texto.
struct EmbeddedReplyView: View {
    let repliedMessage: EnhancedMessage
    let isOutgoingBubble: Bool
    let otherParticipantName: String
    let onTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var repliedToSelf: Bool {
        repliedMessage.senderId == currentUserId
    }

    private var accent: Color {
        repliedToSelf ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor
    }

    private var tint: Color {
        if isOutgoingBubble {
            return Color.white.opacity(0.18)
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var barColor: Color {
        isOutgoingBubble ? Color.white.opacity(0.9) : accent
    }

    private var titleColor: Color {
        isOutgoingBubble ? Color.white.opacity(0.95) : accent
    }

    private var bodyColor: Color {
        isOutgoingBubble ? Color.white.opacity(0.8) : adaptiveColors.messageTextColor.opacity(0.7)
    }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(repliedToSelf ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                Text(repliedMessage.preview)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(bodyColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if !repliedMessage.isViewOnce, let mediaUrl = repliedMessage.replyPreviewThumbnailURL, let url = URL(string: mediaUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(repliedToSelf ? NSLocalizedString("chat.reply.you", comment: "You") : otherParticipantName), \(repliedMessage.preview)"
        )
        .accessibilityAddTraits(.isButton)
    }
}

struct ChatQuickReactionsBar: View {
    let onReaction: (String) -> Void
    let onMore: () -> Void

    @StateObject private var emojiUsageTracker = EmojiUsageTracker()

    var body: some View {
        HStack(spacing: 14) {
            ForEach(emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.chat), id: \.self) { emoji in
                Button {
                    HapticManager.shared.mediumImpact()
                    onReaction(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
            }

            Button {
                HapticManager.shared.lightImpact()
                onMore()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    @Environment(\.colorScheme) private var colorScheme
}

struct MessageReactionChip: View {
    let reactions: [String: [String]]
    let onTap: (String) -> Void
    var compact: Bool = false
    var cluster: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var sortedEntries: [(emoji: String, count: Int)] {
        reactions
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.emoji < $1.emoji }
                return $0.count > $1.count
            }
    }

    private var emojiSize: CGFloat {
        MessageReactionMetrics.emojiSize(compact: compact, cluster: cluster)
    }
    private var countSize: CGFloat {
        MessageReactionMetrics.countSize(compact: compact, cluster: cluster)
    }
    private var badgeDiameter: CGFloat {
        MessageReactionMetrics.badgeDiameter(compact: compact, cluster: cluster)
    }
    private var overlapSpacing: CGFloat {
        MessageReactionMetrics.overlapSpacing(compact: compact, cluster: cluster)
    }

    /// Área táctil mínima (HIG ~44pt). Solo en cluster, donde el badge de 18pt va en un overlay
    /// con offset (expandir es seguro y no altera el layout en fila de las reacciones normales).
    private var hitTarget: CGFloat {
        cluster ? max(44, badgeDiameter) : badgeDiameter
    }

    var body: some View {
        Group {
            if sortedEntries.count == 1, let entry = sortedEntries.first {
                singleBadge(entry)
            } else {
                HStack(spacing: overlapSpacing) {
                    ForEach(Array(sortedEntries.prefix(5)), id: \.emoji) { entry in
                        singleBadge(entry)
                    }
                }
            }
        }
    }

    private func singleBadge(_ entry: (emoji: String, count: Int)) -> some View {
        Button(action: { onTap(entry.emoji) }) {
            Group {
                if entry.count > 1 {
                    VStack(spacing: -1) {
                        Text(entry.emoji)
                            .font(.system(size: emojiSize))
                        Text("\(entry.count)")
                            .font(.system(size: countSize, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.65))
                    }
                } else {
                    Text(entry.emoji)
                        .font(.system(size: emojiSize))
                }
            }
            .frame(width: badgeDiameter, height: badgeDiameter)
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reactionAccessibilityLabel(entry))
    }

    private func reactionAccessibilityLabel(_ entry: (emoji: String, count: Int)) -> String {
        entry.count > 1 ? "\(entry.emoji) \(entry.count)" : entry.emoji
    }
}

enum MessageReactionMetrics {
    static func emojiSize(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 12 }
        return compact ? 18 : 20
    }

    static func countSize(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 7 }
        return compact ? 8 : 10
    }

    static func badgeDiameter(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 18 }
        return compact ? 22 : 24
    }

    static func overlapSpacing(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return -5 }
        return compact ? -5 : -7
    }

    static func horizontalHangOffset(compact: Bool, anchoredInsideBounds: Bool) -> CGFloat {
        if anchoredInsideBounds { return 3 }
        return compact ? 1 : 2
    }

    /// Cuánto cuelga el badge por debajo del borde inferior de la burbuja.
    static func hangOffset(compact: Bool, cluster: Bool = false) -> CGFloat {
        let diameter = badgeDiameter(compact: compact, cluster: cluster)
        return diameter * 0.62
    }

    /// Espacio extra bajo la fila para que el badge no pise el mensaje de abajo.
    /// 0.66 cubre lo que cuelga el badge (`hangOffset` = 0.62·d) con un pequeño margen.
    static func reactionRowSpacing(compact: Bool, cluster: Bool = false) -> CGFloat {
        let diameter = badgeDiameter(compact: compact, cluster: cluster)
        return diameter * 0.66
    }

    /// Mitad de la diferencia entre el área táctil (44pt) y el badge cluster, para recolocar el badge.
    static func clusterHitTargetInset(compact: Bool) -> CGFloat {
        let diameter = badgeDiameter(compact: compact, cluster: true)
        return max(0, (max(44, diameter) - diameter) / 2)
    }

    /// Reserva en la burbuja de texto para que el emoji no tape letras cortas.
    static func bubbleContentInsets(
        isOutgoing: Bool,
        compact: Bool,
        hasReactions: Bool,
        hasStar: Bool = false
    ) -> EdgeInsets {
        let reactionClearance = badgeDiameter(compact: compact, cluster: false) * 0.42
        let starClearance = starBadgeDiameter(compact: compact) * 0.42
        var leading: CGFloat = 0
        var bottom: CGFloat = 0
        var trailing: CGFloat = 0

        if hasReactions {
            bottom = max(bottom, reactionClearance * 0.3)
            if isOutgoing {
                leading = max(leading, reactionClearance * 0.75)
            } else {
                trailing = max(trailing, reactionClearance * 0.75)
            }
        }

        if hasStar {
            bottom = max(bottom, starClearance * 0.3)
            if starUsesLeadingCorner(isOutgoing: isOutgoing, hasReactions: hasReactions) {
                leading = max(leading, starClearance * 0.75)
            } else {
                trailing = max(trailing, starClearance * 0.75)
            }
        }

        guard leading > 0 || bottom > 0 || trailing > 0 else { return EdgeInsets() }
        return EdgeInsets(top: 0, leading: leading, bottom: bottom, trailing: trailing)
    }

    static func starBadgeDiameter(compact: Bool, cluster: Bool = false) -> CGFloat {
        if cluster { return 16 }
        return compact ? 20 : 22
    }

    static func starIconSize(compact: Bool, cluster: Bool = false) -> CGFloat {
        if cluster { return 8 }
        return compact ? 10 : 11
    }

    /// Esquina inferior de la estrella (opuesta a reacciones si conviven).
    static func starUsesLeadingCorner(isOutgoing: Bool, hasReactions: Bool) -> Bool {
        if hasReactions {
            return !isOutgoing
        }
        return isOutgoing
    }
}

struct MessageStarBadge: View {
    var compact: Bool = false
    var cluster: Bool = false

    private var diameter: CGFloat {
        MessageReactionMetrics.starBadgeDiameter(compact: compact, cluster: cluster)
    }

    private var iconSize: CGFloat {
        MessageReactionMetrics.starIconSize(compact: compact, cluster: cluster)
    }

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(Color(hex: "FFD60A"))
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(Text("chat.action.star"))
    }
}

extension View {
    func reversedMask<M: View>(
        alignment: Alignment = .center,
        @ViewBuilder mask: () -> M
    ) -> some View {
        self.overlay(alignment: alignment) {
            mask()
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    @ViewBuilder
    func messageReactionCutout(
        isOutgoing: Bool,
        reactions: [String: [String]]?,
        compact: Bool = false,
        anchoredInsideBounds: Bool = false,
        gap: CGFloat = 1.5
    ) -> some View {
        let hasReactions = reactions.map { !$0.isEmpty } ?? false

        if hasReactions, let reactions = reactions {
            let sortedEntries = reactions
                .map { (emoji: $0.key, count: $0.value.count) }
                .sorted {
                    if $0.count == $1.count { return $0.emoji < $1.emoji }
                    return $0.count > $1.count
                }

            let visibleCount = min(5, sortedEntries.count)
            if visibleCount > 0 {
                let diameter = MessageReactionMetrics.badgeDiameter(compact: compact, cluster: false)
                let overlap = MessageReactionMetrics.overlapSpacing(compact: compact, cluster: false)
                let chipWidth = diameter + CGFloat(visibleCount - 1) * (diameter + overlap)
                let chipHeight = diameter

                let cutoutWidth = chipWidth + gap * 2
                let cutoutHeight = chipHeight + gap * 2

                let hangOffset = MessageReactionMetrics.hangOffset(compact: compact)
                let horizontalOffset = MessageReactionMetrics.horizontalHangOffset(
                    compact: compact,
                    anchoredInsideBounds: anchoredInsideBounds
                )

                let cutoutX = isOutgoing ? (horizontalOffset - gap) : (-horizontalOffset + gap)
                let cutoutY = anchoredInsideBounds ? (-3 + gap) : (hangOffset + gap)

                self.reversedMask(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
                    Capsule()
                        .frame(width: cutoutWidth, height: cutoutHeight)
                        .offset(x: cutoutX, y: cutoutY)
                }
            } else {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func messageStarCutout(
        isStarred: Bool,
        isOutgoing: Bool,
        hasReactions: Bool,
        compact: Bool = false,
        anchoredInsideBounds: Bool = false,
        gap: CGFloat = 1.5
    ) -> some View {
        if isStarred {
            let starOnLeading = MessageReactionMetrics.starUsesLeadingCorner(
                isOutgoing: isOutgoing,
                hasReactions: hasReactions
            )
            let diameter = MessageReactionMetrics.starBadgeDiameter(compact: compact)
            let hangOffset = MessageReactionMetrics.hangOffset(compact: compact)
            let horizontalOffset = MessageReactionMetrics.horizontalHangOffset(
                compact: compact,
                anchoredInsideBounds: anchoredInsideBounds
            )
            let cutoutX = starOnLeading ? (horizontalOffset - gap) : (-horizontalOffset + gap)
            let cutoutY = anchoredInsideBounds ? (-3 + gap) : (hangOffset + gap)

            self.reversedMask(alignment: starOnLeading ? .bottomLeading : .bottomTrailing) {
                Circle()
                    .frame(width: diameter + gap * 2, height: diameter + gap * 2)
                    .offset(x: cutoutX, y: cutoutY)
            }
        } else {
            self
        }
    }

    func messageReactionOverlay(
        isOutgoing: Bool,
        reactions: [String: [String]]?,
        isStarred: Bool = false,
        compact: Bool = false,
        anchoredInsideBounds: Bool = false,
        onTap: @escaping (String) -> Void
    ) -> some View {
        let hasReactions = reactions.map { !$0.isEmpty } ?? false
        let hangOffset = MessageReactionMetrics.hangOffset(compact: compact)
        let rowSpacing = MessageReactionMetrics.reactionRowSpacing(compact: compact)
        let horizontalOffset = MessageReactionMetrics.horizontalHangOffset(
            compact: compact,
            anchoredInsideBounds: anchoredInsideBounds
        )
        let starOnLeading = MessageReactionMetrics.starUsesLeadingCorner(
            isOutgoing: isOutgoing,
            hasReactions: hasReactions
        )
        let needsBottomSpacing = (hasReactions || isStarred) && !anchoredInsideBounds

        return self
            .messageReactionCutout(
                isOutgoing: isOutgoing,
                reactions: reactions,
                compact: compact,
                anchoredInsideBounds: anchoredInsideBounds
            )
            .messageStarCutout(
                isStarred: isStarred,
                isOutgoing: isOutgoing,
                hasReactions: hasReactions,
                compact: compact,
                anchoredInsideBounds: anchoredInsideBounds
            )
            .overlay(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
                if let reactions, !reactions.isEmpty {
                    MessageReactionChip(reactions: reactions, onTap: onTap, compact: compact)
                        .offset(
                            x: isOutgoing ? horizontalOffset : -horizontalOffset,
                            y: anchoredInsideBounds ? -3 : hangOffset
                        )
                        .zIndex(5)
                }
            }
            .overlay(alignment: starOnLeading ? .bottomLeading : .bottomTrailing) {
                if isStarred {
                    MessageStarBadge(compact: compact)
                        .offset(
                            x: starOnLeading ? horizontalOffset : -horizontalOffset,
                            y: anchoredInsideBounds ? -3 : hangOffset
                        )
                        .zIndex(6)
                }
            }
            .padding(.bottom, needsBottomSpacing ? rowSpacing : 0)
    }
}

/// Alias legacy — usar `MessageReactionChip`.
typealias GlassmorphicReactionsView = MessageReactionChip

/// Acción de reintento inyectada por entorno: el badge de fallo vive dentro de la
/// burbuja (MessageTimestamp) y así no hay que propagar callbacks por cada tipo.
struct ChatFailedMessageRetryAction {
    let canRetry: (EnhancedMessage) -> Bool
    let retry: (EnhancedMessage) -> Void
}

private struct ChatFailedMessageRetryActionKey: EnvironmentKey {
    static let defaultValue: ChatFailedMessageRetryAction? = nil
}

extension EnvironmentValues {
    var chatFailedMessageRetryAction: ChatFailedMessageRetryAction? {
        get { self[ChatFailedMessageRetryActionKey.self] }
        set { self[ChatFailedMessageRetryActionKey.self] = newValue }
    }
}

struct MessageTimestamp: View {
    @ObservedObject var message: EnhancedMessage
    let isCurrentUser: Bool
    var showSeenLabel: Bool = false
    var overrideStatus: MessageStatus? = nil
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var displayStatus: MessageStatus {
        overrideStatus ?? message.status
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(formatTime(message.timestamp))
                .font(.system(size: legacyPoppinsSize(11)))
                .foregroundStyle(adaptiveColors.timestampColor)

            if message.editedAt != nil {
                Text("chat.edited")
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundStyle(adaptiveColors.timestampColor)
            }

            if isCurrentUser {
                if showSeenLabel && displayStatus == .read {
                    Text("chat.seen")
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                        .foregroundStyle(adaptiveColors.timestampColor.opacity(0.9))
                } else {
                    MessageStatusIcon(status: displayStatus)
                }
            }
        }
        .id("\(message.id)-\(displayStatus.rawValue)")
    }

    private func formatTime(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .timeOnly)
    }
}

struct MessageStatusIcon: View {
    let status: MessageStatus
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(adaptiveColors.timestampColor.opacity(0.8))
        case .sending:
            ProgressView()
                .scaleEffect(0.45)
                .tint(adaptiveColors.timestampColor)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(adaptiveColors.timestampColor)
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(adaptiveColors.timestampColor)
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(adaptiveColors.userAccentColor)
        case .failed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.red)

                Text("chat.error")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }
}

struct GlassmorphicReactionsOverlay: View {
    let emojis = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    let onReaction: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    onReaction(emoji)
                }) {
                    Text(emoji)
                        .font(.system(size: 26))
                        .scaleEffect(1.0)
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(0.8))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .transition(.asymmetric(
            insertion: MotionPolicy.Transition.enterPop.animation(MotionPolicy.Spring.toggle),
            removal: MotionPolicy.Transition.enterPop.animation(MotionPolicy.Spring.toast)
        ))
    }
}
