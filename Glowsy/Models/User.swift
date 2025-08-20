import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Online Status Enum
enum OnlineStatus: String, CaseIterable, Codable {
    case online = "online"
    case away = "away"
    case busy = "busy"
    case offline = "offline"
    case invisible = "invisible"
    
    var displayName: String {
        switch self {
        case .online: return "En línea"
        case .away: return "Ausente"
        case .busy: return "Ocupado"
        case .offline: return "Desconectado"
        case .invisible: return "Invisible"
        }
    }
    
    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .busy: return "exclamationmark.circle.fill"
        case .offline: return "circle"
        case .invisible: return "eye.slash.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .online: return .green
        case .away: return .orange
        case .busy: return .red
        case .offline: return .gray
        case .invisible: return .gray
        }
    }
}

struct AppUser: Identifiable, Codable {
    let id: String
    let username: String
    let email: String
    let interests: [String]
    let isPlusSubscriber: Bool
    let profileImagePath: String?
    let bio: String?
    let blockedUsers: [String]
    let isPrivate: Bool
    let showMutualConnections: Bool
    let showFollowing: Bool
    let showAdmirers: Bool
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let notificationPreferences: [String: Bool]?
    let bestFriends: [String]
    
    // ✅ NUEVO: Campo para estado de cuenta
    let isActive: Bool
    let deactivatedAt: Date?
    let deactivatedBy: String?
    
    // ✅ NUEVO: Campos para sistema de badges
    let ownedBadges: [UserBadge]
    let plusSubscription: PlusSubscription?
    
    // ✅ NUEVO: Campos para preferencias de badge
    let primaryBadgeId: String?
    let showBadge: Bool
    let showPlusBadge: Bool // ✅ NUEVO: Para ocultar el badge Plus
    
    // ✅ NUEVO: Campo para tema de perfil
    let selectedProfileTheme: String?
    
    // ✅ NUEVO: Campo para verificación de perfil
    let isVerified: Bool
    
    // ✅ NUEVO: Campos para estado en línea
    let onlineStatus: OnlineStatus
    let lastSeen: Date?
    let isOnline: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case interests
        case isPlusSubscriber
        case profileImagePath
        case bio
        case blockedUsers
        case isPrivate
        case showMutualConnections
        case showFollowing
        case showAdmirers
        case activeHoursStart
        case activeHoursEnd
        case notificationPreferences
        case bestFriends
        case isActive
        case deactivatedAt
        case deactivatedBy
        case ownedBadges
        case plusSubscription
        case primaryBadgeId
        case showBadge
        case showPlusBadge
        case selectedProfileTheme
        case isVerified
        case onlineStatus
        case lastSeen
        case isOnline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.username = (try container.decodeIfPresent(String.self, forKey: .username)) ?? "Usuario Desconocido"
        self.email = (try container.decodeIfPresent(String.self, forKey: .email)) ?? ""
        self.interests = (try container.decodeIfPresent([String].self, forKey: .interests)) ?? []
        self.isPlusSubscriber = (try container.decodeIfPresent(Bool.self, forKey: .isPlusSubscriber)) ?? false
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.blockedUsers = (try container.decodeIfPresent([String].self, forKey: .blockedUsers)) ?? []
        self.isPrivate = (try container.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? false
        self.showMutualConnections = (try container.decodeIfPresent(Bool.self, forKey: .showMutualConnections)) ?? true
        self.showFollowing = (try container.decodeIfPresent(Bool.self, forKey: .showFollowing)) ?? true
        self.showAdmirers = (try container.decodeIfPresent(Bool.self, forKey: .showAdmirers)) ?? true
        self.activeHoursStart = try container.decodeIfPresent(String.self, forKey: .activeHoursStart)
        self.activeHoursEnd = try container.decodeIfPresent(String.self, forKey: .activeHoursEnd)
        self.notificationPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .notificationPreferences)
        self.bestFriends = (try container.decodeIfPresent([String].self, forKey: .bestFriends)) ?? []
        
