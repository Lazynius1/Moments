import FirebaseFirestore
import Foundation

extension FirestoreService {
    func saveCustomAudienceForContent(
        contentType: String,
        contentId: String? = nil,
        authorId: String,
        allowedUsers: [String],
        completion: @escaping (Error?) -> Void
    ) {
        let data: [String: Any] = [
            "contentType": contentType,
            "allowedUsers": allowedUsers,
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        let documentId: String
        if let contentId, !contentId.isEmpty {
            documentId = "\(contentType)_\(contentId)"
        } else {
            documentId = "default_\(contentType)"
        }

        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document(documentId)
            .setData(data, merge: true, completion: completion)
    }

    func getCustomAudience(
        contentType: String,
        authorId: String,
        completion: @escaping ([String]) -> Void
    ) {
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("default_\(contentType)")
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data(),
                      let allowedUsers = data["allowedUsers"] as? [String] else {
                    completion([])
                    return
                }
                completion(allowedUsers)
            }
    }

    func canUserViewContentWithCustomList(
        contentId: String,
        contentType: String,
        authorId: String,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        let collection = contentType == "moment" ? "moments" : "stories"

        db.collection("users").document(authorId)
            .collection(collection).document(contentId)
            .getDocument { [weak self] document, _ in
                guard let self,
                      let data = document?.data(),
                      let customListId = data["customListId"] as? String else {
                    completion(false)
                    return
                }

                self.isUserInCustomList(
                    userId: viewerId,
                    listId: customListId,
                    listOwnerId: authorId,
                    completion: completion
                )
            }
    }

    func fetchCustomLists(
        for userId: String,
        completion: @escaping (Result<[CustomAudienceList], Error>) -> Void
    ) {
        db.collection("users").document(userId)
            .collection("customAudienceLists")
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let lists = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: CustomAudienceList.self)
                } ?? []

                completion(.success(lists))
            }
    }

    func fetchCustomListDetails(
        listId: String,
        ownerId: String,
        completion: @escaping (Result<CustomAudienceList, Error>) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let list = try? document?.data(as: CustomAudienceList.self) else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lista no encontrada"])))
                    return
                }

                completion(.success(list))
            }
    }

    func addMembersToCustomList(
        listId: String,
        ownerId: String,
        memberIds: [String],
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .updateData([
                "members": FieldValue.arrayUnion(memberIds),
                "updatedAt": FieldValue.serverTimestamp()
            ], completion: completion)
    }

    func removeMembersFromCustomList(
        listId: String,
        ownerId: String,
        memberIds: [String],
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .updateData([
                "members": FieldValue.arrayRemove(memberIds),
                "updatedAt": FieldValue.serverTimestamp()
            ], completion: completion)
    }

    private func isUserInCustomList(
        userId: String,
        listId: String,
        listOwnerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("users").document(listOwnerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, _ in
                guard let data = document?.data(),
                      let members = data["members"] as? [String] else {
                    completion(false)
                    return
                }

                completion(members.contains(userId))
            }
    }
}
