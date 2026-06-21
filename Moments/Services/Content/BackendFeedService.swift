import Foundation
import FirebaseAuth
import FirebaseCore

// MARK: - Backend Feed Response
struct BackendFeedResponse: Codable {
    let moments: [BackendMoment]
    let nextCursor: FeedCursor?
    let source: String
    let totalCandidates: Int
}

struct BackendHighlightsResponse: Codable {
    let highlights: [BackendHighlight]
    let source: String
    let totalCandidates: Int
}

struct BackendHighlight: Codable {
    let id: String
    let title: String
    let coverImageUrl: String?
    let storiesCount: Int
    let createdAt: Double?
    let storyIds: [String]
    let authorId: String

    func toHighlightedStory() -> HighlightedStory {
        HighlightedStory(
            id: id,
            title: title,
            coverImageUrl: coverImageUrl,
            storiesCount: storiesCount,
            createdAt: Date(timeIntervalSince1970: (createdAt ?? 0) / 1000),
            storyIds: storyIds,
            authorId: authorId
        )
    }
}

struct BackendStoryTrayResponse: Codable {
    let items: [BackendStoryTrayItem]
    let nextCursor: StoryRingCursor?
    let source: String
    let totalCandidates: Int
}

struct StoryRingCursor: Codable {
    let offset: Int
}

struct BackendAuthorStoryBundleResponse: Codable {
    let authorId: String
    let stories: [BackendStoryDocument]
    let segments: [BackendStoryTraySegment]
    let source: String
}

/// Firestore story document serialized by Cloud Functions (timestamps as epoch millis).
struct BackendStoryDocument: Codable {
    let id: String
    let authorId: String
    let duration: Double?
    let expirationHours: Int?
    let expirationDate: Double?
    let timestamp: Double?
    let username: String?
    let profileImagePath: String?
    let audience: String?
    let customListId: String?
    let text: String?
    let textStyle: String?
    let textPositionX: Double?
    let textPositionY: Double?
    let textPositionNormX: Double?
    let textPositionNormY: Double?
    let textColorHex: String?
    let textFontSize: Double?
    let textAlignment: String?
    let textBackgroundFill: String?
    let textStroke: String?
    let textVisualEffect: String?
    let textMotion: String?
    let forcesAllCaps: Bool?
    let textLayerOrder: Int?
    let textOverlayLive: Bool?
    let textOverlays: [StoryTextOverlayMetadata]?
    let drawingData: String?
    let stickers: [StickerData]?
    let aspectRatio: String?
    let backgroundFrameURL: String?
    let backgroundBlurredFrameURL: String?
    let chainId: String?
    let chainPosition: Int?
    let chainTitle: String?
    let mediaItem: BackendStoryMediaItem?
    let imagePath: String?
    let videoUrl: String?
}

struct BackendStoryMediaItem: Codable {
    let type: String
    let url: String
}

struct BackendStoryTrayItem: Codable {
    let userId: String
    let storyCount: Int
    let hasUnseenStory: Bool
    let segments: [BackendStoryTraySegment]
    let latestStoryAt: Double?
}

struct BackendStoryTraySegment: Codable {
    let storyId: String
    let viewed: Bool
    let audience: String?
    let timestamp: Double?
}

struct FeedCursor: Codable {
    let timestamp: Double
    let momentId: String
    let authorId: String?
    let globalStreamTimestamp: Double?
    let globalStreamMomentId: String?
    let globalStreamAuthorId: String?

    init(
        timestamp: Double,
        momentId: String,
        authorId: String? = nil,
        globalStreamTimestamp: Double? = nil,
        globalStreamMomentId: String? = nil,
        globalStreamAuthorId: String? = nil
    ) {
        self.timestamp = timestamp
        self.momentId = momentId
        self.authorId = authorId
        self.globalStreamTimestamp = globalStreamTimestamp
        self.globalStreamMomentId = globalStreamMomentId
        self.globalStreamAuthorId = globalStreamAuthorId
    }
}

/// Lightweight moment from backend (timestamps as epoch millis)
struct BackendMoment: Codable {
    let id: String
    let authorId: String
    let username: String
    let content: String
    let imageUrl: String?
    let videoUrl: String?
    let timestamp: Double? // epoch millis
    let reactions: [String: [String]]?
    let commentCount: Int?
    let profileImagePath: String?
    let taggedUsers: [String]?
    let mentionedUsers: [String]?
    let location: String?
    let locationCoordinate: Moment.LocationCoordinate?
    let audience: String?
    let mediaItems: [MediaItem]?
    let aspectRatio: String?
    let customListId: String?
    let thumbnailUrl: String?
    let videoDuration: Double?
    let videoFileSize: Int64?
    let videoResolution: String?
    let disableComments: Bool?
    let hideLikeCounts: Bool?
    let allowSharing: Bool?
    let scheduledDate: Double? // epoch millis
    let hasHiddenLayers: Bool?
    let hiddenLayerCount: Int?
    
