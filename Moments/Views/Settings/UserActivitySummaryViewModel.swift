import SwiftUI
import FirebaseAuth
import FirebaseFirestore

final class ActivitySummaryViewModel: ObservableObject, @unchecked Sendable {
    @Published var summaries: [ActivityInteractionCategory: ActivityCategorySummary] = [:]
    private var dummyVMs: [ActivityInteractionDetailViewModel] = []
    private var isRefreshing = false

    func autoRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        // Keep these alive while they refresh their caches in the background.
        dummyVMs = [
            ActivityInteractionDetailViewModel(category: .reactions),
            ActivityInteractionDetailViewModel(category: .comments),
            ActivityInteractionDetailViewModel(category: .tags),
            ActivityInteractionDetailViewModel(category: .stickerReplies),
            ActivityInteractionDetailViewModel(category: .archived),
            ActivityInteractionDetailViewModel(category: .recentlyDeleted),
            ActivityInteractionDetailViewModel(category: .echoes),
            ActivityInteractionDetailViewModel(category: .followers),
            ActivityInteractionDetailViewModel(category: .visits),
            ActivityInteractionDetailViewModel(category: .moments),
            ActivityInteractionDetailViewModel(category: .reels)
        ]

        for vm in dummyVMs {
            vm.reload()
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.load()
            self.load()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.load()
            DispatchQueue.main.async {
                self.dummyVMs = []
                self.isRefreshing = false
            }
        }
    }

    func load() {
        guard let userId = FirebaseAuth.Auth.auth().currentUser?.uid, !userId.isEmpty else { return }
        Task {
            let reactions = ActivityCache.loadReactions(userId: userId)
            let comments = ActivityCache.loadComments(userId: userId)
            let tagged = ActivityCache.loadTagged(userId: userId)
            let stickerRepliesCount = ActivityCache.loadStickerReplyCount(userId: userId)
            let db = Firestore.firestore()

            async let echoes = EchoService.shared.fetchEchoHistoryOnce(userId: userId)
            async let archivedCount = await withCheckedContinuation { continuation in
                FirestoreService.shared.fetchArchivedMoments(userId: userId) { result in
                    switch result {
                    case .success(let moments):
                        continuation.resume(returning: moments.count)
                    case .failure:
                        continuation.resume(returning: 0)
                    }
                }
            }
            async let followersCount = try? await db.collection("users").document(userId).collection("followers").getDocuments().count
            async let visitsCount = try? await db.collection("users").document(userId).collection("visits").getDocuments().count
            async let storiesArchiveCount = try? await db.collection("users")
                .document(userId)
                .collection("stories")
                .whereField("expirationDate", isLessThan: Date())
                .getDocuments()
                .count

            async let allMomentsResult = await withCheckedContinuation { (continuation: CheckedContinuation<[Moment], Never>) in
                FirestoreService.shared.fetchMoments(for: userId) { result in
                    switch result {
                    case .success(let moments):
                        continuation.resume(returning: moments)
                    case .failure:
                        continuation.resume(returning: [])
                    }
                }
            }

            let allMoments = await allMomentsResult
            let momentsCount = allMoments.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && !isReel
            }.count

            let reelsCount = allMoments.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && isReel
            }.count

            let result: [ActivityInteractionCategory: ActivityCategorySummary] = [
                .reactions: ActivityCategorySummary(count: reactions.count, thumbnails: []),
                .comments: ActivityCategorySummary(count: comments.count, thumbnails: []),
                .tags: ActivityCategorySummary(count: tagged.count, thumbnails: []),
                .stickerReplies: ActivityCategorySummary(count: stickerRepliesCount, thumbnails: []),
                .recentlyDeleted: ActivityCategorySummary(count: ActivityCache.loadRecentlyDeletedCount(userId: userId), thumbnails: []),
                .archived: ActivityCategorySummary(count: await archivedCount, thumbnails: []),
                .storiesArchive: ActivityCategorySummary(count: (await storiesArchiveCount) ?? 0, thumbnails: []),
                .echoes: ActivityCategorySummary(count: await echoes.count, thumbnails: []),
                .followers: ActivityCategorySummary(count: (await followersCount) ?? 0, thumbnails: []),
                .visits: ActivityCategorySummary(count: (await visitsCount) ?? 0, thumbnails: []),
                .moments: ActivityCategorySummary(count: momentsCount, thumbnails: []),
                .reels: ActivityCategorySummary(count: reelsCount, thumbnails: [])
            ]

            await MainActor.run {
                self.summaries = result
            }
        }
    }
}