        // ✅ NUEVO: Decodificación de campos de activación
        self.isActive = (try container.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
        
        // Manejo de timestamps de Firestore
        if let deactivatedTimestamp = try container.decodeIfPresent(Double.self, forKey: .deactivatedAt) {
            self.deactivatedAt = Date(timeIntervalSince1970: deactivatedTimestamp)
        } else {
            self.deactivatedAt = nil
        }
        
        self.deactivatedBy = try container.decodeIfPresent(String.self, forKey: .deactivatedBy)
        
        // ✅ NUEVO: Decodificación de campos de badges
        self.ownedBadges = (try container.decodeIfPresent([UserBadge].self, forKey: .ownedBadges)) ?? []
        self.plusSubscription = try container.decodeIfPresent(PlusSubscription.self, forKey: .plusSubscription)
        
        // ✅ NUEVO: Decodificación de preferencias de badge
        self.primaryBadgeId = try container.decodeIfPresent(String.self, forKey: .primaryBadgeId)
        self.showBadge = (try container.decodeIfPresent(Bool.self, forKey: .showBadge)) ?? true
        self.showPlusBadge = (try container.decodeIfPresent(Bool.self, forKey: .showPlusBadge)) ?? true
        
        // ✅ NUEVO: Decodificación de tema de perfil
        self.selectedProfileTheme = try container.decodeIfPresent(String.self, forKey: .selectedProfileTheme)
        
        // ✅ NUEVO: Decodificación de verificación de perfil
        self.isVerified = (try container.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        
        // ✅ NUEVO: Decodificación de campos de estado en línea
        let statusString = try container.decodeIfPresent(String.self, forKey: .onlineStatus) ?? "offline"
        self.onlineStatus = OnlineStatus(rawValue: statusString) ?? .offline
        
        if let lastSeenTimestamp = try container.decodeIfPresent(Timestamp.self, forKey: .lastSeen) {
            self.lastSeen = lastSeenTimestamp.dateValue()
        } else {
            self.lastSeen = nil
        }
        
        self.isOnline = (try container.decodeIfPresent(Bool.self, forKey: .isOnline)) ?? false
    }

    init(
        id: String,
        username: String,
        email: String,
        interests: [String],
        isPlusSubscriber: Bool,
        profileImagePath: String?,
        bio: String?,
        blockedUsers: [String],
        isPrivate: Bool,
        showMutualConnections: Bool = true,
        showFollowing: Bool = true,
        showAdmirers: Bool = true,
        activeHoursStart: String?,
        activeHoursEnd: String?,
        notificationPreferences: [String: Bool]?,
        bestFriends: [String],
        isActive: Bool = true,
        deactivatedAt: Date? = nil,
        deactivatedBy: String? = nil,
        ownedBadges: [UserBadge] = [],
        plusSubscription: PlusSubscription? = nil,
        primaryBadgeId: String? = nil,
        showBadge: Bool = true,
        showPlusBadge: Bool = true,
        selectedProfileTheme: String? = nil,
        isVerified: Bool = false,
        onlineStatus: OnlineStatus = .offline,
        lastSeen: Date? = nil,
        isOnline: Bool = false
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.interests = interests
        self.isPlusSubscriber = isPlusSubscriber
        self.profileImagePath = profileImagePath
        self.bio = bio
        self.blockedUsers = blockedUsers
        self.isPrivate = isPrivate
        self.showMutualConnections = showMutualConnections
        self.showFollowing = showFollowing
        self.showAdmirers = showAdmirers
        self.activeHoursStart = activeHoursStart
        self.activeHoursEnd = activeHoursEnd
        self.notificationPreferences = notificationPreferences
        self.bestFriends = bestFriends
        self.isActive = isActive
        self.deactivatedAt = deactivatedAt
        self.deactivatedBy = deactivatedBy
        self.ownedBadges = ownedBadges
        self.plusSubscription = plusSubscription
        self.primaryBadgeId = primaryBadgeId
        self.showBadge = showBadge
        self.showPlusBadge = showPlusBadge
        self.selectedProfileTheme = selectedProfileTheme
        self.isVerified = isVerified
        self.onlineStatus = onlineStatus
        self.lastSeen = lastSeen
        self.isOnline = isOnline
    }
}

extension AppUser: Equatable {
    static func == (lhs: AppUser, rhs: AppUser) -> Bool {
        return lhs.id == rhs.id
    }
}

extension AppUser: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ✅ NUEVAS funciones de badge para el ProfileEditor
extension AppUser {
    
    // MARK: - Badge Display Properties (NUEVAS - no duplicadas)
    
    /// Badge principal para mostrar en el perfil (basado en preferencias del usuario)
    var displayBadge: UserBadge? {
        // Si el usuario ha deshabilitado mostrar badge, no mostrar nada
        guard showBadge != false else { return nil }
        
        // Si hay un primaryBadgeId específico, intentar encontrarlo
        if let primaryBadgeId = primaryBadgeId {
            // Verificar si es el badge Plus
            if primaryBadgeId == "plus" && isPlusSubscriber {
                return createPlusBadge()
            }
            
            // Buscar en badges propios
            if let badge = ownedBadges.first(where: { $0.badgeId == primaryBadgeId }) {
                return badge
            }
        }
        
        // Fallback al sistema de prioridad original
        return primaryBadge
    }
    
