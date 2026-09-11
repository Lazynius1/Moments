import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class SavedMomentsViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var savedMomentIds: [String] = []
    @Published var visibilityByMomentId: [String: Bool] = [:]
    @Published private(set) var mutedUserIds: Set<String> = []
    @Published var isLoading = false
    @Published var error: Error?

    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService.shared
    private var visibilityValidationToken = UUID()

    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var dataOwnerId: String?

    func loadSavedMoments(completion: @escaping (Error?) -> Void = { _ in }) {
        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }
        if dataOwnerId != userId {
            moments = []
            savedMomentIds = []
            visibilityByMomentId = [:]
            mutedUserIds = []
            dataOwnerId = userId
        }
        isLoading = true
        error = nil
        firestoreService.fetchMutedUserIds(userId: userId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                guard self?.loadGeneration == generation else { return }
                self?.mutedUserIds = mutedIds
            }
        }
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.firestoreService.db.collection("users").document(userId)
                    .collection("savedMoments").getDocuments()
                try Task.checkCancellation()
                guard self.loadGeneration == generation, Auth.auth().currentUser?.uid == userId else { return }
                let ids = snapshot.documents.map(\.documentID)
                let cachedAuthors = Dictionary(self.moments.compactMap { moment in
                    moment.id.map { ($0, moment.authorId) }
                }, uniquingKeysWith: { first, _ in first })
                let references = snapshot.documents.compactMap { document -> (String, String)? in
                    guard let author = (document.data()["authorId"] as? String) ?? cachedAuthors[document.documentID],
                          !author.isEmpty else { return nil }
                    return (document.documentID, author)
                }
                let resolvedIds = Set(references.map { $0.0 })
                let legacyIds = Set(ids).subtracting(resolvedIds)
                var found: [Moment] = []
                var firstError: Error?
                // Read exact paths for new saves, with bounded concurrency.
                for start in stride(from: 0, to: references.count, by: 6) {
                    try Task.checkCancellation()
                    let batch = Array(references[start..<min(start + 6, references.count)])
                    let results = await withTaskGroup(of: Result<Moment?, Error>.self) { group in
                        for (id, author) in batch {
                            group.addTask {
                                do {
                                    let doc = try await Firestore.firestore().collection("users").document(author)
                                        .collection("moments").document(id).getDocument()
                                    guard doc.exists else { return .success(nil) }
                                    let moment = try doc.data(as: Moment.self)
                                    return .success(moment.isArchived == true ? nil : moment)
                                } catch { return .failure(error) }
                            }
                        }
                        var results: [Result<Moment?, Error>] = []
                        for await result in group { results.append(result) }
                        return results
                    }
                    for result in results {
                        switch result {
                        case .success(let moment): if let moment { found.append(moment) }
                        case .failure(let error): firstError = firstError ?? error
                        }
                    }
                }
                // Compatibility for old bookmarks that have no author. Never infer deletion
                // from this incomplete search; the bookmark stays available for a later retry.
                if !legacyIds.isEmpty {
                    let db = self.firestoreService.db
                    let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
                    var authors: [String] = []
                    do {
                        authors = try await db.collection("users")
                            .whereField("lastActiveAt", isGreaterThan: Timestamp(date: cutoff)).limit(to: 100).getDocuments()
                            .documents.map(\.documentID)
                    } catch {
                        try Task.checkCancellation()
                    }
                    if authors.isEmpty {
                        authors = try await db.collection("users").limit(to: 200).getDocuments().documents.map(\.documentID)
                    }
                    for start in stride(from: 0, to: authors.count, by: 6) {
                        try Task.checkCancellation()
                        let batch = Array(authors[start..<min(start + 6, authors.count)])
                        let legacyMoments = await withTaskGroup(of: [Moment].self) { group in
                            for author in batch {
                                group.addTask {
                                    await withCheckedContinuation { continuation in
                                        FirestoreService.shared.fetchMoments(for: author) { result in
                                            continuation.resume(returning: (try? result.get()) ?? [])
                                        }
                                    }
                                }
                            }
                            var matches: [Moment] = []
                            for await moments in group {
                                matches += moments.filter { $0.id.map(legacyIds.contains) ?? false }
                            }
                            return matches
                        }
                        found += legacyMoments
                    }
                }
                try Task.checkCancellation()
                guard self.loadGeneration == generation, Auth.auth().currentUser?.uid == userId else { return }
                if found.isEmpty, let firstError { throw firstError }
                self.savedMomentIds = ids
                self.moments = found.sorted { $0.timestamp > $1.timestamp }
                self.validateVisibilityForLoadedMoments(self.moments)
                self.error = firstError
                self.isLoading = false
                completion(firstError)
            } catch is CancellationError {
                // A newer load owns the UI state.
            } catch {
                guard self.loadGeneration == generation, Auth.auth().currentUser?.uid == userId else { return }
                self.error = error
                self.isLoading = false
                completion(error)
            }
        }
    }

    func isMomentSaved(momentId: String) -> Bool {
        return savedMomentIds.contains(momentId)
    }

    func isMomentFromMutedUser(_ moment: Moment) -> Bool {
        mutedUserIds.contains(moment.authorId)
    }

    func removeMoment(momentId: String, completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }


        firestoreService.toggleSaveMoment(userId: userId, momentId: momentId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(error)
                } else {
                    self?.moments.removeAll { $0.id == momentId }
                    self?.savedMomentIds.removeAll { $0 == momentId }
                    self?.visibilityByMomentId.removeValue(forKey: momentId)
                    completion(nil)
                }
            }
        }
    }

    func addSavedMoment(_ moment: Moment) {
        guard let momentId = moment.id else { return }

        if !savedMomentIds.contains(momentId) {
            savedMomentIds.append(momentId)
            visibilityByMomentId[momentId] = true

            if !moments.contains(where: { $0.id == momentId }) {
                moments.append(moment)
                moments.sort { $0.timestamp > $1.timestamp }
            }
        }
    }

    func refreshVisibilityForMoment(_ moment: Moment, completion: ((Bool) -> Void)? = nil) {
        guard let momentId = moment.id,
              let viewerId = Auth.auth().currentUser?.uid else {
            completion?(false)
            return
        }

        privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { [weak self] canView in
            DispatchQueue.main.async {
                self?.visibilityByMomentId[momentId] = canView
                completion?(canView)
            }
        }
    }

    // MARK: - Debug Methods
    func debugSavedMoments() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        firestoreService.db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { snapshot, error in
                if error != nil {
                    return
                }

                let docs = snapshot?.documents ?? []

                docs.forEach { doc in
                }
            }
    }

    func forceRefresh() {
        loadSavedMoments()
    }

    private func validateVisibilityForLoadedMoments(_ moments: [Moment]) {
        guard let viewerId = Auth.auth().currentUser?.uid else {
            return
        }

        let token = UUID()
        visibilityValidationToken = token

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "saved.moments.visibility.sync")
        var result: [String: Bool] = [:]

        for moment in moments {
            guard let momentId = moment.id else { continue }
            group.enter()
            privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                queue.async {
                    result[momentId] = canView
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.visibilityValidationToken == token else { return }
            self.visibilityByMomentId = result
        }
    }
}

