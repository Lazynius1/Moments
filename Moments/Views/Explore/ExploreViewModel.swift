import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - ExploreViewModel ACTUALIZADO
@MainActor
class ExploreViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var filteredMoments: [Moment] = []
    @Published var searchedUsers: [AppUser] = []
    @Published var suggestedUsers: [AppUser] = []
    @Published var followedUserIds: Set<String> = []
    @Published var pendingRequests: Set<String> = []
    @Published var authorProfiles: [String: AppUser] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var userButtonStates: [String: FollowButtonState] = [:]

    // ✅ HISTORIAL DE BÚSQUEDA
    @Published var recentSearches: [CachedSearch] = []
    @Published var followerUserIds: Set<String> = []


    private let firestoreService = FirestoreService.shared
    private let privacyService = PrivacyService()
    var currentUserInterests: [String] = []
    private var currentUserId: String?
    private var blockedUsers: Set<String> = []
    private var followStateObserver: NSObjectProtocol?
    private var searchWorkItem: DispatchWorkItem?
    private var activeSearchQuery: String = ""
    @Published var isSearchingMoments = false
    @Published var isSearchingUsers = false
    @Published var searchFailed = false
    @Published var hasMoreSearchResults = false
    @Published var searchFilter = "mixed"
    @Published var isLoadingMoreExplore = false
    @Published var hasMoreExplore = false
    @Published var explorePageFailed = false
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var searchCursor: String?
    private var contentSearchQuery = ""
    private var contentSearchMode = "mixed"
    private var exploreTask: Task<Void, Never>?
    private var exploreGeneration = 0
    private var exploreCursor: FeedCursor?
    var isSearching: Bool { isSearchingMoments || isSearchingUsers }


    init() {
        followStateObserver = NotificationCenter.default.addObserver(
            forName: FollowStateStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            Task { @MainActor in
                self?.userButtonStates[userId] = state
            }
        }

        loadRecentSearches()
    }

    deinit {
        if let followStateObserver {
            NotificationCenter.default.removeObserver(followStateObserver)
        }
        searchWorkItem?.cancel()
        searchTask?.cancel()
        exploreTask?.cancel()
    }


    // MARK: - FLUJO PRINCIPAL SIMPLIFICADO
    func fetchMomentsByInterests() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = NSLocalizedString("errors.authRequired", comment: "User not authenticated")
            return
        }

        self.currentUserId = userId
        loadExplorePage(reset: true)
        isLoading = true
        errorMessage = nil

        // ✅ SwiftData: Cargar del caché local inmediatamente
        let cachedMoments = LocalPersistenceService.shared.loadExploreMoments()
        if !cachedMoments.isEmpty && self.moments.isEmpty {
            self.moments = cachedMoments
            if activeSearchQuery.isEmpty { self.filteredMoments = cachedMoments }
            self.isLoading = false // UI instantánea con datos cacheados
        }


        // 1. PASO OBLIGATORIO: Cargar perfil del usuario actual
        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let currentUserProfile):
                self.currentUserInterests = currentUserProfile.interests
                self.blockedUsers = Set(currentUserProfile.blockedUsers)

                // 2. Cargar conexiones (usuarios seguidos) primero
                self.loadConnectionsFirst { [weak self] in
                    guard let self = self else { return }
                    // 3. PASO PRINCIPAL: Cargar usuarios y momentos (ya con conexiones cargadas)
                    self.loadUsersAndMoments()
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = String(
                        format: NSLocalizedString("errors.profileLoadFailed", comment: "Profile load failed"),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - ✅ FUNCIÓN ACTUALIZADA: Cargar usuarios y momentos con estrategia mejorada
    private func loadUsersAndMoments() {
        guard let userId = currentUserId else { return }

        // ✅ ESTRATEGIA PARA EXPLORE: Obtener una mezcla diversa de usuarios
        let group = DispatchGroup()
        var allDiscoveredUsers: Set<AppUser> = []
        let syncQueue = DispatchQueue(label: "explore.users.discovery")

        // 1. Usuarios con intereses compartidos
        group.enter()
        self.firestoreService.fetchUsersWithSharedInterests(
            interests: self.currentUserInterests,
            excludingUserId: userId
        ) { result in
            defer { group.leave() }

            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users)
                }
            }
        }

        // 2. Usuarios sugeridos (algoritmo interno de Firebase)
        group.enter()
        self.firestoreService.fetchSuggestedUsers { result in
            defer { group.leave() }

            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users.prefix(20))
                }
            }
        }

        // 3. Usuarios populares (fallback)
        group.enter()
        self.fetchPopularUsersForExplore(excludingUserId: userId) { users in
            syncQueue.async {
                allDiscoveredUsers.formUnion(users)
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // ✅ Capturar followedUserIds en este momento para asegurar que esté actualizado
            let currentFollowedUserIds = self.followedUserIds

            // ✅ LECTURA SINCRONIZADA: Asegurar que todas las escrituras hayan terminado
            let finalUsers = syncQueue.sync {
                return allDiscoveredUsers
            }

            // Filtro COMPLETO - bloqueos Y usuarios ya seguidos
            let filteredUsers = Array(finalUsers).filter { user in
                !self.blockedUsers.contains(user.id) &&
                !user.blockedUsers.contains(userId) &&
                !currentFollowedUserIds.contains(user.id) // ✅ Usar la copia capturada
            }



            // Ordenar por relevancia (intereses comunes)
            let sortedUsers = filteredUsers.sorted { user1, user2 in
                let commonInterests1 = Set(user1.interests).intersection(self.currentUserInterests).count
                let commonInterests2 = Set(user2.interests).intersection(self.currentUserInterests).count
                return commonInterests1 > commonInterests2
            }

            DispatchQueue.main.async {
                self.suggestedUsers = Array(sortedUsers.prefix(10))
                // ✅ Filtrar usuarios seguidos después de asignar la lista (por si acaso)
                self.filterFollowedUsersFromSuggestions()
            }

            // Cargar momentos de una muestra diversa de usuarios
            // Recommendations are loaded independently by the ranked backend.
        }
    }

    // MARK: - ✅ NUEVA FUNCIÓN: Obtener usuarios populares para Explore
    private func fetchPopularUsersForExplore(excludingUserId: String, completion: @escaping ([AppUser]) -> Void) {
        firestoreService.db.collection("users")
            .whereField("isPrivate", isEqualTo: false) // Solo perfiles públicos para Explore
            .limit(to: 30)
            .getDocuments { snapshot, error in
                if error != nil {
                    completion([])
                    return
                }

                let users = snapshot?.documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != excludingUserId ? user : nil
                    } catch {
                        return nil
                    }
                } ?? []

                completion(users)
            }
    }

    // MARK: - Cargar conexiones PRIMERO (antes de mostrar usuarios sugeridos)
    private func loadConnectionsFirst(completion: @escaping () -> Void) {
        guard let userId = currentUserId else {
            completion()
            return
        }

        let group = DispatchGroup()
        var loadedFollowing: [AppUser] = [] // ✅ Usamos AppUser (colección 'following') en lugar de Connection
        var loadedNotifications: [Notification] = []
        var loadedFollowers: [AppUser] = []

        // Cargar usuarios seguidos (Colección 'following' correcta)
        group.enter()
        firestoreService.fetchFollowing(userId: userId) { result in
            defer { group.leave() }
            if case .success(let users) = result {
                loadedFollowing = users
            }
        }

        // Cargar seguidores (para Social Status)
        group.enter()
        firestoreService.fetchFollowers(userId: userId) { result in
            defer { group.leave() }
            if case .success(let followers) = result {
                loadedFollowers = followers
            }
        }

        // Cargar solicitudes pendientes
        group.enter()
        NotificationService.shared.fetchNotificationsOnce(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let notifications):
                loadedNotifications = notifications
            case .failure(_):
                break
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            // ✅ Actualizar en el hilo principal después de que todo haya cargado
            // Nota: fetchFollowing devuelve AppUser, así que usamos .id
            let loadedFollowedIds = Set(loadedFollowing.map { $0.id })

            self.followedUserIds = loadedFollowedIds
            self.followerUserIds = Set(loadedFollowers.map { $0.id })

            self.pendingRequests = Set(loadedNotifications.filter {
                $0.type == .followRequest && $0.isPending
            }.map { $0.senderId })

            // ✅ Filtrar usuarios seguidos de la lista actual si ya hay usuarios cargados
            self.suggestedUsers = self.suggestedUsers.filter { user in
                !loadedFollowedIds.contains(user.id)
            }

            // ✅ Actualizar estados de botones para sugerencias y perfiles buscados
            self.updateButtonStatesForAllUsers()

            completion()
        }
    }

    // MARK: - Actualizar estados de botones
    private func updateButtonStatesForAllUsers() {
        for user in suggestedUsers {
            checkUserButtonState(for: user.id)
        }
        for user in searchedUsers {
            checkUserButtonState(for: user.id)
        }

        // ✅ Filtrar usuarios seguidos de la lista después de actualizar estados
        filterFollowedUsersFromSuggestions()
    }

    // ✅ NUEVO: Filtrar usuarios seguidos de las sugerencias
    func filterFollowedUsersFromSuggestions() {
        suggestedUsers = suggestedUsers.filter { user in
            !followedUserIds.contains(user.id)
        }
    }


    // MARK: - Cargar perfil de autor
    func loadAuthorProfile(for userId: String) {
        if authorProfiles[userId] == nil {
            firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
                switch result {
                case .success(let userProfile):
                    DispatchQueue.main.async {
                        self?.authorProfiles[userId] = userProfile
                    }
                case .failure(_):
                    break
                }
            }
        }
    }

    // MARK: - Verificar si puede ver contenido
    func checkCanViewContent(for userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = self.currentUserId else {
            completion(false)
            return
        }

        privacyService.canViewUserContent(
            viewerId: currentUserId,
            targetUserId: userId
        ) { canView in
            DispatchQueue.main.async {
                completion(canView)
            }
        }
    }

    // MARK: - Verificar estado del botón de usuario
    func checkUserButtonState(for userId: String) {
        guard let currentUserId = self.currentUserId else { return }

        if let cachedState = FollowStateStore.shared.state(for: userId) {
            userButtonStates[userId] = cachedState
        }

        FollowStateStore.shared.resolve(
            viewerId: currentUserId,
            targetUserId: userId
        ) { [weak self] state in
            guard let state else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.userButtonStates[userId] = state

                // ✅ Si el estado es "siguiendo", agregar a followedUserIds y eliminar de sugerencias
                if state.isFollowingOrMutual {
                    self.followedUserIds.insert(userId)
                    // Eliminar de la lista de sugerencias
                    if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                        self.suggestedUsers.remove(at: index)
                    }
                }
            }
        }
    }

    // MARK: - Seguir usuario
    func followUser(userId: String) {
        guard let currentUserId = self.currentUserId else {
            return
        }

        if userButtonStates[userId] == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = String(
                            format: NSLocalizedString("errors.cancelRequestFailed", comment: "Cancel request failed"),
                            error.localizedDescription
                        )
                    } else {
                        self?.userButtonStates[userId] = .canRequestFollow
                        self?.pendingRequests.remove(userId)
                        FollowStateStore.shared.setState(.canRequestFollow, for: userId)
                    }
                }
            }
            return
        }

        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let userProfile):
                if userProfile.isPrivate {
                    // ✅ Eliminar inmediatamente de la lista antes de enviar solicitud
                    DispatchQueue.main.async {
                        if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                            self.suggestedUsers.remove(at: index)
                        }
                        self.pendingRequests.insert(userId)
                        self.userButtonStates[userId] = .requestPendingCancellable
                        FollowStateStore.shared.setState(.requestPendingCancellable, for: userId)
                    }

                    self.firestoreService.sendFollowRequest(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = String(
                                    format: NSLocalizedString("errors.sendRequestFailed", comment: "Send request failed"),
                                    error.localizedDescription
                                )
                                // Si hay error, revertir el estado del botón
                                self?.userButtonStates[userId] = .canRequestFollow
                                self?.pendingRequests.remove(userId)
                                FollowStateStore.shared.setState(.canRequestFollow, for: userId)
                            }
                            // Si no hay error, el usuario ya fue eliminado de la lista arriba
                        }
                    }
                } else {
                    // ✅ Eliminar inmediatamente de la lista antes de seguir
                    DispatchQueue.main.async {
                        if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                            self.suggestedUsers.remove(at: index)
                        }
                        self.followedUserIds.insert(userId)
                        self.userButtonStates[userId] = .following
                        FollowStateStore.shared.setState(.following, for: userId)
                    }

                    self.firestoreService.followUser(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = String(
                                    format: NSLocalizedString("errors.followUserFailed", comment: "Follow user failed"),
                                    error.localizedDescription
                                )
                                // Si hay error, revertir el estado del botón
                                self?.userButtonStates[userId] = .canFollow
                                self?.followedUserIds.remove(userId)
                                FollowStateStore.shared.setState(.canFollow, for: userId)
                            }
                            // Si no hay error, el usuario ya fue eliminado de la lista arriba
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = String(
                        format: NSLocalizedString("errors.fetchProfileFailed", comment: "Fetch profile failed"),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Obtener estado del botón
    func getButtonState(for userId: String) -> FollowButtonState {
        return userButtonStates[userId] ?? .canFollow
    }
}