    /// Crea un UserBadge para representar el estado Plus
    private func createPlusBadge() -> UserBadge {
        return UserBadge(
            badgeId: "plus",
            name: "Plus",
            emoji: "👑",
            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
            purchaseDate: plusSubscription?.startDate ?? Date(),
            isVisible: true,
            price: "€2.99/mes"
        )
    }
    
    /// Todos los badges disponibles para el usuario (propios + Plus si aplica)
    var availableBadges: [UserBadge] {
        var badges = ownedBadges
        
        // Añadir badge Plus si es suscriptor
        if isPlusSubscriber {
            badges.append(createPlusBadge())
        }
        
        return badges
    }
    
    /// Verifica si el usuario tiene algún badge disponible para mostrar
    var hasDisplayableBadges: Bool {
        return isPlusSubscriber || !ownedBadges.isEmpty
    }
    
    // MARK: - ✅ Sistema de Temas de Perfil (Lógica en ProfileTheme.swift)
    
    /// Obtiene el tema actual del perfil
    var currentProfileTheme: ProfileTheme {
        if let themeString = selectedProfileTheme,
           let theme = ProfileTheme(rawValue: themeString),
           theme.isAvailableForUser(self) {
            return theme
        }
        
        // Fallback al tema basado en el badge principal
        if let primaryBadge = primaryBadge {
            switch primaryBadge.badgeId {
            case "supporter": return .supporter
            case "early_adopter": return .earlyAdopter
            case "champion": return .champion
            case "vip": return .vip
            case "plus": return .plus
            default: return .default
            }
        }
        
        return .default
    }
    
    /// Obtiene todos los temas disponibles para el usuario
    var availableProfileThemes: [ProfileTheme] {
        var themes: [ProfileTheme] = [.default]
        
        // Agregar temas basados en badges
        if hasBadge("supporter") { themes.append(.supporter) }
        if hasBadge("early_adopter") { themes.append(.earlyAdopter) }
        if hasBadge("champion") { themes.append(.champion) }
        if hasBadge("vip") { themes.append(.vip) }
        if isPlusSubscriber { themes.append(.plus) }
        
        return themes
    }
    
    /// Verifica si el usuario puede cambiar el tema
    var canChangeProfileTheme: Bool {
        return availableProfileThemes.count > 1
    }
}

// MARK: - Badge Management Extensions
extension AppUser {
    
    // MARK: - Badge Management
    
    /// Verifica si el usuario tiene un badge específico
    func hasBadge(_ badgeId: String) -> Bool {
        return ownedBadges.contains { $0.badgeId == badgeId }
    }
    
    /// Obtiene los badges visibles del usuario
    var visibleBadges: [UserBadge] {
        return ownedBadges.filter { $0.isVisible }
    }
    
    /// Obtiene el badge principal para mostrar en el perfil
    var primaryBadge: UserBadge? {
        // Prioridad: VIP > Champion > Early Adopter > Supporter
        let priority = ["vip", "champion", "early_adopter", "supporter"]
        
        for badgeId in priority {
            if let badge = visibleBadges.first(where: { $0.badgeId == badgeId }) {
                return badge
            }
        }
        
        // Si no hay badges prioritarios, devolver el más reciente
        return visibleBadges.sorted { $0.purchaseDate > $1.purchaseDate }.first
    }
    
    /// Calcula el total gastado en badges
    var totalSpentOnBadges: Double {
        return ownedBadges.compactMap { badge in
            // Extraer el número del precio (€2.99 -> 2.99)
            let priceString = badge.price.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: ",", with: ".")
            return Double(priceString)
        }.reduce(0, +)
    }
    
    /// Verifica si es un supporter (tiene al menos un badge)
    var isSupporter: Bool {
        return !ownedBadges.isEmpty
    }
    
    /// Obtiene el nivel de supporter basado en badges
    var supporterLevel: SupporterLevel {
        if hasBadge("vip") { return .vip }
        if hasBadge("champion") { return .champion }
        if hasBadge("early_adopter") { return .earlyAdopter }
        if hasBadge("supporter") { return .supporter }
        return .none
    }
    
    // MARK: - Plus Subscription Management
    
    /// Verifica si la suscripción Plus está activa
    var hasActivePlusSubscription: Bool {
        return isPlusSubscriber && !(plusSubscription?.isExpired ?? true)
    }
    
    /// Obtiene los beneficios disponibles
    var availableBenefits: [String] {
        var benefits: [String] = []
        
        if hasActivePlusSubscription {
            benefits.append("Sin anuncios")
            benefits.append("Badge Plus exclusivo")
            benefits.append("Acceso anticipado")
        }
        
        if isSupporter {
            benefits.append("Badge de supporter")
            benefits.append("Perfil destacado")
        }
        
        return benefits
    }
    
