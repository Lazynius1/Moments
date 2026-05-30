import Foundation
import FirebaseFirestore
import FirebaseAI
import UIKit

actor NovaSocialTools {
    private let firestoreService = FirestoreService()

    func listAudienceLists(userId: String) async -> JSONObject {
        do {
            let lists = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CustomAudienceList], Error>) in
                firestoreService.fetchCustomLists(for: userId) { result in
                    continuation.resume(with: result)
                }
            }

            let payload: [JSONValue] = lists.compactMap { list in
                guard let id = list.id else { return nil }
                return .object([
                    "id": .string(id),
                    "name": .string(list.name),
                    "member_count": NovaJSON.int(list.members.count)
                ])
            }

            return [
                "count": NovaJSON.int(payload.count),
                "lists": .array(payload)
            ]
        } catch {
            return [
                "count": NovaJSON.int(0),
                "error": .string(error.localizedDescription),
                "lists": .array([])
            ]
        }
    }

    func createMoment(
        userId: String,
        content: String,
        audienceRaw: String,
        targetUsername: String?,
        customListName: String?,
        customListId: String?,
        attachedImage: UIImage?
    ) async -> JSONObject {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let image = attachedImage else {
            return [
                "success": .bool(false),
                "error": .string("missing_media"),
                "hint": .string("Moments require a photo or video. The user must attach media in the chat.")
            ]
        }

        let audienceResult = await NovaMomentAudienceResolver.resolve(
            userId: userId,
            audienceRaw: audienceRaw,
            targetUsername: targetUsername,
            customListName: customListName,
            customListId: customListId,
            firestoreService: firestoreService
        )

        switch audienceResult {
        case .failure(let error):
            return [
                "success": .bool(false),
                "error": .string(error.code)
            ]
        case .success(let audience):
            return await uploadMomentWithImage(
                userId: userId,
                content: trimmed,
                audience: audience,
                image: image
            )
        }
    }

    private func uploadMomentWithImage(
        userId: String,
        content: String,
        audience: NovaMomentAudience,
        image: UIImage
    ) async -> JSONObject {
        let ratio = image.size.width / max(image.size.height, 1)
        let media = CreatorMedia(
            type: .image,
            image: image,
            videoURL: nil,
            aspectRatio: CreatorMedia.AspectRatio.fromRatio(ratio)
        )

        let captionMentionIds = await MomentMentionResolver.resolveUserIds(from: content)
        let audienceTaggedIds = audience.customViewers ?? []
        let allTaggedUsers = Array(Set(captionMentionIds + audienceTaggedIds))

        let started = await MainActor.run {
            BackgroundMomentUploadService.shared.uploadMoment(
                content: content,
                mediaItems: [media],
                taggedUsers: allTaggedUsers.isEmpty ? nil : allTaggedUsers,
                location: nil,
                audienceSetting: audience.audienceSetting,
                customViewers: audience.customViewers,
                customListId: audience.customListId,
                aspectRatio: media.aspectRatio.displayName
            ) != nil
        }

        guard started else {
            return [
                "success": .bool(false),
                "error": .string("upload_start_failed")
            ]
        }

        return [
            "success": .bool(true),
            "status": .string("uploading"),
            "audience": .string(audience.contentAudience.rawValue),
            "audience_label": .string(audience.displayLabel),
            "has_media": .bool(true),
            "content_preview": .string(String(content.prefix(120))),
            "tagged_users_count": NovaJSON.int(allTaggedUsers.count)
        ]
    }

    func connectionSuggestions(limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let users = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[AppUser], Error>) in
                firestoreService.fetchSuggestedUsers { result in
                    continuation.resume(with: result)
                }
            }

            let suggestions: [JSONValue] = users.prefix(capped).map { user in
                .object([
                    "user_id": .string(user.id),
                    "username": .string(user.username),
                    "bio_preview": .string(String((user.bio ?? "").prefix(80)))
                ])
            }

            return [
                "count": NovaJSON.int(suggestions.count),
                "suggestions": .array(suggestions)
            ]
        } catch {
            return [
                "count": NovaJSON.int(0),
                "error": .string(error.localizedDescription),
                "suggestions": .array([])
            ]
        }
    }
}

private enum NovaSocialToolsError: Error {
    case missingMomentId
}
