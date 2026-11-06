#if DEBUG
import Foundation
import CoreLocation
import UIKit

// MARK: - Textos de demostración

/// Lee `ScreenshotCopy.json` para el idioma actual y cae a inglés si falta algo.
enum ScreenshotCopy {
    private static let table: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "ScreenshotCopy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return json
    }()

    private static var languageChain: [String] {
        let lang = ScreenshotMode.lang
        var chain = [lang]
        if let base = lang.split(separator: "-").first.map(String.init), base != lang {
            chain.append(base)
        }
        if !chain.contains("en") {
            chain.append("en")
        }
        return chain
    }

    private static func lookup(_ path: String, language: String) -> Any? {
        var node: Any? = table[language]
        for part in path.split(separator: ".") {
            node = (node as? [String: Any])?[String(part)]
        }
        return node
    }

    private static func resolve(_ path: String) -> Any? {
        for language in languageChain {
            if let value = lookup(path, language: language) {
                return value
            }
        }
        return nil
    }

    static func text(_ path: String) -> String {
        (resolve(path) as? String) ?? ""
    }

    static func list(_ path: String) -> [String] {
        (resolve(path) as? [String]) ?? []
    }

    static func entries(_ path: String) -> [[String: String]] {
        (resolve(path) as? [[String: String]]) ?? []
    }
}

// MARK: - Datos de demostración