    /// Genera un mensaje de agradecimiento personalizado
    var thankYouMessage: String? {
        if hasActivePlusSubscription && isSupporter {
            return "¡Gracias por ser un Plus Subscriber y Supporter! Tu apoyo mantiene Moments gratuito para todos."
        } else if hasActivePlusSubscription {
            return "¡Gracias por ser Plus Subscriber! Disfruta de tu experiencia sin anuncios."
        } else if isSupporter {
            return "¡Gracias por apoyar Moments! Tu badge muestra tu compromiso con la comunidad."
        }
        return nil
    }
}

// MARK: - EXTENSIONES PARA SISTEMA DE SEGUIMIENTO

extension AppUser {
    var isPrivateAccount: Bool {
        return isPrivate
    }
    
    // ✅ NUEVO: Verificar si la cuenta está activa
    var canLogin: Bool {
        return isActive
    }
    
    // ✅ NUEVO: Obtener información de desactivación
    var deactivationInfo: String? {
        guard !isActive, let deactivatedAt = deactivatedAt else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        return "Cuenta desactivada el \(formatter.string(from: deactivatedAt))"
    }
    
    // ✅ NUEVO: Tiempo desde desactivación
    var daysSinceDeactivation: Int? {
        guard let deactivatedAt = deactivatedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: deactivatedAt, to: Date()).day
    }
    
    var followersCount: Int {
        // Esta propiedad se podría calcular dinámicamente o almacenar como campo
        // Por ahora retornamos 0, pero se puede implementar con un contador
        return 0
    }
    
    var followingCount: Int {
        // Similar al anterior
        return 0
    }
    
    var hasActiveStory: Bool {
        // Se podría verificar si tiene historias activas
        // Por ahora retornamos false
        return false
    }
    
    // Verificar si dos usuarios tienen conexión mutua
    func hasMutualConnection(with userId: String) -> Bool {
        // Esta lógica se implementaría consultando las conexiones
        // Por ahora retornamos false como placeholder
        return false
    }
    
    // Verificar si puede recibir mensajes directos
    func canReceiveDirectMessages(from userId: String) -> Bool {
        // ✅ NUEVO: Verificar si la cuenta está activa
        guard isActive else { return false }
        
        // Verificar si está bloqueado
        if blockedUsers.contains(userId) {
            return false
        }
        
        // Si es cuenta privada, verificar si tienen conexión mutua
        if isPrivate {
            return hasMutualConnection(with: userId)
        }
        
        return true
    }
    
    // Verificar si puede ver el contenido del usuario
    func canViewContent(from userId: String) -> Bool {
        // ✅ NUEVO: Verificar si la cuenta está activa
        guard isActive else { return false }
        
        // Verificar si está bloqueado
        if blockedUsers.contains(userId) {
            return false
        }
        
        // Si es cuenta privada, verificar conexión mutua
        if isPrivate {
            return hasMutualConnection(with: userId)
        }
        
        return true
    }
    
    // Verificar configuración de privacidad para mostrar conexiones
    func canShowConnections(to userId: String) -> Bool {
        // ✅ NUEVO: Verificar si la cuenta está activa
        guard isActive else { return false }
        
        // Si el usuario que consulta está bloqueado
        if blockedUsers.contains(userId) {
            return false
        }
        
        // Si es cuenta privada y no hay conexión mutua
        if isPrivate && !hasMutualConnection(with: userId) {
            return false
        }
        
        return showMutualConnections && showFollowing
    }
    
    // Obtener nivel de privacidad
    var privacyLevel: PrivacyLevel {
        // ✅ NUEVO: Si está desactivada, es privada por defecto
        if !isActive {
            return .deactivated
        }
        
        if isPrivate {
            return .private
        } else if !showMutualConnections || !showFollowing {
            return .restricted
        } else {
            return .public
        }
    }
    
    // Verificar si necesita aprobación para seguir
    var requiresFollowApproval: Bool {
        return isPrivate && isActive // Solo si está activa y es privada
    }
}

enum PrivacyLevel {
    case `public`
    case restricted
    case `private`
    case deactivated // ✅ NUEVO: Estado desactivado
    
    var displayName: String {
        switch self {
        case .public: return "Público"
        case .restricted: return "Restringido"
        case .private: return "Privado"
        case .deactivated: return "Desactivado"
        }
    }
    
    var description: String {
        switch self {
        case .public: return "Cualquiera puede ver tu perfil y contenido"
        case .restricted: return "Tu perfil es público pero algunas opciones están restringidas"
        case .private: return "Solo tus seguidores pueden ver tu contenido"
        case .deactivated: return "La cuenta está temporalmente desactivada"
        }
    }
}

extension AppUser {
    /// Versión simplificada para testing
    var shouldHideAds: Bool {
        let result = isPlusSubscriber // Por ahora solo verificar el flag básico
        return result
    }
}
