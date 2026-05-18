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

struct GlassmorphicReactionsView: View {
    let reactions: [String: [String]]
    let onTap: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(reactions.keys), id: \.self) { emoji in
                Button(action: { onTap(emoji) }) {
                    HStack(spacing: 2) {
                        Text(emoji)
                            .font(.caption)
                        if let count = reactions[emoji]?.count, count > 1 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(adaptiveColors.messageBubbleBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct MessageTimestamp: View {
    let message: EnhancedMessage
    let status: MessageStatus
    let isCurrentUser: Bool
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
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
                MessageStatusIcon(status: status)
            }
        }
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
            HStack(spacing: 2) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(adaptiveColors.timestampColor)

                Text("chat.sending")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(adaptiveColors.timestampColor.opacity(0.8))
            }
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