enum ScreenshotFixtures {
    static let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)

    // MARK: Usuarios

    private static func makeUser(
        id: String,
        username: String,
        avatar: String,
        verified: Bool,
        bestFriends: [String] = [],
        followers: Int = 0,
        following: Int = 0,
        moments: Int = 0
    ) -> AppUser {
        AppUser(
            id: id,
            username: username,
            email: "",
            interests: [],
            isPlusSubscriber: false,
            profileImagePath: ScreenshotImages.url(avatar),
            bio: nil,
            blockedUsers: [],
            isPrivate: false,
            activeHoursStart: nil,
            activeHoursEnd: nil,
            notificationPreferences: nil,
            bestFriends: bestFriends,
            followersCount: followers,
            followingCount: following,
            momentsCount: moments,
            isVerified: verified
        )
    }

    static let lucia = makeUser(id: "ss_lucia", username: "lucia.mar", avatar: "ss_avatar_lucia", verified: true, followers: 2840, following: 412, moments: 186)
    static let theo = makeUser(id: "ss_theo", username: "theo.wav", avatar: "ss_avatar_theo", verified: false, followers: 932, following: 380, moments: 74)
    static let aiko = makeUser(id: "ss_aiko", username: "aiko.film", avatar: "ss_avatar_aiko", verified: true, followers: 5120, following: 290, moments: 241)
    static let mateo = makeUser(id: "ss_mateo", username: "mateo.rv", avatar: "ss_avatar_mateo", verified: false, followers: 640, following: 512, moments: 58)
    static let nora = makeUser(id: "ss_nora", username: "nora.eats", avatar: "ss_avatar_nora", verified: false, followers: 1210, following: 455, moments: 133)
    static let sam = makeUser(id: "ss_sam", username: "sam.trails", avatar: "ss_avatar_sam", verified: false, followers: 488, following: 301, moments: 92)
    static let ines = makeUser(id: "ss_ines", username: "ines.draws", avatar: "ss_avatar_ines", verified: false, followers: 1764, following: 388, moments: 117)
    static let kai = makeUser(id: "ss_kai", username: "kai.waves", avatar: "ss_avatar_kai", verified: true, followers: 3390, following: 270, moments: 204)

    static let friends: [AppUser] = [lucia, theo, aiko, mateo, nora, sam, ines, kai]

    static let me = makeUser(
        id: ScreenshotMode.meId,
        username: "alex",
        avatar: "ss_me",
        verified: false,
        bestFriends: [lucia.id, theo.id, aiko.id],
        followers: 1280,
        following: 344,
        moments: 96
    )

    static var allUsers: [AppUser] { [me] + friends }

    static func user(_ id: String) -> AppUser? {
        allUsers.first { $0.id == id }
    }

    static func avatarURL(for userId: String) -> String? {
        user(userId)?.profileImagePath
    }

    // MARK: Momentos

    private static func ago(minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    private static func reactions(_ count: Int) -> [String: [String]] {
        let ids = (allUsers.map(\.id) + (0..<max(0, count - allUsers.count)).map { "ss_fan_\($0)" })
        let love = Array(ids.prefix(count))
        return [
            "love": love,
            "fire": Array(ids.prefix(max(1, count / 3))),
            "vibe": Array(ids.prefix(max(1, count / 5)))
        ]
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> Moment.LocationCoordinate {
        Moment.LocationCoordinate(latitude: lat, longitude: lon)
    }

    private static func makeMoment(
        id: String,
        author: AppUser,
        asset: String,
        caption: String,
        minutesAgo: Double,
        location: String?,
        coordinate: Moment.LocationCoordinate?,
        likes: Int,
        comments: Int,
        aspectRatio: String = "4:5",
        aiGenerated: Bool = false,
        hiddenLayerCount: Int = 0
    ) -> Moment {
        let url = ScreenshotImages.url(asset)
        return Moment(
            id: id,
            authorId: author.id,
            username: author.username,
            content: ScreenshotCopy.text("captions.\(caption)"),
            imagePath: url,
            videoUrl: nil,
            timestamp: ago(minutes: minutesAgo),
            reactions: reactions(likes),
            commentCount: comments,
            profileImagePath: author.profileImagePath,
            taggedUsers: nil,
            location: location,
            locationCoordinate: coordinate,
            audience: "everyone",
            mediaItems: [MediaItem(id: "\(id)_media", type: .image, url: url, aspectRatio: aspectRatio)],
            aspectRatio: aspectRatio,
            customListId: nil,
            thumbnailUrl: nil,
            videoDuration: nil,
            videoFileSize: nil,
            videoResolution: nil,
            disableComments: false,
            hideLikeCounts: false,
            allowSharing: true,
            aiGenerated: aiGenerated,
            aiLabelSource: aiGenerated ? AILabelSource.creator : nil,
            hasHiddenLayers: hiddenLayerCount > 0,
            hiddenLayerCount: hiddenLayerCount
        )
    }

    static let beachSunset = makeMoment(id: "ss_m_beach_sunset", author: lucia, asset: "ss_moment_beach_sunset", caption: "beach_sunset", minutesAgo: 18, location: "Barceloneta", coordinate: coordinate(41.3784, 2.1925), likes: 214, comments: 4)
    static let picnic = makeMoment(id: "ss_m_picnic", author: lucia, asset: "ss_moment_picnic", caption: "picnic", minutesAgo: 52, location: "Montjuïc", coordinate: coordinate(41.3636, 2.1580), likes: 168, comments: 4, hiddenLayerCount: 3)
    static let mountainLake = makeMoment(id: "ss_m_mountain_lake", author: aiko, asset: "ss_moment_mountain_lake", caption: "mountain_lake", minutesAgo: 95, location: nil, coordinate: nil, likes: 342, comments: 21, aiGenerated: true)
    static let rooftopDinner = makeMoment(id: "ss_m_rooftop_dinner", author: theo, asset: "ss_moment_rooftop_dinner", caption: "rooftop_dinner", minutesAgo: 140, location: "Eixample", coordinate: coordinate(41.3917, 2.1649), likes: 97, comments: 8)
    static let latte = makeMoment(id: "ss_m_latte", author: nora, asset: "ss_moment_latte", caption: "latte", minutesAgo: 210, location: "Gràcia", coordinate: coordinate(41.4036, 2.1564), likes: 76, comments: 5)
    static let concert = makeMoment(id: "ss_m_concert", author: kai, asset: "ss_moment_concert", caption: "concert", minutesAgo: 300, location: "Parc del Fòrum", coordinate: coordinate(41.4105, 2.2266), likes: 451, comments: 33)
    static let nightMarket = makeMoment(id: "ss_m_night_market", author: mateo, asset: "ss_moment_night_market", caption: "night_market", minutesAgo: 380, location: "El Born", coordinate: coordinate(41.3851, 2.1834), likes: 88, comments: 6)
    static let dogPark = makeMoment(id: "ss_m_dog_park", author: sam, asset: "ss_moment_dog_park", caption: "dog_park", minutesAgo: 460, location: "Parc de la Ciutadella", coordinate: coordinate(41.3881, 2.1873), likes: 129, comments: 9)
    static let roadTrip = makeMoment(id: "ss_m_road_trip", author: ines, asset: "ss_moment_road_trip", caption: "road_trip", minutesAgo: 600, location: "Costa Brava", coordinate: coordinate(41.8930, 3.1650), likes: 157, comments: 12)
    static let ski = makeMoment(id: "ss_m_ski", author: mateo, asset: "ss_moment_ski", caption: "ski", minutesAgo: 1_300, location: "La Molina", coordinate: coordinate(42.3360, 1.9400), likes: 203, comments: 14)
    static let birthday = makeMoment(id: "ss_m_birthday", author: nora, asset: "ss_moment_birthday", caption: "birthday", minutesAgo: 900, location: "Poblenou", coordinate: coordinate(41.4030, 2.2010), likes: 264, comments: 41)
    static let lisbonTram = makeMoment(id: "ss_m_lisbon_tram", author: aiko, asset: "ss_moment_lisbon_tram", caption: "lisbon_tram", minutesAgo: 2_100, location: "Lisboa", coordinate: coordinate(38.7139, -9.1394), likes: 188, comments: 10)

    /// Feed: en `aiLabel` el momento con etiqueta IA va primero.
    static var feedMoments: [Moment] {
        let base = [beachSunset, picnic, mountainLake, rooftopDinner, latte, concert, nightMarket, dogPark, roadTrip]
        guard ScreenshotMode.screen == .aiLabel else { return base }
        return [mountainLake] + base.filter { $0.id != mountainLake.id }
    }

    static var hiddenLayersMoment: Moment { picnic }

    // MARK: Capas ocultas

    static func hiddenLayers(for momentId: String) -> [MomentHiddenLayer] {
        guard momentId == picnic.id else { return [] }
        let created = ago(minutes: 52)
        return [
            MomentHiddenLayer(
                id: "ss_hl_text",
                type: .text,
                anchorX: 0.30,
                anchorY: 0.28,
                width: 0.46,
                height: 0.16,
                shape: .roundedRect,
                zIndex: 0,
                text: ScreenshotCopy.text("hiddenLayers.note"),
                textStyle: .handwritten,
                presentationStyle: .paperNote,
                hintStyle: .aurora,
                createdAt: created
            ),
            MomentHiddenLayer(
                id: "ss_hl_image",
                type: .image,
                anchorX: 0.70,
                anchorY: 0.56,
                width: 0.38,
                height: 0.30,
                shape: .roundedRect,
                zIndex: 1,
                mediaURL: ScreenshotImages.url("ss_hidden_polaroid"),
                thumbnailURL: ScreenshotImages.url("ss_hidden_polaroid"),
                caption: ScreenshotCopy.text("hiddenLayers.imageCaption"),
                imageFrameStyle: .classic,
                presentationStyle: .glassCard,
                hintStyle: .actual,
                createdAt: created
            ),
            MomentHiddenLayer(
                id: "ss_hl_audio",
                type: .audio,
                anchorX: 0.32,
                anchorY: 0.80,
                width: 0.20,
                height: 0.20,
                shape: .circle,
                zIndex: 2,
                mediaURL: "https://\(ScreenshotImages.host)/ss_hidden_voice.m4a",
                duration: 12,
                caption: ScreenshotCopy.text("hiddenLayers.audioCaption"),
                presentationStyle: .captionPill,
                hintStyle: .ember,
                createdAt: created
            )
        ]
    }

    // MARK: Comentarios (se siembran en la caché local de Firestore)

    struct SeedComment {
        let id: String
        let author: AppUser
        let text: String
        let timestamp: Date
    }

    static var commentThreads: [(moment: Moment, comments: [SeedComment])] {
        let texts = ScreenshotCopy.list("comments")
        let authors = [theo, aiko, kai, nora]
        func thread(for moment: Moment) -> [SeedComment] {
            texts.enumerated().map { index, text in
                SeedComment(
                    id: "ss_c_\(moment.id ?? "")_\(index)",
                    author: authors[index % authors.count],
                    text: text,
                    timestamp: ago(minutes: Double(40 - index * 8))
                )
            }
        }
        return [beachSunset, picnic, mountainLake].map { (moment: $0, comments: thread(for: $0)) }
    }

    // MARK: Anillo de historias

    static let storyRing: [FeedStoryUserState] = [
        (userId: me.id, hasStory: false, hasUnseenStory: false, storyCount: 0, storyViewedStatus: [], storyAudiences: []),
        (userId: lucia.id, hasStory: true, hasUnseenStory: true, storyCount: 3, storyViewedStatus: [false, false, false], storyAudiences: ["everyone", "bestFriends", "everyone"]),
        (userId: aiko.id, hasStory: true, hasUnseenStory: true, storyCount: 2, storyViewedStatus: [false, false], storyAudiences: ["bestFriends", "bestFriends"]),
        (userId: theo.id, hasStory: true, hasUnseenStory: true, storyCount: 1, storyViewedStatus: [false], storyAudiences: ["everyone"]),
        (userId: kai.id, hasStory: true, hasUnseenStory: true, storyCount: 4, storyViewedStatus: [true, false, false, false], storyAudiences: ["everyone", "everyone", "everyone", "everyone"]),
        (userId: nora.id, hasStory: true, hasUnseenStory: false, storyCount: 1, storyViewedStatus: [true], storyAudiences: ["everyone"]),
        (userId: mateo.id, hasStory: true, hasUnseenStory: false, storyCount: 2, storyViewedStatus: [true, true], storyAudiences: ["everyone", "mutuals"]),
        (userId: sam.id, hasStory: true, hasUnseenStory: false, storyCount: 1, storyViewedStatus: [true], storyAudiences: ["everyone"]),
        (userId: ines.id, hasStory: true, hasUnseenStory: false, storyCount: 1, storyViewedStatus: [true], storyAudiences: ["everyone"])
    ]

    // MARK: Historias (visor)

    /// Duración larga para que la barra de progreso no avance durante la captura.
    static let storyDuration: Double = 600

    private static func makeStory(id: String, asset: String, minutesAgo: Double, audience: String, stickers: [StickerData]) -> Story {
        Story(
            id: id,
            authorId: lucia.id,
            username: lucia.username,
            mediaItem: MediaItem(id: "\(id)_media", type: .image, url: ScreenshotImages.url(asset), aspectRatio: "9:16"),
            duration: storyDuration,
            timestamp: ago(minutes: minutesAgo),
            expirationDate: Date().addingTimeInterval(20 * 3600),
            profileImagePath: lucia.profileImagePath,
            audience: audience,
            stickers: stickers,
            aspectRatio: "9:16"
        )
    }

    static let stories: [Story] = [
        // A: rasca y gana a pantalla completa.
        makeStory(
            id: "ss_story_a",
            asset: "ss_story_festival",
            minutesAgo: 190,
            audience: "everyone",
            stickers: [
                StickerData(
                    stickerId: "ss_reveal",
                    type: "reveal",
                    content: "",
                    position: CGPoint(x: 0.5, y: 0.5),
                    scale: 1,
                    rotation: 0,
                    zIndex: 1,
                    revealType: "gradient",
                    revealPattern: "dots",
                    revealPrimaryColor: "5B2C6F",
                    revealSecondaryColor: "C86DD7",
                    revealEffectColor: "FFFFFF"
                )
            ]
        ),
        // B: polaroid + encuesta.
        makeStory(
            id: "ss_story_b",
            asset: "ss_story_sunrise",
            minutesAgo: 120,
            audience: "bestFriends",
            stickers: [
                StickerData(
                    stickerId: "ss_frame",
                    type: "frame",
                    content: ScreenshotImages.base64JPEG("ss_moment_lisbon_tram"),
                    position: CGPoint(x: 0.5, y: 0.36),
                    scale: 1.2,
                    rotation: -0.07,
                    zIndex: 1,
                    caption: ScreenshotCopy.text("story.frameCaption"),
                    frameStyle: "classic"
                ),
                StickerData(
                    stickerId: "ss_poll",
                    type: "poll",
                    content: "",
                    position: CGPoint(x: 0.5, y: 0.76),
                    scale: 0.95,
                    rotation: 0,
                    zIndex: 2,
                    styleVariant: 0,
                    pollOptions: [
                        ScreenshotCopy.text("story.pollQuestion"),
                        ScreenshotCopy.text("story.pollOptionA"),
                        ScreenshotCopy.text("story.pollOptionB")
                    ]
                )
            ]
        ),
        // C: caja de preguntas.
        makeStory(
            id: "ss_story_c",
            asset: "ss_story_cooking",
            minutesAgo: 40,
            audience: "everyone",
            stickers: [
                StickerData(
                    stickerId: "ss_question",
                    type: "question",
                    content: "",
                    position: CGPoint(x: 0.5, y: 0.72),
                    scale: 1,
                    rotation: 0,
                    zIndex: 1,
                    styleVariant: 1,
                    questionText: ScreenshotCopy.text("story.question")
                )
            ]
        )
    ]

    // MARK: Mensajes

    static let chatConversationId = "ss_conv_lucia"

    private static func makeConversation(
        with friend: AppUser,
        lastMessage: String,
        minutesAgo: Double,
        unread: Bool,
        lastFromMe: Bool
    ) -> Conversation {
        var conversation = Conversation(
            id: friend.id == lucia.id ? chatConversationId : "ss_conv_\(friend.id)",
            participants: [friend.id, me.id],
            lastMessage: lastMessage,
            timestamp: ago(minutes: minutesAgo),
            // La clave "" cubre las vistas que leen el uid de Auth (sin sesión).
            readStatus: [me.id: !unread, "": !unread, friend.id: true],
            otherParticipantId: friend.id,
            otherParticipantUsername: friend.username,
            otherParticipantProfileImagePath: friend.profileImagePath
        )
        conversation.lastMessageSenderId = lastFromMe ? me.id : friend.id
        conversation.lastMessageType = .text
        return conversation
    }

    static var conversations: [Conversation] {
        let lastChatLine = ScreenshotCopy.entries("chat").last(where: { $0["text"] != nil })?["text"] ?? ""
        return [
            makeConversation(with: lucia, lastMessage: lastChatLine, minutesAgo: 3, unread: false, lastFromMe: true),
            makeConversation(with: theo, lastMessage: ScreenshotCopy.text("inbox.theo"), minutesAgo: 12, unread: true, lastFromMe: false),
            makeConversation(with: aiko, lastMessage: ScreenshotCopy.text("inbox.aiko"), minutesAgo: 34, unread: true, lastFromMe: false),
            makeConversation(with: kai, lastMessage: ScreenshotCopy.text("inbox.kai"), minutesAgo: 75, unread: false, lastFromMe: false),
            makeConversation(with: mateo, lastMessage: ScreenshotCopy.text("inbox.mateo"), minutesAgo: 160, unread: false, lastFromMe: false),
            makeConversation(with: nora, lastMessage: ScreenshotCopy.text("inbox.nora"), minutesAgo: 320, unread: false, lastFromMe: false),
            makeConversation(with: ines, lastMessage: ScreenshotCopy.text("inbox.ines"), minutesAgo: 1_440, unread: false, lastFromMe: false),
            makeConversation(with: sam, lastMessage: ScreenshotCopy.text("inbox.sam"), minutesAgo: 2_900, unread: false, lastFromMe: false)
        ]
    }

    private static let voiceWaveform: [Float] = [
        0.18, 0.32, 0.55, 0.41, 0.72, 0.9, 0.64, 0.38, 0.5, 0.82,
        0.95, 0.7, 0.44, 0.3, 0.58, 0.76, 0.62, 0.4, 0.26, 0.48,
        0.68, 0.86, 0.74, 0.52, 0.36, 0.6, 0.8, 0.66, 0.42, 0.28,
        0.46, 0.7, 0.88, 0.6, 0.34, 0.22, 0.4, 0.56, 0.3, 0.16
    ]

    static func messages(for conversationId: String) -> [EnhancedMessage] {
        guard conversationId == chatConversationId else { return [] }
        let lines = ScreenshotCopy.entries("chat")
        let start = Double(max(lines.count, 1)) * 6 + 4
        return lines.enumerated().map { (index, line) -> EnhancedMessage in
            let fromMe = line["from"] == "me"
            let senderId = fromMe ? me.id : lucia.id
            let timestamp = ago(minutes: start - Double(index) * 6)
            let messageId = "ss_msg_\(index)"
            switch line["type"] ?? "text" {
            case "image":
                return EnhancedMessage(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: .image,
                    mediaUrl: ScreenshotImages.url("ss_chat_photo"),
                    thumbnailUrl: ScreenshotImages.url("ss_chat_photo"),
                    mediaWidth: 1080,
                    mediaHeight: 1350,
                    timestamp: timestamp,
                    status: .read,
                    isRead: true
                )
            case "audio":
                return EnhancedMessage(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: .audio,
                    mediaUrl: "https://\(ScreenshotImages.host)/ss_voice_note.m4a",
                    duration: 14,
                    audioWaveform: voiceWaveform,
                    timestamp: timestamp,
                    status: .read,
                    isRead: true
                )
            default:
                return EnhancedMessage(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: .text,
                    content: line["text"] ?? "",
                    timestamp: timestamp,
                    status: .read,
                    isRead: true
                )
            }
        }
    }

    // MARK: Echo

    private static let echoConcertKai = makeMoment(id: "ss_echo_m_kai", author: kai, asset: "ss_moment_concert", caption: "concert", minutesAgo: 70, location: "Parc del Fòrum", coordinate: coordinate(41.4105, 2.2266), likes: 120, comments: 6)
    private static let echoFestivalLucia = makeMoment(id: "ss_echo_m_lucia", author: lucia, asset: "ss_story_festival", caption: "festival", minutesAgo: 62, location: "Parc del Fòrum", coordinate: coordinate(41.4107, 2.2262), likes: 98, comments: 4, aspectRatio: "9:16")
    private static let echoNightTheo = makeMoment(id: "ss_echo_m_theo", author: theo, asset: "ss_moment_night_market", caption: "night_market", minutesAgo: 55, location: "Parc del Fòrum", coordinate: coordinate(41.4101, 2.2270), likes: 64, comments: 3)

    private static var echoMoments: [Moment] { [echoFestivalLucia, echoConcertKai, echoNightTheo] }

    static func echoMoment(id: String) -> Moment? {
        echoMoments.first { $0.id == id }
    }

    static var echo: Echo {
        let participants = [lucia, kai, theo].map {
            EchoParticipant(userId: $0.id, username: $0.username, profileImagePath: $0.profileImagePath, status: .accepted)
        }
        let refs = echoMoments.compactMap { moment in
            moment.mediaItems?.first.map { EchoMomentRef(from: $0, author: moment) }
        }
        var echo = Echo(
            id: "ss_echo",
            hostId: lucia.id,
            participants: participants,
            location: coordinate(41.4105, 2.2266),
            locationName: "Parc del Fòrum",
            moments: refs
        )
        echo.status = .active
        echo.vibeSummary = ScreenshotCopy.text("echo.vibe")
        return echo
    }

    // MARK: Mapa

    static var mapPayload: MapDiscoverPayload {
        let moments = [beachSunset, picnic, rooftopDinner, latte, concert, nightMarket, dogPark, birthday]
        let stories = [
            MapStoryPreview(
                id: "ss_map_story_aiko",
                authorId: aiko.id,
                username: aiko.username,
                profileImagePath: aiko.profileImagePath,
                timestamp: ago(minutes: 35),
                locationName: "Sagrada Família",
                coordinate: CLLocationCoordinate2D(latitude: 41.4036, longitude: 2.1744),
                previewURL: ScreenshotImages.url("ss_story_sunrise"),
                locationFuzzed: false
            ),
            MapStoryPreview(
                id: "ss_map_story_kai",
                authorId: kai.id,
                username: kai.username,
                profileImagePath: kai.profileImagePath,
                timestamp: ago(minutes: 80),
                locationName: "Bunkers del Carmel",
                coordinate: CLLocationCoordinate2D(latitude: 41.4190, longitude: 2.1620),
                previewURL: ScreenshotImages.url("ss_story_festival"),
                locationFuzzed: false
            )
        ]
        return MapDiscoverPayload(
            moments: moments,
            stories: stories,
            source: "screenshots",
            momentsError: nil,
            storiesError: nil
        )
    }

    // MARK: Listas de audiencia

    static var customLists: [CustomAudienceList] {
        [
            CustomAudienceList(
                id: "ss_list_climbing",
                name: ScreenshotCopy.text("lists.climbing"),
                members: [mateo.id, sam.id, kai.id, theo.id],
                color: "06D6A0",
                icon: "figure.climbing"
            ),
            CustomAudienceList(
                id: "ss_list_family",
                name: ScreenshotCopy.text("lists.family"),
                members: [nora.id, ines.id],
                color: "FF6B6B",
                icon: "house.fill"
            ),
            CustomAudienceList(
                id: "ss_list_studio",
                name: ScreenshotCopy.text("lists.studio"),
                members: [aiko.id, lucia.id, ines.id, theo.id, mateo.id],
                color: "3A86FF",
                icon: "briefcase.fill"
            )
        ]
    }

    // MARK: Nova

    static var novaMessages: [ChatMessage] {
        ScreenshotCopy.entries("nova").map { entry in
            ChatMessage(text: entry["text"] ?? "", isUser: entry["from"] == "me", isHistorical: true)
        }
    }
}
#endif
