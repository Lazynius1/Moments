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

    func fetchUserDataForGemini(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
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
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.success([]))
            return
        }

        fetchMutualConnections(userId: currentUserId) { result in
            switch result {
            case .success(let mutuals):
                if mutuals.count >= 5 {
                    self.db.collection("users")
                        .limit(to: 20)
                        .getDocuments { snapshot, _ in
                            var allUsers = mutuals
                            if let documents = snapshot?.documents {
                                let randomUsers = documents.compactMap { try? $0.data(as: AppUser.self) }
                                    .filter { user in
                                        !mutuals.contains(where: { $0.id == user.id }) &&
                                        user.id != currentUserId
                                    }
                                allUsers.append(contentsOf: randomUsers)
                            }
                            completion(.success(Array(allUsers.prefix(20))))
                        }
                } else {
                    self.db.collection("users")
                        .limit(to: 30)
                        .getDocuments { snapshot, error in
                            if let error = error {
                                completion(.failure(error))
                                return
                            }
                            let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) }
                                .filter { $0.id != currentUserId }
                            completion(.success(users ?? []))
                        }
                }
            case .failure:
                self.db.collection("users")
                    .limit(to: 30)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) }
                            .filter { $0.id != currentUserId }
                        completion(.success(users ?? []))
                    }
            }
        }
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
