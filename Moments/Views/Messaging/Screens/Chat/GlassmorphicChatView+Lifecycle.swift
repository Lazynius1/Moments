import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    // MARK: - Helper Methods
    func setupOnlineStatusObserver() {
        let otherUserId = viewModel.conversation.otherParticipantId

        statusListener = onlineStatusService.observeUserStatus(userId: otherUserId) { status, lastSeen in
            DispatchQueue.main.async {
                self.otherUserStatus = status
                self.otherUserLastSeen = lastSeen
            }
        }
    }

    func handleCameraCapture(
        data: Data,
        mediaType: EnhancedCameraPickerView.MediaType,
        mode: ChatMediaSendMode,
        overlayPayload: ChatMediaOverlayPayload? = nil
    ) {
        guard !isOtherParticipantUnavailable else {
            showEnhancedCamera = false
            return
        }

        guard viewModel.conversation.id != nil else {
            return
        }

        let replyTo = pendingCameraReplyToMessageId
        pendingCameraReplyToMessageId = nil

        switch mode {
        case .viewOnce:
            viewModel.sendViewOnceMessage(data: data, mediaType: mediaType, allowReplay: false, replyTo: replyTo, overlayPayload: overlayPayload)
        case .allowReplay:
            viewModel.sendViewOnceMessage(data: data, mediaType: mediaType, allowReplay: true, replyTo: replyTo, overlayPayload: overlayPayload)
        case .keepInChat:
            if mediaType == .image {
                viewModel.sendImageMessage(data, replyTo: replyTo)
            } else {
                viewModel.sendVideoMessage(data: data, mediaBatchId: nil, replyTo: replyTo)
            }
        }

        showEnhancedCamera = false
    }

    // El visor de view-once se cierra a sí mismo (dismiss del fullScreenCover) al
    // pedir la cámara; sin este pequeño delay, showEnhancedCamera=true compite con
    // ese dismiss y SwiftUI puede no presentar el segundo fullScreenCover.
    func openCameraForReply(to messageId: String) {
        pendingCameraReplyToMessageId = messageId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showEnhancedCamera = true
        }
    }

    func presentViewOnceViewer(message: EnhancedMessage, isReplaySession: Bool) {
        let authorName = message.senderId == viewModel.currentUserId
            ? NSLocalizedString("chat.reply.you", comment: "You")
            : otherParticipantDisplayName
        viewOnceViewerPresentation = ViewOnceViewerPresentation(
            message: message,
            authorName: authorName,
            isReplaySession: isReplaySession
        )
    }

    func handleViewOnceViewerViewed(_ presentation: ViewOnceViewerPresentation) {
        let message = presentation.message
        let viewerId = viewModel.currentUserId

        if message.allowReplay == true, !presentation.isReplaySession {
            ViewOnceReplaySessionStore.shared.markAvailable(message: message, viewerId: viewerId)
            message.replayAvailableInCurrentChatSession = true
        }

        ChatService.shared.markViewOnceAsViewed(
            conversationId: message.conversationId,
            messageId: message.id,
            viewerId: viewerId
        ) { _ in }
    }

    func handleViewOnceReplayConsumed(_ presentation: ViewOnceViewerPresentation) {
        let message = presentation.message
        let viewerId = viewModel.currentUserId

        ViewOnceReplaySessionStore.shared.markConsumed(message: message, viewerId: viewerId)
        message.replayAvailableInCurrentChatSession = false
        message.replayConsumedInCurrentChatSession = true
    }

    func refreshOtherParticipantUsername() {
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else {
            liveOtherParticipantUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: otherUserId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                self.liveOtherParticipantUsername = fetchedUsername
            }
        }
    }

    func refreshOtherParticipantAvailability() {
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty, NetworkMonitor.shared.isConnected else { return }

        firestoreService.checkPublicProfileAvailability(userId: otherUserId) { availability in
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                if availability == .unavailable {
                    self.markOtherParticipantUnavailable(clearLiveUsername: true)
                } else {
                    self.refreshOtherParticipantBlockAvailability(userId: otherUserId)
                }
            }
        }
    }

    func refreshOtherParticipantBlockAvailability(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.checkIfBlocked(currentUserId: currentUserId, targetUserId: userId) { isBlockedByCurrentUser, isCurrentUserBlocked, _ in
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == userId else { return }

                if isBlockedByCurrentUser || isCurrentUserBlocked {
                    self.isOtherParticipantBlockedByCurrentUser = isBlockedByCurrentUser
                    self.markOtherParticipantUnavailable(clearLiveUsername: false)
                } else {
                    self.isOtherParticipantBlockedByCurrentUser = false
                    self.isOtherParticipantUnavailable = false
                    self.refreshOtherParticipantUsername()
                }
            }
        }
    }

    func markOtherParticipantUnavailable(clearLiveUsername: Bool) {
        isOtherParticipantUnavailable = true
        if clearLiveUsername {
            liveOtherParticipantUsername = ""
            isOtherParticipantBlockedByCurrentUser = false
        }
        disableUnavailableParticipantStories()
    }

    func unblockOtherParticipantFromChat() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else { return }

        firestoreService.unblockUser(currentUserId: currentUserId, targetUserId: otherUserId) { error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                self.isOtherParticipantBlockedByCurrentUser = false
                self.isOtherParticipantUnavailable = false
                self.refreshOtherParticipantUsername()
                self.checkUserStories()
            }
        }
    }

    func disableUnavailableParticipantStories() {
        storyRoute = nil
        hasStory = false
        hasUnseenStory = false
        storyCount = 0
        storyViewedStatus = []
        storyAudiences = []
    }

    func shouldShowAvatar(for message: EnhancedMessage, in messages: [EnhancedMessage]) -> Bool {
        let source = viewModel.messages
        guard let index = viewModel.messageIndexById[message.id], index < source.count else { return true }
        if index == source.count - 1 { return true }
        return source[index + 1].senderId != message.senderId
    }

    func messageGroupPosition(for message: EnhancedMessage, in messages: [EnhancedMessage]) -> ChatMessageGroupPosition {
        let source = viewModel.messages
        guard let index = viewModel.messageIndexById[message.id], index < source.count else { return .single }
        let prevSameSender = index > 0 && source[index - 1].senderId == message.senderId
        let nextSameSender = index < source.count - 1 && source[index + 1].senderId == message.senderId

        switch (prevSameSender, nextSameSender) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

}
