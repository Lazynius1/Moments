import FirebaseAuth
import FirebaseFirestore
import Foundation

extension FirestoreService {
    func createUser(userId: String, username: String, email: String, interests: [String], profileImagePath: String? = nil, completion: @escaping (Error?) -> Void) {
        let newUser = AppUser(
            id: userId,
            username: username.lowercased(),
            email: email,
            interests: interests,
            isPlusSubscriber: false,
            profileImagePath: profileImagePath,
            bio: nil,
            blockedUsers: [],
            isPrivate: false,
            showMutualConnections: true,
            showFollowing: true,
            showAdmirers: true,
            activeHoursStart: nil,
            activeHoursEnd: nil,
            notificationPreferences: [
                NotificationType.like.rawValue: true,
                NotificationType.newFollower.rawValue: true,
                NotificationType.followRequest.rawValue: true,
                NotificationType.mutualConnection.rawValue: true,
                NotificationType.profileVisit.rawValue: true,
                NotificationType.comment.rawValue: true,
                NotificationType.storyReaction.rawValue: true,
                "gentleReminders": true,
                "commentsMutualsOnly": false,
                "muteOldPostReactions": false
            ],
            bestFriends: [],
            isActive: true,
            deactivatedAt: nil,
            deactivatedBy: nil,
            ownedBadges: [],
            plusSubscription: nil,
            primaryBadgeId: nil,
            showBadge: true,
            showPlusBadge: true,
            selectedProfileTheme: nil,
            isVerified: false,
            onlineStatus: .offline,
            lastSeen: nil,
            isOnline: false
        )

        do {
            let encoder = Firestore.Encoder()
            var userData = try encoder.encode(newUser)

            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["updatedAt"] = FieldValue.serverTimestamp()
            userData["isActive"] = true
            userData["isSuspended"] = false
            userData.removeValue(forKey: "deactivatedAt")
            userData.removeValue(forKey: "deactivatedBy")
            userData.removeValue(forKey: "reactivatedAt")
            userData.removeValue(forKey: "suspendedUntil")
            userData.removeValue(forKey: "suspensionReason")

            let usernameData: [String: Any] = [
                "userId": userId,
                "email": email,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            let batch = db.batch()
            let userRef = db.collection("users").document(userId)
            batch.setData(userData, forDocument: userRef)

            let usernameRef = db.collection("usernames").document(username.lowercased())
            batch.setData(usernameData, forDocument: usernameRef)

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    self.verifyUserCreation(userId: userId) { _ in
                        completion(nil)
                    }
                }
            }
        } catch {
            completion(error)
        }
    }

    private func verifyUserCreation(userId: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.db.collection("users").document(userId).getDocument { snapshot, error in
                if let error = error {
                    completion(false)
                    return
                }

                if let data = snapshot?.data() {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    func changeUsername(
        userId: String,
        oldUsername: String,
        newUsername: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let clean = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard clean.count >= 3 && clean.count <= 30 else {
            completion(.failure(NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.length", comment: "Username must be between 3 and 30 characters")])))
            return
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard clean.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            completion(.failure(NSError(domain: "", code: 2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.characters", comment: "Username can only contain letters, numbers, and underscores")])))
            return
        }
        guard clean != oldUsername.lowercased() else {
            completion(.failure(NSError(domain: "", code: 3, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.same", comment: "New username must be different from current")])))
            return
        }

        let userRef = db.collection("users").document(userId)
        let oldUsernameRef = db.collection("usernames").document(oldUsername.lowercased())
        let newUsernameRef = db.collection("usernames").document(clean)

        userRef.getDocument { [weak self] userSnap, error in
            guard let self = self else { return }
            if let error = error { completion(.failure(error)); return }
            let userData = userSnap?.data() ?? [:]
            let userEmail = (userData["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackAuthEmail = Auth.auth().currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let ts = userData["lastUsernameChange"] as? Timestamp {
                let lastChange = ts.dateValue()
                let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
                if lastChange > sixMonthsAgo {
                    let nextAvailable = Calendar.current.date(byAdding: .month, value: 6, to: lastChange) ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateStyle = .long
                    formatter.locale = Locale.current
                    let dateStr = formatter.string(from: nextAvailable)
                    completion(.failure(NSError(domain: "", code: 4, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("username.error.cooldown", comment: "Username can be changed on %@"), dateStr)])))
                    return
                }
            }

            newUsernameRef.getDocument { snap, error in
                if let error = error { completion(.failure(error)); return }
                if snap?.exists == true {
                    completion(.failure(NSError(domain: "", code: 5, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.taken", comment: "This username is already taken")])))
                    return
                }

                oldUsernameRef.getDocument { oldUsernameSnap, error in
                    if let error = error { completion(.failure(error)); return }

                    var newUsernameData = oldUsernameSnap?.data() ?? [:]
                    newUsernameData["userId"] = userId
                    newUsernameData["updatedAt"] = FieldValue.serverTimestamp()

                    if let email = userEmail, !email.isEmpty {
                        newUsernameData["email"] = email
                    } else if let email = fallbackAuthEmail, !email.isEmpty {
                        newUsernameData["email"] = email
                    }

                    if newUsernameData["createdAt"] == nil {
                        newUsernameData["createdAt"] = FieldValue.serverTimestamp()
                    }

                    let batch = self.db.batch()
                    batch.deleteDocument(oldUsernameRef)
                    batch.setData(newUsernameData, forDocument: newUsernameRef)
                    batch.updateData([
                        "username": clean,
                        "lastUsernameChange": FieldValue.serverTimestamp()
                    ], forDocument: userRef)

                    batch.commit { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }

    func fetchUser(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard !userId.isEmpty else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "El userId está vacío"])))
            return
        }

        let source: FirestoreSource = NetworkMonitor.shared.isConnected ? .default : .cache

        db.collection("users").document(userId).getDocument(source: source) { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")])))
                return
            }
            do {
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                if let data = document.data() {
                    self.attemptManualDecoding(data: data, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchUserByUsername(_ username: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        db.collection("users")
            .whereField("username", isEqualTo: cleanUsername)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents, let document = documents.first else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                    return
                }

                do {
                    let user = try document.data(as: AppUser.self)
                    completion(.success(user))
                } catch {
                    let data = document.data()
                    self.attemptManualDecoding(data: data, completion: completion)
                }
            }
    }

    private func attemptManualDecoding(data: [String: Any], completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard let id = data["id"] as? String,
              let email = data["email"] as? String else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Campos obligatorios faltantes"])))
            return
        }
        let user = AppUser(
            id: id,
            username: (data["username"] as? String) ?? "usuario_desconocido",
            email: email,
            interests: (data["interests"] as? [String]) ?? [],
            isPlusSubscriber: (data["isPlusSubscriber"] as? Bool) ?? false,
            profileImagePath: data["profileImagePath"] as? String,
            bio: data["bio"] as? String,
            blockedUsers: (data["blockedUsers"] as? [String]) ?? [],
            isPrivate: (data["isPrivate"] as? Bool) ?? false,
            showMutualConnections: (data["showMutualConnections"] as? Bool) ?? true,
            showFollowing: (data["showFollowing"] as? Bool) ?? true,
            activeHoursStart: data["activeHoursStart"] as? String,
            activeHoursEnd: data["activeHoursEnd"] as? String,
            notificationPreferences: data["notificationPreferences"] as? [String: Bool],
            bestFriends: (data["bestFriends"] as? [String]) ?? [],
            isActive: (data["isActive"] as? Bool) ?? true,
            deactivatedAt: nil,
            deactivatedBy: data["deactivatedBy"] as? String,
            ownedBadges: [],
            plusSubscription: nil,
            primaryBadgeId: data["primaryBadgeId"] as? String,
            showBadge: (data["showBadge"] as? Bool) ?? true
        )

        completion(.success(user))
    }

    func fetchAvailableInterests(completion: @escaping (Result<[String], Error>) -> Void) {
        db.collection("interests").getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let interests = snapshot?.documents.compactMap { $0.data()["name"] as? String } ?? []
            completion(.success(interests))
        }
    }

    func fetchUserProfile(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        self.db.collection("users").document(userId).getDocument(source: .default, completion: { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")])))
                return
            }

            do {
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        })
    }

    func checkPublicProfileAvailability(userId: String, completion: @escaping (PublicProfileAvailability) -> Void) {
        db.collection("users").document(userId).getDocument(source: .default) { snapshot, error in
            if error != nil {
                completion(.available)
                return
            }

            guard let document = snapshot, document.exists, let data = document.data() else {
                completion(.unavailable)
                return
            }

            let isActive = data["isActive"] as? Bool ?? true
            guard isActive else {
                completion(.unavailable)
                return
            }

            let isSuspended = data["isSuspended"] as? Bool ?? false
            guard isSuspended else {
                completion(.available)
                return
            }

            if let suspendedUntil = data["suspendedUntil"] as? Timestamp,
               Date() > suspendedUntil.dateValue() {
                completion(.available)
            } else {
                completion(.unavailable)
            }
        }
    }

    func fetchConnections(userId: String, completion: @escaping (Result<[Connection], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("connections")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let connections = documents.compactMap { doc -> Connection? in
                    do {
                        return try doc.data(as: Connection.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(connections))
            }
    }

    func fetchAdmirers(userId: String, completion: @escaping (Result<[Admirer], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("admirers")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let admirers = documents.compactMap { doc -> Admirer? in
                    do {
                        return try doc.data(as: Admirer.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(admirers))
            }
    }

    func fetchMutualConnections(userId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        let group = DispatchGroup()
        var followingIds: Set<String> = []
        var followerIds: Set<String> = []
        var fetchError: Error?

        group.enter()
        fetchFollowing(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                let ids = users.map { $0.id }
                followingIds = Set(ids)
            case .failure(let error):
                fetchError = error
            }
        }

        group.enter()
        fetchFollowers(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                let ids = users.map { $0.id }
                followerIds = Set(ids)
            case .failure(let error):
                fetchError = error
            }
        }

        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
                return
            }

            let mutualIds = Array(followingIds.intersection(followerIds))

            if mutualIds.isEmpty {
                completion(.success([]))
                return
            }

            self.fetchUsersByIdsClean(userIds: mutualIds, completion: completion)
        }
    }

    func updateProfilePicture(userId: String, profileImagePath: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "profileImagePath": profileImagePath
        ]) { error in
            if let error = error {
                // Handle error silently
            } else {
                // Success
            }
            completion(error)
        }
    }

    func removeProfilePicture(userId: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "profileImagePath": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }
}
