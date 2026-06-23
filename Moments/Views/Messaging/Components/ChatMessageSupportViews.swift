import SwiftUI
import FirebaseAuth
import Kingfisher

struct GlassmorphicReplyBar: View {
    let message: EnhancedMessage
    let otherParticipantName: String
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                .frame(width: 3.5)
                .padding(.vertical, 8)
                .padding(.leading, 1)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.senderId == currentUserId ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)

                    Text(message.preview)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(adaptiveColors.replyBarText)
                        .lineLimit(1)
                }

                Spacer()

                if let mediaUrl = message.thumbnailUrl ?? message.mediaUrl, let url = URL(string: mediaUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 8)
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(adaptiveColors.replyBarSecondaryText)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(adaptiveColors.replyBarBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
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

    var body: some View {
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
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .foregroundColor(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)

                        Text(message.preview)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.messageTextColor.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    if let mediaUrl = message.thumbnailUrl ?? message.mediaUrl, let url = URL(string: mediaUrl) {
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
                    .foregroundColor(MomentsChromeGlass.contentColor(for: colorScheme))
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

    private var separatorColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

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
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.65))
                    }
                } else {
                    Text(entry.emoji)
                        .font(.system(size: emojiSize))
                }
            }
            .frame(width: badgeDiameter, height: badgeDiameter)
            .background(
                Circle()
                    .fill(separatorColor)
            )
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

enum MessageReactionMetrics {
    static func emojiSize(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 12 }
        return compact ? 16 : 18
    }

    static func countSize(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 7 }
        return compact ? 8 : 10
    }

    static func badgeDiameter(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return 18 }
        return compact ? 24 : 28
    }

    static func overlapSpacing(compact: Bool, cluster: Bool) -> CGFloat {
        if cluster { return -5 }
        return compact ? -6 : -8
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
    static func reactionRowSpacing(compact: Bool, cluster: Bool = false) -> CGFloat {
        let diameter = badgeDiameter(compact: compact, cluster: cluster)
        return diameter * 0.58
    }

    /// Reserva en la burbuja de texto para que el emoji no tape letras cortas.
    static func bubbleContentInsets(isOutgoing: Bool, compact: Bool, hasReactions: Bool) -> EdgeInsets {
        guard hasReactions else { return EdgeInsets() }
        let clearance = badgeDiameter(compact: compact, cluster: false) * 0.42
        return EdgeInsets(
            top: 0,
            leading: isOutgoing ? clearance * 0.75 : 0,
            bottom: clearance * 0.3,
            trailing: isOutgoing ? 0 : clearance * 0.75
        )
    }
}

extension View {
    func messageReactionOverlay(
        isOutgoing: Bool,
        reactions: [String: [String]]?,
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

        return overlay(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
            if let reactions, !reactions.isEmpty {
                MessageReactionChip(reactions: reactions, onTap: onTap, compact: compact)
                    .offset(
                        x: isOutgoing ? horizontalOffset : -horizontalOffset,
                        y: anchoredInsideBounds ? -3 : hangOffset
                    )
                    .zIndex(5)
            }
        }
        .padding(.bottom, hasReactions && !anchoredInsideBounds ? rowSpacing : 0)
    }
}

/// Alias legacy — usar `MessageReactionChip`.
typealias GlassmorphicReactionsView = MessageReactionChip

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
                .font(.custom("Poppins-Regular", size: 11))
                .foregroundColor(adaptiveColors.timestampColor)

            if message.editedAt != nil {
                Text("chat.edited")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(adaptiveColors.timestampColor)
            }

            if isCurrentUser {
                if showSeenLabel && displayStatus == .read {
                    Text("chat.seen")
                        .font(.custom("Poppins-Medium", size: 11))
                        .foregroundColor(adaptiveColors.timestampColor.opacity(0.9))
                } else {
                    MessageStatusIcon(status: displayStatus)
                }
            }
        }
        .id("\(message.id)-\(displayStatus.rawValue)")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                .foregroundColor(adaptiveColors.timestampColor.opacity(0.8))
        case .sending:
            ProgressView()
                .scaleEffect(0.45)
                .tint(adaptiveColors.timestampColor)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(adaptiveColors.timestampColor)
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(adaptiveColors.timestampColor)
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(adaptiveColors.userAccentColor)
        case .failed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.red)

                Text("chat.error")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
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
            insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.7)),
            removal: .scale.combined(with: .opacity).animation(.easeOut(duration: 0.2))
        ))
    }
}