    /// Convert to the app's Moment model
    func toMoment() -> Moment {
        Moment(
            id: id,
            authorId: authorId,
            username: username,
            content: content,
            imagePath: imageUrl,
            videoUrl: videoUrl,
            timestamp: timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
            reactions: reactions ?? [:],
            commentCount: commentCount ?? 0,
            profileImagePath: profileImagePath,
            taggedUsers: taggedUsers,
            mentionedUsers: mentionedUsers,
            location: location,
            locationCoordinate: locationCoordinate,
            audience: audience,
            mediaItems: mediaItems,
            aspectRatio: aspectRatio,
            customListId: customListId,
            thumbnailUrl: thumbnailUrl,
            videoDuration: videoDuration,
            videoFileSize: videoFileSize,
            videoResolution: videoResolution,
            disableComments: disableComments ?? false,
            hideLikeCounts: hideLikeCounts ?? false,
            allowSharing: allowSharing ?? true,
            scheduledDate: scheduledDate.map { Date(timeIntervalSince1970: $0 / 1000) },
            hasHiddenLayers: hasHiddenLayers ?? false,
            hiddenLayerCount: hiddenLayerCount ?? 0
        )
    }
}

// MARK: - Backend Feed Service

@MainActor
class BackendFeedService {
    static let shared = BackendFeedService()
    
    // Circuit breaker state
    private var failCount = 0
    private var lastFailTime: Date = .distantPast
    private let maxFails = 3
    private let cooldownInterval: TimeInterval = 300 // 5 minutes
    
    /// Whether the circuit breaker is open (should use legacy)
    var isCircuitOpen: Bool {
        guard failCount >= maxFails else { return false }
        // Check if cooldown has passed
        if Date().timeIntervalSince(lastFailTime) > cooldownInterval {
            // Reset — give backend another chance
            failCount = 0
            return false
        }
        return true
    }
    
    private func recordSuccess() {
        failCount = 0
    }
    
    private func recordFailure() {
        failCount += 1
        lastFailTime = Date()
    }
    
    /// Fetch feed page from backend Cloud Function.
    /// Returns nil if circuit breaker is open (caller should use legacy).
    func fetchFeedPage(
        feedType: String, // "following" or "forYou"
        cursor: FeedCursor? = nil,
        limit: Int = 20
    ) async -> (moments: [Moment], nextCursor: FeedCursor?, source: String)? {
        
        guard !isCircuitOpen else {
            LogConfig.log("⚡ BackendFeed: Circuit breaker OPEN — usando legacy", category: "BackendFeed")
            return nil
        }
        
        guard let user = Auth.auth().currentUser else {
            LogConfig.log("⚡ BackendFeed: No authenticated user", category: "BackendFeed")
            return nil
        }
        
        do {
            // Get fresh ID token
            let idToken = try await user.getIDToken()
            
            // Build request body
            var body: [String: Any] = [
                "feedType": feedType,
                "limit": limit
            ]
            if let cursor = cursor {
                var cursorPayload: [String: Any] = [
                    "timestamp": cursor.timestamp,
                    "momentId": cursor.momentId
                ]
                if let authorId = cursor.authorId, !authorId.isEmpty {
                    cursorPayload["authorId"] = authorId
                }
                if let globalStreamTimestamp = cursor.globalStreamTimestamp,
                   let globalStreamMomentId = cursor.globalStreamMomentId,
                   let globalStreamAuthorId = cursor.globalStreamAuthorId,
                   !globalStreamMomentId.isEmpty,
                   !globalStreamAuthorId.isEmpty {
                    cursorPayload["globalStreamTimestamp"] = globalStreamTimestamp
                    cursorPayload["globalStreamMomentId"] = globalStreamMomentId
                    cursorPayload["globalStreamAuthorId"] = globalStreamAuthorId
                }
                body["cursor"] = cursorPayload
            }
            
            // Build URL — uses the function's region
            // Format: https://{region}-{projectId}.cloudfunctions.net/getFeedPage
            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/getFeedPage"
            
            guard let url = URL(string: urlString) else {
                LogConfig.log("❌ BackendFeed: Invalid URL", category: "BackendFeed")
                recordFailure()
                return nil
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                LogConfig.log("❌ BackendFeed: HTTP \(httpResponse.statusCode)", category: "BackendFeed")
                recordFailure()
                return nil
            }
            
            let decoded = try JSONDecoder().decode(BackendFeedResponse.self, from: data)
            let moments = decoded.moments.map { $0.toMoment() }
            
            recordSuccess()
            LogConfig.log("✅ BackendFeed: \(moments.count) moments (source: \(decoded.source), candidates: \(decoded.totalCandidates))", category: "BackendFeed")
            
            return (moments: moments, nextCursor: decoded.nextCursor, source: decoded.source)
            
        } catch {
            LogConfig.log("❌ BackendFeed error: \(error.localizedDescription)", category: "BackendFeed")
            recordFailure()
            return nil
        }
    }

