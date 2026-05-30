import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - ✅ VIEWMODEL
@MainActor
class UserProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var taggedMoments: [Moment] = [] // ✅ NUEVO
    @Published var isLoadingTagged: Bool = false // ✅ NUEVO
    @Published var isFollowing: Bool = false
    @Published var isBlockedByCurrentUser: Bool = false
    @Published var isCurrentUserBlocked: Bool = false
    @Published var isLoading: Bool = true
    @Published var followButtonState: FollowButtonState = .canFollow
    @Published var canViewContent: Bool = false
    @Published var canViewConnections: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var isProfileUnavailable: Bool = false
    @Published var isInBestFriends: Bool = false
    @Published var isMutedByCurrentUser: Bool = false
    @Published var isMutualRelationship: Bool = false
    @Published var customListMembershipCount: Int = 0
    @Published var customListsContainingProfile: [CustomAudienceList] = []
    @Published var isUpdatingBestFriend: Bool = false
    @Published var isUpdatingMute: Bool = false
    @Published var isUpdatingLists: Bool = false

    // ✅ NUEVAS PROPIEDADES: Control granular de visibilidad
    @Published var visibleConnectionTypes = VisibleConnectionTypes(
        canViewAdmirers: false,
        canViewConnections: false,
        canViewMutualConnections: false
    )

    let userId: String
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    private let bestFriendsService = BestFriendsService()

    // Cache local para tracking de unfollows recientes
    private var recentUnfollows: Set<String> = []
    private var lastUnfollowTime: [String: Date] = [:]
    private var followStateObserver: NSObjectProtocol?

    init(userId: String) {
        self.userId = userId
        followStateObserver = NotificationCenter.default.addObserver(
            forName: FollowStateStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            Task { @MainActor [weak self] in
                guard let self, changedUserId == self.userId else { return }
                self.followButtonState = state
                self.isFollowing = (state == .following)
            }
        }
    }

    deinit {
        if let followStateObserver {
            NotificationCenter.default.removeObserver(followStateObserver)
        }
    }

    func fetchProfile() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        isLoading = true
        isProfileUnavailable = false

        // ✅ SwiftData: Carga inicial desde caché local
        if let cachedProfile = LocalPersistenceService.shared.loadUser(userId: userId) {
            DispatchQueue.main.async {
                if cachedProfile.isActive {
                    self.userProfile = cachedProfile
                    self.isLoading = false
                } else {
                    self.userProfile = nil
                    self.canViewContent = false
                    self.isProfileUnavailable = true
                    self.isLoading = false
                }
            }
        }

        // ✅ Cargar conexiones del caché
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingIds: cachedConnections.following.map(\.id),
                targetFollowerIds: cachedConnections.followers.map(\.id)
            )
        }

        checkIfBlocked()

        firestoreService.checkPublicProfileAvailability(userId: userId) { [weak self] availability in
            guard let self = self else { return }
            guard availability == .unavailable else { return }
            DispatchQueue.main.async {
                self.userProfile = nil
                self.canViewContent = false
                self.isProfileUnavailable = true
                self.isLoading = false
            }
        }

        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    guard !self.isProfileUnavailable else { return }
                    guard profile.isActive else {
                        self.userProfile = nil
                        self.canViewContent = false
                        self.isProfileUnavailable = true
                        self.isLoading = false
                        return
                    }

                    self.isProfileUnavailable = false
                    self.userProfile = profile
                }
                if profile.isActive {
                    self.checkContentVisibility(currentUserId: currentUserId)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if self.isUnavailableProfileError(error) {
                        self.userProfile = nil
                        self.canViewContent = false
                        self.isProfileUnavailable = true
                    }
                    self.isLoading = false
                }
            }
        }
    }

    private func isUnavailableProfileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let documentNotFound = NSLocalizedString("errors.documentNotFound", comment: "Document not found")
        return nsError.code == -1 && nsError.localizedDescription == documentNotFound
    }

    // ✅ FUNCIÓN DE REFRESH COMPLETA
    func refreshProfile() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        guard !isRefreshing && !isLoading else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshing = true
        }

        // Delay mínimo para que Firestore procese cambios recientes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performRefresh(currentUserId: currentUserId)
        }
    }

    private func performRefresh(currentUserId: String) {
        let refreshGroup = DispatchGroup()
        var hasErrors = false

        // 1. Refresh perfil principal
        refreshGroup.enter()
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    self?.userProfile = profile
                }
            case .failure:
                hasErrors = true
            }
            refreshGroup.leave()
        }

        // 2. Re-verificar permisos de privacidad
        refreshGroup.enter()
        checkConnectionsVisibility(currentUserId: currentUserId) {
            refreshGroup.leave()
        }

        // 3. Refresh conexiones con verificación directa
        refreshGroup.enter()
        self.checkConnectionsVisibility(currentUserId: currentUserId) {
            self.fetchConnectionsDirect()
            refreshGroup.leave()
        }

        // 4. Refresh momentos
        refreshGroup.enter()
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else {
                refreshGroup.leave()
                return
            }

            switch result {
            case .success(let allMoments):
                // ✅ Aplicar filtrado de audiencia
                self.filterMomentsForAudience(moments: allMoments, viewerId: currentUserId) { filteredMoments in
                    DispatchQueue.main.async {
                        self.moments = filteredMoments
                    }
                    refreshGroup.leave()
                }
            case .failure:
                hasErrors = true
                refreshGroup.leave()
            }
        }

        // 5. Refresh momentos etiquetados
        refreshGroup.enter()
        self.fetchTaggedMoments {
            refreshGroup.leave()
        }

        // Cuando terminen todas las operaciones
        refreshGroup.notify(queue: .main) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.isRefreshing = false
            }

            if !hasErrors {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }

    private func checkContentVisibility(currentUserId: String) {
        if currentUserId == userId {
            canViewContent = true
            checkConnectionsVisibility(currentUserId: currentUserId) {
                self.fetchConnectionsDirect()
            }
            return
        }

        privacyService.canViewUserContent(viewerId: currentUserId, targetUserId: userId) { [weak self] canView in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canViewContent = canView
                if canView {
                    self.checkConnectionsVisibility(currentUserId: currentUserId) {
                        self.fetchConnectionsDirect()
                    }
                } else {
                    self.isLoading = false
                }
            }
        }
    }

    // ✅ FUNCIÓN CLAVE: Verificar visibilidad de conexiones con configuraciones de privacidad
    private func checkConnectionsVisibility(currentUserId: String, completion: (() -> Void)? = nil) {
        privacyService.getVisibleConnectionTypes(viewerId: currentUserId, targetUserId: userId) { [weak self] visibleTypes in
            DispatchQueue.main.async {
                self?.visibleConnectionTypes = visibleTypes
                // Para compatibilidad con código existente
                self?.canViewConnections = visibleTypes.canViewAdmirers || visibleTypes.canViewConnections || visibleTypes.canViewMutualConnections
                completion?()
            }
        }
    }



    // ✅ FUNCIÓN MEJORADA: Fetch conexiones directo con filtrado de privacidad
    private func fetchConnectionsDirect() {
        let group = DispatchGroup()
        var targetFollowingIds: [String] = []
        var targetFollowerIds: [String] = []

        if visibleConnectionTypes.canViewConnections || visibleConnectionTypes.canViewMutualConnections {
            group.enter()
            let snapshotUnfollowTime = self.lastUnfollowTime
            let snapshotRecentUnfollows = self.recentUnfollows
            firestoreService.db.collection("users").document(userId).collection("following")
                .getDocuments { [weak self] followingSnapshot, error in
                    defer { group.leave() }
                    guard let self = self else { return }
                    guard error == nil else { return }

                    let followingIds = followingSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []

                    var localUnfollowTime = snapshotUnfollowTime
                    var localRecentUnfollows = snapshotRecentUnfollows
                    var expiredKeys: [String] = []

                    targetFollowingIds = followingIds.filter { followedUserId in
                        if let unfollowTime = localUnfollowTime[followedUserId] {
                            let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                            if timeSinceUnfollow < 5.0 {
                                return false
                            } else {
                                expiredKeys.append(followedUserId)
                                localUnfollowTime.removeValue(forKey: followedUserId)
                                localRecentUnfollows.remove(followedUserId)
                            }
                        }
                        return true
                    }

                    if !expiredKeys.isEmpty {
                        let keysToRemove = expiredKeys
                        Task { @MainActor [weak self] in
                            for key in keysToRemove {
                                self?.lastUnfollowTime.removeValue(forKey: key)
                                self?.recentUnfollows.remove(key)
                            }
                        }
                    }
                }
        }

        if visibleConnectionTypes.canViewAdmirers || visibleConnectionTypes.canViewMutualConnections {
            group.enter()
            firestoreService.db.collection("users").document(userId).collection("followers")
                .getDocuments { followersSnapshot, error in
                    defer { group.leave() }
                    guard error == nil else { return }

                    targetFollowerIds = followersSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []
                }
        }

        group.notify(queue: .main) {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingIds: targetFollowingIds,
                targetFollowerIds: targetFollowerIds
            )
        }
    }

    // ✅ NUEVA FUNCIÓN: Obtener momentos etiquetados con filtrado de audiencia
    func fetchTaggedMoments(completion: (() -> Void)? = nil) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        isLoadingTagged = true

        // Buscar momentos donde el usuario del perfil está etiquetado
        firestoreService.db.collectionGroup("moments")
            .whereField("taggedUsers", arrayContains: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
                guard let self = self else {
                    completion?()
                    return
                }

                if let error = error {
                    print("❌ Error loading tagged moments: \(error)")
                    DispatchQueue.main.async {
                        self.isLoadingTagged = false
                        completion?()
                    }
                    return
                }

                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self.isLoadingTagged = false
                        self.taggedMoments = []
                        completion?()
                    }
                    return
                }

                let allMoments = documents.compactMap { doc -> Moment? in
                    guard let moment = try? doc.data(as: Moment.self) else { return nil }
                    return moment.isArchived == true ? nil : moment
                }

                // ✅ IMPORTANTE: Filtrar por audiencia usando PrivacyService
                // Capture privacyService before this Sendable closure to avoid main-actor isolation warning
                Task { @MainActor in
                    let ps = self.privacyService
                    ps.filterVisibleContent(moments: allMoments, for: currentUserId) { filteredMoments in
                        DispatchQueue.main.async {
                            self.taggedMoments = filteredMoments
                            self.isLoadingTagged = false
                            completion?()
                        }
                    }
                }
            }
    }

    // ✅ NUEVA FUNCIÓN: Categorizar conexiones respetando configuraciones de privacidad
    private func categorizeConnectionsWithPrivacy(targetFollowingIds: [String], targetFollowerIds: [String]) {
        let targetFollowingSet = Set(targetFollowingIds)
        let targetFollowerSet = Set(targetFollowerIds)

        let mutualIds: Set<String> = visibleConnectionTypes.canViewMutualConnections
            ? targetFollowingSet.intersection(targetFollowerSet)
            : []
        let connectionIds = targetFollowingSet.subtracting(mutualIds)
        let admirerIds = targetFollowerSet.subtracting(mutualIds)

        let fetchGroup = DispatchGroup()

        // ✅ SOLO cargar si tengo permisos específicos
        if visibleConnectionTypes.canViewMutualConnections {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(mutualIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.mutualConnections = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.mutualConnections = []
            }
        }

        if visibleConnectionTypes.canViewConnections {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(connectionIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.connections = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.connections = []
            }
        }

        if visibleConnectionTypes.canViewAdmirers {
            fetchGroup.enter()
            self.fetchUsersInBatches(userIds: Array(admirerIds)) { [weak self] users in
                DispatchQueue.main.async {
                    self?.admirers = users
                }
                fetchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.admirers = []
            }
        }

        // ✅ Cargar momentos cuando terminen todas las conexiones
        fetchGroup.notify(queue: .main) {
            self.fetchMoments()
            self.isLoading = false

            // ✅ SwiftData: Persistir conexiones en el caché local
            let allFollowers = self.mutualConnections + self.admirers
            let allFollowing = self.mutualConnections + self.connections
            LocalPersistenceService.shared.saveFollowers(userId: self.userId, followers: allFollowers)
            LocalPersistenceService.shared.saveFollowing(userId: self.userId, following: allFollowing)
        }
    }

    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            firestoreService.fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                switch result {
                case .success(let users):
                    allUsers.append(contentsOf: users)
                case .failure:
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
    }

    func fetchMoments() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let allMoments):
                // ✅ FILTRAR momentos por audiencia usando PrivacyService
                self.filterMomentsForAudience(moments: allMoments, viewerId: currentUserId) { filteredMoments in
                    DispatchQueue.main.async {
                        self.moments = filteredMoments
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.moments = []
                }
            }
        }
    }

    private func filterMomentsForAudience(moments: [Moment], viewerId: String, completion: @escaping ([Moment]) -> Void) {
        let group = DispatchGroup()
        var visibleIds: Set<String> = []
        let lock = NSLock()

        for moment in moments {
            group.enter()
            privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                if canView, let id = moment.id {
                    lock.lock()
                    visibleIds.insert(id)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Mantener el orden original de los momentos
            let orderedVisibleMoments = moments.filter { moment in
                guard let id = moment.id else { return false }
                return visibleIds.contains(id)
            }

            completion(orderedVisibleMoments)
        }
    }

    private func filterStoriesForAudience(stories: [Story], viewerId: String, completion: @escaping ([Story]) -> Void) {
        let group = DispatchGroup()
        var visibleIds: Set<String> = []
        let lock = NSLock()

        for story in stories {
            group.enter()
            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                if canView, let id = story.id {
                    lock.lock()
                    visibleIds.insert(id)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Mantener el orden original de las historias
            let orderedVisibleStories = stories.filter { story in
                guard let id = story.id else { return false }
                return visibleIds.contains(id)
            }

            completion(orderedVisibleStories)
        }
    }


    func checkFollowButtonState() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        if let cachedState = FollowStateStore.shared.state(for: userId) {
            followButtonState = cachedState
            isFollowing = (cachedState == .following)
        }

        privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: self.userId)
                self.followButtonState = reconciledState
                self.isFollowing = (reconciledState == .following)
                FollowStateStore.shared.setState(reconciledState, for: self.userId)
            }
        }
    }

    func loadRelationshipManagementState() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else { return }

        privacyService.checkIfBestFriend(userId: currentUserId, friendId: userId) { [weak self] isBestFriend in
            DispatchQueue.main.async {
                self?.isInBestFriends = isBestFriend
            }
        }

        firestoreService.fetchMutedUserIds(userId: currentUserId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                self?.isMutedByCurrentUser = mutedIds.contains(self?.userId ?? "")
            }
        }

        privacyService.checkMutualConnection(user1: currentUserId, user2: userId) { [weak self] isMutual in
            DispatchQueue.main.async {
                self?.isMutualRelationship = isMutual
            }
        }

        firestoreService.fetchCustomLists(for: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let lists):
                    let matchingLists = lists.filter { $0.members.contains(self.userId) }
                    self.customListsContainingProfile = matchingLists
                    self.customListMembershipCount = matchingLists.count
                case .failure:
                    self.customListsContainingProfile = []
                    self.customListMembershipCount = 0
                }
            }
        }
    }

    func removeFromCustomList(_ list: CustomAudienceList) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let listId = list.id,
              currentUserId != userId,
              !isUpdatingLists else { return }

        isUpdatingLists = true
        firestoreService.removeMembersFromCustomList(
            listId: listId,
            ownerId: currentUserId,
            memberIds: [userId]
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingLists = false
                if error == nil {
                    self.customListsContainingProfile.removeAll { $0.id == list.id }
                    self.customListMembershipCount = self.customListsContainingProfile.count
                }
            }
        }
    }

    func toggleBestFriend() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId,
              !isUpdatingBestFriend else { return }

        isUpdatingBestFriend = true
        let shouldAdd = !isInBestFriends

        let completion: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingBestFriend = false
                if error == nil {
                    self.isInBestFriends = shouldAdd
                }
            }
        }

        if shouldAdd {
            bestFriendsService.addBestFriend(currentUserId: currentUserId, friendId: userId, completion: completion)
        } else {
            bestFriendsService.removeBestFriend(currentUserId: currentUserId, friendId: userId, completion: completion)
        }
    }

    func toggleMute() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId,
              !isUpdatingMute else { return }

        isUpdatingMute = true
        let shouldMute = !isMutedByCurrentUser

        firestoreService.db.collection("users").document(currentUserId).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            var muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any] ?? [:]
            var mutedUsers = Set((muteSettings["mutedUsers"] as? [String] ?? []).filter { !$0.isEmpty })

            if shouldMute {
                mutedUsers.insert(self.userId)
            } else {
                mutedUsers.remove(self.userId)
            }

            muteSettings["mutedUsers"] = Array(mutedUsers)

            Task { @MainActor in
                do {
                    try await self.firestoreService.db
                        .collection("users")
                        .document(currentUserId)
                        .updateData(["muteSettings": muteSettings])
                    self.isUpdatingMute = false
                    self.isMutedByCurrentUser = shouldMute
                } catch {
                    self.isUpdatingMute = false
                }
            }
        }
    }

    func registerVisit() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else {
            return
        }

        // Track the visit locally for affinity scoring
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .profileVisit, with: userId)
        }

        guard !IncognitoModeService.shared.isActive else { return }

        // ✅ UNA SOLA LÍNEA - Todo se maneja en FirestoreService
        firestoreService.registerVisit(visitorId: currentUserId, to: userId) { error in
            // Silently handle error
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Follow user con actualización inmediata de UI
    func followUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid, let userProfile = self.userProfile else { return }

        // Limpiar unfollow reciente si existe
        recentUnfollows.remove(userId)
        lastUnfollowTime.removeValue(forKey: userId)

        if userProfile.isPrivate {
            firestoreService.sendFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if error != nil {
                        return
                    }
                    self.followButtonState = .requestPendingCancellable
                    FollowStateStore.shared.setState(.requestPendingCancellable, for: userId)
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if error != nil {
                        return
                    }

                    self.followButtonState = .following
                    self.isFollowing = true
                    FollowStateStore.shared.setState(.following, for: userId)

                    // Actualizar UI inmediatamente si tengo permisos para ver admirers
                    if self.visibleConnectionTypes.canViewAdmirers,
                       let admirerIndex = self.admirers.firstIndex(where: { $0.id == userId }) {
                        let user = self.admirers.remove(at: admirerIndex)
                        if self.visibleConnectionTypes.canViewMutualConnections {
                            self.mutualConnections.append(user)
                        }
                    } else if self.visibleConnectionTypes.canViewConnections {
                        // Obtener usuario y agregarlo a conexiones si puedo verlas
                        self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                            if case .success(let user) = result {
                                DispatchQueue.main.async {
                                    if self?.visibleConnectionTypes.canViewConnections == true {
                                        self?.connections.append(user)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func cancelFollowRequest(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                return
            }

            DispatchQueue.main.async {
                self.followButtonState = .canRequestFollow
                FollowStateStore.shared.setState(.canRequestFollow, for: userId)
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Unfollow user con actualización inmediata de UI
    func unfollowUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Marcar como unfollow reciente
        recentUnfollows.insert(userId)
        lastUnfollowTime[userId] = Date()

        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                // Limpiar cache de unfollow si falló
                self.recentUnfollows.remove(userId)
                self.lastUnfollowTime.removeValue(forKey: userId)
                return
            }

            DispatchQueue.main.async {
                self.followButtonState = .canFollow
                self.isFollowing = false
                FollowStateStore.shared.setState(.canFollow, for: userId)

                // Actualizar UI inmediatamente respetando permisos de privacidad
                if self.visibleConnectionTypes.canViewMutualConnections,
                   let mutualIndex = self.mutualConnections.firstIndex(where: { $0.id == userId }) {
                    let user = self.mutualConnections.remove(at: mutualIndex)
                    if self.visibleConnectionTypes.canViewAdmirers {
                        self.admirers.append(user)
                    }
                } else if self.visibleConnectionTypes.canViewConnections,
                          let connectionIndex = self.connections.firstIndex(where: { $0.id == userId }) {
                    self.connections.remove(at: connectionIndex)
                }
            }
        }
    }

    func checkIfFollowing() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.fetchConnections(userId: currentUserId) { [weak self] result in
            guard let self = self else { return }
            if case .success(let connections) = result {
                let followingIds = connections.map { $0.userId }
                DispatchQueue.main.async {
                    self.isFollowing = followingIds.contains(self.userId)
                }
            }
        }
    }

    func checkIfBlocked() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.checkIfBlocked(currentUserId: currentUserId, targetUserId: userId) { [weak self] isBlockedByCurrentUser, isCurrentUserBlocked, error in
            guard let self = self else { return }
            if error != nil {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = isBlockedByCurrentUser
                self.isCurrentUserBlocked = isCurrentUserBlocked
                self.canViewContent = false
                self.isProfileUnavailable = isCurrentUserBlocked
            }
        }
    }

    func blockUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.blockUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = true
                self.isProfileUnavailable = true
                self.followButtonState = .blocked
                self.isFollowing = false
            }
        }
    }

    func unblockUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.unblockUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                return
            }
            DispatchQueue.main.async {
                self.isBlockedByCurrentUser = false
                self.isProfileUnavailable = false
                self.checkFollowButtonState()
                self.fetchProfile()
            }
        }
    }
}
