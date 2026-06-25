import FirebaseAuth
import FirebaseFirestore
import Foundation

extension FirestoreService {
    func searchUsers(query: String, limit: Int = 10, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        guard !query.isEmpty else {
            completion(.success([]))
            return
        }

        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query.lowercased())
            .whereField("username", isLessThanOrEqualTo: query.lowercased() + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        return try doc.data(as: AppUser.self)
                    } catch {
                        return nil
                    }
                }

                self.applySearchMuteFilterIfNeeded(users: users) { filteredUsers in
                    completion(.success(Array(filteredUsers.prefix(max(1, limit)))))
                }
            }
    }

    func fetchMutedUserIds(userId: String, completion: @escaping (Set<String>) -> Void) {
        guard !userId.isEmpty else {
            completion([])
            return
        }

        db.collection("users").document(userId).getDocument { snapshot, _ in
            let muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any]
            let mutedUsers = (muteSettings?["mutedUsers"] as? [String] ?? [])
                .filter { !$0.isEmpty }
            completion(Set(mutedUsers))
        }
    }

    func fetchUsers(userIds: [String], completion: @escaping (Result<[AppUser], Error>) -> Void) {
        if userIds.isEmpty {
            completion(.success([]))
            return
        }

        self.db.collection("users")
            .whereField(FieldPath.documentID(), in: userIds)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        return try doc.data(as: AppUser.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(users))
            }
    }

    func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                if case .success(let users) = result {
                    allUsers.append(contentsOf: users)
                }
            }
        }

        batchGroup.notify(queue: .main) {
            var seen = Set<String>()
            let uniqueUsers = allUsers.filter { user in
                guard !seen.contains(user.id) else { return false }
                seen.insert(user.id)
                return true
            }
            completion(uniqueUsers)
        }
    }

    func fetchUserDataForNova(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                return
            }
            do {
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchSuggestedUsers(completion: @escaping (Result<[AppUser], Error>) -> Void) {
        fetchNewConversationSuggestions(recentPartnerIds: [], completion: completion)
    }

    /// Sugerencias para «Nuevo mensaje»: chats recientes, mutuas y gente que sigues.
    func fetchNewConversationSuggestions(
        recentPartnerIds: [String],
        limit: Int = 40,
        completion: @escaping (Result<[AppUser], Error>) -> Void
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.success([]))
            return
        }

        let orderedRecentIds = Self.uniquePreservingOrder(
            recentPartnerIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != currentUserId }
        )

        let group = DispatchGroup()
        var recentUsers: [AppUser] = []
        var mutualUsers: [AppUser] = []
        var followingUsers: [AppUser] = []
        var capturedError: Error?

        if !orderedRecentIds.isEmpty {
            group.enter()
            fetchUsersByIdsClean(userIds: orderedRecentIds) { result in
                defer { group.leave() }
                switch result {
                case .success(let users):
                    recentUsers = users
                case .failure(let error):
                    capturedError = capturedError ?? error
                }
            }
        }

        group.enter()
        fetchMutuals(userId: currentUserId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                mutualUsers = users
            case .failure(let error):
                capturedError = capturedError ?? error
            }
        }

        group.enter()
        fetchFollowing(userId: currentUserId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                followingUsers = users
            case .failure(let error):
                capturedError = capturedError ?? error
            }
        }

        group.notify(queue: .main) {
            let merged = Self.mergeNewConversationSuggestions(
                orderedRecentIds: orderedRecentIds,
                recentUsers: recentUsers,
                mutualUsers: mutualUsers,
                followingUsers: followingUsers,
                currentUserId: currentUserId,
                limit: limit
            )

            if merged.isEmpty, let capturedError {
                completion(.failure(capturedError))
                return
            }

            self.applySearchMuteFilterIfNeeded(users: merged) { filteredUsers in
                completion(.success(filteredUsers))
            }
        }
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func mergeNewConversationSuggestions(
        orderedRecentIds: [String],
        recentUsers: [AppUser],
        mutualUsers: [AppUser],
        followingUsers: [AppUser],
        currentUserId: String,
        limit: Int
    ) -> [AppUser] {
        var seen = Set<String>()
        var merged: [AppUser] = []

        func appendUnique(_ users: [AppUser]) {
            for user in users where user.id != currentUserId && seen.insert(user.id).inserted {
                merged.append(user)
            }
        }

        let recentById = Dictionary(uniqueKeysWithValues: recentUsers.map { ($0.id, $0) })
        appendUnique(orderedRecentIds.compactMap { recentById[$0] })
        appendUnique(mutualUsers)
        appendUnique(followingUsers)

        return Array(merged.prefix(limit))
    }

    func searchUsers(query: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        let cleanQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            completion(.success([]))
            return
        }

        let currentUserId = Auth.auth().currentUser?.uid

        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: cleanQuery)
            .whereField("username", isLessThanOrEqualTo: cleanQuery + "\u{f8ff}")
            .limit(to: 30)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let users = snapshot?.documents.compactMap { doc -> AppUser? in
                    try? doc.data(as: AppUser.self)
                }.filter { $0.id != currentUserId } ?? []

                self.applySearchMuteFilterIfNeeded(users: users) { filteredUsers in
                    completion(.success(filteredUsers))
                }
            }
    }

    private func applySearchMuteFilterIfNeeded(users: [AppUser], completion: @escaping ([AppUser]) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(users)
            return
        }

        db.collection("users").document(currentUserId).getDocument { snapshot, _ in
            guard
                let muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any],
                let hideFromSearch = muteSettings["hideFromSearch"] as? Bool,
                hideFromSearch
            else {
                completion(users)
                return
            }

            let mutedUsers = Set((muteSettings["mutedUsers"] as? [String] ?? []).filter { !$0.isEmpty })
            guard !mutedUsers.isEmpty else {
                completion(users)
                return
            }

            completion(users.filter { !mutedUsers.contains($0.id) })
        }
    }
}
