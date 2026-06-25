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
        self.scaleEffect(1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: UUID())
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

            await MainActor.run {
                NotificationService.shared.sendStoryMentionNotification(
                    to: userId,
                    storyId: storyId,
                    storyAuthorId: storyAuthorId
                )
            }
            sentUserIds.append(userId)
        }

        return StoryMentionNotificationResult(
            sentUserIds: sentUserIds,
            skippedOutsideAudienceUserIds: skippedOutsideAudienceUserIds
        )
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