// MARK: - EXTENSIÓN: Funciones específicas para Explore

extension ExploreViewModel {

    // ✅ FUNCIÓN DE DEBUG: Verificar contenido visible
    func debugVisibleContent() {
        guard currentUserId != nil else { return }

        // Mostrar distribución por audiencia
        let audienceDistribution = moments.reduce(into: [String: Int]()) { counts, moment in
            let audience = moment.audience ?? "everyone"
            counts[audience, default: 0] += 1
        }

        for _ in audienceDistribution {

        }
    }

    // ✅ FUNCIÓN PARA REFRESCAR CONTENIDO
    func refreshContent() {
        moments = []
        filteredMoments = []
        suggestedUsers = []
        searchedUsers = []
        followedUserIds = [] // ✅ Limpiar usuarios seguidos para recargarlos
        pendingRequests = [] // ✅ Limpiar solicitudes pendientes para recargarlas
        fetchMomentsByInterests()
    }

    // ✅ FUNCIÓN PARA LIMPIAR DATOS
    func clearData() {
        smartSearch(query: "")
        exploreGeneration += 1
        exploreTask?.cancel()
        hasMoreExplore = false
        moments = []
        filteredMoments = []
        searchedUsers = []
        suggestedUsers = []
        authorProfiles = [:]
        userButtonStates = [:]
        errorMessage = nil
        isLoading = false
    }

