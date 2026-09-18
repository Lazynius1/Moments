import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct GroupedPerspective: Identifiable {
    var id: String { authorId }
    let authorId: String
    let username: String
    let profileImagePath: String?
    /// Refs planas (validación / preload).
    var moments: [EchoMomentRef]
    /// Posts únicos: un carrusel por `momentId` (no una capa por slide).
    var posts: [EchoDeckPost]
}

/// Un momento del Echo (puede tener varias medias = carrusel).
struct EchoDeckPost: Identifiable {
    var id: String { momentId }
    let momentId: String
    let authorId: String
    let username: String
    let timestamp: Date
    let aspectRatio: String?
    let slides: [EchoMomentRef]
}

class EchoViewModel: ObservableObject {
    @Published var echo: Echo?
    @Published var isLoading = true
    
    // 2D Navigation indices
    @Published var currentPerspectiveIndex = 0
    @Published var currentVerticalIndex = 0
    
    @Published var isVideoPlaying = true
    @Published var ripplePhase = 0.0
    
    // ✅ Grouped Moments: One entry per friend, containing 1+ moments
    @Published var groupedPerspectives: [GroupedPerspective] = []
    
    // ✅ Social Threshold: 2+ accepted participants
    var acceptedCount: Int {
        acceptedParticipantMomentCount
    }
    
    var acceptedParticipantMomentCount: Int {
        guard let echo = echo else { return 0 }
        let acceptedIds = Set(echo.participants.filter { $0.status == .accepted }.map(\.userId))
        let momentAuthorIds = Set(echo.moments.map(\.authorId))
        return acceptedIds.intersection(momentAuthorIds).count
    }
    
    var isEchoActive: Bool {
        acceptedCount >= 2 && (echo?.hasMinimumMomentParticipants ?? false)
    }
    
    var hasExpired: Bool {
        guard let echo = echo else { return false }
        return echo.expiresAt <= Date()
    }
    
    var isHistoricalIncomplete: Bool {
        guard let echo = echo else { return false }
        return hasExpired && !echo.hasMinimumMomentParticipants
    }
    
    var canOpenLocationMap: Bool {
        !isHistoricalIncomplete
    }
    
    var canBrowseMedia: Bool {
        isEchoActive || isHistoricalIncomplete
    }
    
    // Legacy helper to keep some UI code working or for flat preloading
    var allMoments: [EchoMomentRef] {
        groupedPerspectives.flatMap { $0.moments }
    }
    
    // Current active post (ángulo + índice vertical de posts, no de slides)
    var currentPost: EchoDeckPost? {
        guard canBrowseMedia else { return nil }
        guard currentPerspectiveIndex < groupedPerspectives.count else { return nil }
        let posts = groupedPerspectives[currentPerspectiveIndex].posts
        guard currentVerticalIndex < posts.count else { return nil }
        return posts[currentVerticalIndex]
    }

    /// Primera slide del post actual (compat media / video flag).
    var currentMoment: EchoMomentRef? {
        guard let post = currentPost else { return nil }
        return visibleSlides(for: post).first ?? post.slides.first
    }

    /// Paridad feed `visibleMediaItems`: saca del carrusel las slides ocultas por moderación.
    func visibleSlides(for post: EchoDeckPost) -> [EchoMomentRef] {
        guard let moment = postMoments[post.momentId] else { return post.slides }
        let visible = moment.visibleMediaItems
        if (moment.mediaItems ?? []).isEmpty && visible.isEmpty {
            return post.slides
        }
        let urls = Set(visible.map(\.url))
        return post.slides.filter { urls.contains($0.mediaUrl) }
    }

    /// Caption denormalizado cargado desde el documento del momento.
    @Published var postCaptions: [String: String] = [:]
    @Published var postAspectRatios: [String: String] = [:]
    /// Momento completo (para CroppedVideoPlayer / mediaItems del feed).
    @Published var postMoments: [String: Moment] = [:]

    // ✅ NUEVO: Estado de disponibilidad en vivo (momentId -> isAvailable)
    @Published var momentAvailability: [String: Bool] = [:]
    
