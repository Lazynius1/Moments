import FirebaseFirestore
import FirebaseAuth
import Foundation

extension FirestoreService {
    func updateLastAppOpenAt(userId: String? = nil, completion: ((Error?) -> Void)? = nil) {
        let resolvedUserId = userId ?? Auth.auth().currentUser?.uid
        guard let resolvedUserId else {
            completion?(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        updateUserActivityMetadata(
            userId: resolvedUserId,
            fields: ["lastAppOpenAt": FieldValue.serverTimestamp()],
            completion: completion
        )
    }

    func updateLastMomentCreatedAt(userId: String, completion: ((Error?) -> Void)? = nil) {
        updateUserActivityMetadata(
            userId: userId,
            fields: ["lastMomentCreatedAt": FieldValue.serverTimestamp()],
            completion: completion
        )
    }

    func fetchVisits(userId: String, completion: @escaping (Result<[Visit], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("visits")
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

                let visits = documents.compactMap { doc -> Visit? in
                    do {
                        return try doc.data(as: Visit.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(visits))
            }
    }

    func fetchVisitsWithUsers(userId: String) async throws -> [(user: AppUser, visit: Visit)] {
        let snapshot = try await db.collection("users").document(userId).collection("visits")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments()

        let visits = snapshot.documents.compactMap { try? $0.data(as: Visit.self) }
        if visits.isEmpty { return [] }

        let visitorIds = Array(Set(visits.map { $0.visitorId }))
        let users = try await fetchUsersAsync(userIds: visitorIds)
        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })

        return visits.compactMap { visit in
            guard let user = userDict[visit.visitorId] else { return nil }
            return (user, visit)
        }
    }

    func registerVisit(visitorId: String, to targetUserId: String, completion: @escaping (Error?) -> Void) {
        guard visitorId != targetUserId else {
            completion(nil)
            return
        }

        guard !IncognitoModeService.isActiveSnapshot else {
            completion(nil)
            return
        }

        checkIfBlocked(currentUserId: visitorId, targetUserId: targetUserId) { [weak self] isBlockedByVisitor, isVisitorBlocked, error in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
                return
            }

            if let error = error {
                completion(error)
                return
            }

            if isBlockedByVisitor || isVisitorBlocked {
                completion(nil)
                return
            }

            let visitsRef = self.db.collection("users").document(targetUserId).collection("visits")
            let fiveMinutesAgo = Date().addingTimeInterval(-300)

            visitsRef
                .whereField("visitorId", isEqualTo: visitorId)
                .whereField("timestamp", isGreaterThan: Timestamp(date: fiveMinutesAgo))
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    if let error = error {
                        completion(error)
                        return
                    }

                    if let documents = snapshot?.documents, !documents.isEmpty {
                        completion(nil)
                        return
                    }

                    let visit = Visit(visitorId: visitorId, timestamp: Date())

                    do {
                        let encoder = Firestore.Encoder()
                        let visitData = try encoder.encode(visit)

                        visitsRef.addDocument(data: visitData) { error in
                            if let error = error {
                                completion(error)
                                return
                            }

                            self.updateVisitSummary(targetUserId: targetUserId, visitorId: visitorId)
                            completion(nil)
                        }
                    } catch {
                        completion(error)
                    }
                }
        }
    }

    private func updateVisitSummary(targetUserId: String, visitorId: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        let visitSummaryRef = db.collection("users").document(targetUserId).collection("visitSummaries").document(today)

        visitSummaryRef.setData([
            "date": today,
            "visitorIds": FieldValue.arrayUnion([visitorId]),
            "visitCount": FieldValue.increment(Int64(1)),
            "timestamp": Timestamp(date: Date())
        ], merge: true) { error in
            if error != nil {
                // Error silencioso al actualizar resumen
            }
        }
    }
}
