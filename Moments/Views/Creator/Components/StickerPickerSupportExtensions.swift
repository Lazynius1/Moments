import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Extensions y Efectos Visuales (AGREGAR AL FINAL)

extension View {
    func glow(color: Color, radius: CGFloat) -> some View {
        self
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
    }

    func pressAnimation() -> some View {
        buttonStyle(.momentsPress)
    }
}

// MARK: - MeshGradient Fallback para iOS < 18
struct MeshGradient: View {
    let width: Int
    let height: Int
    let points: [[Float]]
    let colors: [Color]

    var body: some View {
        LinearGradient(
            colors: [colors.first ?? .black, colors.last ?? .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func pressAnimatioon() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    // Animation handled by button press
                }
            }
    }
}

// MARK: - Notificación de Menciones
struct StoryMentionNotificationResult {
    let sentUserIds: [String]
    let skippedOutsideAudienceUserIds: [String]
    let failedDeliveryUserIds: [String]
}

extension StickerPickerView {
    // ✅ Función para enviar notificaciones de menciones al publicar historia
    static func sendMentionNotificationsForStory(storyId: String, stickers: [StickerItem]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        Task {
            _ = await sendMentionNotificationsForStory(
                storyId: storyId,
                storyAuthorId: currentUserId,
                audience: .everyone,
                customViewers: nil,
                customListId: nil,
                stickers: stickers
            )
        }
    }

    static func sendMentionNotificationsForStory(
        storyId: String,
        storyAuthorId: String,
        audience: ContentAudience,
        customViewers: [String]?,
        customListId: String?,
        stickers: [StickerItem]
    ) async -> StoryMentionNotificationResult {
        // ✅ Filtrar solo stickers de menciones
        let mentionedUserIds = Array(Set(stickers
            .filter { $0.type == .mention }
            .compactMap { $0.interactionData?.userId }
            .filter { !$0.isEmpty && $0 != storyAuthorId }
        ))

        var sentUserIds: [String] = []
        var skippedOutsideAudienceUserIds: [String] = []
        var failedDeliveryUserIds: [String] = []

        let story: Story
        do {
            story = try await fetchMentionedStory(authorId: storyAuthorId, storyId: storyId)
        } catch {
            return StoryMentionNotificationResult(
                sentUserIds: [],
                skippedOutsideAudienceUserIds: [],
                failedDeliveryUserIds: mentionedUserIds
            )
        }

        for userId in mentionedUserIds {
            let canNotify = await canNotifyStoryMention(
                mentionedUserId: userId,
                storyAuthorId: storyAuthorId,
                audience: audience,
                customViewers: customViewers,
                customListId: customListId
            )

            guard canNotify else {
                skippedOutsideAudienceUserIds.append(userId)
                continue
            }

            do {
                try await sendStoryMentionMessage(
                    story: story,
                    authorId: storyAuthorId,
                    recipientId: userId
                )
                sentUserIds.append(userId)
            } catch {
                failedDeliveryUserIds.append(userId)
            }
        }

        return StoryMentionNotificationResult(
            sentUserIds: sentUserIds,
            skippedOutsideAudienceUserIds: skippedOutsideAudienceUserIds,
            failedDeliveryUserIds: failedDeliveryUserIds
        )
    }

