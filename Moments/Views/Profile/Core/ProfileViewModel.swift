import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import WidgetKit

// MARK: - ProfileViewModel
@MainActor
class ProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var visits: [AppUser] = []
    @Published var groupedVisits: [GroupedVisit] = []
    @Published var isLoadingVisits: Bool = false
    @Published var visitTimestamps: [String: [Date]] = [:]
    @Published var following: [AppUser] = []
    @Published var mutuals: [AppUser] = []
    @Published var followers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var customListNamesById: [String: String] = [:]
    @Published var taggedMoments: [Moment] = [] // ✅ NUEVO
    @Published var isLoadingTagged: Bool = false // ✅ NUEVO
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var profileImagePath: String?
    @Published var isRefreshing: Bool = false

    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    private let privacyService = PrivacyService()
    // ✅ UserDefaults compartido con el widget (App Group "group.com.glowsyapp")
    private let widgetUserDefaults = UserDefaults(suiteName: "group.com.glowsyapp")

    // ✅ NUEVO: Cache local para tracking de unfollows recientes
    private var recentUnfollows: Set<String> = []
    private var lastUnfollowTime: [String: Date] = [:]

    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        firestoreService.fetchUsersInBatches(userIds: userIds, completion: completion)
    }

    func fetchProfile(userId: String) {
        self.isLoading = true
        self.errorMessage = nil

        // ✅ SwiftData: Cargar perfil y moments del caché local inmediatamente
        if let cachedProfile = LocalPersistenceService.shared.loadUser(userId: userId) {
            self.userProfile = cachedProfile
            self.profileImagePath = cachedProfile.profileImagePath
            self.isLoading = false // UI instantánea
        }

        // ✅ Cargar conexiones del caché
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty || !cachedConnections.mutuals.isEmpty {
            self.applyConnectionSnapshots(
                userId: userId,
                followingUsers: cachedConnections.following,
                followerUsers: cachedConnections.followers,
                mutualUsers: cachedConnections.mutuals
            )
        }

        let cachedMoments = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
        if !cachedMoments.isEmpty && self.moments.isEmpty {
            self.moments = sortProfileMoments(cachedMoments)
        }

        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                self.userProfile = profile
                self.profileImagePath = profile.profileImagePath

                // ✅ SwiftData: Guardar perfil en caché local
                Task { @MainActor in
                    LocalPersistenceService.shared.saveUser(profile)
                }

                self.fetchConnections(userId: userId)
                self.fetchVisits(userId: userId)
                self.fetchMoments(userId: userId)
                self.fetchCustomAudienceListNames(userId: userId)
            case .failure(let error):
                self.errorMessage = "Error al cargar el perfil: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // ✅ NUEVA FUNCIÓN: Fetch conexiones con verificación directa
    private func fetchConnections(userId: String) {
        let group = DispatchGroup()
        var fetchedFollowing: [AppUser] = []
        var fetchedFollowers: [AppUser] = []
        var fetchedMutuals: [AppUser] = []
        var capturedError: Error?

        group.enter()
        firestoreService.fetchFollowing(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                fetchedFollowing = users.filter { user in
                    guard let unfollowTime = self.lastUnfollowTime[user.id] else { return true }
                    let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                    if timeSinceUnfollow < 5.0 {
                        return false
                    }
                    self.lastUnfollowTime.removeValue(forKey: user.id)
                    self.recentUnfollows.remove(user.id)
                    return true
                }
            case .failure(let error):
                capturedError = error
            }
        }

        group.enter()
        firestoreService.fetchFollowers(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                fetchedFollowers = users
            case .failure(let error):
                capturedError = error
            }
        }

        group.enter()
        firestoreService.fetchMutuals(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                fetchedMutuals = users
            case .failure(let error):
                capturedError = error
            }
        }

        group.notify(queue: .main) {
            if let capturedError {
                self.errorMessage = "Error al cargar conexiones: \(capturedError.localizedDescription)"
                self.isLoading = false
                return
            }

            self.applyConnectionSnapshots(
                userId: userId,
                followingUsers: fetchedFollowing,
                followerUsers: fetchedFollowers,
                mutualUsers: fetchedMutuals
            )
        }
    }

    private func applyConnectionSnapshots(
        userId: String,
        followingUsers: [AppUser],
        followerUsers: [AppUser],
        mutualUsers: [AppUser]
    ) {
        self.following = followingUsers
        self.followers = followerUsers
        self.mutuals = mutualUsers
        self.isLoading = false

        LocalPersistenceService.shared.saveFollowers(userId: userId, followers: followerUsers)
        LocalPersistenceService.shared.saveFollowing(userId: userId, following: followingUsers)
        LocalPersistenceService.shared.saveMutuals(userId: userId, mutuals: mutualUsers)
    }

    // ✅ FUNCIÓN EXISTENTE: Fetch visitas
    func refreshVisits() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        fetchVisits(userId: userId)
    }

    private func fetchVisits(userId: String) {
        isLoadingVisits = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoadingVisits = false }

            let grouped = await ProfileVisitsService.shared.fetchGroupedVisits(userId: userId)
            self.groupedVisits = grouped
            self.visits = grouped.map(\.user)

            var timestamps: [String: [Date]] = [:]
            for visitGroup in grouped {
                timestamps[visitGroup.user.id] = visitGroup.visits.map(\.timestamp)
            }
            self.visitTimestamps = timestamps

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let todayCount = grouped.reduce(0) { partial, group in
                partial + group.visits.filter { calendar.startOfDay(for: $0.timestamp) == today }.count
            }

            self.widgetUserDefaults?.set(todayCount, forKey: "widget_profile_visits_today")
            WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
        }
    }

    // ✅ FUNCIÓN EXISTENTE: Fetch momentos
    private func fetchMoments(userId: String) {
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
                case .success(let moments):
                    DispatchQueue.main.async {
                    self.moments = self.sortProfileMoments(moments)

                    // ✅ SwiftData: Guardar moments del perfil en caché local
                    Task { @MainActor in
                        // Usamos sync: true para purgar momentos eliminados del perfil
                        LocalPersistenceService.shared.saveProfileMoments(self.moments, userId: userId, sync: true)
                    }
                }
            case .failure(let error):
                self.errorMessage = "Error al cargar momentos: \(error.localizedDescription)"
            }
        }
    }

    private func sortProfileMoments(_ moments: [Moment]) -> [Moment] {
        moments.sorted { lhs, rhs in
            let lhsPinned = lhs.isPinned == true
            let rhsPinned = rhs.isPinned == true

            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }

            if lhsPinned, rhsPinned {
                let lhsPinnedAt = lhs.pinnedAt ?? lhs.timestamp
                let rhsPinnedAt = rhs.pinnedAt ?? rhs.timestamp
                if lhsPinnedAt != rhsPinnedAt {
                    return lhsPinnedAt > rhsPinnedAt
                }
            }

            return lhs.timestamp > rhs.timestamp
        }
    }

    func oldestPinnedMomentId(excluding momentId: String? = nil) -> String? {
        moments
            .filter { $0.isPinned == true && $0.id != momentId }
            .min(by: { ($0.pinnedAt ?? $0.timestamp) < ($1.pinnedAt ?? $1.timestamp) })?
            .id
    }

    func applyMomentPinState(momentId: String, isPinned: Bool, pinnedAt: Date) {
        moments = sortProfileMoments(
            moments.map { moment in
                guard moment.id == momentId else { return moment }
                return rebuiltMoment(
                    moment,
                    isPinned: isPinned ? true : nil,
                    pinnedAt: isPinned ? pinnedAt : nil
                )
            }
        )

        if let userId = userProfile?.id {
            LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
        }
    }

    func applyGridPreview(momentId: String, settings: MomentGridPreviewSettings) {
        moments = moments.map { moment in
            guard moment.id == momentId else { return moment }
            return momentWithGridPreview(moment, settings: settings)
        }

        if let userId = userProfile?.id {
            LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
        }
    }

    func applyPinReplacement(unpinningMomentId: String, pinningMomentId: String, pinnedAt: Date) {
        moments = sortProfileMoments(
            moments.map { moment in
                if moment.id == unpinningMomentId {
                    return rebuiltMoment(moment, isPinned: nil, pinnedAt: nil)
                }
                if moment.id == pinningMomentId {
                    return rebuiltMoment(moment, isPinned: true, pinnedAt: pinnedAt)
                }
                return moment
            }
        )

        if let userId = userProfile?.id {
            LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
        }
    }

    private func rebuiltMoment(_ moment: Moment, isPinned: Bool?, pinnedAt: Date?) -> Moment {
        Moment(
            id: moment.id,
            authorId: moment.authorId,
            username: moment.username,
            content: moment.content,
            imagePath: moment.imagePath,
            videoUrl: moment.videoUrl,
            timestamp: moment.timestamp,
            reactions: moment.reactions,
            commentCount: moment.commentCount,
            profileImagePath: moment.profileImagePath,
            taggedUsers: moment.taggedUsers,
            mentionedUsers: moment.mentionedUsers,
            location: moment.location,
            locationCoordinate: moment.locationCoordinate,
            audience: moment.audience,
            mediaItems: moment.mediaItems,
            aspectRatio: moment.aspectRatio,
            customListId: moment.customListId,
            thumbnailUrl: moment.thumbnailUrl,
            videoDuration: moment.videoDuration,
            videoFileSize: moment.videoFileSize,
            videoResolution: moment.videoResolution,
            disableComments: moment.disableComments,
            hideLikeCounts: moment.hideLikeCounts,
            allowSharing: moment.allowSharing,
            scheduledDate: moment.scheduledDate,
            isArchived: moment.isArchived,
            archivedAt: moment.archivedAt,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            gridPreviewScale: moment.gridPreviewScale,
            gridPreviewOffsetX: moment.gridPreviewOffsetX,
            gridPreviewOffsetY: moment.gridPreviewOffsetY,
            gridPreviewFitMode: moment.gridPreviewFitMode,
            gridPreviewBackground: moment.gridPreviewBackground,
            hasHiddenLayers: moment.hasHiddenLayers,
            hiddenLayerCount: moment.hiddenLayerCount,
            isModerationHidden: moment.isModerationHidden,
            originalAudience: moment.originalAudience,
            reviewRequired: moment.reviewRequired,
            canRestore: moment.canRestore
        )
    }

    private func momentWithGridPreview(_ moment: Moment, settings: MomentGridPreviewSettings) -> Moment {
        let persistedSettings = settings.isDefault ? MomentGridPreviewSettings.default : settings

        return Moment(
            id: moment.id,
            authorId: moment.authorId,
            username: moment.username,
            content: moment.content,
            imagePath: moment.imagePath,
            videoUrl: moment.videoUrl,
            timestamp: moment.timestamp,
            reactions: moment.reactions,
            commentCount: moment.commentCount,
            profileImagePath: moment.profileImagePath,
            taggedUsers: moment.taggedUsers,
            mentionedUsers: moment.mentionedUsers,
            location: moment.location,
            locationCoordinate: moment.locationCoordinate,
            audience: moment.audience,
            mediaItems: moment.mediaItems,
            aspectRatio: moment.aspectRatio,
            customListId: moment.customListId,
            thumbnailUrl: moment.thumbnailUrl,
            videoDuration: moment.videoDuration,
            videoFileSize: moment.videoFileSize,
            videoResolution: moment.videoResolution,
            disableComments: moment.disableComments,
            hideLikeCounts: moment.hideLikeCounts,
            allowSharing: moment.allowSharing,
            scheduledDate: moment.scheduledDate,
            isArchived: moment.isArchived,
            archivedAt: moment.archivedAt,
            isPinned: moment.isPinned,
            pinnedAt: moment.pinnedAt,
            gridPreviewScale: persistedSettings.isDefault ? nil : Double(persistedSettings.scale),
            gridPreviewOffsetX: persistedSettings.isDefault ? nil : Double(persistedSettings.offsetX),
            gridPreviewOffsetY: persistedSettings.isDefault ? nil : Double(persistedSettings.offsetY),
            gridPreviewFitMode: persistedSettings.isDefault ? nil : persistedSettings.fitMode.rawValue,
            gridPreviewBackground: persistedSettings.isDefault ? nil : persistedSettings.background.rawValue,
            hasHiddenLayers: moment.hasHiddenLayers,
            hiddenLayerCount: moment.hiddenLayerCount,
            isModerationHidden: moment.isModerationHidden,
            originalAudience: moment.originalAudience,
            reviewRequired: moment.reviewRequired,
            canRestore: moment.canRestore
        )
    }

    private func fetchCustomAudienceListNames(userId: String, completion: (() -> Void)? = nil) {
        firestoreService.fetchCustomLists(for: userId) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            guard case .success(let lists) = result else {
                completion?()
                return
            }

            let map = lists.reduce(into: [String: String]()) { partialResult, list in
                guard let id = list.id else { return }
                partialResult[id] = list.name
            }

            DispatchQueue.main.async {
                self.customListNamesById = map
                completion?()
            }
        }
    }

    // ✅ NUEVO: Cargar momentos donde el usuario ha sido etiquetado
    func fetchTaggedMoments(userId: String) {
        isLoadingTagged = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await BackendFeedService.shared.fetchTaggedMoments(targetUserId: userId, limit: 50)
            self.isLoadingTagged = false
            self.taggedMoments = result?.moments ?? []
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Refresh con delay para Firestore
    func refreshProfile() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        guard !isRefreshing && !isLoading else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshing = true
        }

        errorMessage = nil

        // ✅ DELAY MÍNIMO para que Firestore procese cambios recientes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performRefresh(userId: userId)
        }
    }

    // ✅ NUEVA FUNCIÓN: Perform refresh real
    private func performRefresh(userId: String) {
        let refreshGroup = DispatchGroup()
        var hasErrors = false

        // 1. Refresh perfil principal
        refreshGroup.enter()
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    self?.userProfile = profile
                    self?.profileImagePath = profile.profileImagePath
                }
            case .failure(let error):
                hasErrors = true
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al actualizar perfil: \(error.localizedDescription)"
                }
            }
            refreshGroup.leave()
        }

        // 2. Refresh conexiones con verificación directa
        refreshGroup.enter()
        self.fetchConnections(userId: userId)

        // Simular que terminó (ya que fetchConnections maneja su propio completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }

        // 3. Refresh visitas
        refreshGroup.enter()
        self.fetchVisits(userId: userId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }

        // 4. Refresh momentos
        refreshGroup.enter()
        self.fetchMoments(userId: userId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }

        // 5. Refresh nombres de listas personalizadas
        refreshGroup.enter()
        self.fetchCustomAudienceListNames(userId: userId) {
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

    // ✅ FUNCIÓN CORREGIDA: Follow user
    func followUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }


        // Limpiar unfollow reciente si existe
        recentUnfollows.remove(userId)
        lastUnfollowTime.removeValue(forKey: userId)

        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self else { return }
            let isPrivate = (try? result.get().isPrivate) ?? false

            self.firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                    return
                }

                DispatchQueue.main.async {
                    let nextState: FollowButtonState = isPrivate ? .requestPendingCancellable : .following
                    FollowStateStore.shared.setState(nextState, for: userId)

                    guard !isPrivate else { return }

                    if let follower = self.followers.first(where: { $0.id == userId }) {
                        if !self.mutuals.contains(where: { $0.id == userId }) {
                            self.mutuals.append(follower)
                        }
                    }

                    if !self.following.contains(where: { $0.id == userId }) {
                        self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                            switch result {
                            case .success(let user):
                                DispatchQueue.main.async {
                                    if self?.following.contains(where: { $0.id == user.id }) == false {
                                        self?.following.append(user)
                                    }
                                }
                            case .failure(let error):
                                self?.errorMessage = "Error al actualizar conexiones: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Unfollow user
    func unfollowUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado."
            return
        }


        // ✅ MARCAR COMO UNFOLLOW RECIENTE
        recentUnfollows.insert(userId)
        lastUnfollowTime[userId] = Date()

        self.firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Error al dejar de seguir usuario: \(error.localizedDescription)"

                // Limpiar cache de unfollow si falló
                self.recentUnfollows.remove(userId)
                self.lastUnfollowTime.removeValue(forKey: userId)
                return
            }


            // Actualizar UI inmediatamente
            DispatchQueue.main.async {
                if let mutualIndex = self.mutuals.firstIndex(where: { $0.id == userId }) {
                    self.mutuals.remove(at: mutualIndex)
                }
                if let followingIndex = self.following.firstIndex(where: { $0.id == userId }) {
                    self.following.remove(at: followingIndex)
                }
            }
        }
    }

    func cancelFollowRequest(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                self.errorMessage = "Error al cancelar solicitud: \(error!.localizedDescription)"
                return
            }

            DispatchQueue.main.async {
                FollowStateStore.shared.setState(.canRequestFollow, for: userId)
            }
        }
    }

    func removeFollower(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado."
            return
        }

        let batch = firestoreService.db.batch()
        let followerRef = firestoreService.db
            .collection("users")
            .document(currentUserId)
            .collection("followers")
            .document(userId)
        batch.deleteDocument(followerRef)

        batch.commit { [weak self] error in
            guard let self else { return }
            if let error {
                self.errorMessage = "Error al suprimir seguidor: \(error.localizedDescription)"
                return
            }

            DispatchQueue.main.async {
                if let followerIndex = self.followers.firstIndex(where: { $0.id == userId }) {
                    self.followers.remove(at: followerIndex)
                }
                if let mutualIndex = self.mutuals.firstIndex(where: { $0.id == userId }) {
                    self.mutuals.remove(at: mutualIndex)
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

    // ✅ NUEVA FUNCIÓN: Verificar estado de seguimiento real
    func verifyFollowingStatus(userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: userId) { isFollowing in
            completion(isFollowing)
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Upload profile picture (OFFLINE AWARE)
    func uploadProfilePicture(item: PhotosPickerItem) {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    DispatchQueue.main.async {
                        self.errorMessage = NSLocalizedString("profile.error.loadingImage", comment: "Error loading image")
                    }
                    return
                }

                // 1. Guardar copia local temporal
                let fileName = "temp_profile_\(UUID().uuidString).jpg"
                if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = documentsDir.appendingPathComponent(fileName)
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                        try jpegData.write(to: fileURL)

                        // 2. Delegar a LocalPersistence (Optimistic UI + Sync)
                        await LocalPersistenceService.shared.updateProfile(
                            userId: userId,
                            bio: nil,
                            website: nil,
                            interests: nil,
                            profileImageLocalPath: fileURL.path
                        )

                        // 3. Refrescar localmente (Optimistic UI ya se encarga, pero aseguramos)
                        fetchProfile(userId: userId)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error al cargar la imagen: \(error.localizedDescription)"
                }
            }
        }
    }


    // ✅ FUNCIÓN EXISTENTE: Update bio (OFFLINE AWARE)
    func updateProfileDetails(bio: String?, websiteUrl: String?, interests: [String]? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        // Delegar a LocalPersistence (Optimistic UI + Sync)
        Task {
            await LocalPersistenceService.shared.updateProfile(
                userId: userId,
                bio: bio,
                website: websiteUrl,
                interests: interests,
                profileImageLocalPath: nil
            )

            DispatchQueue.main.async {
                self.fetchProfile(userId: userId)
            }
        }
    }

    // Mantenemos updateBio por compatibilidad, pero redirigimos
    func updateBio(newBio: String) {
        updateProfileDetails(bio: newBio, websiteUrl: nil)
    }

    func updateProfileNote(_ note: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let trimmed = String(note.prefix(ProfileAvatarNoteMetrics.maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        userProfile = userProfile.map { profile in
            AppUser(
                id: profile.id,
                username: profile.username,
                email: profile.email,
                interests: profile.interests,
                isPlusSubscriber: profile.isPlusSubscriber,
                profileImagePath: profile.profileImagePath,
                bio: profile.bio,
                blockedUsers: profile.blockedUsers,
                isPrivate: profile.isPrivate,
                showMutuals: profile.showMutuals,
                showFollowing: profile.showFollowing,
                showFollowers: profile.showFollowers,
                activeHoursStart: profile.activeHoursStart,
                activeHoursEnd: profile.activeHoursEnd,
                notificationPreferences: profile.notificationPreferences,
                bestFriends: profile.bestFriends,
                websiteUrl: profile.websiteUrl,
                profileNote: trimmed.isEmpty ? nil : trimmed,
                followersCount: profile.followersCount,
                followingCount: profile.followingCount,
                momentsCount: profile.momentsCount,
                isActive: profile.isActive,
                deactivatedAt: profile.deactivatedAt,
                deactivatedBy: profile.deactivatedBy,
                ownedBadges: profile.ownedBadges,
                plusSubscription: profile.plusSubscription,
                primaryBadgeId: profile.primaryBadgeId,
                showBadge: profile.showBadge,
                showPlusBadge: profile.showPlusBadge,
                selectedProfileTheme: profile.selectedProfileTheme,
                isVerified: profile.isVerified,
                onlineStatus: profile.onlineStatus,
                lastSeen: profile.lastSeen,
                isOnline: profile.isOnline,
                showReadReceipts: profile.showReadReceipts,
                lastUsernameChange: profile.lastUsernameChange
            )
        }

        firestoreService.updateProfileNote(userId: userId, note: trimmed) { [weak self] error in
            Task { @MainActor in
                if error != nil {
                    self?.fetchProfile(userId: userId)
                }
            }
        }
    }
}