    /// Fetch tagged moments from backend with full audience/privacy filtering.
    func fetchTaggedMoments(
        targetUserId: String? = nil,
        cursor: BackendTagsCursor? = nil,
        limit: Int = 50
    ) async -> (moments: [Moment], nextCursor: BackendTagsCursor?, source: String)? {
        guard !isCircuitOpen else {
            LogConfig.log("⚡ BackendFeed tagged: Circuit breaker OPEN", category: "BackendFeed")
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            LogConfig.log("⚡ BackendFeed tagged: No authenticated user", category: "BackendFeed")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()

            var body: [String: Any] = [
                "limit": limit
            ]
            if let cursor {
                body["cursor"] = ["timestamp": cursor.timestamp]
            }
            if let targetUserId, !targetUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["targetUserId"] = targetUserId
            }

            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/getTaggedMomentsPage"

            guard let url = URL(string: urlString) else {
                LogConfig.log("❌ BackendFeed tagged: Invalid URL", category: "BackendFeed")
                recordFailure()
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                LogConfig.log("❌ BackendFeed tagged: HTTP \(httpResponse.statusCode)", category: "BackendFeed")
                recordFailure()
                return nil
            }

            let decoded = try JSONDecoder().decode(BackendTagsResponse.self, from: data)
            let moments = decoded.items.compactMap { item -> Moment? in
                guard item.canView ?? false else { return nil }
                return item.moment.toMoment()
            }

            recordSuccess()
            LogConfig.log("✅ BackendFeed tagged: \(moments.count) moments (source: \(decoded.source), candidates: \(decoded.totalCandidates))", category: "BackendFeed")
            return (moments: moments, nextCursor: decoded.nextCursor, source: decoded.source)
        } catch {
            LogConfig.log("❌ BackendFeed tagged error: \(error.localizedDescription)", category: "BackendFeed")
            recordFailure()
            return nil
        }
    }

    func fetchProfileMoments(
        targetUserId: String? = nil,
        cursor: FeedCursor? = nil,
        limit: Int = 50
    ) async -> (moments: [Moment], nextCursor: FeedCursor?, source: String)? {
        guard !isCircuitOpen else {
            LogConfig.log("⚡ BackendFeed profile: Circuit breaker OPEN", category: "BackendFeed")
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            LogConfig.log("⚡ BackendFeed profile: No authenticated user", category: "BackendFeed")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()

            var body: [String: Any] = ["limit": limit]
            if let cursor {
                body["cursor"] = [
                    "timestamp": cursor.timestamp,
                    "momentId": cursor.momentId,
                    "authorId": cursor.authorId as Any
                ]
            }
            if let targetUserId, !targetUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["targetUserId"] = targetUserId
            }

            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/getProfileMomentsPage"

            guard let url = URL(string: urlString) else {
                recordFailure()
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                recordFailure()
                return nil
            }

            let decoded = try JSONDecoder().decode(BackendFeedResponse.self, from: data)
            let moments = decoded.moments.map { $0.toMoment() }
            recordSuccess()
            LogConfig.log("✅ BackendFeed profile: \(moments.count) moments (source: \(decoded.source), candidates: \(decoded.totalCandidates))", category: "BackendFeed")
            return (moments: moments, nextCursor: decoded.nextCursor, source: decoded.source)
        } catch {
            LogConfig.log("❌ BackendFeed profile error: \(error.localizedDescription)", category: "BackendFeed")
            recordFailure()
            return nil
        }
    }

    func fetchVisibleHighlights(
        targetUserId: String? = nil,
        limit: Int = 30
    ) async -> (highlights: [HighlightedStory], source: String)? {
        guard !isCircuitOpen else {
            LogConfig.log("⚡ BackendFeed highlights: Circuit breaker OPEN", category: "BackendFeed")
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            LogConfig.log("⚡ BackendFeed highlights: No authenticated user", category: "BackendFeed")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()
            var body: [String: Any] = ["limit": limit]
            if let targetUserId, !targetUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["targetUserId"] = targetUserId
            }

            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/getVisibleHighlightsPage"

            guard let url = URL(string: urlString) else {
                recordFailure()
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                recordFailure()
                return nil
            }

            let decoded = try JSONDecoder().decode(BackendHighlightsResponse.self, from: data)
            recordSuccess()
            return (highlights: decoded.highlights.map { $0.toHighlightedStory() }, source: decoded.source)
        } catch {
            LogConfig.log("❌ BackendFeed highlights error: \(error.localizedDescription)", category: "BackendFeed")
            recordFailure()
            return nil
        }
    }
}

