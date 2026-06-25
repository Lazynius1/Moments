import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - ✅ VIEWMODEL
@MainActor
class UserProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var viewerProfile: AppUser?
    @Published var following: [AppUser] = []
    @Published var mutuals: [AppUser] = []
    @Published var followers: [AppUser] = []
    @Published var commonConnections: [AppUser] = []
    @Published var suggestedConnectionsForViewer: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var taggedMoments: [Moment] = [] // ✅ NUEVO
    @Published var isLoadingTagged: Bool = false // ✅ NUEVO
    @Published var isFollowing: Bool = false
    @Published var isBlockedByCurrentUser: Bool = false
    @Published var isCurrentUserBlocked: Bool = false
    @Published var isLoading: Bool = true
    @Published var followButtonState: FollowButtonState = .canFollow
    @Published var canViewContent: Bool = false
    @Published var canViewSocialLists: Bool = false
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
    @Published private(set) var viewerInterests: [String] = []

    // ✅ NUEVAS PROPIEDADES: Control granular de visibilidad
    @Published var visibleConnectionTypes = VisibleConnectionTypes(
        canViewFollowers: false,
        canViewFollowing: false,
        canViewMutuals: false
    )

    let userId: String
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    private let bestFriendsService = BestFriendsService()
    private var viewerNetworkIds: Set<String> = []
    private var viewerFollowingIds: Set<String> = []
    private var viewerFollowerIds: Set<String> = []
    private var viewerBlockedUserIds: Set<String> = []
    private var targetVisibleFollowingIds: Set<String> = []
    private var targetVisibleFollowerIds: Set<String> = []
    private var lastSuggestionsSignature: String?

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
        loadViewerContext(currentUserId: currentUserId)

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
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty || !cachedConnections.mutuals.isEmpty {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingUsers: cachedConnections.following,
                targetFollowerUsers: cachedConnections.followers,
                targetMutualUsers: cachedConnections.mutuals
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
                    self.refreshMutedUserIds()
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
        self.fetchMoments {
            refreshGroup.leave()
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
                self?.canViewSocialLists = visibleTypes.canViewFollowers || visibleTypes.canViewFollowing
                completion?()
            }
        }
    }



    // ✅ FUNCIÓN MEJORADA: Fetch conexiones directo con filtrado de privacidad
    private func fetchConnectionsDirect() {
        let group = DispatchGroup()
        var fetchedFollowing: [AppUser] = []
        var fetchedFollowers: [AppUser] = []

        if visibleConnectionTypes.canViewFollowing {
            group.enter()
            firestoreService.fetchFollowing(userId: userId) { result in
                defer { group.leave() }
                if case .success(let users) = result {
                    fetchedFollowing = users
                }
            }
        }

        if visibleConnectionTypes.canViewFollowers {
            group.enter()
            firestoreService.fetchFollowers(userId: userId) { result in
                defer { group.leave() }
                if case .success(let users) = result {
                    fetchedFollowers = users
                }
            }
        }

        group.notify(queue: .main) {
            self.categorizeConnectionsWithPrivacy(
                targetFollowingUsers: fetchedFollowing,
                targetFollowerUsers: fetchedFollowers,
                targetMutualUsers: []
            )
        }
    }

    // ✅ NUEVA FUNCIÓN: Obtener momentos etiquetados con filtrado de audiencia
    func fetchTaggedMoments(completion: (() -> Void)? = nil) {
        guard Auth.auth().currentUser?.uid != nil else {
            completion?()
            return
        }

        isLoadingTagged = true
        Task { @MainActor [weak self] in
            guard let self else {
                completion?()
                return
            }
            let result = await BackendFeedService.shared.fetchTaggedMoments(targetUserId: self.userId, limit: 50)
            self.taggedMoments = result?.moments ?? []
            self.isLoadingTagged = false
            completion?()
        }
    }

    // ✅ NUEVA FUNCIÓN: Categorizar conexiones respetando configuraciones de privacidad
    private func categorizeConnectionsWithPrivacy(
        targetFollowingUsers: [AppUser],
        targetFollowerUsers: [AppUser],
        targetMutualUsers: [AppUser]
    ) {
        let targetFollowingSet = Set(targetFollowingUsers.map(\.id))
        let targetFollowerSet = Set(targetFollowerUsers.map(\.id))
        targetVisibleFollowingIds = visibleConnectionTypes.canViewFollowing ? targetFollowingSet : []
        targetVisibleFollowerIds = visibleConnectionTypes.canViewFollowers ? targetFollowerSet : []

        let filteredFollowing = visibleConnectionTypes.canViewFollowing ? targetFollowingUsers : []
        let filteredFollowers = visibleConnectionTypes.canViewFollowers ? targetFollowerUsers : []

        self.mutuals = []
        self.following = filteredFollowing
        self.followers = filteredFollowers

        self.recomputeVisitorSections()
        self.fetchMoments()
        self.isLoading = false

        LocalPersistenceService.shared.saveFollowers(userId: self.userId, followers: filteredFollowers)
        LocalPersistenceService.shared.saveFollowing(userId: self.userId, following: filteredFollowing)
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

    private func loadViewerContext(currentUserId: String) {
        let group = DispatchGroup()
        var fetchedViewerProfile: AppUser?
        var followingIds: Set<String> = []
        var followerIds: Set<String> = []

        group.enter()
        firestoreService.fetchUserProfile(userId: currentUserId) { result in
            if case .success(let profile) = result {
                fetchedViewerProfile = profile
            }
            group.leave()
        }

        group.enter()
        firestoreService.db.collection("users").document(currentUserId).collection("following")
            .getDocuments { snapshot, _ in
                followingIds = Set(snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    return data["userId"] as? String ?? doc.documentID
                } ?? [])
                group.leave()
            }

        group.enter()
        firestoreService.db.collection("users").document(currentUserId).collection("followers")
            .getDocuments { snapshot, _ in
                followerIds = Set(snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    return data["userId"] as? String ?? doc.documentID
                } ?? [])
                group.leave()
            }

        group.notify(queue: .main) {
            self.viewerProfile = fetchedViewerProfile
            self.viewerInterests = fetchedViewerProfile?.interests ?? []
            self.viewerBlockedUserIds = Set(fetchedViewerProfile?.blockedUsers ?? [])
            self.viewerFollowingIds = followingIds
            self.viewerFollowerIds = followerIds
            self.viewerNetworkIds = followingIds.union(followerIds)
            self.recomputeVisitorSections()
        }
    }

    private func recomputeVisitorSections() {
        guard let viewerId = Auth.auth().currentUser?.uid else {
            commonConnections = []
            suggestedConnectionsForViewer = []
            return
        }

        let targetVisibleNetworkIds = targetVisibleFollowingIds.union(targetVisibleFollowerIds)
        let commonIds = viewerNetworkIds
            .intersection(targetVisibleNetworkIds)
            .subtracting([viewerId, userId])

        let visibleUsers = uniqueUsersPreservingOrder(mutuals + followers + following)
        commonConnections = visibleUsers.filter { commonIds.contains($0.id) }

        refreshSuggestedConnections(excludingIds: Set(commonConnections.map(\.id)).union([viewerId, userId]))
    }

    private func refreshSuggestedConnections(excludingIds: Set<String>) {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        guard !viewerInterests.isEmpty else {
            suggestedConnectionsForViewer = []
            return
        }

        let signature = ([viewerId, userId] + excludingIds.sorted() + viewerInterests.sorted()).joined(separator: "|")
        guard signature != lastSuggestionsSignature else { return }
        lastSuggestionsSignature = signature

        firestoreService.fetchUsersWithSharedInterests(interests: viewerInterests, excludingUserId: viewerId) { [weak self] result in
            guard let self else { return }
            guard case .success(let users) = result else {
                DispatchQueue.main.async {
                    self.suggestedConnectionsForViewer = []
                }
                return
            }

            let excludedNetworkIds = self.viewerFollowingIds.union(self.viewerFollowerIds)
            let filtered = self.uniqueUsersPreservingOrder(users).filter { user in
                guard !excludingIds.contains(user.id) else { return false }
                guard !excludedNetworkIds.contains(user.id) else { return false }
                guard !self.viewerBlockedUserIds.contains(user.id) else { return false }
                guard !user.blockedUsers.contains(viewerId) else { return false }
                return true
            }
            .sorted { lhs, rhs in
                let lhsInterests = Set(lhs.interests).intersection(Set(self.viewerInterests)).count
                let rhsInterests = Set(rhs.interests).intersection(Set(self.viewerInterests)).count
                if lhsInterests != rhsInterests {
                    return lhsInterests > rhsInterests
                }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.suggestedConnectionsForViewer = Array(filtered.prefix(8))
                self.suggestedConnectionsForViewer.forEach { self.prefetchRelationshipState(for: $0.id) }
            }
        }
    }

    private func uniqueUsersPreservingOrder(_ users: [AppUser]) -> [AppUser] {
        var seen = Set<String>()
        return users.filter { user in
            seen.insert(user.id).inserted
        }
    }

    func fetchMoments(completion: (() -> Void)? = nil) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion?()
                return
            }

            if let result = await BackendFeedService.shared.fetchProfileMoments(targetUserId: self.userId, limit: 50) {
                self.moments = result.moments
                completion?()
                return
            }

            self.firestoreService.fetchMoments(for: self.userId) { [weak self] result in
                guard let self = self else {
                    completion?()
                    return
                }

                switch result {
                case .success(let allMoments):
                    self.filterMomentsForAudience(moments: allMoments, viewerId: currentUserId) { filteredMoments in
                        DispatchQueue.main.async {
                            self.moments = filteredMoments
                            completion?()
                        }
                    }
                case .failure:
                    DispatchQueue.main.async {
                        self.moments = []
                        completion?()
                    }
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

    private func refreshMutedUserIds() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.fetchMutedUserIds(userId: currentUserId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                self?.isMutedByCurrentUser = mutedIds.contains(self?.userId ?? "")
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
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Limpiar unfollow reciente si existe
        recentUnfollows.remove(userId)
        lastUnfollowTime.removeValue(forKey: userId)

        if userId == self.userId, let userProfile = self.userProfile {
            if userProfile.isPrivate {
                firestoreService.sendFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        guard error == nil else { return }
                        self.followButtonState = .requestPendingCancellable
                        FollowStateStore.shared.setState(.requestPendingCancellable, for: userId)
                    }
                }
            } else {
                firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        guard error == nil else { return }

                        self.followButtonState = .following
                        self.isFollowing = true
                        FollowStateStore.shared.setState(.following, for: userId)

                        if self.visibleConnectionTypes.canViewMutuals,
                           let follower = self.followers.first(where: { $0.id == userId }),
                           !self.mutuals.contains(where: { $0.id == userId }) {
                            self.mutuals.append(follower)
                        }

                        if self.visibleConnectionTypes.canViewFollowing,
                           !self.following.contains(where: { $0.id == userId }) {
                            self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                                if case .success(let user) = result {
                                    DispatchQueue.main.async {
                                        if self?.visibleConnectionTypes.canViewFollowing == true {
                                            if self?.following.contains(where: { $0.id == user.id }) == false {
                                                self?.following.append(user)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return
        }

        privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { [weak self] state in
            guard let self else { return }
            let reconciled = FollowStateStore.shared.reconciledState(state, for: userId)

            switch reconciled {
            case .canRequestFollow:
                self.firestoreService.sendFollowRequest(currentUserId: currentUserId, targetUserId: userId) { error in
                    guard error == nil else { return }
                    DispatchQueue.main.async {
                        FollowStateStore.shared.setState(.requestPendingCancellable, for: userId)
                    }
                }
            case .canFollow:
                self.firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                    guard let self else { return }
                    guard error == nil else { return }
                    DispatchQueue.main.async {
                        FollowStateStore.shared.setState(.following, for: userId)
                        self.suggestedConnectionsForViewer.removeAll { $0.id == userId }
                    }
                }
            default:
                break
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
                if userId == self.userId {
                    self.followButtonState = .canRequestFollow
                }
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
                let nextState: FollowButtonState
                if userId == self.userId {
                    nextState = self.userProfile?.isPrivate == true ? .canRequestFollow : .canFollow
                } else {
                    let knownUser = self.followers.first(where: { $0.id == userId })
                        ?? self.following.first(where: { $0.id == userId })
                        ?? self.mutuals.first(where: { $0.id == userId })
                    nextState = knownUser?.isPrivate == true ? .canRequestFollow : .canFollow
                }
                FollowStateStore.shared.setState(nextState, for: userId)

                guard userId == self.userId else { return }

                self.followButtonState = nextState
                self.isFollowing = false

                if self.userProfile?.isPrivate == true {
                    self.canViewContent = false
                }

                if self.visibleConnectionTypes.canViewMutuals,
                   let mutualIndex = self.mutuals.firstIndex(where: { $0.id == userId }) {
                    self.mutuals.remove(at: mutualIndex)
                }
                if self.visibleConnectionTypes.canViewFollowing,
                   let followingIndex = self.following.firstIndex(where: { $0.id == userId }) {
                    self.following.remove(at: followingIndex)
                }
            }
        }
    }

    func relationshipState(for userId: String) -> FollowButtonState {
        if let cached = FollowStateStore.shared.state(for: userId) {
            return cached
        }

        if let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId {
            return .ownProfile
        }

        if following.contains(where: { $0.id == userId }) || mutuals.contains(where: { $0.id == userId }) {
            return .following
        }

        let knownUser = followers.first(where: { $0.id == userId })
            ?? following.first(where: { $0.id == userId })
            ?? mutuals.first(where: { $0.id == userId })

        if knownUser?.isPrivate == true {
            return .canRequestFollow
        }

        return .canFollow
    }

    func prefetchRelationshipState(for userId: String) {
        guard FollowStateStore.shared.state(for: userId) == nil,
              let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else { return }

        privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { state in
            let reconciled = FollowStateStore.shared.reconciledState(state, for: userId)
            FollowStateStore.shared.setState(reconciled, for: userId)
        }
    }

    func checkIfFollowing() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: userId) { [weak self] isFollowing in
            DispatchQueue.main.async {
                self?.isFollowing = isFollowing
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
