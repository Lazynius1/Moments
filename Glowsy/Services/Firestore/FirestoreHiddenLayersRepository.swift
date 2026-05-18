import FirebaseFirestore
import Foundation

extension FirestoreService {
    func saveHiddenLayers(
        userId: String,
        momentId: String,
        layers: [MomentHiddenLayer],
        completion: @escaping (Error?) -> Void
    ) {
        guard !layers.isEmpty else {
            updateMomentHiddenLayerSummary(userId: userId, momentId: momentId, count: 0, completion: completion)
            return
        }

        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        let batch = db.batch()
        let encoder = Firestore.Encoder()

        do {
            let visibleCount = layers.reduce(into: 0) { partialResult, layer in
                if layer.isVisibleInViewer {
                    partialResult += 1
                }
            }

            for layer in layers {
                var layerData = try encoder.encode(layer)
                layerData["id"] = layer.id
                batch.setData(layerData, forDocument: momentRef.collection("hiddenLayers").document(layer.id), merge: true)
            }

            batch.updateData([
                "hasHiddenLayers": visibleCount > 0,
                "hiddenLayerCount": visibleCount
            ], forDocument: momentRef)

            batch.commit(completion: completion)
        } catch {
            completion(error)
        }
    }

    func updateMomentHiddenLayerSummary(
        userId: String,
        momentId: String,
        count: Int,
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .updateData([
                "hasHiddenLayers": count > 0,
                "hiddenLayerCount": count
            ], completion: completion)
    }

