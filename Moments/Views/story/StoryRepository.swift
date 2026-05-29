import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct StoryReplyData {
    let mediaUrl: String
    let mediaType: String

    var payload: [String: String] {
        [
            "storyMediaUrl": mediaUrl,
            "storyMediaType": mediaType
        ]
    }
}

final class StoryRepository {
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    func fetchActiveStories(for userId: String, completion: @escaping (Result<[Story], Error>) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let stories = snapshot?.documents.compactMap(Self.decodeStory) ?? []
                completion(.success(stories))
            }
    }

    func hasActiveStories(userId: String, completion: @escaping (Bool) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                guard error == nil else {
                    completion(false)
                    return
                }

                completion(!(snapshot?.isEmpty ?? true))
            }
    }

    func fetchStory(userId: String, storyId: String, completion: @escaping (Result<Story, Error>) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .getDocument { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot, snapshot.exists, let story = Self.decodeStory(from: snapshot) else {
                    completion(.failure(NSError(
                        domain: "",
                        code: -404,
                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.storyNotFound", comment: "Story not found")]
                    )))
                    return
                }

                completion(.success(story))
            }
    }

    func fetchStoryReplyData(userId: String, storyId: String, completion: @escaping (StoryReplyData?) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId).getDocument { snapshot, error in
            guard error == nil,
                  let snapshot,
                  snapshot.exists,
                  let storyData = snapshot.data(),
                  let mediaItem = storyData["mediaItem"] as? [String: Any],
                  let storyMediaUrl = mediaItem["url"] as? String,
                  let storyMediaType = mediaItem["type"] as? String else {
                completion(nil)
                return
            }

            completion(StoryReplyData(mediaUrl: storyMediaUrl, mediaType: storyMediaType))
        }
    }

    func observeReactions(userId: String, storyId: String, onChange: @escaping ([StoryReaction]) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("reactions")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                guard error == nil else { return }

                let reactions = snapshot?.documents.compactMap { doc -> StoryReaction? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let reaction = data["reaction"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    return StoryReaction(id: doc.documentID, userId: userId, reaction: reaction, timestamp: timestamp)
                } ?? []

                onChange(reactions)
            }
    }

    func fetchViewers(userId: String, storyId: String, completion: @escaping ([StoryViewer]) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("viewers")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                guard error == nil else {
                    completion([])
                    return
                }

                let viewers = snapshot?.documents.compactMap { doc -> StoryViewer? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    return StoryViewer(
                        id: doc.documentID,
                        userId: userId,
                        username: data["username"] as? String,
                        profileImagePath: data["profileImagePath"] as? String,
                        timestamp: timestamp
                    )
                } ?? []

                completion(viewers)
            }
    }

    func markStoryAsViewed(authorId: String, storyId: String, viewer: AppUser, completion: ((Error?) -> Void)? = nil) {
        let viewerData: [String: Any] = [
            "userId": viewer.id,
            "username": viewer.username,
            "profileImagePath": viewer.profileImagePath ?? "",
            "timestamp": Timestamp()
        ]

        firestoreService.db.collection("users").document(authorId).collection("stories").document(storyId)
            .collection("viewers").document(viewer.id).setData(viewerData) { error in
                completion?(error)
            }
    }

    func addReaction(userId: String, storyId: String, currentUserId: String, reaction: String, completion: @escaping (Error?) -> Void) {
        let reactionData: [String: Any] = [
            "userId": currentUserId,
            "reaction": reaction,
            "timestamp": Timestamp()
        ]

        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("reactions").addDocument(data: reactionData) { error in
                completion(error)
            }
    }

    func softDeleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        let storyRef = firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
        let recentlyDeletedRef = firestoreService.db.collection("users").document(userId).collection("recentlyDeleted").document(storyId)

        storyRef.getDocument { document, error in
            if let error {
                completion(error)
                return
            }

            guard let data = document?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.storyNotFound", comment: "Story not found")]))
                return
            }

            var deletedData = data
            deletedData["deletedAt"] = FieldValue.serverTimestamp()
            deletedData["type"] = "story"

            recentlyDeletedRef.setData(deletedData) { error in
                if let error {
                    completion(error)
                    return
                }

                storyRef.delete(completion: completion)
            }
        }
    }

    func permanentlyDeleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        guard Auth.auth().currentUser?.uid == userId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
            return
        }

        Task {
            do {
                try await FirestoreService.shared.permanentlyDeleteRecentlyDeleted(ids: [storyId])
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func restoreStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        let storyRef = firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
        let recentlyDeletedRef = firestoreService.db.collection("users").document(userId).collection("recentlyDeleted").document(storyId)

        recentlyDeletedRef.getDocument { snapshot, error in
            if let error {
                completion(error)
                return
            }

            guard var data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")]))
                return
            }

            data.removeValue(forKey: "deletedAt")
            data.removeValue(forKey: "type")

            storyRef.setData(data) { error in
                if let error {
                    completion(error)
                    return
                }

                recentlyDeletedRef.delete(completion: completion)
            }
        }
    }

    private static func decodeStory(from doc: DocumentSnapshot) -> Story? {
        guard let data = doc.data() else { return nil }
        return decodeStoryData(data, documentId: doc.documentID)
    }

    private static func decodeStory(_ doc: QueryDocumentSnapshot) -> Story? {
        decodeStoryData(doc.data(), documentId: doc.documentID)
    }

    private static func decodeStoryData(_ rawData: [String: Any], documentId: String) -> Story? {
        var data = rawData
        var mediaItem: MediaItem?

        if let mediaItemData = data["mediaItem"] as? [String: Any],
           let typeString = mediaItemData["type"] as? String,
           let type = MediaItem.MediaType(rawValue: typeString),
           let url = mediaItemData["url"] as? String {
            mediaItem = MediaItem(type: type, url: url)
        } else if let imagePath = data["imagePath"] as? String, !imagePath.isEmpty {
            mediaItem = MediaItem(type: .image, url: imagePath)
        } else if let videoUrl = data["videoUrl"] as? String, !videoUrl.isEmpty {
            mediaItem = MediaItem(type: .video, url: videoUrl)
        }

        guard let mediaItem else { return nil }

        data["mediaItem"] = ["type": mediaItem.type.rawValue, "url": mediaItem.url]
        data["id"] = documentId

        return try? Firestore.Decoder().decode(Story.self, from: data)
    }

    private func deleteMediaFromStorage(mediaUrl: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: mediaUrl) else {
            completion(
                NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("stories.error.invalidMediaUrl", comment: "Invalid media URL")]
                )
            )
            return
        }

        let storagePath = extractStoragePath(from: url)
        Storage.storage().reference().child(storagePath).delete(completion: completion)
    }

    private func extractStoragePath(from url: URL) -> String {
        let path = url.path
        if path.contains("/o/") {
            let components = path.components(separatedBy: "/o/")
            if components.count > 1 {
                let encodedPath = components[1]
                return encodedPath.removingPercentEncoding ?? encodedPath
            }
        }

        return url.lastPathComponent
    }
}