    // MARK: - HISTORIAL DE BÚSQUEDA (SwiftData)
    func loadRecentSearches() {
        self.recentSearches = LocalPersistenceService.shared.loadRecentSearches()
    }

    func saveSearchRecord(query: String, type: String, targetId: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Si el tipo es genérico "text", intentamos detectar si es hashtag o usuario
        var finalType = type
        var finalQuery = trimmed

        if type == "text" {
            let detected = detectSearchType(query: trimmed)
            switch detected {
            case .hashtag(let h):
                finalType = "hashtag"
                finalQuery = "#\(h)"
            case .username(let u):
                finalType = "user"
                finalQuery = "@\(u)"
            case .location(let l):
                finalType = "location"
                finalQuery = l
            default:
                finalType = "text"
            }
        }

        LocalPersistenceService.shared.saveSearch(query: finalQuery, type: finalType, targetId: targetId)
        loadRecentSearches()
    }

    func deleteSearch(_ search: CachedSearch) {
        LocalPersistenceService.shared.deleteSearch(id: search.id)
        loadRecentSearches()
    }

    func clearAllSearches() {
        LocalPersistenceService.shared.clearSearchHistory()
        self.recentSearches = []
    }

    // MARK: - SOCIAL STATUS HELPER
    func getSocialStatus(userId: String) -> String? {
        let isFollowing = followedUserIds.contains(userId)
        let isFollower = followerUserIds.contains(userId)

        if isFollowing && isFollower {
            return NSLocalizedString("social.mutual", comment: "Mutual connection status")
        } else if isFollower {
            return NSLocalizedString("social.followsYou", comment: "User follows current user status")
        } else if isFollowing {
            return NSLocalizedString("social.following", comment: "Current user follows user status")
        }
        return nil
    }
}

