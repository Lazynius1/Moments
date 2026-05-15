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

struct FeedCursor: Codable {
    let timestamp: Double
    let momentId: String
    let authorId: String?
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
    let trendingScore: Double?
    let engagementRate: Double?
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
            trendingScore: trendingScore,
            engagementRate: engagementRate,
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
}
