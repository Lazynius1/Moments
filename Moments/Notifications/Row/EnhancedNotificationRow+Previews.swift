import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

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
        isLoadingStoryImage = true
        
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, error in
                if error != nil {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                    return
                }
                
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                    return
                }
                
                if let previewURL = storyPreviewURL(from: data) {
                    DispatchQueue.main.async {
                        self.storyImagePath = previewURL
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoadingStoryImage = false
                        self.storyImageLoadFailed = true
                    }
                }
            }
    }

    func storyPreviewURL(from data: [String: Any]) -> String? {
        let mediaItem = data["mediaItem"] as? [String: Any]
        let mediaType = mediaItem?["type"] as? String

        if mediaType == MediaItem.MediaType.image.rawValue {
            return nonEmptyString(mediaItem?["url"])
                ?? nonEmptyString(data["imagePath"])
        }

        if mediaType == MediaItem.MediaType.video.rawValue {
            return nonEmptyString(mediaItem?["thumbnailUrl"])
                ?? nonEmptyString(data["backgroundFrameURL"])
                ?? nonEmptyString(data["backgroundBlurredFrameURL"])
        }

        return nonEmptyString(data["imagePath"])
            ?? nonEmptyString(mediaItem?["thumbnailUrl"])
            ?? nonEmptyString(data["backgroundFrameURL"])
            ?? nonEmptyString(data["backgroundBlurredFrameURL"])
            ?? nonEmptyString(mediaItem?["url"])
    }

    func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}