// MARK: - Backend Story Tray Service

@MainActor
final class StoryTrayService {
    static let shared = StoryTrayService()

    private struct CacheEntry {
        let response: BackendStoryTrayResponse
        let expiresAt: Date
    }

    private var failCount = 0
    private var lastFailTime: Date = .distantPast
    private let maxFails = 3
    private let cooldownInterval: TimeInterval = 180
    private let cacheTTL: TimeInterval = 20
    private var cacheByViewerId: [String: CacheEntry] = [:]

    var isCircuitOpen: Bool {
        guard failCount >= maxFails else { return false }
        if Date().timeIntervalSince(lastFailTime) > cooldownInterval {
            failCount = 0
            return false
        }
        return true
    }

    func cachedTray(for viewerId: String) -> BackendStoryTrayResponse? {
        guard let entry = cacheByViewerId[viewerId] else { return nil }
        if entry.expiresAt < Date() {
            cacheByViewerId.removeValue(forKey: viewerId)
            return nil
        }
        return entry.response
    }

    func invalidate(viewerId: String? = nil) {
        if let viewerId {
            cacheByViewerId.removeValue(forKey: viewerId)
        } else {
            cacheByViewerId.removeAll()
        }
    }

    func fetchStoryTray(limit: Int = 80) async -> BackendStoryTrayResponse? {
        await fetchStoryRingPage(limit: limit, cursor: nil)
    }

    func fetchStoryRingPage(limit: Int = 16, cursor: StoryRingCursor?) async -> BackendStoryTrayResponse? {
        var body: [String: Any] = ["limit": limit]
        if let cursor {
            body["cursor"] = ["offset": cursor.offset]
        }
        return await postStoryEndpoint(
            functionName: "getStoryRingPage",
            body: body,
            cacheOnSuccess: cursor == nil
        )
    }

    func fetchAuthorStoryBundle(authorId: String) async -> BackendAuthorStoryBundleResponse? {
        guard !authorId.isEmpty else { return nil }
        return await postStoryEndpoint(
            functionName: "getAuthorStoryBundle",
            body: ["authorId": authorId],
            cacheOnSuccess: false
        )
    }

    private func postStoryEndpoint<T: Decodable>(
        functionName: String,
        body: [String: Any],
        cacheOnSuccess: Bool
    ) async -> T? {
        guard !isCircuitOpen else {
            LogConfig.log("⚡ StoryTray: Circuit breaker OPEN — usando legacy", category: "BackendFeed")
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            LogConfig.log("⚡ StoryTray: No authenticated user", category: "BackendFeed")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()
            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/\(functionName)"

            guard let url = URL(string: urlString) else {
                recordFailure()
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 12

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                LogConfig.log("❌ StoryTray \(functionName): HTTP \(httpResponse.statusCode)", category: "BackendFeed")
                recordFailure()
                return nil
            }

            let decoded = try JSONDecoder().decode(T.self, from: data)
            if let tray = decoded as? BackendStoryTrayResponse {
                LogConfig.log(
                    "✅ StoryTray \(functionName): \(tray.items.count) authors (source: \(tray.source), candidates: \(tray.totalCandidates))",
                    category: "BackendFeed"
                )
            } else if let bundle = decoded as? BackendAuthorStoryBundleResponse {
                LogConfig.log(
                    "✅ StoryBundle \(functionName): author=\(bundle.authorId), docs=\(bundle.stories.count), source=\(bundle.source)",
                    category: "BackendFeed"
                )
            }
            if cacheOnSuccess, let tray = decoded as? BackendStoryTrayResponse {
                cacheByViewerId[user.uid] = CacheEntry(
                    response: tray,
                    expiresAt: Date().addingTimeInterval(cacheTTL)
                )
            }
            recordSuccess()
            return decoded
        } catch is CancellationError {
            LogConfig.log("ℹ️ StoryTray \(functionName): cancelled", category: "BackendFeed")
            return nil
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                LogConfig.log("ℹ️ StoryTray \(functionName): cancelled", category: "BackendFeed")
                return nil
            }
            LogConfig.log("❌ StoryTray \(functionName): \(error.localizedDescription)", category: "BackendFeed")
            recordFailure()
            return nil
        }
    }

    private func recordSuccess() {
        failCount = 0
    }

    private func recordFailure() {
        failCount += 1
        lastFailTime = Date()
    }
}