    private let db = Firestore.firestore()
    private var echoId: String
    private var listener: ListenerRegistration?
    
    init(echoId: String, initialEcho: Echo? = nil) {
        self.echoId = echoId
        if let initial = initialEcho {
            self.echo = initial
            self.isLoading = false
            self.updateDisplayedMoments()
            self.validateMomentsLive()
            self.preloadMedia()
        }
    }
    
    deinit {
        listener?.remove()
    }
    
    func loadEcho() {
        isLoading = true
        listener?.remove()
        
        listener = db.collection("echoes").document(echoId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let data = snapshot, data.exists {
                do {
                    var fetchedEcho = try data.data(as: Echo.self)
                    // ✅ FALLBACK MANUAL: Si @DocumentID no se inyectó, lo forzamos con el ID del documento
                    if fetchedEcho.id == nil {
                        fetchedEcho.id = data.documentID
                    }
                    
                    self.echo = fetchedEcho
                    self.updateDisplayedMoments()
                    self.validateMomentsLive()
                    self.isLoading = false
                    self.preloadMedia()
                    
                    if let echo = self.echo, echo.participantIds.isEmpty {
                        EchoService.shared.repairEcho(echo)
                    }
                } catch {
                    print("Error decoding Echo in ViewModel: \(error)")
                    self.isLoading = false
                }
            } else {
                self.isLoading = false
            }
        }
    }
    
    private func updateDisplayedMoments() {
        guard let echo = echo else { return }
        
        guard isEchoActive || isHistoricalIncomplete else {
            self.groupedPerspectives = []
            return
        }
        
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        
        // 1. Filtrado Estricto de Momentos:
        // - Veo mis propios momentos (aunque esté pending, pero ahora todos empiezan pending)
        // - Veo los momentos de los demás SOLO si ellos han aceptado (.accepted)
        let rawMoments = echo.moments.filter { moment in
            if isHistoricalIncomplete {
                return echo.participantIds.contains(moment.authorId)
            }
            if moment.authorId == currentUserId {
                return true
            }
            return echo.participants.contains { $0.userId == moment.authorId && $0.status == .accepted }
        }
        
        // 2. Group by authorId
        let grouped = Dictionary(grouping: rawMoments) { $0.authorId }
        
        // 3. Convert to GroupedPerspective and Sort
        var perspectives: [GroupedPerspective] = grouped.map { (authorId, moments) in
            let first = moments[0]
            let participant = echo.participants.first(where: { $0.userId == authorId })
            let ordered = moments.sorted { $0.timestamp < $1.timestamp }

            return GroupedPerspective(
                authorId: authorId,
                username: participant?.username ?? first.username,
                profileImagePath: participant?.profileImagePath,
                moments: ordered,
                posts: Self.posts(from: ordered)
            )
        }
        
        // 4. Sort perspectives: Me first, then by earliest moment
        perspectives.sort { p1, p2 in
            if p1.authorId == currentUserId { return true }
            if p2.authorId == currentUserId { return false }
            
            let t1 = p1.posts.first?.timestamp ?? Date()
            let t2 = p2.posts.first?.timestamp ?? Date()
            return t1 < t2
        }
        
        self.groupedPerspectives = perspectives
        if currentPerspectiveIndex >= groupedPerspectives.count {
            currentPerspectiveIndex = max(0, groupedPerspectives.count - 1)
        }
        if currentPerspectiveIndex < groupedPerspectives.count {
            let visiblePosts = groupedPerspectives[currentPerspectiveIndex].posts
            if currentVerticalIndex >= visiblePosts.count {
                currentVerticalIndex = max(0, visiblePosts.count - 1)
            }
            if let post = currentPost {
                loadPostDetailsIfNeeded(post)
            }
        } else {
            currentVerticalIndex = 0
        }
    }

