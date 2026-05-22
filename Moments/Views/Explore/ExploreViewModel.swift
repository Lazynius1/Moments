import SwiftUI
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
    @Published var trendingContent: TrendingService.PersonalizedTrendingContent?
    @Published var isLoadingTrending: Bool = false
    @Published var trendingError: String?

    // ✅ HISTORIAL DE BÚSQUEDA
    @Published var recentSearches: [CachedSearch] = []
    @Published var followerUserIds: Set<String> = []


    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    var currentUserInterests: [String] = []
    private var currentUserId: String?
    private var blockedUsers: Set<String> = []
    private let trendingService = TrendingService.shared
    private var followStateObserver: NSObjectProtocol?

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
    }


    // MARK: - FLUJO PRINCIPAL SIMPLIFICADO
    func fetchMomentsByInterests() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        self.currentUserId = userId
        isLoading = true
        errorMessage = nil

        // ✅ SwiftData: Cargar del caché local inmediatamente
        let cachedMoments = LocalPersistenceService.shared.loadExploreMoments()
        if !cachedMoments.isEmpty && self.moments.isEmpty {
            self.moments = cachedMoments
            self.filteredMoments = cachedMoments
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
                    self.errorMessage = "Error al cargar tu perfil: \(error.localizedDescription)"
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
            let userIds = Array(sortedUsers.prefix(100).map { $0.id })
            self.loadMomentsFromUsers(userIds: userIds)
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

    // MARK: - ✅ FUNCIÓN ACTUALIZADA: Cargar momentos con filtrado específico para Explore
    private func loadMomentsFromUsers(userIds: [String]) {


        self.firestoreService.fetchMomentsFromUsers(userIds: userIds) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let allMoments):


                // ✅ USAR LA FUNCIÓN DE FILTRADO ESPECÍFICA PARA EXPLORE
                self.filterMomentsForExploreVisibility(moments: allMoments) { filteredMoments in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.moments = filteredMoments
                        self.filteredMoments = filteredMoments

                        // ✅ SwiftData: Guardar en caché local para offline
                        Task { @MainActor in
                            // Usamos sync: true para purgar momentos que ya no son tendencia/interés
                            LocalPersistenceService.shared.saveExploreMoments(filteredMoments, sync: true)
                        }

                        // ✅ Ya no necesitamos llamar a loadConnectionsOptionally aquí
                        // porque se cargan en paralelo al inicio de la vista
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error al cargar momentos: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - ✅ FUNCIÓN DE FILTRADO ESPECÍFICA PARA EXPLORE
    private func filterMomentsForExploreVisibility(moments: [Moment], completion: @escaping ([Moment]) -> Void) {
        guard let currentUserId = self.currentUserId else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var visibleMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "explore.moments.filter", attributes: .concurrent)



        for moment in moments {
            // Excluir momentos del propio usuario (Explore es para descubrir contenido de otros)
            guard moment.authorId != currentUserId else {
                continue
            }

            // Excluir usuarios bloqueados (filtro básico)
            guard !blockedUsers.contains(moment.authorId) else {
                continue
            }

            group.enter()

            // ✅ USAR LA NUEVA FUNCIÓN ESPECÍFICA PARA EXPLORE
            privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                if canView {
                    syncQueue.sync {
                        visibleMoments.append(moment)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // ✅ SEGURO: Obtener la lista final de manera thread-safe
            let finalVisibleMoments = syncQueue.sync {
                visibleMoments
            }

            // Mantener el orden original por timestamp
            let orderedVisibleMoments = moments.filter { moment in
                finalVisibleMoments.contains { $0.id == moment.id }
            }


            completion(orderedVisibleMoments)
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

        privacyService.getFollowButtonState(
            viewerId: currentUserId,
            targetUserId: userId
        ) { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: userId)
                self.userButtonStates[userId] = reconciledState
                FollowStateStore.shared.setState(reconciledState, for: userId)

                // ✅ Si el estado es "siguiendo", agregar a followedUserIds y eliminar de sugerencias
                if reconciledState == .following {
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
                        self.userButtonStates[userId] = .requestPending
                        FollowStateStore.shared.setState(.requestPending, for: userId)
                    }

                    self.firestoreService.sendFollowRequest(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Error al enviar solicitud: \(error.localizedDescription)"
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
                                self?.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
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
                    self.errorMessage = "Error al obtener perfil: \(error.localizedDescription)"
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

    // ✅ NUEVA FUNCIÓN: Cargar contenido trending
    func fetchTrendingContent() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        isLoadingTrending = true
        trendingError = nil



        trendingService.fetchPersonalizedTrendingContent(for: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingTrending = false

                switch result {
                case .success(let content):
                    self?.trendingContent = content


                case .failure(let error):
                    self?.trendingError = "Error cargando trending: \(error.localizedDescription)"
                }
            }
        }
    }

    // ✅ ACTUALIZAR la función principal para incluir trending
    func fetchMomentsByInterestsWithTrending(completion: (() -> Void)? = nil) {
        // Cargar contenido normal
        fetchMomentsByInterests()

        // Cargar trending en paralelo
        fetchTrendingContent()

        // ✅ NUEVO: Llamar completion cuando termine
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion?()
        }
    }

    // ✅ FUNCIÓN para buscar por hashtag
    func searchByHashtag(_ hashtag: String) {


        // Limpiar búsqueda de usuarios
        searchedUsers = []

        // Buscar momentos que contengan el hashtag
        let filteredByHashtag = moments.filter { moment in
            moment.content.lowercased().contains("#\(hashtag.lowercased())")
        }

        filteredMoments = filteredByHashtag

    }

    // ✅ FUNCIÓN para explorar por ubicación
    func exploreByLocation(_ locationName: String) {


        // Filtrar momentos de esa ubicación
        let filteredByLocation = moments.filter { moment in
            (moment.location ?? "").lowercased().contains(locationName.lowercased())
        }

        filteredMoments = filteredByLocation
        searchedUsers = []

    }

    // ✅ FUNCIÓN para refrescar todo
    func refreshAllContent() {
        clearData()
        fetchMomentsByInterestsWithTrending()
    }
}

// ✅ UTILIDAD: Haptic Feedback (agregar a tu proyecto)
struct ExploreHapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let feedback = UIImpactFeedbackGenerator(style: style)
        feedback.impactOccurred()
    }

    static func success() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }

    static func error() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.error)
    }
}

