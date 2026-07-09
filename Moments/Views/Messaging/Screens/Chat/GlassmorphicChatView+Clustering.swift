import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    // MARK: - Clustering Logic
    func clusterMessages(_ input: [EnhancedMessage]) -> [MessageItem] {
        ClusterMessageGrouper.group(input)
    }

    func jumpTo(_ messageId: String, proxy: ScrollViewProxy?) {
        _ = proxy
        jumpToMessageInList(messageId)
    }

    func jumpToMessageInList(_ messageId: String) {
        isPinnedToBottom = false
        listIsAtBottom = false
        let rowId = messageRowId(containingMessageId: messageId) ?? messageId
        chatListController.scrollToRow(id: rowId, at: .centeredVertically, animated: !reduceMotion)
        highlightMessages([messageId], scroll: false)
    }

    func highlightMessages(
        _ messageIds: Set<String>,
        duration: TimeInterval = ChatBubbleAnchorMetrics.highlightDuration,
        scroll: Bool = false
    ) {
        guard !messageIds.isEmpty else { return }

        if scroll, let targetId = messageIds.first {
            let rowId = messageRowId(containingMessageId: targetId) ?? targetId
            chatListController.scrollToRow(id: rowId, at: .centeredVertically, animated: !reduceMotion)
        }

        let insertAnimation: Animation? = reduceMotion ? nil : MotionPolicy.Spring.press
        let removeAnimation: Animation? = reduceMotion ? nil : MotionPolicy.Spring.row
        withAnimation(insertAnimation) {
            flashingMessageIds.formUnion(messageIds)
        }
        HapticManager.shared.mediumImpact()

        let idsToClear = messageIds
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(removeAnimation) {
                flashingMessageIds.subtract(idsToClear)
            }
        }
    }

    func resolvePendingBuzzEventForReplay() -> ChatBuzzEvent? {
        if let intent = notificationOpenIntent, intent.playBuzzOnOpen {
            if let event = resolvePendingBuzzEvent(for: intent) {
                return event
            }
            if intent.buzzEventId != nil {
                return nil
            }
        }
        return viewModel.pendingReplayBuzzEvent()
    }

    func resolvePendingBuzzEvent(
        for intent: ChatNavigationIntentStore.OpenIntent
    ) -> ChatBuzzEvent? {
        if let buzzEventId = intent.buzzEventId,
           !buzzEventId.isEmpty,
           let event = viewModel.buzzEvents.first(where: { $0.id == buzzEventId }) {
            return event
        }

        if intent.buzzEventId != nil {
            return nil
        }

        let recentCutoff = Date().addingTimeInterval(-ChatBuzzProcessedStore.replayWindow)
        return viewModel.buzzEvents
            .filter { $0.senderId != viewModel.currentUserId && $0.createdAt >= recentCutoff }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    func handleMomentNavigationFromChat(message: EnhancedMessage) {
        if let sharedMomentData = message.sharedMomentData,
           let momentId = sharedMomentData["momentId"] {

            // ✅ CORREGIDO: Obtener el authorId del momento compartido o usar el senderId como fallback
            let authorId = sharedMomentData["momentAuthorId"] ?? message.senderId

            firestoreService.fetchMoment(momentId: momentId, userId: authorId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(var moment):
                        if moment.id == nil {
                            moment.id = momentId
                        }
                        self.selectedMoment = moment
                        self.showingMomentDetail = true
                    case .failure:
                        self.showingMomentError = true
                    }
                }
            }
        }
    }

    func handleStoryNavigationFromChat(message: EnhancedMessage) {
        guard let sharedStoryData = message.sharedStoryData,
              let storyId = sharedStoryData["storyId"],
              let viewerId = Auth.auth().currentUser?.uid else { return }

        let authorId = sharedStoryData["storyAuthorId"] ?? message.senderId
        guard !authorId.isEmpty else {
            storyUnavailableReason = .restricted
            showingStoryUnavailable = true
            return
        }

        let payloadExpiration = sharedStoryData["storyExpiration"].flatMap { TimeInterval($0) }

        SharedStoryAccessEvaluator.evaluate(
            authorId: authorId,
            storyId: storyId,
            payloadExpiration: payloadExpiration,
            viewerId: viewerId
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let story):
                    storyRoute = ChatStoryRoute(story: story)
                case .failure(let reason):
                    storyUnavailableReason = reason
                    showingStoryUnavailable = true
                }
            }
        }
    }
}