    private static func posts(from refs: [EchoMomentRef]) -> [EchoDeckPost] {
        var order: [String] = []
        var buckets: [String: [EchoMomentRef]] = [:]
        for ref in refs {
            if buckets[ref.momentId] == nil {
                order.append(ref.momentId)
                buckets[ref.momentId] = []
            }
            buckets[ref.momentId]?.append(ref)
        }
        return order.compactMap { momentId in
            guard let slides = buckets[momentId], let first = slides.first else { return nil }
            return EchoDeckPost(
                momentId: momentId,
                authorId: first.authorId,
                username: first.username,
                timestamp: first.timestamp,
                aspectRatio: first.aspectRatio,
                slides: slides
            )
        }
    }

    func loadPostDetailsIfNeeded(_ post: EchoDeckPost) {
        if postMoments[post.momentId] != nil {
            if postCaptions[post.momentId] == nil {
                postCaptions[post.momentId] = postMoments[post.momentId]?.content ?? ""
            }
            return
        }
        db.collection("users").document(post.authorId)
            .collection("moments").document(post.momentId)
            .getDocument { [weak self] snapshot, _ in
                guard let self else { return }
                let moment = try? snapshot?.data(as: Moment.self)
                DispatchQueue.main.async {
                    self.applyLoadedMoment(moment, fallbackPost: post)
                }
            }
    }

    func playbackMoment(for post: EchoDeckPost) -> Moment {
        if let moment = postMoments[post.momentId] { return moment }
        return Self.stubMoment(from: post, caption: postCaptions[post.momentId] ?? "")
    }

    private func applyLoadedMoment(_ moment: Moment?, fallbackPost: EchoDeckPost) {
        if let moment {
            postMoments[fallbackPost.momentId] = moment
            postCaptions[fallbackPost.momentId] = moment.content
            if let ratio = moment.aspectRatio, !ratio.isEmpty {
                postAspectRatios[fallbackPost.momentId] = ratio
            } else if let existing = fallbackPost.aspectRatio {
                postAspectRatios[fallbackPost.momentId] = existing
            }
        } else {
            postCaptions[fallbackPost.momentId] = postCaptions[fallbackPost.momentId] ?? ""
            if let existing = fallbackPost.aspectRatio {
                postAspectRatios[fallbackPost.momentId] = existing
            }
            setMoment(fallbackPost.momentId, available: false)
        }
    }

    private static func stubMoment(from post: EchoDeckPost, caption: String) -> Moment {
        let mediaItems = post.slides.map { slide -> MediaItem in
            MediaItem(
                type: slide.mediaType == "video" ? .video : .image,
                url: slide.mediaUrl,
                aspectRatio: slide.aspectRatio ?? post.aspectRatio,
                thumbnailUrl: slide.thumbnailUrl
            )
        }
        let firstVideo = post.slides.first(where: { $0.mediaType == "video" })
        let firstImage = post.slides.first(where: { $0.mediaType != "video" })
        return Moment(
            id: post.momentId,
            authorId: post.authorId,
            username: post.username,
            content: caption,
            imagePath: firstImage?.mediaUrl,
            videoUrl: firstVideo?.mediaUrl,
            timestamp: post.timestamp,
            reactions: [:],
            commentCount: 0,
            profileImagePath: nil,
            taggedUsers: nil,
            location: nil,
            audience: post.slides.first?.audience,
            mediaItems: mediaItems,
            aspectRatio: post.aspectRatio,
            customListId: post.slides.first?.customListId,
            thumbnailUrl: post.slides.first?.thumbnailUrl,
            videoDuration: nil,
            videoFileSize: nil,
            videoResolution: nil,
            disableComments: false,
            hideLikeCounts: false,
            allowSharing: true
        )
    }
    
    private func preloadMedia() {
        let moments = allMoments
        guard !moments.isEmpty else { return }

        // Acotar a una ventana inicial para evitar descargas masivas full-res
        // y llenado de disco/red cuando hay decenas/cientos de ecos.
        let mediaWindow = 6
        let thumbWindow = 12

        let mediaSlice = Array(moments.prefix(mediaWindow))
        let thumbSlice = Array(moments.prefix(thumbWindow))

        // Thumbnails (ligeros) en una ventana más amplia.
        let thumbUrls = thumbSlice.compactMap { $0.thumbnailUrl.flatMap { URL(string: $0) } }
        // Media principal (pesada) en ventana estrecha, solo imágenes.
        let imageUrls = mediaSlice
            .filter { $0.mediaType != "video" }
            .compactMap { URL(string: $0.mediaUrl) }

        ImagePrefetchManager.shared.prefetch(urls: thumbUrls + imageUrls)

        let videoUrls = mediaSlice.filter { $0.mediaType == "video" }.map { $0.mediaUrl }
        VideoPreloader.shared.preloadAssets(urls: videoUrls)
    }
    
