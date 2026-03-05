import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct GroupedPerspective: Identifiable {
    var id: String { authorId }
    let authorId: String
    let username: String
    let profileImagePath: String?
    var moments: [EchoMomentRef]
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
        echo?.participants.filter { $0.status == .accepted }.count ?? 0
    }
    
    var isEchoActive: Bool {
        acceptedCount >= 2
    }
    
    // Legacy helper to keep some UI code working or for flat preloading
    var allMoments: [EchoMomentRef] {
        groupedPerspectives.flatMap { $0.moments }
    }
    
    // Current active moment helper
    var currentMoment: EchoMomentRef? {
        guard isEchoActive else { return nil }
        guard currentPerspectiveIndex < groupedPerspectives.count,
              currentVerticalIndex < groupedPerspectives[currentPerspectiveIndex].moments.count else {
            return nil
        }
        return groupedPerspectives[currentPerspectiveIndex].moments[currentVerticalIndex]
    }
    
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
        
        // Si no hay al menos 2 personas que hayan aceptado, no mostramos NADA (o solo mis momentos para pre-view personal)
        // Pero siguiendo la regla estricta: No hay Echo activo hasta que hay 2 aceptados.
        guard isEchoActive else {
            self.groupedPerspectives = []
            return
        }
        
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        
        // 1. Filtrado Estricto de Momentos:
        // - Veo mis propios momentos (aunque esté pending, pero ahora todos empiezan pending)
        // - Veo los momentos de los demás SOLO si ellos han aceptado (.accepted)
        var rawMoments = echo.moments.filter { moment in
            if moment.authorId == currentUserId {
                // Si el usuario actual ha aceptado, ve sus momentos.
                // Si aún no ha aceptado, también los ve (es su propia cámara)
                return true
            } else {
                // Solo ve lo de los demás si ellos han aceptado
                return echo.participants.contains { $0.userId == moment.authorId && $0.status == .accepted }
            }
        }
        
        // 2. Group by authorId
        let grouped = Dictionary(grouping: rawMoments) { $0.authorId }
        
        // 3. Convert to GroupedPerspective and Sort
        var perspectives: [GroupedPerspective] = grouped.map { (authorId, moments) in
            let first = moments[0]
            let participant = echo.participants.first(where: { $0.userId == authorId })
            
            return GroupedPerspective(
                authorId: authorId,
                username: participant?.username ?? first.username,
                profileImagePath: participant?.profileImagePath,
                moments: moments.sorted { $0.timestamp < $1.timestamp }
            )
        }
        
        // 4. Sort perspectives: Me first, then by earliest moment
        perspectives.sort { p1, p2 in
            if p1.authorId == currentUserId { return true }
            if p2.authorId == currentUserId { return false }
            
            let t1 = p1.moments.first?.timestamp ?? Date()
            let t2 = p2.moments.first?.timestamp ?? Date()
            return t1 < t2
        }
        
        self.groupedPerspectives = perspectives
    }
    
    private func preloadMedia() {
        let moments = allMoments
        guard !moments.isEmpty else { return }
        
        let urls = moments.compactMap { URL(string: $0.mediaUrl) }
        let thumbUrls = moments.compactMap { $0.thumbnailUrl.flatMap { URL(string: $0) } }
        
        ImagePrefetchManager.shared.prefetch(urls: urls + thumbUrls)
        
        let videoUrls = moments.filter { $0.mediaType == "video" }.map { $0.mediaUrl }
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
                
                // 2. Solo activar video si el primer momento de la nueva persona es video
                if let firstMoment = self.groupedPerspectives[index].moments.first, firstMoment.mediaType == "video" {
                    self.isVideoPlaying = true
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.ripplePhase = 0
        }
    }
    
    func switchVerticalIndex(to index: Int) {
        guard currentPerspectiveIndex < groupedPerspectives.count else { return }
        let moments = groupedPerspectives[currentPerspectiveIndex].moments
        guard index >= 0 && index < moments.count else { return }
        
        // 1. Apagar video antes de cambiar el índice para frenar el audio del actual
        isVideoPlaying = false
        
        // 🚀 Delay sutil para que el player actual reciba el 'pause' antes de ser desmontado
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeOut(duration: 0.22)) {
                self.currentVerticalIndex = index
                
                // 2. Solo activar video si el siguiente momento es un video
                if moments[index].mediaType == "video" {
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
            if momentRef.authorId == currentUserId {
                self.momentAvailability[momentRef.momentId] = true
                continue
            }
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
                    DispatchQueue.main.async { self.momentAvailability[momentRef.momentId] = false }
                    return
                }
                
                let audience = momentRef.audience ?? "everyone"
                
                if audience == "everyone" || audience == "connections" {
                    DispatchQueue.main.async { self.momentAvailability[momentRef.momentId] = true }
                } else if audience == "bestFriends" {
                    privacyService.checkIfBestFriend(userId: momentRef.authorId, friendId: viewerId) { isBestFriend in
                        DispatchQueue.main.async { self.momentAvailability[momentRef.momentId] = isBestFriend }
                    }
                } else if audience == "custom" || audience == "customList" {
                    let moment = try? snapshot?.data(as: Moment.self)
                    if let moment = moment {
                        privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                            DispatchQueue.main.async { self.momentAvailability[momentRef.momentId] = canView }
                        }
                    } else {
                        DispatchQueue.main.async { self.momentAvailability[momentRef.momentId] = false }
                    }
                }
            }
    }
}