extension ExploreViewModel {

    // ✅ NUEVA FUNCIÓN: Búsqueda inteligente que reemplaza searchUsers
    func smartSearch(query: String) {


        if query.isEmpty {
            // Limpiar resultados
            searchedUsers = []
            filteredMoments = self.moments

            return
        }

        let searchType = detectSearchType(query: query)


        switch searchType {
        case .hashtag(let hashtag):

            searchHashtags(hashtag: hashtag)

        case .username(let username):

            searchUsers(username: username)

        case .location(let location):

            searchLocations(location: location)

        case .mixed(let cleanQuery):

            searchEverything(query: cleanQuery)
        }
        // NOTA: El historial se guarda explícitamente en .onSubmit o al tocar un resultado
        // para evitar que cada pulsación de tecla genere una entrada en el historial.

        // ✅ NUEVO: Debug final

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

        // 3. Ubicación: contiene palabras clave
        let locationKeywords = ["en ", "lugar ", "city ", "ciudad ", "beach ", "playa ", "restaurant ", "cafe "]
        if locationKeywords.contains(where: { trimmedQuery.lowercased().contains($0) }) {
            return .location(trimmedQuery)
        }

        // 4. Mixto: buscar en todo
        return .mixed(trimmedQuery)
    }

    // ✅ BUSCAR usuarios (función original mejorada CON FILTRADO COMPLETO)
    private func searchUsers(username: String) {
        filteredMoments = [] // Limpiar momentos
        let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else {
            searchedUsers = []
            return
        }

        firestoreService.searchUsers(query: cleanUsername, limit: 20) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Error al buscar usuarios: \(error.localizedDescription)"
                }
            case .success(let users):
                let currentUserId = self.currentUserId ?? ""
                let filteredUsers = users.filter { user in
                    guard user.id != currentUserId else { return false }
                    guard !self.blockedUsers.contains(user.id) else { return false }
                    guard !user.blockedUsers.contains(currentUserId) else { return false }
                    return true
                }

                DispatchQueue.main.async {
                    self.searchedUsers = filteredUsers
                }
            }
        }
    }
    private func searchHashtags(hashtag: String) {


        // Debug de cada momento
        for _ in moments.enumerated() {


        }

        searchedUsers = []

        let candidateMoments = moments.filter { moment in
            // 1. Debe contener el hashtag
            guard moment.content.lowercased().contains("#\(hashtag)") else {

                return false
            }

            // 2. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else {

                return false
            }

            // 3. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else {

                return false
            }


            return true
        }

        filteredMoments = candidateMoments

    }

    // ✅ BUSCAR por ubicaciones CON FILTRADO DE PRIVACIDAD
    private func searchLocations(location: String) {
        searchedUsers = [] // Limpiar usuarios

        // ✅ FILTRAR: momentos visibles en la lista cargada + sin bloqueos
        let candidateMoments = moments.filter { moment in
            // 1. Debe tener ubicación que coincida
            guard let momentLocation = moment.location else { return false }
            guard momentLocation.lowercased().contains(location.lowercased()) else { return false }

            // 2. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }

            // 3. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }

            return true
        }

        filteredMoments = candidateMoments

    }

    // ✅ BÚSQUEDA MIXTA: usuarios + hashtags + ubicaciones CON FILTRADO
    private func searchEverything(query: String) {
        let lowercaseQuery = query.lowercased()

        // 1. Buscar usuarios (ya tiene filtrado correcto)
        searchUsers(username: lowercaseQuery)

        // 2. Buscar momentos CON FILTRADO DE PRIVACIDAD
        let candidateMoments = moments.filter { moment in
            // Verificar coincidencias
            let contentMatch = moment.content.lowercased().contains(lowercaseQuery)
            let locationMatch = (moment.location ?? "").lowercased().contains(lowercaseQuery)
            let usernameMatch = moment.username.lowercased().contains(lowercaseQuery)

            // Debe tener alguna coincidencia
            guard contentMatch || locationMatch || usernameMatch else { return false }

            // ✅ FILTROS DE PRIVACIDAD:
            // 1. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }

            // 2. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }

            return true
        }

        DispatchQueue.main.async {
            self.filteredMoments = candidateMoments

        }
    }
}

// MARK: - 🎯 Tipos de búsqueda
enum SearchType {
    case hashtag(String)     // #viaje
    case username(String)    // @juan
    case location(String)    // Madrid, playa, etc.
    case mixed(String)       // búsqueda general
}
