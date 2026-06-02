import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Foundation

extension FirestoreService {
    func createStory(
        userId: String,
        mediaItem: MediaItem,
        audience: String? = nil,
        text: String? = nil,
        textPosition: CGPoint? = nil,
        textStyle: String? = nil,
        stickers: [StickerData]? = nil,
        drawingData: Data? = nil,
        chainId: String? = nil,
        chainPosition: Int? = nil,
        chainTitle: String? = nil,
        duration: Double? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        createStoryDocument(
            userId: userId,
            mediaItem: mediaItem,
            audience: audience,
            customListId: nil,
            customViewers: nil,
            text: text,
            textPosition: textPosition,
            textStyle: textStyle,
            stickers: stickers,
            drawingData: drawingData,
            aspectRatio: nil,
            backgroundFrameURL: nil,
            backgroundBlurredFrameURL: nil,
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle,
            allowOthersToContinue: nil,
            continuationAudience: nil,
            continuationCustomViewers: nil,
            continuationCustomListId: nil,
            continuationCustomListName: nil,
            duration: duration
        ) { _, error in
            completion(error)
        }
    }

    func createStoryWithVisibility(
        userId: String,
        mediaItem: MediaItem,
        audienceSetting: ContentAudience,
        customViewers: [String]? = nil,
        text: String? = nil,
        textPosition: CGPoint? = nil,
        textStyle: String? = nil,
        stickers: [StickerData]? = nil,
        drawingData: Data? = nil,
        aspectRatio: String? = nil,
        backgroundFrameURL: String? = nil,
        backgroundBlurredFrameURL: String? = nil,
        chainId: String? = nil,
        chainPosition: Int? = nil,
        chainTitle: String? = nil,
        allowOthersToContinue: Bool? = nil,
        continuationAudience: ContentAudience? = nil,
        continuationCustomViewers: [String]? = nil,
        continuationCustomListId: String? = nil,
        continuationCustomListName: String? = nil,
        duration: Double? = nil,
        storyId: String? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        createStoryDocument(
            userId: userId,
            mediaItem: mediaItem,
            audience: audienceSetting.rawValue,
            customListId: nil,
            customViewers: customViewers,
            text: text,
            textPosition: textPosition,
            textStyle: textStyle,
            stickers: stickers,
            drawingData: drawingData,
            aspectRatio: aspectRatio,
            backgroundFrameURL: backgroundFrameURL,
            backgroundBlurredFrameURL: backgroundBlurredFrameURL,
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle,
            allowOthersToContinue: allowOthersToContinue,
            continuationAudience: continuationAudience,
            continuationCustomViewers: continuationCustomViewers,
            continuationCustomListId: continuationCustomListId,
            continuationCustomListName: continuationCustomListName,
            duration: duration,
            storyId: storyId,
            completion: completion
        )
    }

    func createStoryWithCustomList(
        userId: String,
        mediaItem: MediaItem,
        customListId: String,
        text: String? = nil,
        textPosition: CGPoint? = nil,
        textStyle: String? = nil,
        stickers: [StickerData]? = nil,
        drawingData: Data? = nil,
        aspectRatio: String? = nil,
        backgroundFrameURL: String? = nil,
        backgroundBlurredFrameURL: String? = nil,
        chainId: String? = nil,
        chainPosition: Int? = nil,
        chainTitle: String? = nil,
        allowOthersToContinue: Bool? = nil,
        continuationAudience: ContentAudience? = nil,
        continuationCustomViewers: [String]? = nil,
        continuationCustomListId: String? = nil,
        continuationCustomListName: String? = nil,
        duration: Double? = nil,
        storyId: String? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        createStoryDocument(
            userId: userId,
            mediaItem: mediaItem,
            audience: ContentAudience.customList.rawValue,
            customListId: customListId,
            customViewers: nil,
            text: text,
            textPosition: textPosition,
            textStyle: textStyle,
            stickers: stickers,
            drawingData: drawingData,
            aspectRatio: aspectRatio,
            backgroundFrameURL: backgroundFrameURL,
            backgroundBlurredFrameURL: backgroundBlurredFrameURL,
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle,
            allowOthersToContinue: allowOthersToContinue,
            continuationAudience: continuationAudience,
            continuationCustomViewers: continuationCustomViewers,
            continuationCustomListId: continuationCustomListId,
            continuationCustomListName: continuationCustomListName,
            duration: duration,
            storyId: storyId,
            completion: completion
        )
    }

