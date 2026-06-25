import SwiftUI
import FirebaseAuth

struct InAppMessageQuickReplyPanel: View {
    let notification: Notification
    let onDismiss: () -> Void

    @ObservedObject private var accessCoordinator = ChatAccessCoordinator.shared
    @ObservedObject private var service = InAppNotificationService.shared
    @State private var replyText = ""
    @State private var isSending = false
    @FocusState private var isFieldFocused: Bool

    private var previewText: String? {
        let copy = NotificationCopyResolver.resolve(notification)
        if let body = copy.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            if body == NSLocalizedString("notification.message.single.text", comment: "")
                || body == NSLocalizedString("notification.message.single.default", comment: "") {
                return nil
            }
            return body
        }
        if let messageType = notification.messageType,
           let type = MessageType(rawValue: messageType),
           type != .text {
            return type.conversationPreview
        }
        return nil
    }

    private var canReply: Bool {
        accessCoordinator.isAvailable && notification.conversationId?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AsyncProfileImageView(userId: notification.senderId)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.senderUsername)
                        .font(.system(size: legacyPoppinsSize(15), weight: .bold))
                        .foregroundColor(.primary)
                    Text(NSLocalizedString("notification.action.reply", comment: "Reply"))
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let previewText {
                Text(previewText)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if canReply {
                HStack(spacing: 10) {
                    TextField(
                        NSLocalizedString("notification.action.placeholder", comment: "Message"),
                        text: $replyText,
                        axis: .vertical
                    )
                    .font(.system(size: legacyPoppinsSize(15)))
                    .lineLimit(1...4)
                    .focused($isFieldFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06))
                    .clipShape(Capsule())

                    Button(action: sendReply) {
                        Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor
                            )
                    }
                    .disabled(isSending || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
            } else {
                Text(NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable"))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .onAppear {
            service.pauseDismissTimer()
            Task { _ = await accessCoordinator.ensureAccess() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if canReply { isFieldFocused = true }
            }
        }
        .onDisappear {
            service.resumeDismissTimerIfNeeded()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let conversationId = notification.conversationId,
              let senderId = Auth.auth().currentUser?.uid else { return }

        isSending = true
        ChatService.shared.sendTextMessage(
            conversationId: conversationId,
            senderId: senderId,
            content: trimmed
        ) { _ in
            DispatchQueue.main.async {
                isSending = false
                HapticManager.shared.notification(.success)
                onDismiss()
                service.dismissManually()
            }
        }
    }
}