extension ExploreViewModel {
    func searchByHashtag(_ hashtag: String) {
        searchFilter = "hashtag"
        smartSearch(query: "#" + hashtag.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
    }

    func exploreByLocation(_ locationName: String) {
        searchFilter = "location"
        smartSearch(query: locationName)
    }

    // ✅ FUNCIÓN para refrescar todo
    func refreshAllContent() {
        clearData()
        fetchMomentsByInterests()
    }
}

// ✅ UTILIDAD: Haptic Feedback — delega en HapticManager centralizado.
struct ExploreHapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        HapticManager.shared.impact(style)
    }

    static func success() {
        HapticManager.shared.success()
    }

    static func error() {
        HapticManager.shared.error()
    }
}

extension ExploreViewModel {

    func setSearchFilter(_ filter: String) {
        searchFilter = filter
        smartSearch(query: activeSearchQuery)
    }

    func smartSearch(query: String) {
        activeSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchWorkItem?.cancel()
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1
        let generation = searchGeneration
        searchCursor = nil
        hasMoreSearchResults = false
        searchFailed = false
        searchedUsers = []
        filteredMoments = []
        isSearchingMoments = false
        isSearchingUsers = false
        guard !activeSearchQuery.isEmpty else {
            filteredMoments = moments
            return
        }
        let raw = activeSearchQuery
        let mode = raw.hasPrefix("#") ? "hashtag" : raw.hasPrefix("@") ? "username" : searchFilter
        let clean = (raw.hasPrefix("#") || raw.hasPrefix("@")) ? String(raw.dropFirst()) : raw
        contentSearchQuery = clean
        contentSearchMode = mode
        guard !clean.isEmpty else { return }
        isSearchingMoments = mode != "username"
        isSearchingUsers = mode == "username" || mode == "mixed"
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.searchGeneration == generation else { return }
            if self.isSearchingUsers { self.searchUsers(username: clean) }
            if self.isSearchingMoments { self.loadMoreSearchResults() }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func retrySearch() { smartSearch(query: activeSearchQuery) }

    func loadMoreSearchResults() {
        guard searchTask == nil || !isSearchingMoments else { return }
        guard contentSearchMode != "username", !contentSearchQuery.isEmpty else { return }
        let generation = searchGeneration
        let uid = Auth.auth().currentUser?.uid
        isSearchingMoments = true
        searchFailed = false
        searchTask = Task { [weak self] in
            guard let self else { return }
            let page = await BackendFeedService.shared.searchMoments(query: contentSearchQuery, mode: contentSearchMode, cursor: searchCursor)
            guard !Task.isCancelled, self.searchGeneration == generation, Auth.auth().currentUser?.uid == uid else { return }
            self.isSearchingMoments = false
            self.searchTask = nil
            guard let page else { self.searchFailed = true; return }
            var keys = Set(self.filteredMoments.map { "\($0.authorId)/\($0.id ?? "")" })
            self.filteredMoments += page.moments.filter { keys.insert("\($0.authorId)/\($0.id ?? "")").inserted }
            self.searchCursor = page.nextCursor
            self.hasMoreSearchResults = page.nextCursor != nil
        }
    }

    func loadMoreExplore() { loadExplorePage(reset: false) }

    private func loadExplorePage(reset: Bool) {
        if !reset && (isLoadingMoreExplore || (!hasMoreExplore && !explorePageFailed)) { return }
        if reset {
            exploreGeneration += 1
            exploreTask?.cancel()
            exploreCursor = nil
            hasMoreExplore = false
        }
        let generation = exploreGeneration
        let replacesResults = reset || exploreCursor == nil
        let uid = Auth.auth().currentUser?.uid
        isLoadingMoreExplore = true
        explorePageFailed = false
        exploreTask = Task { [weak self] in
            guard let self else { return }
            let page = await BackendFeedService.shared.fetchExplorePage(cursor: self.exploreCursor)
            guard !Task.isCancelled, self.exploreGeneration == generation, Auth.auth().currentUser?.uid == uid else { return }
            self.isLoading = false
            self.isLoadingMoreExplore = false
            guard let page else { self.explorePageFailed = true; return }
            if replacesResults { self.moments = [] }
            var keys = Set(self.moments.map { "\($0.authorId)/\($0.id ?? "")" })
            self.moments += page.moments.filter { keys.insert("\($0.authorId)/\($0.id ?? "")").inserted }
            if self.activeSearchQuery.isEmpty { self.filteredMoments = self.moments }
            self.exploreCursor = page.nextCursor
            self.hasMoreExplore = page.nextCursor != nil
            LocalPersistenceService.shared.saveExploreMoments(Array(self.moments.prefix(120)), sync: true)
        }
    }

    // ✅ DETECTAR tipo de búsqueda
    private func detectSearchType(query: String) -> SearchType {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Hashtag: empieza con #
        if trimmedQuery.hasPrefix("#") {
            let hashtag = String(trimmedQuery.dropFirst()).lowercased()
            return .hashtag(hashtag)
        }

        // 2. Usuario: empieza con @
        if trimmedQuery.hasPrefix("@") {
            let username = String(trimmedQuery.dropFirst()).lowercased()
            return .username(username)
        }

        // 4. Mixto: buscar en todo
        return .mixed(trimmedQuery)
    }

    private func searchUsers(username: String) {
        let generation = searchGeneration
        let uid = Auth.auth().currentUser?.uid
        firestoreService.searchUsers(query: username.lowercased(), limit: 20) { [weak self] result in
            Task { @MainActor in
                guard let self, self.searchGeneration == generation, Auth.auth().currentUser?.uid == uid else { return }
                self.isSearchingUsers = false
                switch result {
                case .failure:
                    self.searchFailed = true
                case .success(let users):
                    self.searchedUsers = users.filter { $0.id != uid && !self.blockedUsers.contains($0.id) && !$0.blockedUsers.contains(uid ?? "") }
                }
            }
        }
    }
}

// Search history categories.
enum SearchType {
    case hashtag(String), username(String), location(String), mixed(String)
}