    func switchPerspective(to index: Int) {
        guard index >= 0 && index < groupedPerspectives.count else { return }
        
        // 1. Apagar video antes de cambiar para evitar leak de audio
        isVideoPlaying = false
        
        // 🚀 Agregamos un pequeñísimo delay igual que en StoriesView para asegurar cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeInOut(duration: 0.24)) {
                self.currentPerspectiveIndex = index
                self.currentVerticalIndex = 0 // ✅ Reset vertical index when changing person / Reset a 0
                self.ripplePhase = 0
                
                if let firstPost = self.groupedPerspectives[index].posts.first {
                    self.loadPostDetailsIfNeeded(firstPost)
                    if let firstSlide = firstPost.slides.first,
                       firstSlide.mediaType == "video",
                       self.momentAvailability[firstPost.momentId] != false {
                        self.isVideoPlaying = true
                    }
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.ripplePhase = 0
        }
    }
    
    func switchVerticalIndex(to index: Int) {
        guard currentPerspectiveIndex < groupedPerspectives.count else { return }
        let posts = groupedPerspectives[currentPerspectiveIndex].posts
        guard index >= 0 && index < posts.count else { return }
        
        isVideoPlaying = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeOut(duration: 0.22)) {
                self.currentVerticalIndex = index
                let post = posts[index]
                self.loadPostDetailsIfNeeded(post)
                if let firstSlide = post.slides.first,
                   firstSlide.mediaType == "video",
                   self.momentAvailability[post.momentId] != false {
                    self.isVideoPlaying = true
                }
            }
        }
    }
    
    // ✅ LIVE PRIVACY VALIDATION
    private func validateMomentsLive() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let privacyService = PrivacyService.shared
        
        for momentRef in allMoments {
            validateSingleMoment(momentRef: momentRef, viewerId: currentUserId, privacyService: privacyService)
        }
    }
    
    private func validateSingleMoment(momentRef: EchoMomentRef, viewerId: String, privacyService: PrivacyService) {
        let db = Firestore.firestore()
        db.collection("users").document(momentRef.authorId)
            .collection("moments").document(momentRef.momentId)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                
                guard snapshot?.exists == true else {
                    DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: false) }
                    return
                }

                let moment = try? snapshot?.data(as: Moment.self)
                if moment?.isArchived == true {
                    DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: false) }
                    return
                }

                if momentRef.authorId == viewerId {
                    DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: true) }
                    return
                }

                DispatchQueue.main.async {
                    if let moment {
                        self.postMoments[momentRef.momentId] = moment
                        self.postCaptions[momentRef.momentId] = moment.content
                        if let ratio = moment.aspectRatio, !ratio.isEmpty {
                            self.postAspectRatios[momentRef.momentId] = ratio
                        }
                    }
                }
                
                let audience = momentRef.audience ?? "everyone"
                
                if audience == "everyone" || audience == "mutuals" {
                    DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: true) }
                } else if audience == "bestFriends" {
                    privacyService.checkIfBestFriend(userId: momentRef.authorId, friendId: viewerId) { isBestFriend in
                        DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: isBestFriend) }
                    }
                } else if audience == "custom" || audience == "customList" {
                    if let moment {
                        privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                            DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: canView) }
                        }
                    } else {
                        DispatchQueue.main.async { self.setMoment(momentRef.momentId, available: false) }
                    }
                }
            }
    }

    private func setMoment(_ momentId: String, available: Bool) {
        momentAvailability[momentId] = available
        if !available, currentMoment?.momentId == momentId {
            isVideoPlaying = false
        }
    }
}
