import FirebaseFirestore
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
        chainId: String? = nil,
        chainPosition: Int? = nil,
        chainTitle: String? = nil,
        allowOthersToContinue: Bool? = nil,
        continuationAudience: ContentAudience? = nil,
        continuationCustomViewers: [String]? = nil,
        continuationCustomListId: String? = nil,
        continuationCustomListName: String? = nil,
        duration: Double? = nil,
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
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle,
            allowOthersToContinue: allowOthersToContinue,
            continuationAudience: continuationAudience,
            continuationCustomViewers: continuationCustomViewers,
            continuationCustomListId: continuationCustomListId,
            continuationCustomListName: continuationCustomListName,
            duration: duration,
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
        chainId: String? = nil,
        chainPosition: Int? = nil,
        chainTitle: String? = nil,
        allowOthersToContinue: Bool? = nil,
        continuationAudience: ContentAudience? = nil,
        continuationCustomViewers: [String]? = nil,
        continuationCustomListId: String? = nil,
        continuationCustomListName: String? = nil,
        duration: Double? = nil,
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
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle,
            allowOthersToContinue: allowOthersToContinue,
            continuationAudience: continuationAudience,
            continuationCustomViewers: continuationCustomViewers,
            continuationCustomListId: continuationCustomListId,
            continuationCustomListName: continuationCustomListName,
            duration: duration,
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
        chainId: String?,
        chainPosition: Int?,
        chainTitle: String?,
        allowOthersToContinue: Bool?,
        continuationAudience: ContentAudience?,
        continuationCustomViewers: [String]?,
        continuationCustomListId: String?,
        continuationCustomListName: String?,
        duration: Double?,
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
                let storyId = UUID().uuidString

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
}
