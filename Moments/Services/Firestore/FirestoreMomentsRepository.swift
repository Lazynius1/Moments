import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

extension FirestoreService {
    func updateMoment(userId: String, momentId: String, content: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)

        let updateData: [String: Any] = [
            "content": content,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        momentRef.updateData(updateData) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    func deleteMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(userId)
        let momentRef = userRef.collection("moments").document(momentId)
        let recentlyDeletedRef = userRef.collection("recentlyDeleted").document(momentId)

        momentRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.momentNotFound", comment: "Moment not found")]))
                return
            }

            var deletedData = data
            deletedData["deletedAt"] = FieldValue.serverTimestamp()
            deletedData["type"] = "moment"

            recentlyDeletedRef.setData(deletedData) { error in
                if let error = error {
                    completion(error)
                    return
                }

                momentRef.delete { error in
                    completion(error)
                }
            }
        }
    }

    func permanentlyDeleteMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        guard Auth.auth().currentUser?.uid == userId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
            return
        }

        Task {
            do {
                try await permanentlyDeleteRecentlyDeleted(ids: [momentId])
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func permanentlyDeleteMoment(momentId: String, userId: String) async throws {
        guard Auth.auth().currentUser?.uid == userId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        try await permanentlyDeleteRecentlyDeleted(ids: [momentId])
    }

    func permanentlyDeleteRecentlyDeleted(ids: [String]) async throws {
        let cleanIds = Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !cleanIds.isEmpty else { return }
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }
        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/permanentlyDeleteRecentlyDeletedBatch") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        let idToken = try await currentUser.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ids": cleanIds])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Backend error \(http.statusCode)"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func restoreMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(userId)
        let momentRef = userRef.collection("moments").document(momentId)
        let recentlyDeletedRef = userRef.collection("recentlyDeleted").document(momentId)

        recentlyDeletedRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard var data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")]))
                return
            }

            data.removeValue(forKey: "deletedAt")
            data.removeValue(forKey: "type")

            momentRef.setData(data) { error in
                if let error = error {
                    completion(error)
                    return
                }

                recentlyDeletedRef.delete { error in
                    completion(error)
                }
            }
        }
    }

    func restoreMoment(momentId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            restoreMoment(userId: userId, momentId: momentId) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func archiveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isArchived": true,
            "archivedAt": FieldValue.serverTimestamp()
        ]) { error in
            completion(error)
        }
    }

    func unarchiveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isArchived": FieldValue.delete(),
            "archivedAt": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }

    func pinMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isPinned": true,
            "pinnedAt": FieldValue.serverTimestamp()
        ]) { error in
            completion(error)
        }
    }

    func unpinMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isPinned": FieldValue.delete(),
            "pinnedAt": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }

    func updateMomentGridPreview(
        userId: String,
        momentId: String,
        settings: MomentGridPreviewSettings,
        completion: @escaping (Error?) -> Void
    ) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        var updateData: [String: Any] = [
            "gridPreviewScale": settings.scale,
            "gridPreviewOffsetX": settings.offsetX,
            "gridPreviewOffsetY": settings.offsetY,
            "gridPreviewFitMode": settings.fitMode.rawValue,
            "gridPreviewBackground": settings.background.rawValue
        ]

        if settings.isDefault {
            updateData["gridPreviewScale"] = FieldValue.delete()
            updateData["gridPreviewOffsetX"] = FieldValue.delete()
            updateData["gridPreviewOffsetY"] = FieldValue.delete()
            updateData["gridPreviewFitMode"] = FieldValue.delete()
            updateData["gridPreviewBackground"] = FieldValue.delete()
        }

        momentRef.updateData(updateData) { error in
            completion(error)
        }
    }

    func pinMomentReplacingOldestIfNeeded(
        userId: String,
        momentId: String,
        pinnedMoments: [Moment],
        completion: @escaping (Error?) -> Void
    ) {
        let currentlyPinned = pinnedMoments.filter { $0.isPinned == true && $0.id != momentId }

        if currentlyPinned.count < 3 {
            pinMoment(userId: userId, momentId: momentId, completion: completion)
            return
        }

        guard let oldestPinned = currentlyPinned.min(by: {
            ($0.pinnedAt ?? $0.timestamp) < ($1.pinnedAt ?? $1.timestamp)
        }), let oldestId = oldestPinned.id else {
            completion(
                NSError(
                    domain: "FirestoreMomentsRepository",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to resolve oldest pinned moment"]
                )
            )
            return
        }

        unpinMoment(userId: userId, momentId: oldestId) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(error)
                return
            }
            self.pinMoment(userId: userId, momentId: momentId, completion: completion)
        }
    }

    func unarchiveMoment(momentId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unarchiveMoment(userId: userId, momentId: momentId) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func fetchArchivedMoments(userId: String, completion: @escaping (Result<[Moment], Error>) -> Void) {
        db.collection("users").document(userId).collection("moments")
            .whereField("isArchived", isEqualTo: true)
            .order(by: "archivedAt", descending: true)
            .limit(to: 100)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let moments = snapshot?.documents.compactMap { doc -> Moment? in
                    try? doc.data(as: Moment.self)
                } ?? []
                completion(.success(moments))
            }
    }

    func deleteMomentComments(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let commentsRef = db.collection("users").document(userId)
            .collection("moments").document(momentId)
            .collection("comments")

        commentsRef.getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }

            let batch = self.db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
            }

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func deleteMomentReactions(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let reactionsRef = db.collection("users").document(userId)
            .collection("moments").document(momentId)
            .collection("reactions")

        reactionsRef.getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }

            let batch = self.db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
            }

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func loadSavedMoments(userId: String) {
        db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { [weak self] snapshot, error in
                if error != nil {
                    DispatchQueue.main.async {
                        self?.savedMomentIds = []
                        self?.savedMomentsLoadedForUserId = userId
                    }
                    return
                }
                let momentIds = snapshot?.documents.compactMap { $0.documentID } ?? []
                DispatchQueue.main.async {
                    self?.savedMomentIds = momentIds
                    self?.savedMomentsLoadedForUserId = userId
                }
            }
    }

    func hasLoadedSavedMoments(for userId: String) -> Bool {
        savedMomentsLoadedForUserId == userId
    }

    func checkIfSaved(userId: String, momentId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        db.collection("users").document(userId).collection("savedMoments").document(momentId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(snapshot?.exists ?? false))
            }
        }
    }

    func toggleSaveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        if !NetworkMonitor.shared.isConnected {
            let payload = SavePayload(userId: userId, momentId: momentId)
            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.save.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Guardado (save) en outbox (offline)")
                    completion(nil)
                }
                return
            }
        }

        let savedMomentRef = db.collection("users").document(userId).collection("savedMoments").document(momentId)
        db.runTransaction({ [weak self] (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                try snapshot = transaction.getDocument(savedMomentRef)
                if snapshot.exists {
                    transaction.deleteDocument(savedMomentRef)
                    DispatchQueue.main.async {
                        self?.savedMomentIds.removeAll { $0 == momentId }
                    }
                } else {
                    transaction.setData(["momentId": momentId, "timestamp": Timestamp()], forDocument: savedMomentRef)
                    DispatchQueue.main.async {
                        self?.savedMomentIds.append(momentId)
                    }
                }
                return nil
            } catch let error {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }) { _, error in
            completion(error)
        }
    }

    func createMoment(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        taggedUsers: [String]? = nil,
        mentionedUsers: [String]? = nil,
        location: String? = nil,
        locationCoordinate: Moment.LocationCoordinate? = nil,
        audience: String? = nil,
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        scheduledDate: Date? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]
                ))
                return
            }

            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url

                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution

                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    mentionedUsers: mentionedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,
                    audience: audience,
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: nil,
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )

                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)

                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    momentData["hasHiddenLayers"] = false
                    momentData["hiddenLayerCount"] = 0

                    self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .addDocument(data: momentData) { error in
                            if let error = error {
                                completion(error)
                            } else {
                                self.updateLastMomentCreatedAt(userId: userId) { _ in
                                    completion(nil)
                                }
                            }
                        }
                } catch {
                    completion(error)
                }

            case .failure(let error):
                completion(error)
            }
        }
    }

    func fetchInitialMoments(for userId: String, completion: @escaping (Result<(moments: [Moment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        self.fetchFollowing(userId: userId) { result in
            switch result {
            case .success(let following):
                let connectionIds = following.map { $0.id }
                if connectionIds.isEmpty {
                    completion(.success((moments: [], lastDocument: nil)))
                    return
                }

                var allMoments: [Moment] = []
                let group = DispatchGroup()
                var lastDocument: DocumentSnapshot?

                for connectionId in connectionIds {
                    group.enter()
                    self.db.collection("users").document(connectionId).collection("moments")
                        .order(by: "timestamp", descending: true)
                        .limit(to: 10)
                        .getDocuments { snapshot, error in
                            if error != nil {
                                group.leave()
                                return
                            }

                            let moments = snapshot?.documents.compactMap { doc -> Moment? in
                                try? doc.data(as: Moment.self)
                            } ?? []
                            allMoments.append(contentsOf: moments)
                            lastDocument = snapshot?.documents.last
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    allMoments.sort { $0.timestamp > $1.timestamp }

                    let now = Date()
                    let filteredMoments = allMoments.filter { moment in
                        if moment.isArchived == true { return false }
                        guard let scheduledDate = moment.scheduledDate else { return true }
                        return scheduledDate <= now
                    }

                    let limitedMoments = Array(filteredMoments.prefix(10))
                    completion(.success((moments: limitedMoments, lastDocument: lastDocument)))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchMoreMoments(for userId: String, startAfter: DocumentSnapshot, completion: @escaping (Result<(moments: [Moment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        self.fetchFollowing(userId: userId) { result in
            switch result {
            case .success(let following):
                let connectionIds = following.map { $0.id }
                if connectionIds.isEmpty {
                    completion(.success((moments: [], lastDocument: nil)))
                    return
                }

                var allMoments: [Moment] = []
                let group = DispatchGroup()
                var lastDocument: DocumentSnapshot?

                for connectionId in connectionIds {
                    group.enter()
                    self.db.collection("users").document(connectionId).collection("moments")
                        .order(by: "timestamp", descending: true)
                        .start(afterDocument: startAfter)
                        .limit(to: 10)
                        .getDocuments { snapshot, error in
                            if error != nil {
                                group.leave()
                                return
                            }

                            let moments = snapshot?.documents.compactMap { doc -> Moment? in
                                try? doc.data(as: Moment.self)
                            } ?? []
                            allMoments.append(contentsOf: moments)
                            lastDocument = snapshot?.documents.last
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    allMoments.sort { $0.timestamp > $1.timestamp }

                    let now = Date()
                    let filteredMoments = allMoments.filter { moment in
                        if moment.isArchived == true { return false }
                        guard let scheduledDate = moment.scheduledDate else { return true }
                        return scheduledDate <= now
                    }

                    let limitedMoments = Array(filteredMoments.prefix(10))
                    completion(.success((moments: limitedMoments, lastDocument: lastDocument)))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchMoments(for userId: String, completion: @escaping (Result<[Moment], Error>) -> Void) {
        let momentsRef = self.db.collection("users").document(userId).collection("moments")
        let pinnedQuery = momentsRef
            .whereField("isPinned", isEqualTo: true)
            .limit(to: 50)
        let recentQuery = momentsRef
            .order(by: "timestamp", descending: true)
            .limit(to: 50)

        let group = DispatchGroup()
        var pinnedDocuments: [QueryDocumentSnapshot] = []
        var recentDocuments: [QueryDocumentSnapshot] = []
        var firstError: Error?

        group.enter()
        pinnedQuery.getDocuments { snapshot, error in
            defer { group.leave() }
            if let error {
                firstError = error
                return
            }
            pinnedDocuments = snapshot?.documents ?? []
        }

        group.enter()
        recentQuery.getDocuments { snapshot, error in
            defer { group.leave() }
            if let error {
                firstError = error
                return
            }
            recentDocuments = snapshot?.documents ?? []
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let currentUserId = Auth.auth().currentUser?.uid
            let now = Date()
            var seenIds = Set<String>()
            let mergedDocuments = (pinnedDocuments + recentDocuments).filter { doc in
                seenIds.insert(doc.documentID).inserted
            }

            let moments = mergedDocuments.compactMap { doc -> Moment? in
                try? doc.data(as: Moment.self)
            }

            let filteredMoments = moments.filter { moment in
                if moment.isArchived == true { return false }

                if moment.authorId == currentUserId {
                    return true
                }

                guard let scheduledDate = moment.scheduledDate else { return true }
                return scheduledDate <= now
            }

            let sortedMoments = filteredMoments.sorted { lhs, rhs in
                let lhsPinned = lhs.isPinned == true
                let rhsPinned = rhs.isPinned == true

                if lhsPinned != rhsPinned {
                    return lhsPinned && !rhsPinned
                }

                if lhsPinned, rhsPinned {
                    let lhsPinnedAt = lhs.pinnedAt ?? lhs.timestamp
                    let rhsPinnedAt = rhs.pinnedAt ?? rhs.timestamp
                    if lhsPinnedAt != rhsPinnedAt {
                        return lhsPinnedAt > rhsPinnedAt
                    }
                }

                return lhs.timestamp > rhs.timestamp
            }

            completion(.success(sortedMoments))
        }
    }

    func createMomentWithVisibility(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        taggedUsers: [String]? = nil,
        mentionedUsers: [String]? = nil,
        location: String? = nil,
        audienceSetting: CaptionAndDetailsView.AudienceSetting,
        locationCoordinate: Moment.LocationCoordinate? = nil,
        selectedListId: String? = nil,
        customViewers: [String]? = nil,
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        scheduledDate: Date? = nil,
        momentId: String? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        let contentAudience: ContentAudience
        switch audienceSetting {
        case .everyone: contentAudience = .everyone
        case .mutuals: contentAudience = .mutuals
        case .bestFriends: contentAudience = .bestFriends
        case .custom: contentAudience = selectedListId != nil ? .customList : .custom
        case .onlyMe: contentAudience = .onlyMe
        }

        self.fetchUser(userId: userId) { [weak self] result in
            guard let self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
                return
            }

            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url
                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution

                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    mentionedUsers: mentionedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,
                    audience: contentAudience.rawValue,
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: selectedListId,
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )

                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)

                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    momentData["hasHiddenLayers"] = false
                    momentData["hiddenLayerCount"] = 0
                    momentData["mapVisibility"] = MapVisibilityPolicy.resolvedVisibility(
                        hasLocation: location != nil || locationCoordinate != nil,
                        audience: contentAudience.rawValue
                    )
                    let resolvedMomentId = momentId ?? UUID().uuidString

                    if audienceSetting == .custom, let customViewers, !customViewers.isEmpty {
                        self.saveCustomAudienceForContent(
                            contentType: "moment",
                            contentId: resolvedMomentId,
                            authorId: userId,
                            allowedUsers: customViewers
                        ) { _ in }
                    }

                    self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .document(resolvedMomentId)
                        .setData(momentData) { error in
                            if let error {
                                completion(nil, error)
                            } else {
                                self.updateLastMomentCreatedAt(userId: userId) { _ in
                                    completion(resolvedMomentId, nil)
                                }
                            }
                        }
                } catch {
                    completion(nil, error)
                }

            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    func fetchMomentsWithVisibility(
        for userId: String,
        viewerId: String,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        fetchMoments(for: userId) { [weak self] result in
            switch result {
            case .success(let moments):
                self?.filterMomentsForVisibility(
                    moments: moments,
                    viewerId: viewerId,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func createMomentWithCustomList(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        customListId: String,
        taggedUsers: [String]? = nil,
        mentionedUsers: [String]? = nil,
        location: String? = nil,
        locationCoordinate: Moment.LocationCoordinate? = nil,
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        scheduledDate: Date? = nil,
        momentId: String? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
                return
            }

            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url
                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution

                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    mentionedUsers: mentionedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,
                    audience: ContentAudience.customList.rawValue,
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: customListId,
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )

                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)

                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    momentData["hasHiddenLayers"] = false
                    momentData["hiddenLayerCount"] = 0
                    momentData["mapVisibility"] = MapVisibilityPolicy.resolvedVisibility(
                        hasLocation: location != nil || locationCoordinate != nil,
                        audience: ContentAudience.customList.rawValue
                    )

                    let resolvedMomentId = momentId ?? UUID().uuidString
                    self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .document(resolvedMomentId)
                        .setData(momentData) { error in
                            if let error {
                                completion(nil, error)
                            } else {
                                self.updateLastMomentCreatedAt(userId: userId) { _ in
                                    completion(resolvedMomentId, nil)
                                }
                            }
                        }
                } catch {
                    completion(nil, error)
                }

            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    private func filterMomentsForVisibility(
        moments: [Moment],
        viewerId: String,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        let visibilityService = ContentVisibilityService.shared
        let group = DispatchGroup()
        var visibleMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "moments.visibility.filter")

        for moment in moments {
            group.enter()
            visibilityService.canUserSeeContent(
                contentOwnerId: moment.authorId,
                viewerId: viewerId,
                contentType: moment.visibilityType,
                customViewers: moment.customViewers,
                hiddenFrom: moment.hiddenFrom
            ) { canSee in
                syncQueue.sync {
                    if canSee {
                        visibleMoments.append(moment)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let orderedVisibleMoments = moments.filter { moment in
                visibleMoments.contains { $0.id == moment.id }
            }
            completion(.success(orderedVisibleMoments))
        }
    }
}