    private func createStoryDocument(
        userId: String,
        mediaItem: MediaItem,
        audience: String?,
        customListId: String?,
        customViewers: [String]?,
        text: String?,
        textPosition: CGPoint?,
        textStyle: String?,
        stickers: [StickerData]?,
        drawingData: Data?,
        aspectRatio: String?,
        backgroundFrameURL: String?,
        backgroundBlurredFrameURL: String?,
        chainId: String?,
        chainPosition: Int?,
        chainTitle: String?,
        allowOthersToContinue: Bool?,
        continuationAudience: ContentAudience?,
        continuationCustomViewers: [String]?,
        continuationCustomListId: String?,
        continuationCustomListName: String?,
        duration: Double?,
        storyId: String? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        fetchUser(userId: userId) { [weak self] result in
            guard let self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
                return
            }

            switch result {
            case .success(let user):
                let isChain = chainId != nil
                let expirationDate = self.calculateStoryExpirationDate(isChain: isChain, chainId: chainId)
                let duration = duration ?? (mediaItem.type == .video ? 60.0 : 15.0)
                let storyId = storyId ?? UUID().uuidString

                let story = Story(
                    id: storyId,
                    authorId: userId,
                    username: user.username,
                    mediaItem: mediaItem,
                    duration: duration,
                    timestamp: Date(),
                    expirationDate: expirationDate,
                    profileImagePath: user.profileImagePath,
                    audience: audience,
                    customListId: customListId,
                    text: text,
                    textPosition: textPosition,
                    textStyle: textStyle,
                    stickers: stickers,
                    drawingData: drawingData,
                    aspectRatio: aspectRatio,
                    backgroundFrameURL: backgroundFrameURL,
                    backgroundBlurredFrameURL: backgroundBlurredFrameURL,
                    chainId: chainId,
                    chainPosition: chainPosition,
                    chainTitle: chainTitle
                )

                do {
                    var storyData = try self.makeStoryPayload(
                        for: story,
                        textPosition: textPosition,
                        stickers: stickers
                    )

                    self.applyChainConfiguration(
                        to: &storyData,
                        userId: userId,
                        chainId: chainId,
                        chainPosition: chainPosition,
                        chainTitle: chainTitle,
                        allowOthersToContinue: allowOthersToContinue,
                        continuationAudience: continuationAudience,
                        continuationCustomViewers: continuationCustomViewers,
                        continuationCustomListId: continuationCustomListId,
                        continuationCustomListName: continuationCustomListName
                    )

                    if audience == ContentAudience.custom.rawValue,
                       let customViewers,
                       !customViewers.isEmpty {
                        self.saveCustomAudienceForContent(
                            contentType: "story",
                            contentId: storyId,
                            authorId: userId,
                            allowedUsers: customViewers
                        ) { _ in }
                    }

                    self.db.collection("users").document(userId)
                        .collection("stories").document(storyId)
                        .setData(storyData) { error in
                            if let error {
                                completion(nil, error)
                            } else {
                                self.bumpStorySummaryOnCreate(
                                    userId: userId,
                                    audience: story.audience,
                                    timestamp: story.timestamp,
                                    expirationDate: story.expirationDate
                                )
                                self.rebuildStorySummary(for: userId) { _ in }
                                completion(storyId, nil)
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

    private func makeStoryPayload(
        for story: Story,
        textPosition: CGPoint?,
        stickers: [StickerData]?
    ) throws -> [String: Any] {
        let encoder = Firestore.Encoder()
        var storyData = try encoder.encode(story)

        storyData.removeValue(forKey: "stickers")
        storyData.removeValue(forKey: "textPosition")

        if let textPosition {
            storyData["textPositionX"] = textPosition.x
            storyData["textPositionY"] = textPosition.y
        }

        if let stickers {
            storyData["stickers"] = stickers.map(serializedStorySticker)
        }

        return storyData
    }

    private func serializedStorySticker(_ sticker: StickerData) -> [String: Any] {
        var stickerData: [String: Any] = [
            "type": sticker.type,
            "content": sticker.content,
            "positionX": Double(sticker.position.x),
            "positionY": Double(sticker.position.y),
            "scale": Double(sticker.scale),
            "rotation": sticker.rotation
        ]

        if let stickerId = sticker.stickerId {
            stickerData["stickerId"] = stickerId
        }
        if let username = sticker.username {
            stickerData["username"] = username
        }
        if let userId = sticker.userId {
            stickerData["userId"] = userId
        }
        if let hashtag = sticker.hashtag {
            stickerData["hashtag"] = hashtag
        }
        if let location = sticker.location {
            stickerData["location"] = location
        }
        if let latitude = sticker.latitude, let longitude = sticker.longitude {
            stickerData["latitude"] = latitude
            stickerData["longitude"] = longitude
        }
        if let styleVariant = sticker.styleVariant {
            stickerData["styleVariant"] = styleVariant
        }
        if let questionText = sticker.questionText {
            stickerData["questionText"] = questionText
        }
        if let pollOptions = sticker.pollOptions {
            stickerData["pollOptions"] = pollOptions
        }
        if let weatherSymbol = sticker.weatherSymbol {
            stickerData["weatherSymbol"] = weatherSymbol
        }
        if let linkURL = sticker.linkURL {
            stickerData["linkURL"] = linkURL
        }
        if let linkTitle = sticker.linkTitle {
            stickerData["linkTitle"] = linkTitle
        }
        if let countdownTitle = sticker.countdownTitle {
            stickerData["countdownTitle"] = countdownTitle
        }
        if let countdownTargetAtMs = sticker.countdownTargetAtMs {
            stickerData["countdownTargetAtMs"] = countdownTargetAtMs
        }
        if let sliderEmoji = sticker.sliderEmoji {
            stickerData["sliderEmoji"] = sliderEmoji
        }
        if let sliderPrompt = sticker.sliderPrompt {
            stickerData["sliderPrompt"] = sliderPrompt
        }
        if let caption = sticker.caption {
            stickerData["caption"] = caption
        }
        if let profileImagePath = sticker.profileImagePath {
            stickerData["profileImagePath"] = profileImagePath
        }
        if let momentId = sticker.momentId {
            stickerData["momentId"] = momentId
        }
        if let mediaCount = sticker.mediaCount {
            stickerData["mediaCount"] = mediaCount
        }
        if let quizQuestion = sticker.quizQuestion {
            stickerData["quizQuestion"] = quizQuestion
        }
        if let quizOptions = sticker.quizOptions {
            stickerData["quizOptions"] = quizOptions
        }
        if let quizCorrectIndex = sticker.quizCorrectIndex {
            stickerData["quizCorrectIndex"] = quizCorrectIndex
        }
        if let revealType = sticker.revealType {
            stickerData["revealType"] = revealType
        }
        if let revealPattern = sticker.revealPattern {
            stickerData["revealPattern"] = revealPattern
        }
        if let revealPrimaryColor = sticker.revealPrimaryColor {
            stickerData["revealPrimaryColor"] = revealPrimaryColor
        }
        if let revealSecondaryColor = sticker.revealSecondaryColor {
            stickerData["revealSecondaryColor"] = revealSecondaryColor
        }
        if let frameStyle = sticker.frameStyle {
            stickerData["frameStyle"] = frameStyle
        }
        if let contentScale = sticker.contentScale {
            stickerData["contentScale"] = contentScale
        }
        if let contentOffsetX = sticker.contentOffsetX {
            stickerData["contentOffsetX"] = contentOffsetX
        }
        if let contentOffsetY = sticker.contentOffsetY {
            stickerData["contentOffsetY"] = contentOffsetY
        }
        if let audioURL = sticker.audioURL {
            stickerData["audioURL"] = audioURL
        }
        if let audioDuration = sticker.audioDuration {
            stickerData["audioDuration"] = audioDuration
        }

        if sticker.isAnimated {
            stickerData["isAnimated"] = true
            if let gifURL = sticker.gifURL {
                stickerData["gifURL"] = String(describing: gifURL)
            }
            if let videoURL = sticker.videoURL {
                stickerData["videoURL"] = videoURL
            }
        }

        return stickerData
    }

    private func applyChainConfiguration(
        to storyData: inout [String: Any],
        userId: String,
        chainId: String?,
        chainPosition: Int?,
        chainTitle: String?,
        allowOthersToContinue: Bool?,
        continuationAudience: ContentAudience?,
        continuationCustomViewers: [String]?,
        continuationCustomListId: String?,
        continuationCustomListName: String?
    ) {
        guard let chainId else { return }

        if let allowOthersToContinue {
            storyData["allowOthersToContinue"] = allowOthersToContinue
        }
        if let continuationAudience {
            storyData["continuationAudience"] = continuationAudience.rawValue
        }
        if let continuationCustomViewers {
            storyData["continuationCustomViewers"] = continuationCustomViewers
        }
        if let continuationCustomListId {
            storyData["continuationCustomListId"] = continuationCustomListId
        }
        if let continuationCustomListName {
            storyData["continuationCustomListName"] = continuationCustomListName
        }

        guard chainPosition == 1 else { return }

        let chainMetadata: [String: Any] = [
            "chainId": chainId,
            "authorId": userId,
            "title": chainTitle ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "allowOthersToContinue": allowOthersToContinue ?? true,
            "continuationAudience": continuationAudience?.rawValue ?? "everyone",
            "continuationCustomViewers": continuationCustomViewers ?? [],
            "continuationCustomListId": continuationCustomListId ?? "",
            "continuationCustomListName": continuationCustomListName ?? "",
            "isExpired": false
        ]

        db.collection("storyChains").document(chainId).setData(chainMetadata, merge: true) { _ in }
    }


    // MARK: - HIGHLIGHTED STORIES METHODS

    func fetchHighlights(userId: String, completion: @escaping (Result<[HighlightedStory], Error>) -> Void) {
        db.collection("users").document(userId).collection("highlights")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let highlights = snapshot?.documents.compactMap { doc -> HighlightedStory? in
                    try? doc.data(as: HighlightedStory.self)
                } ?? []

                completion(.success(highlights))
            }
    }

    // ✅ NUEVO: Obtener todas las historias (activas y archivadas) para crear destacadas
    func fetchAllStories(userId: String, completion: @escaping (Result<[Story], Error>) -> Void) {
        db.collection("users").document(userId).collection("stories")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let stories = snapshot?.documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                } ?? []

                completion(.success(stories))
            }
    }

    // ✅ NUEVA: Paginación para mejor rendimiento
    func fetchStoriesPaginated(userId: String, limit: Int, lastDocument: DocumentSnapshot?, completion: @escaping (Result<(stories: [Story], lastDoc: DocumentSnapshot?), Error>) -> Void) {
        var query = db.collection("users").document(userId).collection("stories")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)

        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }

        query.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let snapshot = snapshot else {
                completion(.success((stories: [], lastDoc: nil)))
                return
            }

            let stories = snapshot.documents.compactMap { doc -> Story? in
                try? doc.data(as: Story.self)
            }

            completion(.success((stories: stories, lastDoc: snapshot.documents.last)))
        }
    }

    // ✅ NUEVO: Obtener historias específicas por ID
    func fetchStoriesByIds(userId: String, storyIds: [String], completion: @escaping (Result<[Story], Error>) -> Void) {
        let group = DispatchGroup()
        var stories: [Story] = []
        var lastError: Error?

        for storyId in storyIds {
            group.enter()
            db.collection("users").document(userId).collection("stories").document(storyId).getDocument { snapshot, error in
                defer { group.leave() }

                if let error = error {
                    lastError = error
                    return
                }

                if let snapshot = snapshot, snapshot.exists {
                    if let story = try? snapshot.data(as: Story.self) {
                        stories.append(story)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if stories.isEmpty && !storyIds.isEmpty && lastError != nil {
                completion(.failure(lastError!))
            } else {
                // Mantener el orden de los IDs originales
                let orderedStories = storyIds.compactMap { id in
                    stories.first(where: { $0.id == id })
                }
                completion(.success(orderedStories))
            }
        }
    }

    /// Obtiene historias activas para un conjunto de autores de forma batched (collectionGroup),
    /// con fallback seguro al flujo legacy por usuario si falta índice.
    func fetchActiveStoriesForUsers(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        let normalizedUserIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !normalizedUserIds.isEmpty else {
            completion(.success([:]))
            return
        }

        let batches = normalizedUserIds.chunked(into: 10)
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "active.stories.users.sync")
        var aggregated: [String: [Story]] = [:]
        var capturedError: Error?

        for batch in batches {
            group.enter()
            self.fetchActiveStoriesBatch(userIds: batch) { result in
                syncQueue.sync {
                    switch result {
                    case .success(let storiesByUser):
                        for (authorId, stories) in storiesByUser {
                            aggregated[authorId, default: []].append(contentsOf: stories)
                        }
                    case .failure(let error):
                        capturedError = capturedError ?? error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let (finalMap, error): ([String: [Story]], Error?) = syncQueue.sync {
                var sortedMap: [String: [Story]] = [:]
                for (authorId, stories) in aggregated {
                    sortedMap[authorId] = stories.sorted { $0.timestamp < $1.timestamp }
                }
                return (sortedMap, capturedError)
            }

            if finalMap.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(finalMap))
            }
        }
    }

    private func fetchActiveStoriesBatch(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        guard !userIds.isEmpty else {
            completion(.success([:]))
            return
        }

        db.collectionGroup("stories")
            .whereField("authorId", in: userIds)
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 500)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(.failure(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                    return
                }

                if error != nil {
                    // Fallback para mantener compatibilidad sin depender de índice nuevo.
                    self.fetchActiveStoriesLegacy(userIds: userIds, completion: completion)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([:]))
                    return
                }

                var storiesByUser: [String: [Story]] = [:]
                for document in documents {
                    guard let story = try? document.data(as: Story.self) else { continue }
                    storiesByUser[story.authorId, default: []].append(story)
                }

                completion(.success(storiesByUser))
            }
    }

    private func fetchActiveStoriesLegacy(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "active.stories.legacy.sync")
        var storiesByUser: [String: [Story]] = [:]
        var capturedError: Error?

        for userId in userIds {
            group.enter()
            db.collection("users").document(userId).collection("stories")
                .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
                .getDocuments { snapshot, error in
                    syncQueue.sync {
                        if let error = error {
                            capturedError = capturedError ?? error
                        } else {
                            let stories = snapshot?.documents.compactMap { try? $0.data(as: Story.self) } ?? []
                            storiesByUser[userId] = stories.sorted { $0.timestamp < $1.timestamp }
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let (resultMap, error): ([String: [Story]], Error?) = syncQueue.sync {
                (storiesByUser, capturedError)
            }
            if resultMap.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(resultMap))
            }
        }
    }

    /// Obtiene resumen de stories por autor desde users/{id}.storySummary (lectura ligera).
    func fetchStorySummariesForUsers(
        userIds: [String],
        completion: @escaping (Result<[String: StoryAuthorSummary], Error>) -> Void
    ) {
        let normalizedUserIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !normalizedUserIds.isEmpty else {
            completion(.success([:]))
            return
        }

        let batches = normalizedUserIds.chunked(into: 10)
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.summary.users.sync")
        var mergedSummaries: [String: StoryAuthorSummary] = [:]
        var capturedError: Error?

        for batch in batches {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments { snapshot, error in
                    syncQueue.sync {
                        if let error = error {
                            capturedError = capturedError ?? error
                        } else {
                            for document in snapshot?.documents ?? [] {
                                guard let summary = self.parseStorySummary(from: document.data()) else { continue }
                                let normalized = self.normalizedStorySummary(summary)
                                mergedSummaries[document.documentID] = normalized
                                if summary.activeStoryCount > 0 && normalized.activeStoryCount == 0 {
                                    self.scheduleStorySummaryRebuildIfNeeded(for: document.documentID)
                                }
                            }
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let (result, error): ([String: StoryAuthorSummary], Error?) = syncQueue.sync {
                (mergedSummaries, capturedError)
            }
            if result.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(result))
            }
        }
    }

    /// Recalcula y guarda storySummary para un autor.
    func rebuildStorySummary(for userId: String, completion: ((Error?) -> Void)? = nil) {
        guard !userId.isEmpty else {
            completion?(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "userId vacío"]))
            return
        }

        db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion?(error)
                    return
                }

                let stories = snapshot?.documents.compactMap { try? $0.data(as: Story.self) } ?? []
                let activeCount = stories.count
                let latestStoryAt = stories.map(\.timestamp).max()
                let latestExpirationAt = stories.map(\.expirationDate).max()
                var audiencesSummary: [String: Int] = [:]
                for story in stories {
                    let key = (story.audience?.isEmpty == false ? story.audience! : "everyone")
                    audiencesSummary[key, default: 0] += 1
                }

                let userRef = self.db.collection("users").document(userId)
                let batch = self.db.batch()
                // Reemplazo explícito de subcampos para evitar arrastrar claves antiguas en audiencesSummary.
                var summaryPayload: [AnyHashable: Any] = [
                    FieldPath(["storySummary", "activeStoryCount"]): activeCount,
                    FieldPath(["storySummary", "audiencesSummary"]): audiencesSummary,
                    FieldPath(["storySummary", "updatedAt"]): FieldValue.serverTimestamp()
                ]
                if let latestStoryAt = latestStoryAt {
                    summaryPayload[FieldPath(["storySummary", "latestStoryAt"])] = Timestamp(date: latestStoryAt)
                } else {
                    summaryPayload[FieldPath(["storySummary", "latestStoryAt"])] = FieldValue.delete()
                }
                if let latestExpirationAt = latestExpirationAt {
                    summaryPayload[FieldPath(["storySummary", "latestExpirationAt"])] = Timestamp(date: latestExpirationAt)
                } else {
                    summaryPayload[FieldPath(["storySummary", "latestExpirationAt"])] = FieldValue.delete()
                }
                batch.updateData(summaryPayload, forDocument: userRef)
                batch.updateData(
                    self.legacyStorySummaryCleanupPayload(audienceKeys: Array(audiencesSummary.keys)),
                    forDocument: userRef
                )
                batch.commit { writeError in
                    completion?(writeError)
                }
            }
    }

    private func parseStorySummary(from userData: [String: Any]) -> StoryAuthorSummary? {
        guard let summary = userData["storySummary"] as? [String: Any] else { return nil }

        let activeCount = (summary["activeStoryCount"] as? NSNumber)?.intValue ?? (summary["activeStoryCount"] as? Int) ?? 0
        let latestStoryAt = (summary["latestStoryAt"] as? Timestamp)?.dateValue()
        let latestExpirationAt = (summary["latestExpirationAt"] as? Timestamp)?.dateValue()
        let updatedAt = (summary["updatedAt"] as? Timestamp)?.dateValue()

        var audiencesSummary: [String: Int] = [:]
        if let rawAudiences = summary["audiencesSummary"] as? [String: Any] {
            for (key, value) in rawAudiences {
                if let number = value as? NSNumber {
                    audiencesSummary[key] = number.intValue
                }
            }
        } else if let typedAudiences = summary["audiencesSummary"] as? [String: Int] {
            audiencesSummary = typedAudiences
        }

        return StoryAuthorSummary(
            activeStoryCount: activeCount,
            latestStoryAt: latestStoryAt,
            latestExpirationAt: latestExpirationAt,
            audiencesSummary: audiencesSummary,
            updatedAt: updatedAt
        )
    }

    private func normalizedStorySummary(_ summary: StoryAuthorSummary) -> StoryAuthorSummary {
        guard let latestExpirationAt = summary.latestExpirationAt, latestExpirationAt <= Date() else {
            if summary.latestExpirationAt == nil,
               summary.activeStoryCount > 0,
               let latestStoryAt = summary.latestStoryAt,
               latestStoryAt <= Date().addingTimeInterval(-(52 * 60 * 60)) {
                // Compatibilidad con summaries antiguos sin latestExpirationAt.
                return StoryAuthorSummary(
                    activeStoryCount: 0,
                    latestStoryAt: nil,
                    latestExpirationAt: latestStoryAt,
                    audiencesSummary: [:],
                    updatedAt: summary.updatedAt
                )
            }
            return summary
        }

        return StoryAuthorSummary(
            activeStoryCount: 0,
            latestStoryAt: nil,
            latestExpirationAt: latestExpirationAt,
            audiencesSummary: [:],
            updatedAt: summary.updatedAt
        )
    }

    private func scheduleStorySummaryRebuildIfNeeded(for userId: String) {
        guard !userId.isEmpty else { return }

        var shouldSchedule = false
        storySummaryRebuildQueue.sync {
            let now = Date()
            if let lastAttempt = storySummaryLastRebuildAttempt[userId],
               now.timeIntervalSince(lastAttempt) < storySummaryRebuildCooldown {
                shouldSchedule = false
                return
            }
            if storySummaryRebuildInFlight.contains(userId) {
                shouldSchedule = false
                return
            }
            storySummaryRebuildInFlight.insert(userId)
            storySummaryLastRebuildAttempt[userId] = now
            shouldSchedule = true
        }

        guard shouldSchedule else { return }

        rebuildStorySummary(for: userId) { [weak self] _ in
            guard let self = self else { return }
            self.storySummaryRebuildQueue.async {
                self.storySummaryRebuildInFlight.remove(userId)
            }
        }
    }

    func bumpStorySummaryOnCreate(userId: String, audience: String?, timestamp: Date, expirationDate: Date) {
        guard !userId.isEmpty else { return }

        let audienceKey = (audience?.isEmpty == false ? audience! : "everyone")
        var payload: [AnyHashable: Any] = [
            FieldPath(["storySummary", "activeStoryCount"]): FieldValue.increment(Int64(1)),
            FieldPath(["storySummary", "latestStoryAt"]): Timestamp(date: timestamp),
            FieldPath(["storySummary", "latestExpirationAt"]): Timestamp(date: expirationDate),
            FieldPath(["storySummary", "updatedAt"]): FieldValue.serverTimestamp(),
            FieldPath(["storySummary", "audiencesSummary", audienceKey]): FieldValue.increment(Int64(1))
        ]
        self.legacyStorySummaryCleanupPayload(audienceKeys: [audienceKey]).forEach { key, value in
            payload[key] = value
        }

        db.collection("users").document(userId).updateData(payload) { error in
            _ = error
        }
    }

    private func legacyStorySummaryCleanupPayload(audienceKeys: [String]) -> [AnyHashable: Any] {
        let defaultAudienceKeys = ["everyone", "connections", "mutuals", "bestFriends", "custom", "customList", "onlyMe"]
        let keys = Array(Set(defaultAudienceKeys + audienceKeys))

        var payload: [AnyHashable: Any] = [
            FieldPath(["storySummary.activeStoryCount"]): FieldValue.delete(),
            FieldPath(["storySummary.latestStoryAt"]): FieldValue.delete(),
            FieldPath(["storySummary.latestExpirationAt"]): FieldValue.delete(),
            FieldPath(["storySummary.updatedAt"]): FieldValue.delete(),
            FieldPath(["storySummary.audiencesSummary"]): FieldValue.delete()
        ]
        for key in keys {
            payload[FieldPath(["storySummary.audiencesSummary.\(key)"])] = FieldValue.delete()
        }
        return payload
    }

    func createHighlight(userId: String, title: String, storyIds: [String], coverImageUrl: String?, completion: @escaping (Error?) -> Void) {
        let highlight = HighlightedStory(
            id: nil,
            title: title,
            coverImageUrl: coverImageUrl,
            storiesCount: storyIds.count,
            createdAt: Date(),
            storyIds: storyIds,
            authorId: userId
        )

        do {
            let _ = try db.collection("users").document(userId).collection("highlights").addDocument(from: highlight) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteHighlight(userId: String, highlightId: String, completion: @escaping (Error?) -> Void) {
        db.collection("users").document(userId).collection("highlights").document(highlightId).delete { error in
            completion(error)
        }
    }

    func updateHighlight(userId: String, highlightId: String, title: String, storyIds: [String], coverImageUrl: String?, completion: @escaping (Error?) -> Void) {
        let updateData: [String: Any] = [
            "title": title,
            "storyIds": storyIds,
            "storiesCount": storyIds.count,
            "coverImageUrl": coverImageUrl as Any
        ]

        db.collection("users").document(userId).collection("highlights").document(highlightId).updateData(updateData) { error in
            completion(error)
        }
    }

    // MARK: - PREFETCHING METHODS (PHASE 8)

    /// Precarga las historias de un usuario en el caché local para una apertura instantánea
    func prefetchStoriesForUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .order(by: "timestamp", descending: true)
            .limit(to: 5)
            .getDocuments { snapshot, _ in
                guard let documents = snapshot?.documents, !documents.isEmpty else { return }

                let stories = documents.compactMap { try? $0.data(as: Story.self) }

                // ✅ COMPROBACIÓN DE PRIVACIDAD POR HISTORIA (NUEVO)
                // Usamos ContentVisibilityService para filtrar cada historia individualmente
                let visibilityService = ContentVisibilityService.shared
                let group = DispatchGroup()
                var authorizedStories: [Story] = []
                let syncQueue = DispatchQueue(label: "prefetch.visibility.sync")

                for story in stories {
                    group.enter()

                    // ✅ MAPEO DE AUDIENCIA (NUEVO)
                    // Convertimos el string de la DB al enum que entiende el servicio de visibilidad
                    let visibilityType: ContentVisibilityType
                    if let audienceStr = story.audience {
                        switch audienceStr {
                        case "everyone": visibilityType = .everyone
                        case "connections": visibilityType = .connections
                        case "bestFriends": visibilityType = .bestFriends
                        case "custom", "customList": visibilityType = .custom
                        case "onlyMe": visibilityType = .onlyMe
                        default: visibilityType = .everyone
                        }
                    } else {
                        visibilityType = .everyone
                    }

                    visibilityService.canUserSeeContent(
                        contentOwnerId: story.authorId,
                        viewerId: currentUserId,
                        contentType: visibilityType,
                        customViewers: story.customListId != nil ? [story.customListId!] : [],
                        hiddenFrom: []
                    ) { canSee in
                        if canSee {
                            syncQueue.sync {
                                authorizedStories.append(story)
                            }
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self.prefetchStoriesToCache(authorizedStories)
                }
            }
    }

    /// Precarga las imágenes de un array de historias en el caché de Kingfisher
    private func prefetchStoriesToCache(_ stories: [Story]) {
        let urls = stories.compactMap { story -> URL? in
            let urlString = story.mediaItem.url
            return URL(string: urlString)
        }

        if !urls.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: urls)
        }
    }
}
