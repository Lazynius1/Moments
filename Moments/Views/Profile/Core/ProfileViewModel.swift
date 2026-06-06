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
    @Published var visitTimestamps: [String: [Date]] = [:]
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
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
                case .failure(_):
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
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
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty {
            self.categorizeConnections(
                userId: userId,
                followingIds: cachedConnections.following.map { $0.id },
                followerIds: cachedConnections.followers.map { $0.id }
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

        // Primero obtener following directamente de Firestore
        let db = firestoreService.db
        db.collection("users").document(userId).collection("following")
            .getDocuments { [weak self] followingSnapshot, error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    if let error = error {
                        self.errorMessage = "Error al cargar conexiones: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }

                    let followingIds = followingSnapshot?.documents.compactMap { doc in
                        doc.data()["userId"] as? String
                    } ?? []


                    // Filtrar unfollows recientes
                    let filteredFollowingIds = followingIds.filter { userId in
                        if let unfollowTime = self.lastUnfollowTime[userId] {
                            // Si el unfollow fue hace menos de 5 segundos, no incluir
                            let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                            if timeSinceUnfollow < 5.0 {
                                return false
                            } else {
                                // Limpiar el cache después de 5 segundos
                                self.lastUnfollowTime.removeValue(forKey: userId)
                                self.recentUnfollows.remove(userId)
                            }
                        }
                        return true
                    }


                    // Luego obtener followers
                    let db2 = self.firestoreService.db
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            let followersSnapshot = try await db2
                                .collection("users")
                                .document(userId)
                                .collection("followers")
                                .getDocuments()

                            let followerIds = followersSnapshot.documents.compactMap { doc in
                                doc.data()["userId"] as? String
                            }

                            // Categorizar conexiones con IDs filtrados
                            self.categorizeConnections(
                                userId: userId,
                                followingIds: filteredFollowingIds,
                                followerIds: followerIds
                            )
                        } catch {
                            self.errorMessage = "Error al cargar admiradores: \(error.localizedDescription)"
                            self.isLoading = false
                        }
                    }
                }
            }
    }

    // ✅ NUEVA FUNCIÓN: Categorizar conexiones
    private func categorizeConnections(userId: String, followingIds: [String], followerIds: [String]) {
        let followingSet = Set(followingIds)
        let followersSet = Set(followerIds)

        let mutualIds = followingSet.intersection(followersSet)
        let connectionIds = followingSet.subtracting(mutualIds)
        let admirerIds = followersSet.subtracting(mutualIds)


        let fetchGroup = DispatchGroup()

        // Fetch mutuos
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(mutualIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.mutualConnections = users
            }
            fetchGroup.leave()
        }

        // Fetch conexiones
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(connectionIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.connections = users
            }
            fetchGroup.leave()
        }

        // Fetch admiradores
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(admirerIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.admirers = users
                self?.isLoading = false
            }
            fetchGroup.leave()
        }

        fetchGroup.notify(queue: .main) {
            // ✅ SwiftData: Guardar en caché local
            let allFollowers = self.mutualConnections + self.admirers
            let allFollowing = self.mutualConnections + self.connections
            LocalPersistenceService.shared.saveFollowers(userId: userId, followers: allFollowers)
            LocalPersistenceService.shared.saveFollowing(userId: userId, following: allFollowing)
        }
    }

    // ✅ FUNCIÓN EXISTENTE: Fetch visitas
    private func fetchVisits(userId: String) {
        firestoreService.fetchVisits(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let visits):
                let visitorIds = visits.map { $0.visitorId }
                self.fetchUsersInBatches(userIds: visitorIds) { users in
                    DispatchQueue.main.async {
                        self.visits = users

                        // Actualizar timestamps
                        var timestamps: [String: [Date]] = [:]
                        for visit in visits {
                            if timestamps[visit.visitorId] == nil {
                                timestamps[visit.visitorId] = []
                            }
                            timestamps[visit.visitorId]?.append(visit.timestamp)
                        }
                        self.visitTimestamps = timestamps

                         // 🔄 Actualizar contador de visitas de hoy para el widget
                         let calendar = Calendar.current
                         let today = calendar.startOfDay(for: Date())
                         let todayCount = visits.filter { visit in
                             let visitDay = calendar.startOfDay(for: visit.timestamp)
                             return visitDay == today
                         }.count

                         self.widgetUserDefaults?.set(todayCount, forKey: "widget_profile_visits_today")
                         WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
                    }
                }
            case .failure(let error):
                self.errorMessage = "Error al cargar visitas: \(error.localizedDescription)"
            }
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
            trendingScore: moment.trendingScore,
            engagementRate: moment.engagementRate,
            isArchived: moment.isArchived,
            archivedAt: moment.archivedAt,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
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

        self.firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                return
            }


            // Actualizar UI inmediatamente
            DispatchQueue.main.async {
                if let admirerIndex = self.admirers.firstIndex(where: { $0.id == userId }) {
                    let user = self.admirers[admirerIndex]
                    self.admirers.remove(at: admirerIndex)
                    self.mutualConnections.append(user)
                } else {
                    // Obtener usuario y agregarlo a conexiones
                    self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                        switch result {
                        case .success(let user):
                            DispatchQueue.main.async {
                                self?.connections.append(user)
                            }
                        case .failure(let error):
                            self?.errorMessage = "Error al actualizar conexiones: \(error.localizedDescription)"
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
                if let mutualIndex = self.mutualConnections.firstIndex(where: { $0.id == userId }) {
                    let user = self.mutualConnections[mutualIndex]
                    self.mutualConnections.remove(at: mutualIndex)
                    self.admirers.append(user)
                } else if let connectionIndex = self.connections.firstIndex(where: { $0.id == userId }) {
                    self.connections.remove(at: connectionIndex)
                }
            }
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
}