    func fetchHiddenLayers(
        userId: String,
        momentId: String,
        completion: @escaping (Result<[MomentHiddenLayer], Error>) -> Void
    ) {
        db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .collection("hiddenLayers")
            .order(by: "zIndex")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let layers = snapshot?.documents.compactMap { document in
                    try? document.data(as: MomentHiddenLayer.self)
                } ?? []
                completion(.success(layers))
            }
    }

    func recordHiddenLayerDiscovery(
        ownerUserId: String,
        momentId: String,
        layerId: String,
        viewerId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let cacheUser = UserCacheService.shared.getCachedUser(userId: viewerId)

        let persist: (String?, String?) -> Void = { username, profileImagePath in
            let now = Timestamp(date: Date())
            var discoveryData: [String: Any] = [
                "viewerId": viewerId,
                "discoveredAt": now
            ]
            if let username {
                discoveryData["username"] = username
            }
            if let profileImagePath {
                discoveryData["profileImagePath"] = profileImagePath
            }

            let momentRef = self.db.collection("users")
                .document(ownerUserId)
                .collection("moments")
                .document(momentId)

            let batch = self.db.batch()
            batch.setData(
                discoveryData,
                forDocument: momentRef.collection("hiddenLayers").document(layerId).collection("discoveries").document(viewerId),
                merge: true
            )
            batch.setData(
                {
                    var data: [String: Any] = [
                        "viewerId": viewerId,
                        "lastDiscoveredAt": now
                    ]
                    if let username {
                        data["username"] = username
                    }
                    if let profileImagePath {
                        data["profileImagePath"] = profileImagePath
                    }
                    return data
                }(),
                forDocument: momentRef.collection("hiddenLayerDiscoverers").document(viewerId),
                merge: true
            )
            batch.commit(completion: completion)
        }

        if let cacheUser {
            persist(cacheUser.username, cacheUser.profileImagePath)
            return
        }

        fetchUser(userId: viewerId) { result in
            switch result {
            case .success(let user):
                persist(user.username, user.profileImagePath)
            case .failure:
                persist(nil, nil)
            }
        }
    }

    func fetchHiddenLayerMetrics(
        userId: String,
        momentId: String,
        completion: @escaping (Result<HiddenLayerMetricsSnapshot, Error>) -> Void
    ) {
        let momentRef = db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)

        let hiddenLayersRef = momentRef.collection("hiddenLayers")
        let discoverersRef = momentRef.collection("hiddenLayerDiscoverers")

        hiddenLayersRef.getDocuments { layerSnapshot, layerError in
            if let layerError {
                completion(.failure(layerError))
                return
            }

            let layers = layerSnapshot?.documents.compactMap { document in
                try? document.data(as: MomentHiddenLayer.self)
            } ?? []

            let sortedLayers = layers.sorted { lhs, rhs in
                let lhsCount = lhs.discoverCount ?? 0
                let rhsCount = rhs.discoverCount ?? 0
                if lhsCount == rhsCount {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhsCount > rhsCount
            }

            discoverersRef.getDocuments { discoverersSnapshot, discoverersError in
                if let discoverersError {
                    completion(.failure(discoverersError))
                    return
                }

                let uniquePeopleCount = discoverersSnapshot?.documents.count ?? 0
                let group = DispatchGroup()
                var recentDiscoveriesByLayer: [String: [HiddenLayerDiscovery]] = [:]
                var firstError: Error?
                let lockQueue = DispatchQueue(label: "hiddenLayer.metrics.sync")

                for layer in sortedLayers {
                    group.enter()
                    hiddenLayersRef
                        .document(layer.id)
                        .collection("discoveries")
                        .order(by: "discoveredAt", descending: true)
                        .limit(to: 3)
                        .getDocuments { snapshot, error in
                            defer { group.leave() }

                            if let error {
                                lockQueue.sync {
                                    if firstError == nil {
                                        firstError = error
                                    }
                                }
                                return
                            }

                            let discoveries = snapshot?.documents.compactMap { document in
                                try? document.data(as: HiddenLayerDiscovery.self)
                            } ?? []

                            lockQueue.sync {
                                recentDiscoveriesByLayer[layer.id] = discoveries
                            }
                        }
                }

                group.notify(queue: .main) {
                    if let firstError {
                        completion(.failure(firstError))
                    } else {
                        completion(.success(
                            HiddenLayerMetricsSnapshot(
                                layers: sortedLayers,
                                uniquePeopleCount: uniquePeopleCount,
                                recentDiscoveriesByLayer: recentDiscoveriesByLayer
                            )
                        ))
                    }
                }
            }
        }
    }

    func fetchHiddenLayerDiscoveriesPage(
        userId: String,
        momentId: String,
        layerId: String,
        pageSize: Int = 8,
        startAfter document: DocumentSnapshot? = nil,
        completion: @escaping (Result<([HiddenLayerDiscovery], DocumentSnapshot?, Bool), Error>) -> Void
    ) {
        var query: Query = db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .collection("hiddenLayers")
            .document(layerId)
            .collection("discoveries")
            .order(by: "discoveredAt", descending: true)
            .limit(to: pageSize)

        if let document {
            query = query.start(afterDocument: document)
        }

        query.getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let documents = snapshot?.documents ?? []
            let discoveries = documents.compactMap { document in
                try? document.data(as: HiddenLayerDiscovery.self)
            }
            let lastDocument = documents.last
            let hasMore = documents.count == pageSize
            completion(.success((discoveries, lastDocument, hasMore)))
        }
    }

    func hideHiddenLayer(
        userId: String,
        momentId: String,
        layerId: String,
        reason: String?,
        category: String?,
        completion: @escaping (Error?) -> Void
    ) {
        var data: [String: Any] = [
            "moderationState": MomentHiddenLayer.ModerationState.hidden.rawValue,
            "moderatedAt": Timestamp(date: Date())
        ]
        if let reason {
            data["moderationReason"] = reason
        }
        if let category {
            data["moderationCategory"] = category
        }

        db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .collection("hiddenLayers")
            .document(layerId)
            .updateData(data) { error in
                if let error {
                    completion(error)
                    return
                }

                self.rebuildHiddenLayerSummary(userId: userId, momentId: momentId, completion: completion)
            }
    }

    func markHiddenLayerVisible(
        userId: String,
        momentId: String,
        layerId: String,
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .collection("hiddenLayers")
            .document(layerId)
            .updateData([
                "moderationState": MomentHiddenLayer.ModerationState.visible.rawValue,
                "moderatedAt": Timestamp(date: Date()),
                "moderationReason": FieldValue.delete(),
                "moderationCategory": FieldValue.delete()
            ]) { error in
                if let error {
                    completion(error)
                    return
                }

                self.rebuildHiddenLayerSummary(userId: userId, momentId: momentId, completion: completion)
            }
    }

    func rebuildHiddenLayerSummary(
        userId: String,
        momentId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let layersRef = db.collection("users")
            .document(userId)
            .collection("moments")
            .document(momentId)
            .collection("hiddenLayers")

        layersRef.getDocuments { snapshot, error in
            if let error {
                completion(error)
                return
            }

            let layers = snapshot?.documents.compactMap { document in
                try? document.data(as: MomentHiddenLayer.self)
            } ?? []

            let visibleCount = layers.reduce(into: 0) { partialResult, layer in
                if layer.isVisibleInViewer {
                    partialResult += 1
                }
            }

            self.updateMomentHiddenLayerSummary(
                userId: userId,
                momentId: momentId,
                count: visibleCount,
                completion: completion
            )
        }
    }
}