// MARK: - SavedMomentsView Redesign 2026
enum SavedMediaFilter: String, CaseIterable, Hashable {
    case all
    case photos
    case videos

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("savedMoments.filter.media.all", comment: "Saved moments media filter: all")
        case .photos:
            return NSLocalizedString("savedMoments.filter.media.photos", comment: "Saved moments media filter: photos")
        case .videos:
            return NSLocalizedString("savedMoments.filter.media.videos", comment: "Saved moments media filter: videos")
        }
    }
}

enum SavedCollectionFilter: String, CaseIterable, Hashable {
    case all
    case location
    case text
    case multiple

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("savedMoments.filter.collection.all", comment: "Saved moments collection filter: all")
        case .location:
            return NSLocalizedString("savedMoments.filter.collection.location", comment: "Saved moments collection filter: location")
        case .text:
            return NSLocalizedString("savedMoments.filter.collection.text", comment: "Saved moments collection filter: text")
        case .multiple:
            return NSLocalizedString("savedMoments.filter.collection.multiple", comment: "Saved moments collection filter: multiple media")
        }
    }
}

enum SavedSortMode: String, CaseIterable, Hashable {
    case newest
    case oldest
    case author

    var title: String {
        switch self {
        case .newest:
            return NSLocalizedString("savedMoments.sort.newest", comment: "Saved moments sort newest")
        case .oldest:
            return NSLocalizedString("savedMoments.sort.oldest", comment: "Saved moments sort oldest")
        case .author:
            return NSLocalizedString("savedMoments.sort.author", comment: "Saved moments sort by author")
        }
    }
}

struct SavedMomentsDetailRoute: Identifiable {
    let id = UUID()
    let moments: [Moment]
    let initialIndex: Int
}

struct SavedMomentCommentsRoute: Identifiable {
    let id = UUID()
    let moment: Moment
}
