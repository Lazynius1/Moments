import Foundation
import FirebaseFirestore
import FirebaseAI

enum NovaJSON {
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    static func iso(_ date: Date) -> JSONValue {
        .string(isoFormatter.string(from: date))
    }

    static func string(_ value: String?) -> JSONValue {
        .string(value ?? "")
    }

    static func int(_ value: Int) -> JSONValue {
        .number(Double(value))
    }

    static func pctChange(current: Int, previous: Int) -> Int {
        guard previous > 0 else { return current > 0 ? 100 : 0 }
        return Int(round(Double(current - previous) / Double(previous) * 100))
    }
}

/// Firestore-backed activity queries returning neutral JSON for the model.
actor NovaActivityTools {
    private let db = Firestore.firestore()
    private let firestoreService = FirestoreService()

    func activitySummary(userId: String) async throws -> JSONObject {
        async let visits = profileVisits(userId: userId, limit: 5)
        async let chain = latestStoryChain(userId: userId)

        let visitData = try await visits
        let chainData = try await chain

        return [
            "recent_visits": visitData["visits"] ?? .array([]),
            "total_visits": visitData["total_count"] ?? .number(0),
            "latest_story_chain": chainData ?? .null
        ]
    }

    func weeklySummary(userId: String) async throws -> JSONObject {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek),
              let endOfLastWeek = calendar.date(byAdding: .second, value: -1, to: startOfThisWeek) else {
            return ["error": .string("Could not compute week boundaries.")]
        }

        async let thisWeekMoments = fetchMoments(userId: userId, from: startOfThisWeek)
        async let lastWeekMoments = fetchMoments(userId: userId, from: startOfLastWeek, to: endOfLastWeek)
        async let thisWeekVisits = countVisits(userId: userId, from: startOfThisWeek)
        async let lastWeekVisits = countVisits(userId: userId, from: startOfLastWeek, to: endOfLastWeek)
        async let thisWeekStoryViews = countStoryViews(userId: userId, from: startOfThisWeek)
        async let lastWeekStoryViews = countStoryViews(userId: userId, from: startOfLastWeek, to: endOfLastWeek)

        let (twM, lwM, twV, lwV, twS, lwS) = try await (
            thisWeekMoments, lastWeekMoments, thisWeekVisits, lastWeekVisits, thisWeekStoryViews, lastWeekStoryViews
        )

        let twEngagement = engagement(for: twM)
        let lwEngagement = engagement(for: lwM)

        return [
            "this_week": .object([
                "moments": NovaJSON.int(twM.count),
                "reactions": NovaJSON.int(twEngagement.reactions),
                "comments": NovaJSON.int(twEngagement.comments),
                "profile_visits": NovaJSON.int(twV),
                "story_views": NovaJSON.int(twS)
            ]),
            "last_week": .object([
                "moments": NovaJSON.int(lwM.count),
                "reactions": NovaJSON.int(lwEngagement.reactions),
                "comments": NovaJSON.int(lwEngagement.comments),
                "profile_visits": NovaJSON.int(lwV),
                "story_views": NovaJSON.int(lwS)
            ]),
            "change_pct": .object([
                "moments": NovaJSON.int(NovaJSON.pctChange(current: twM.count, previous: lwM.count)),
                "profile_visits": NovaJSON.int(NovaJSON.pctChange(current: twV, previous: lwV)),
                "story_views": NovaJSON.int(NovaJSON.pctChange(current: twS, previous: lwS))
            ])
        ]
    }

    func profileVisits(userId: String, limit: Int = 5) async throws -> JSONObject {
        let capped = min(max(limit, 1), 10)

        let totalSnapshot = try await db.collection("users").document(userId).collection("visits").getDocuments()
        let totalCount = totalSnapshot.documents.count

        let snapshot = try await db.collection("users").document(userId).collection("visits")
            .order(by: "timestamp", descending: true)
            .limit(to: capped)
            .getDocuments()

        var visits: [ProfileVisitRecord] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let visitorId = data["visitorId"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp else { return nil }
            return ProfileVisitRecord(visitorId: visitorId, timestamp: timestamp.dateValue())
        }

        let visitorIds = Array(Set(visits.map(\.visitorId)))
        if !visitorIds.isEmpty {
            let users = try await fetchUsers(ids: visitorIds)
            let dict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            visits = visits.map { visit in
                var copy = visit
                copy.username = dict[visit.visitorId]?.username
                return copy
            }
        }

        return [
            "total_count": NovaJSON.int(totalCount),
            "visits": .array(visits.map { visit in
                .object([
                    "username": NovaJSON.string(visit.username ?? "unknown"),
                    "visitor_id": .string(visit.visitorId),
                    "timestamp": NovaJSON.iso(visit.timestamp)
                ])
            })
        ]
    }

    func storyChainInfo(userId: String, includeViewers: Bool) async throws -> JSONObject {
        guard let chain = try await latestStoryChainRecord(userId: userId) else {
            return ["latest_chain": .null]
        }

        var result: JSONObject = [
            "latest_chain": .object([
                "chain_id": .string(chain.chainId),
                "title": .string(chain.chainTitle),
                "story_count": NovaJSON.int(chain.storyCount),
                "created_at": NovaJSON.iso(chain.createdAt)
            ])
        ]

        if includeViewers {
            let viewers = try await storyChainViewers(userId: userId, chainId: chain.chainId)
            result["viewers"] = viewers
        }

        return result
    }

    // MARK: - Private

    private struct ProfileVisitRecord {
        let visitorId: String
        let timestamp: Date
        var username: String?
    }

    private struct StoryChainRecord {
        let chainId: String
        let chainTitle: String
        let storyCount: Int
        let createdAt: Date
    }

    private struct EngagementTotals {
        let reactions: Int
        let comments: Int
    }

    private func fetchMoments(userId: String, from: Date, to: Date? = nil) async throws -> [Moment] {
        try await withCheckedThrowingContinuation { continuation in
            firestoreService.fetchMoments(for: userId) { result in
                switch result {
                case .success(let moments):
                    let filtered = moments.filter { moment in
                        guard moment.timestamp >= from else { return false }
                        if let to { return moment.timestamp <= to }
                        return true
                    }
                    continuation.resume(returning: filtered)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func countVisits(userId: String, from: Date, to: Date? = nil) async throws -> Int {
        var query: Query = db.collection("users").document(userId).collection("visits")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: from))
        if let to {
            query = query.whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: to))
        }
        let snapshot = try await query.getDocuments()
        return snapshot.documents.count
    }

    private func countStoryViews(userId: String, from: Date, to: Date? = nil) async throws -> Int {
        var query: Query = db.collection("users").document(userId).collection("stories")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: from))
        if let to {
            query = query.whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: to))
        }
        let snapshot = try await query.getDocuments()
        var total = 0
        for doc in snapshot.documents {
            let viewers = try await db.collection("users").document(userId).collection("stories")
                .document(doc.documentID).collection("viewers").getDocuments()
            total += viewers.documents.count
        }
        return total
    }

    private func engagement(for moments: [Moment]) -> EngagementTotals {
        var reactions = 0
        var comments = 0
        for moment in moments {
            for (_, userIds) in moment.reactions {
                reactions += userIds.count
            }
            comments += moment.commentCount
        }
        return EngagementTotals(reactions: reactions, comments: comments)
    }

    private func latestStoryChain(userId: String) async throws -> JSONValue? {
        guard let chain = try await latestStoryChainRecord(userId: userId) else { return nil }
        return .object([
            "chain_id": .string(chain.chainId),
            "title": .string(chain.chainTitle),
            "story_count": NovaJSON.int(chain.storyCount),
            "created_at": NovaJSON.iso(chain.createdAt)
        ])
    }

    private func latestStoryChainRecord(userId: String) async throws -> StoryChainRecord? {
        let snapshot = try await db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isNotEqualTo: NSNull())
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first,
              let chainId = document.data()["chainId"] as? String,
              let chainTitle = document.data()["chainTitle"] as? String else {
            return nil
        }

        let chainStories = try await db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .getDocuments()

        return StoryChainRecord(
            chainId: chainId,
            chainTitle: chainTitle,
            storyCount: chainStories.documents.count,
            createdAt: (document.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    private func storyChainViewers(userId: String, chainId: String) async throws -> JSONValue {
        let stories = try await db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .getDocuments()

        var viewersByUser: [String: (username: String?, timestamp: Date)] = [:]

        for document in stories.documents {
            let viewersSnapshot = try await db.collection("users").document(userId).collection("stories")
                .document(document.documentID).collection("viewers")
                .getDocuments()

            for viewerDoc in viewersSnapshot.documents {
                let data = viewerDoc.data()
                guard let viewerId = data["userId"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp else { continue }
                let date = timestamp.dateValue()
                if let existing = viewersByUser[viewerId], existing.timestamp > date { continue }
                viewersByUser[viewerId] = (data["username"] as? String, date)
            }
        }

        let sorted = viewersByUser.sorted { $0.value.timestamp > $1.value.timestamp }.prefix(5)
        return .array(sorted.map { entry in
            .object([
                "username": NovaJSON.string(entry.value.username ?? "unknown"),
                "viewer_id": .string(entry.key),
                "timestamp": NovaJSON.iso(entry.value.timestamp)
            ])
        })
    }

    private func fetchUsers(ids: [String]) async throws -> [AppUser] {
        try await withCheckedThrowingContinuation { continuation in
            firestoreService.fetchUsers(userIds: ids) { result in
                continuation.resume(with: result)
            }
        }
    }
}

enum NovaEvents {
    static func triggerEchoSpark(echoId: String, userId: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("NovaEchoSparkTriggered"),
            object: nil,
            userInfo: ["echoId": echoId, "userId": userId]
        )
    }
}
