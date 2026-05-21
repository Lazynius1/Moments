import FirebaseFirestore
import Foundation

struct StoryAuthorSummary {
    let activeStoryCount: Int
    let latestStoryAt: Date?
    let latestExpirationAt: Date?
    let audiencesSummary: [String: Int]
    let updatedAt: Date?

    func shouldSkipDetailedFetch(maxStaleness: TimeInterval = 300) -> Bool {
        if let latestExpirationAt = latestExpirationAt, latestExpirationAt <= Date() {
            // Resumen vencido: evitar fetch detallado y tratar como sin historias.
            return true
        }
        guard activeStoryCount <= 0 else { return false }
        guard let updatedAt = updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) <= maxStaleness
    }
}

enum PublicProfileAvailability {
    case available
    case unavailable
}

extension FirestoreService {
    func updateUserActivityMetadata(
        userId: String,
        fields: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        guard !fields.isEmpty else {
            completion?(nil)
            return
        }

        db.collection("users").document(userId).updateData(fields) { error in
            completion?(error)
        }
    }

    // MARK: - Story expiration helpers

    func calculateStoryExpirationDate(isChain: Bool = false, chainId: String? = nil) -> Date {
        if isChain, let chainId = chainId {
            return calculateChainExpirationDate(chainId: chainId)
        } else {
            return Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date()
        }
    }

    func calculateChainExpirationDate(chainId: String) -> Date {
        let currentExpiration = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) ?? Date()

        Task {
            await updateChainExpirationInBackground(chainId: chainId)
        }

        return currentExpiration
    }

    func updateChainExpirationInBackground(chainId: String) async {
        do {
            let chainDoc = try await db.collection("storyChains")
                .document(chainId)
                .getDocument()

            guard let data = chainDoc.data(),
                  let createdAt = data["createdAt"] as? Timestamp else {
                return
            }

            let createdAtDate = createdAt.dateValue()
            let correctExpiration = Calendar.current.date(byAdding: .hour, value: 48, to: createdAtDate) ?? Date()

            let storiesSnapshot = try await db.collectionGroup("stories")
                .whereField("chainId", isEqualTo: chainId)
                .getDocuments()

            let batch = db.batch()
            var affectedUserIds = Set<String>()
            for doc in storiesSnapshot.documents {
                batch.updateData([
                    "expirationDate": Timestamp(date: correctExpiration)
                ], forDocument: doc.reference)
                if let userId = doc.reference.parent.parent?.documentID, !userId.isEmpty {
                    affectedUserIds.insert(userId)
                }
            }

            try await batch.commit()

            for userId in affectedUserIds {
                rebuildStorySummary(for: userId) { _ in }
            }
        } catch {
            // Error updating chain expiration
        }
    }

    func serializedMediaItems(
        _ mediaItems: [MediaItem],
        encoder: Firestore.Encoder
    ) -> [[String: Any]] {
        mediaItems.map { item in
            var mediaData: [String: Any] = [
                "id": item.id,
                "type": item.type.rawValue,
                "url": item.url
            ]

            if let aspectRatio = item.aspectRatio {
                mediaData["aspectRatio"] = aspectRatio
            }
            if let thumbnailUrl = item.thumbnailUrl {
                mediaData["thumbnailUrl"] = thumbnailUrl
            }
            if let videoDuration = item.videoDuration {
                mediaData["videoDuration"] = videoDuration
            }
            if let videoFileSize = item.videoFileSize {
                mediaData["videoFileSize"] = videoFileSize
            }
            if let videoResolution = item.videoResolution {
                mediaData["videoResolution"] = videoResolution
            }
            if let videoProcessingStatus = item.videoProcessingStatus?.rawValue {
                mediaData["videoProcessingStatus"] = videoProcessingStatus
            }
            if let originalVideoUrl = item.originalVideoUrl {
                mediaData["originalVideoUrl"] = originalVideoUrl
            }
            if let tags = item.tags, !tags.isEmpty {
                mediaData["tags"] = tags.compactMap { tag in
                    try? encoder.encode(tag)
                }
            }
            if let moderationState = item.moderationState?.rawValue {
                mediaData["moderationState"] = moderationState
            }
            if let moderationReason = item.moderationReason {
                mediaData["moderationReason"] = moderationReason
            }
            if let moderationCategory = item.moderationCategory {
                mediaData["moderationCategory"] = moderationCategory
            }
            if let moderationConfidence = item.moderationConfidence {
                mediaData["moderationConfidence"] = moderationConfidence
            }
            if let moderatedAt = item.moderatedAt {
                mediaData["moderatedAt"] = Timestamp(date: moderatedAt)
            }

            return mediaData
        }
    }
}
