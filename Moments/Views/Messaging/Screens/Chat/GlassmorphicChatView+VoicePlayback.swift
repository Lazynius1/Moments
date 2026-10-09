import SwiftUI

// MARK: - Notas de voz: mini barra y reproducción seguida

extension GlassmorphicChatView {
    /// Conecta el reproductor compartido con este chat (al aparecer).
    func configureVoicePlayback() {
        let playback = ChatVoicePlaybackController.shared
        playback.nextVoiceNoteProvider = { messageId in
            guard let next = nextVoiceNoteMessage(after: messageId),
                  let mediaUrl = next.mediaUrl,
                  let url = URL(string: mediaUrl) else { return nil }
            return ChatVoiceQueueItem(
                messageId: next.id,
                url: url,
                duration: next.duration ?? 0,
                senderId: next.senderId
            )
        }
        // Mientras suena una nota, descifra/descarga la siguiente para que empiece sin espera
        // aunque su burbuja no esté en pantalla.
        playback.onActiveMessageChanged = { messageId in
            guard let next = nextVoiceNoteMessage(after: messageId) else { return }
            viewModel.hydrateMediaIfNeeded(for: next)
        }
    }

    /// Al salir del chat se para la nota y se suelta la referencia a este chat.
    func tearDownVoicePlayback() {
        let playback = ChatVoicePlaybackController.shared
        playback.reset()
        playback.nextVoiceNoteProvider = nil
        playback.onActiveMessageChanged = nil
    }

    /// Siguiente mensaje del hilo si es una nota de voz ya enviada (sin nada entre medias).
    func nextVoiceNoteMessage(after messageId: String) -> EnhancedMessage? {
        let ordered = viewModel.messages
            .filter { !$0.isDeleted }
            .sorted {
                MessageSyncCursor(timestamp: $0.timestamp, messageId: $0.id)
                    < MessageSyncCursor(timestamp: $1.timestamp, messageId: $1.id)
            }
        guard let index = ordered.firstIndex(where: { $0.id == messageId }),
              ordered.indices.contains(index + 1) else { return nil }
        let next = ordered[index + 1]
        guard next.type == .audio, next.status != .sending, next.status != .failed else { return nil }
        return next
    }

    func voicePlaybackSenderName(_ senderId: String?) -> String {
        guard let senderId, !senderId.isEmpty else { return otherParticipantDisplayName }
        if senderId == viewModel.currentUserId {
            return NSLocalizedString("chat.reply.you", comment: "You")
        }
        return viewModel.conversation.isGroup ? groupSenderName(senderId) : otherParticipantDisplayName
    }

    var voiceMiniPlayer: some View {
        ChatVoiceMiniPlayerHost(
            adaptiveColors: adaptiveColors,
            senderName: { voicePlaybackSenderName($0) },
            onJump: { messageId in handleJumpToMessageFromOutside(messageId) }
        )
    }
}

/// Observa el reproductor por su cuenta para que el progreso (20 veces por segundo)
/// no redibuje la pantalla entera del chat.
struct ChatVoiceMiniPlayerHost: View {
    @ObservedObject private var playback = ChatVoicePlaybackController.shared
    let adaptiveColors: AdaptiveColors
    let senderName: (String?) -> String
    let onJump: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        playback.activeMessageId != nil && !playback.isActiveBubbleVisible
    }

    var body: some View {
        ZStack {
            if isVisible, let messageId = playback.activeMessageId {
                ChatVoiceMiniPlayerBar(
                    playback: playback,
                    senderName: senderName(playback.activeSenderId),
                    adaptiveColors: adaptiveColors,
                    onTap: { onJump(messageId) }
                )
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : MotionPolicy.Spring.header, value: isVisible)
    }
}
