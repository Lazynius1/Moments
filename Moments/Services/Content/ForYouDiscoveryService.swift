import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Discovery helpers for the Para Ti feed (legacy fallback path).
enum ForYouDiscoveryService {
    static let secondDegreeSampleSize = 15
    static let secondDegreeCap = 30
    static let interestUserCap = 40
    static let followerPublicCap = 20
    static let globalEveryoneFetchLimit = 120

    struct DiscoveryResult {
        let authorIds: [String]
        let authorTierById: [String: String]
    }

    static func loadDiscoveryAuthors(
        viewerId: String,
        interests: [String],
        followingIds: Set<String>,
        followerIds: Set<String>,
        blockedUserIds: Set<String>,
        completion: @escaping (DiscoveryResult) -> Void
    ) {
        let db = Firestore.firestore()
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "foryou.discovery.sync")

        var tierA = Set<String>()
        var tierB = Set<String>()
        var tierC = Set<String>()
        var authorTierById: [String: String] = [:]

        func isExcluded(_ authorId: String) -> Bool {
            authorId == viewerId
                || followingIds.contains(authorId)
                || blockedUserIds.contains(authorId)
        }

        if !interests.isEmpty {
            group.enter()
            FirestoreService.shared.fetchUsersWithSharedInterests(
                interests: interests,
                excludingUserId: viewerId
            ) { result in
                defer { group.leave() }
                guard case .success(let users) = result else { return }
                syncQueue.async {
                    for user in users.prefix(interestUserCap) where !isExcluded(user.id) {
                        tierA.insert(user.id)
                    }
                }
            }
        }

        group.enter()
        loadSecondDegreeUserIds(
            db: db,
            viewerId: viewerId,
            followingIds: followingIds,
            blockedUserIds: blockedUserIds
        ) { ids in
            defer { group.leave() }
            syncQueue.async {
                tierB = ids
            }
        }

        group.enter()
        loadFollowerPublicUserIds(
            db: db,
            followerIds: followerIds,
            followingIds: followingIds,
            blockedUserIds: blockedUserIds,
            viewerId: viewerId
        ) { ids in
            defer { group.leave() }
            syncQueue.async {
                tierC = ids
            }
        }

        group.notify(queue: .main) {
            let merged = syncQueue.sync { () -> Set<String> in
                tierA.forEach { authorTierById[$0] = "A" }
                tierB.forEach {
                    if authorTierById[$0] == nil { authorTierById[$0] = "B" }
                }
                tierC.forEach {
                    if authorTierById[$0] == nil { authorTierById[$0] = "C" }
                }
                return tierA.union(tierB).union(tierC)
            }
            completion(DiscoveryResult(authorIds: Array(merged), authorTierById: authorTierById))
        }
    }

    static func fetchGlobalEveryoneMoments(
        excludingAuthorIds: Set<String>,
        excludingMomentIds: Set<String> = [],
        globalStreamCursor: GlobalStreamCursor? = nil,
        limit: Int = globalEveryoneFetchLimit,
        completion: @escaping (_ moments: [Moment], _ nextStreamCursor: GlobalStreamCursor?) -> Void
    ) {
        let runQuery: (DocumentSnapshot?) -> Void = { cursorSnapshot in
            var query: Query = Firestore.firestore()
                .collectionGroup("moments")
                .whereField("audience", isEqualTo: "everyone")
                .order(by: "timestamp", descending: true)

            if let cursorSnapshot {
                query = query.start(afterDocument: cursorSnapshot)
            }

            query
                .limit(to: limit)
                .getDocuments { snapshot, _ in
                    let documents = snapshot?.documents ?? []
                    let moments = documents.compactMap { doc -> Moment? in
                        guard var moment = try? doc.data(as: Moment.self) else { return nil }
                        moment.id = doc.documentID
                        guard !excludingAuthorIds.contains(moment.authorId) else { return nil }
                        guard let momentId = moment.id, !excludingMomentIds.contains(momentId) else { return nil }
                        return moment
                    }

                    let nextStreamCursor: GlobalStreamCursor?
                    if let lastDoc = documents.last, documents.count >= limit {
                        let data = lastDoc.data()
                        if let authorId = data["authorId"] as? String, !authorId.isEmpty {
                            nextStreamCursor = GlobalStreamCursor(
                                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date.distantPast,
                                momentId: lastDoc.documentID,
                                authorId: authorId
                            )
                        } else {
                            nextStreamCursor = nil
                        }
                    } else {
                        nextStreamCursor = nil
                    }

                    completion(moments, nextStreamCursor)
                }
        }

        guard let globalStreamCursor else {
            runQuery(nil)
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(globalStreamCursor.authorId)
            .collection("moments")
            .document(globalStreamCursor.momentId)
            .getDocument { snapshot, _ in
                runQuery(snapshot?.exists == true ? snapshot : nil)
            }
    }

    struct GlobalStreamCursor {
        let timestamp: Date
        let momentId: String
        let authorId: String
    }

    private static func loadSecondDegreeUserIds(
        db: Firestore,
        viewerId: String,
        followingIds: Set<String>,
        blockedUserIds: Set<String>,
        completion: @escaping (Set<String>) -> Void
    ) {
        let sample = Array(followingIds.prefix(secondDegreeSampleSize))
        guard !sample.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var result = Set<String>()
        let syncQueue = DispatchQueue(label: "foryou.seconddegree.sync")

        for followingId in sample {
            group.enter()
            db.collection("users").document(followingId).collection("following")
                .limit(to: 20)
                .getDocuments { snapshot, _ in
                    defer { group.leave() }
                    let ids = snapshot?.documents.map(\.documentID) ?? []
                    syncQueue.async {
                        for id in ids where result.count < secondDegreeCap {
                            if id != viewerId,
                               !followingIds.contains(id),
                               !blockedUserIds.contains(id) {
                                result.insert(id)
                            }
                        }
                    }
                }
        }

        group.notify(queue: .main) {
            completion(syncQueue.sync { result })
        }
    }

    private static func loadFollowerPublicUserIds(
        db: Firestore,
        followerIds: Set<String>,
        followingIds: Set<String>,
        blockedUserIds: Set<String>,
        viewerId: String,
        completion: @escaping (Set<String>) -> Void
    ) {
        let candidates = followerIds.filter {
            !$0.isEmpty && $0 != viewerId && !followingIds.contains($0) && !blockedUserIds.contains($0)
        }
        guard !candidates.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var publicIds = Set<String>()
        let syncQueue = DispatchQueue(label: "foryou.followers.sync")

        for followerId in candidates.prefix(followerPublicCap * 2) {
            group.enter()
            db.collection("users").document(followerId).getDocument { snapshot, _ in
                defer { group.leave() }
                guard let data = snapshot?.data(), data["isPrivate"] as? Bool != true else { return }
                syncQueue.async {
                    if publicIds.count < followerPublicCap {
                        publicIds.insert(followerId)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            completion(syncQueue.sync { publicIds })
        }
    }
}
