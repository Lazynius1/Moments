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

    func loadSavedMoments(completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        isLoading = true
        error = nil
        firestoreService.fetchMutedUserIds(userId: userId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                self?.mutedUserIds = mutedIds
            }
        }

        // Cargar los IDs de momentos guardados primero
        firestoreService.db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.error = error
                        self.isLoading = false
                        completion(error)
                    }
                    return
                }

                let savedDocuments = snapshot?.documents ?? []
                let momentIds = savedDocuments.compactMap { $0.documentID }

                DispatchQueue.main.async {
                    self.savedMomentIds = momentIds
                }

                // Si no hay momentos guardados
                guard !momentIds.isEmpty else {
                    DispatchQueue.main.async {
                        self.moments = []
                        self.visibilityByMomentId = [:]
                        self.isLoading = false
                        completion(nil)
                    }
                    return
                }

                // ✅ BUSCAR MOMENTOS SIN FILTROS DE PRIVACIDAD
                self.fetchSavedMomentsDirectly(momentIds: momentIds, completion: completion)
            }
    }

    // ✅ NUEVA FUNCIÓN: Buscar momentos guardados directamente sin filtros de privacidad
    private func fetchSavedMomentsDirectly(momentIds: [String], completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        var foundMoments: [Moment] = []
        var notFoundMomentIds: [String] = []
        let syncQueue = DispatchQueue(label: "saved.moments.direct.sync")


        // Obtener usuarios activos para buscar
        fetchActiveUsers { [weak self] userIds in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                return
            }

            for userId in userIds {
                group.enter()

                // Buscar momentos de este usuario
                self.fetchMomentsFromUser(userId: userId) { userMoments in
                    defer { group.leave() }

                    // Filtrar solo los momentos que están en nuestros guardados
                    let matchingMoments = userMoments.filter { moment in
                        guard let momentId = moment.id else { return false }
                        return momentIds.contains(momentId)
                    }

                    if !matchingMoments.isEmpty {
                        syncQueue.async {
                            foundMoments.append(contentsOf: matchingMoments)
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                // Identificar momentos no encontrados para limpieza
                let foundMomentIds = Set(foundMoments.compactMap { $0.id })
                notFoundMomentIds = momentIds.filter { !foundMomentIds.contains($0) }

                // Limpiar momentos que ya no existen
                if !notFoundMomentIds.isEmpty {
                    self.cleanupMissingMoments(missingIds: notFoundMomentIds)
                }

                // Ordenar por timestamp
                let sortedMoments = foundMoments.sorted { $0.timestamp > $1.timestamp }

                self.moments = sortedMoments
                self.validateVisibilityForLoadedMoments(sortedMoments)
                self.isLoading = false
                completion(nil)
            }
        }
    }

    // ✅ FUNCIÓN AUXILIAR: Obtener momentos de un usuario específico
    private func fetchMomentsFromUser(userId: String, completion: @escaping ([Moment]) -> Void) {
        firestoreService.fetchMoments(for: userId) { result in
            switch result {
            case .success(let moments):
                completion(moments)
            case .failure(let error):
                completion([])
            }
        }
    }

    // ✅ FUNCIÓN AUXILIAR: Obtener usuarios activos
    private func fetchActiveUsers(completion: @escaping ([String]) -> Void) {
        // Obtener usuarios que han estado activos en los últimos 6 meses
        let recentDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()

        firestoreService.db.collection("users")
            .whereField("lastActiveAt", isGreaterThan: Timestamp(date: recentDate))
            .limit(to: 100) // Aumentar límite para mejor cobertura
            .getDocuments { snapshot, error in
                if let error = error {
                    // Fallback: buscar en todos los usuarios (menos eficiente pero funcional)
                    self.fetchAllUsers(completion: completion)
                    return
                }

                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []


                if userIds.isEmpty {
                    // Fallback si no hay usuarios con lastActiveAt
                    self.fetchAllUsers(completion: completion)
                } else {
                    completion(userIds)
                }
            }
    }

    // ✅ FUNCIÓN FALLBACK: Obtener todos los usuarios
    private func fetchAllUsers(completion: @escaping ([String]) -> Void) {
        firestoreService.db.collection("users")
            .limit(to: 200)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion([])
                    return
                }

                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []

                completion(userIds)
            }
    }

    // ✅ FUNCIÓN DE LIMPIEZA: Remover momentos que ya no existen
    private func cleanupMissingMoments(missingIds: [String]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let group = DispatchGroup()

        for momentId in missingIds {
            group.enter()

            firestoreService.db.collection("users").document(userId)
                .collection("savedMoments").document(momentId)
                .delete { error in
                    if let error = error {
                    } else {
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            // Actualizar IDs locales
            self.savedMomentIds.removeAll { missingIds.contains($0) }
        }
    }

    // MARK: - Public Methods
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
                if let error = error {
                    return
                }

                let docs = snapshot?.documents ?? []

                docs.forEach { doc in
                }
            }
    }

    func forceRefresh() {
        moments = []
        savedMomentIds = []
        visibilityByMomentId = [:]
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
enum SavedMediaFilter: CaseIterable {
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

enum SavedCollectionFilter: CaseIterable {
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

enum SavedSortMode: CaseIterable {
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
