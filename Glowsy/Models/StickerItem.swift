import CoreLocation
import Photos
import SwiftUI
import UIKit

struct MediaLibraryItem: Identifiable {
    let id: String
    let thumbnail: UIImage
    let isVideo: Bool
    let duration: TimeInterval?
    let videoURL: URL?
    let phAsset: PHAsset?

    init(
        id: String,
        thumbnail: UIImage,
        isVideo: Bool,
        duration: TimeInterval? = nil,
        videoURL: URL? = nil,
        phAsset: PHAsset? = nil
    ) {
        self.id = id
        self.thumbnail = thumbnail
        self.isVideo = isVideo
        self.duration = duration
        self.videoURL = videoURL
        self.phAsset = phAsset
    }
}

struct StickerItem: Identifiable {
    let id: String
    let image: UIImage
    var position: CGPoint
    var scale: CGFloat = 1.0
    var rotation: Angle = .zero

    let gifURL: URL?
    let videoURL: URL?
    let isAnimated: Bool

    let type: StickerType
    var interactionData: StickerInteractionData?

    enum StickerType: String, Codable {
        case emoji
        case sticker
        case mention
        case hashtag
        case location
        case poll
        case question
        case link
        case countdown
        case emojiSlider
        case questionResponse
        case generic
        case weather
        case time
        case selfie
        case shareMoment
        case quiz
        case frame
        case reveal
        case audio
    }

    struct StickerInteractionData {
        var username: String?
        var userId: String?
        var hashtag: String?
        var location: String?
        var locationCoordinate: CLLocationCoordinate2D?
        var pollData: [String]?
        var questionText: String?
        var weatherSymbol: String?
        var linkURL: String?
        var linkTitle: String?
        var countdownTitle: String?
        var countdownTargetAtMs: Double?
        var sliderEmoji: String?
        var sliderPrompt: String?
        var caption: String?
        var profileImagePath: String?
        var momentId: String?
        var mediaCount: Int?

        var quizQuestion: String?
        var quizOptions: [String]?
        var quizCorrectIndex: Int?

        var revealType: String?
        var revealPattern: String?
        var revealPrimaryColor: String?
        var revealSecondaryColor: String?

        var frameStyle: String?
        var contentScale: CGFloat?
        var contentOffsetX: CGFloat?
        var contentOffsetY: CGFloat?

        var audioURL: String?
        var audioDuration: Double?

        init(
            username: String? = nil,
            userId: String? = nil,
            hashtag: String? = nil,
            location: String? = nil,
            locationCoordinate: CLLocationCoordinate2D? = nil,
            pollData: [String]? = nil,
            questionText: String? = nil,
            weatherSymbol: String? = nil,
            linkURL: String? = nil,
            linkTitle: String? = nil,
            countdownTitle: String? = nil,
            countdownTargetAtMs: Double? = nil,
            sliderEmoji: String? = nil,
            sliderPrompt: String? = nil,
            caption: String? = nil,
            profileImagePath: String? = nil,
            momentId: String? = nil,
            mediaCount: Int? = nil,
            quizQuestion: String? = nil,
            quizOptions: [String]? = nil,
            quizCorrectIndex: Int? = nil,
            revealType: String? = nil,
            revealPattern: String? = nil,
            revealPrimaryColor: String? = nil,
            revealSecondaryColor: String? = nil,
            frameStyle: String? = nil,
            contentScale: CGFloat? = nil,
            contentOffsetX: CGFloat? = nil,
            contentOffsetY: CGFloat? = nil,
            audioURL: String? = nil,
            audioDuration: Double? = nil
        ) {
            self.username = username
            self.userId = userId
            self.hashtag = hashtag
            self.location = location
            self.locationCoordinate = locationCoordinate
            self.pollData = pollData
            self.questionText = questionText
            self.weatherSymbol = weatherSymbol
            self.linkURL = linkURL
            self.linkTitle = linkTitle
            self.countdownTitle = countdownTitle
            self.countdownTargetAtMs = countdownTargetAtMs
            self.sliderEmoji = sliderEmoji
            self.sliderPrompt = sliderPrompt
            self.caption = caption
            self.profileImagePath = profileImagePath
            self.momentId = momentId
            self.mediaCount = mediaCount
            self.quizQuestion = quizQuestion
            self.quizOptions = quizOptions
            self.quizCorrectIndex = quizCorrectIndex
            self.revealType = revealType
            self.revealPattern = revealPattern
            self.revealPrimaryColor = revealPrimaryColor
            self.revealSecondaryColor = revealSecondaryColor
            self.frameStyle = frameStyle
            self.contentScale = contentScale
            self.contentOffsetX = contentOffsetX
            self.contentOffsetY = contentOffsetY
            self.audioURL = audioURL
            self.audioDuration = audioDuration
        }
    }

    init(
        image: UIImage,
        position: CGPoint,
        type: StickerType,
        interactionData: StickerInteractionData?,
        videoURL: URL? = nil,
        gifURL: URL? = nil
    ) {
        self.id = "\(type.rawValue)_\(UUID().uuidString)"
        self.image = image
        self.position = position
        self.type = type
        self.gifURL = gifURL
        self.videoURL = videoURL
        self.isAnimated = videoURL != nil || gifURL != nil
        self.interactionData = interactionData
    }

    init(
        image: UIImage,
        gifURL: URL,
        position: CGPoint,
        type: StickerType,
        interactionData: StickerInteractionData?
    ) {
        self.id = "\(type.rawValue)_\(UUID().uuidString)"
        self.image = image
        self.position = position
        self.type = type
        self.gifURL = gifURL
        self.videoURL = nil
        self.isAnimated = true
        self.interactionData = interactionData
    }

    init(
        id: String,
        image: UIImage,
        position: CGPoint,
        scale: CGFloat,
        rotation: Angle,
        gifURL: URL?,
        videoURL: URL? = nil,
        isAnimated: Bool,
        type: StickerType,
        interactionData: StickerInteractionData?
    ) {
        self.id = id
        self.image = image
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.gifURL = gifURL
        self.videoURL = videoURL
        self.isAnimated = isAnimated
        self.type = type
        self.interactionData = interactionData
    }
}
