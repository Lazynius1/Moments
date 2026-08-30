import SwiftUI

struct ForwardMessageWrapper: Identifiable {
    let message: EnhancedMessage
    var id: String { message.id }
}

struct ChatMessageForwardSheet: View {
    let message: EnhancedMessage
    let onDismiss: () -> Void
    let onForward: (Set<String>) -> Void

    var body: some View {
        ShareRecipientsPickerSheet(
            titleKey: "chat.forward.title",
            subtitle: message.content.map {
                ChatTextMarkup.plainText(from: $0, hidesSpoilers: true)
            },
            showsBackButton: false,
            flexibleListHeight: true,
            onDismiss: onDismiss,
            onSend: { selectedUsers, _ in
                guard !selectedUsers.isEmpty else { return }
                onForward(selectedUsers)
                HapticManager.shared.success()
                onDismiss()
            }
        )
    }
}
