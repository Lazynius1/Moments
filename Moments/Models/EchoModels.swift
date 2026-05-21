import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - Echo Status
enum EchoStatus: String, Codable {
    case pending = "pending"   // Waiting for participants to accept
    case active = "active"     // At least two participants accepted
    case expired = "expired"   // Time window closed
    case completed = "completed" // Story published
}

enum EchoParticipantStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

// MARK: - Echo Participant
struct EchoParticipant: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let username: String
    let profileImagePath: String?
    var status: EchoParticipantStatus
    
    enum CodingKeys: String, CodingKey {
        case userId, username, profileImagePath, status
    }
}

// MARK: - Echo Moment Reference
struct EchoMomentRef: Codable {
    let momentId: String
    let authorId: String
    let username: String // ✅ NUEVO
    let timestamp: Date
    let mediaType: String
    let mediaUrl: String
    let aspectRatio: String?     // ✅ NUEVO: Para manejo de orientación (fit/fill)
    let thumbnailUrl: String?    // ✅ NUEVO: Para pre-visualización y blur background
    let audience: String?        // ✅ NUEVO: Para validación de privacidad en vivo
    let customListId: String?    // ✅ NUEVO: Para validación de listas personalizadas
    
    enum CodingKeys: String, CodingKey {
        case momentId, authorId, username, timestamp, mediaType, mediaUrl, aspectRatio, thumbnailUrl, audience, customListId
    }
    
    init(from moment: Moment) {
        self.momentId = moment.id ?? ""
        self.authorId = moment.authorId
        self.username = moment.username
        self.timestamp = moment.timestamp
        self.mediaType = moment.videoUrl != nil ? "video" : "image"
        self.mediaUrl = moment.videoUrl ?? moment.imagePath ?? ""
        self.aspectRatio = moment.aspectRatio
        self.thumbnailUrl = moment.thumbnailUrl
        self.audience = moment.audience
        self.customListId = moment.customListId
    }
    
    // ✅ NUEVO: Inicializador desde un MediaItem específico (para momentos con múltiples archivos)
    init(from mediaItem: MediaItem, author: Moment) {
        self.momentId = author.id ?? ""
        self.authorId = author.authorId
        self.username = author.username
        self.timestamp = author.timestamp
        self.mediaType = mediaItem.type == .video ? "video" : "image"
        self.mediaUrl = mediaItem.url
        self.aspectRatio = author.aspectRatio // Opcional: Podríamos sacar el de la media si existiera
        self.thumbnailUrl = mediaItem.thumbnailUrl
        self.audience = author.audience
        self.customListId = author.customListId
    }
}

// MARK: - Echo Model
struct Echo: Identifiable, Codable {
    @DocumentID var id: String?
    let hostId: String // The user who triggered the detection
    var participants: [EchoParticipant]
    let location: Moment.LocationCoordinate
    let locationName: String?
    let createdAt: Date
    let expiresAt: Date
    var status: EchoStatus
    var moments: [EchoMomentRef]
    var vibeSummary: String? // IA Generated summary
    var participantIds: [String] // Flat array for Firestore arrayContains queries
    
    enum CodingKeys: String, CodingKey {
        case id, hostId, participants, location, locationName, createdAt, expiresAt, status, moments, vibeSummary, participantIds
    }
    
    // ✅ Propiedad calculada: Momentos visibles (de participantes que han aceptado)
    // NOTA: El ViewModel aplica un filtro adicional para que cada uno vea los suyos propios
    var visibleMoments: [EchoMomentRef] {
        let acceptedUserIds = Set(participants.filter { $0.status == .accepted }.map { $0.userId })
        return moments.filter { acceptedUserIds.contains($0.authorId) }
    }
    
    init(id: String? = nil, hostId: String, participants: [EchoParticipant], location: Moment.LocationCoordinate, locationName: String?, moments: [EchoMomentRef] = []) {
        self.id = id
        self.hostId = hostId
        self.participants = participants
        self.location = location
        self.locationName = locationName
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(86400) // 24 hours window (Updated from 2h)
        self.status = .pending
        self.moments = moments
        self.participantIds = participants.map { $0.userId }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // self.id = try container.decodeIfPresent(String.self, forKey: .id) // ❌ QUITADO: @DocumentID no se decodifica del container
        self.hostId = try container.decode(String.self, forKey: .hostId)
        self.participants = try container.decode([EchoParticipant].self, forKey: .participants)
        self.location = try container.decode(Moment.LocationCoordinate.self, forKey: .location)
        self.locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        
        let createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        self.createdAt = createdAt.dateValue()
        
        let expiresAt = try container.decode(Timestamp.self, forKey: .expiresAt)
        self.expiresAt = expiresAt.dateValue()
        
        self.status = try container.decode(EchoStatus.self, forKey: .status)
        self.moments = try container.decode([EchoMomentRef].self, forKey: .moments)
        self.vibeSummary = try container.decodeIfPresent(String.self, forKey: .vibeSummary)
        self.participantIds = try container.decodeIfPresent([String].self, forKey: .participantIds) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // try container.encodeIfPresent(id, forKey: .id) // ❌ QUITADO: @DocumentID no se codifica en el container
        try container.encode(hostId, forKey: .hostId)
        try container.encode(participants, forKey: .participants)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
        try container.encode(Timestamp(date: expiresAt), forKey: .expiresAt)
        try container.encode(status, forKey: .status)
        try container.encode(moments, forKey: .moments)
        try container.encodeIfPresent(vibeSummary, forKey: .vibeSummary)
        try container.encode(participantIds, forKey: .participantIds)
    }
}
