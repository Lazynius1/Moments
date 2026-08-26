import SwiftUI
import FirebaseAuth

extension EnhancedNotificationRow {

    var isModerationNotification: Bool {
        group.notifications.first?.type == .mediaModeration
    }

    func isStoryMention(_ notification: Notification) -> Bool {
        notification.type == .mention && (notification.mentionContext == "story" || notification.storyId != nil)
    }

    func isMomentMention(_ notification: Notification) -> Bool {
        notification.type == .mention && !isStoryMention(notification) && notification.momentId != nil
    }

    func storyAuthorId(for notification: Notification) -> String {
        notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    }

    func momentAuthorId(for notification: Notification) -> String? {
        notification.targetAuthorId
    }

    // MARK: - Métodos auxiliares (mantenidos del original)
    
    // Resuelve el dueño real de la historia. En storyReaction la historia es del
    // usuario actual (es quien recibe la reacción), no del remitente.
    func resolvedStoryAuthorId(for notification: Notification) -> String {
        if let authorId = notification.storyAuthorId, !authorId.isEmpty {
            return authorId
        }
        if notification.type == .storyReaction {
            return Auth.auth().currentUser?.uid ?? notification.senderId
        }
        return notification.targetAuthorId ?? notification.senderId
    }

    func fetchStoryPreview(storyId: String, authorId: String) {
        let userId = authorId
        guard !userId.isEmpty else { return }
        if storyImagePath == nil {
            isLoadingStoryImage = true
        }

        StoryRepository().fetchStory(userId: userId, storyId: storyId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let story):
                    storyPreviewModel = story
                    storyImagePath = storyPreviewURL(for: story)
                    storyImageLoadFailed = false
                case .failure:
                    storyImageLoadFailed = storyImagePath == nil
                }
                isLoadingStoryImage = false
            }
        }
    }

}