    private static func fetchMentionedStory(authorId: String, storyId: String) async throws -> Story {
        try await withCheckedThrowingContinuation { continuation in
            StoryRepository().fetchStory(userId: authorId, storyId: storyId) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func sendStoryMentionMessage(
        story: Story,
        authorId: String,
        recipientId: String
    ) async throws {
        guard let storyId = story.id, !storyId.isEmpty else {
            throw NSError(domain: "StoryMention", code: 400)
        }
        let coordinator = MessageRequestService()
        let deliveryMessageId = "storyMention_\(storyId)_\(recipientId)"
        let context = MessageRequestInteractionContext(
            kind: .shareStory,
            storyId: storyId,
            storyOwnerId: authorId,
            sharedContentId: storyId,
            sharedContentOwnerId: authorId,
            isStoryMention: true
        )
        let route = try await coordinator.resolveRoute(to: recipientId, interaction: context)
        let conversationId: String?
        switch route {
        case .conversation(let id):
            conversationId = id
        case .conversationDraft(let threadId):
            conversationId = try await coordinator.activateConversationDraft(
                to: recipientId,
                threadId: threadId
            )
        case .incomingRequest(let threadId, _):
            conversationId = try await coordinator.acceptIncomingThread(threadId: threadId).conversationId
        case .outgoingRequest:
            _ = try await coordinator.appendRequestMessage(
                to: recipientId,
                text: NSLocalizedString("chat.preview.sharedStory", comment: ""),
                messageType: .sharedStory,
                interaction: context,
                messageId: deliveryMessageId
            )
            conversationId = nil
        }

        guard let conversationId else { return }
        let existing = try? await Firestore.firestore()
            .collection("conversations").document(conversationId)
            .collection("messages").document(deliveryMessageId)
            .getDocument()
        if existing?.exists == true { return }
        try await withCheckedThrowingContinuation { continuation in
            ChatService.shared.sendSharedStoryMessage(
                conversationId: conversationId,
                senderId: authorId,
                story: story,
                shareText: NSLocalizedString("chat.preview.sharedStory", comment: ""),
                isStoryMention: true,
                messageId: deliveryMessageId
            ) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }

    private static func canNotifyStoryMention(
        mentionedUserId: String,
        storyAuthorId: String,
        audience: ContentAudience,
        customViewers: [String]?,
        customListId: String?
    ) async -> Bool {
        switch audience {
        case .onlyMe:
            return false
        case .custom, .customList:
            if let customViewers, !customViewers.isEmpty {
                return await canUserSeeContent(
                    ownerId: storyAuthorId,
                    viewerId: mentionedUserId,
                    visibility: .custom,
                    customViewers: customViewers
                )
            }

            guard audience == .customList, let customListId, !customListId.isEmpty else {
                return false
            }

            let members = await fetchCustomListMembers(listId: customListId, ownerId: storyAuthorId)
            return await canUserSeeContent(
                ownerId: storyAuthorId,
                viewerId: mentionedUserId,
                visibility: .custom,
                customViewers: members
            )
        case .everyone:
            return await canUserSeeContent(ownerId: storyAuthorId, viewerId: mentionedUserId, visibility: .everyone)
        case .mutuals:
            return await canUserSeeContent(ownerId: storyAuthorId, viewerId: mentionedUserId, visibility: .mutuals)
        case .bestFriends:
            return await canUserSeeContent(ownerId: storyAuthorId, viewerId: mentionedUserId, visibility: .bestFriends)
        }
    }

    private static func canUserSeeContent(
        ownerId: String,
        viewerId: String,
        visibility: ContentVisibilityType,
        customViewers: [String]? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            ContentVisibilityService.shared.canUserSeeContent(
                contentOwnerId: ownerId,
                viewerId: viewerId,
                contentType: visibility,
                customViewers: customViewers
            ) { canSee in
                continuation.resume(returning: canSee)
            }
        }
    }

    private static func fetchCustomListMembers(listId: String, ownerId: String) async -> [String] {
        await withCheckedContinuation { continuation in
            Firestore.firestore()
                .collection("users")
                .document(ownerId)
                .collection("customAudienceLists")
                .document(listId)
                .getDocument { snapshot, _ in
                    let members = snapshot?.data()?["members"] as? [String] ?? []
                    continuation.resume(returning: members)
                }
        }
    }

    // ✅ Función auxiliar para extraer userId de sticker de mención
    private func extractUserIdFromMentionSticker(_ sticker: StickerItem) -> String? {
        if let interactionData = sticker.interactionData {
            return interactionData.userId
        }
        return nil
    }

}
