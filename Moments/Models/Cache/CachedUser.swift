import Foundation
import SwiftData

// MARK: - ✅ SwiftData Model: Usuario cacheado localmente
// Espejo ligero de `AppUser` para persistencia offline.
// Solo incluye campos necesarios para display (no toda la lógica de negocio).

@Model
final class CachedUser {
    // MARK: - Identificador
    @Attribute(.unique) var userId: String // Firebase Auth UID
    
    // MARK: - Campos principales de display
    var username: String
    var email: String
    var bio: String?
    var profileImagePath: String?
    var websiteUrl: String?
    var profileNote: String?
    
    // MARK: - Contadores
    var followersCount: Int?
    var followingCount: Int?
    var momentsCount: Int?

    
    // MARK: - Estado de cuenta
    var isPlusSubscriber: Bool?
    var isVerified: Bool?
    var isPrivate: Bool?
    var isActive: Bool?
    
    // MARK: - Preferencias de privacidad
    var showMutuals: Bool?
    var showFollowing: Bool?
    var showFollowers: Bool?
    var showReadReceipts: Bool?
    var showBadge: Bool?
    var showPlusBadge: Bool?
    
    // MARK: - Badge info
    var primaryBadgeId: String?
    var selectedProfileTheme: String?
    
    // MARK: - Datos complejos (serializados como JSON)
    var interestsData: Data?         // [String] encoded
    var blockedUsersData: Data?      // [String] encoded
    var bestFriendsData: Data?       // [String] encoded
    var ownedBadgesData: Data?       // [UserBadge] encoded
    
    // MARK: - Metadatos de caché
    var lastSyncedAt: Date
    var cacheSection: String         // "currentUser", "profile", "explore"
    
    // MARK: - Init
    init(
        userId: String,
        username: String,
        email: String = "",
        bio: String? = nil,
        profileImagePath: String? = nil,
        websiteUrl: String? = nil,
        profileNote: String? = nil,
        isPlusSubscriber: Bool? = false,
        isVerified: Bool? = false,
        isPrivate: Bool? = false,
        isActive: Bool? = true,
        showMutuals: Bool? = true,
        showFollowing: Bool? = true,
        showFollowers: Bool? = true,
        showReadReceipts: Bool? = true,
        showBadge: Bool? = true,
        showPlusBadge: Bool? = true,
        primaryBadgeId: String? = nil,
        selectedProfileTheme: String? = nil,
        followersCount: Int? = 0,
        followingCount: Int? = 0,
        momentsCount: Int? = 0,
        interestsData: Data? = nil,

        blockedUsersData: Data? = nil,
        bestFriendsData: Data? = nil,
        ownedBadgesData: Data? = nil,
        lastSyncedAt: Date = Date(),
        cacheSection: String = "profile"
    ) {
        self.userId = userId
        self.username = username
        self.email = email
        self.bio = bio
        self.profileImagePath = profileImagePath
        self.websiteUrl = websiteUrl
        self.profileNote = profileNote
        self.isPlusSubscriber = isPlusSubscriber
        self.isVerified = isVerified
        self.isPrivate = isPrivate
        self.isActive = isActive
        self.showMutuals = showMutuals
        self.showFollowing = showFollowing
        self.showFollowers = showFollowers
        self.showReadReceipts = showReadReceipts
        self.showBadge = showBadge
        self.showPlusBadge = showPlusBadge
        self.primaryBadgeId = primaryBadgeId
        self.selectedProfileTheme = selectedProfileTheme
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.momentsCount = momentsCount
        self.interestsData = interestsData

        self.blockedUsersData = blockedUsersData
        self.bestFriendsData = bestFriendsData
        self.ownedBadgesData = ownedBadgesData
        self.lastSyncedAt = lastSyncedAt
        self.cacheSection = cacheSection
    }
}

// MARK: - Conversión AppUser ↔ CachedUser

extension CachedUser {
    
    /// Convierte un `AppUser` de Firestore a `CachedUser` para SwiftData
    static func from(_ user: AppUser, section: String = "profile") -> CachedUser {
        let encoder = JSONEncoder()
        
        return CachedUser(
            userId: user.id,
            username: user.username,
            email: user.email,
            bio: user.bio,
            profileImagePath: user.profileImagePath,
            websiteUrl: user.websiteUrl,
            profileNote: user.profileNote,
            isPlusSubscriber: user.isPlusSubscriber,
            isVerified: user.isVerified,
            isPrivate: user.isPrivate,
            isActive: user.isActive,
            showMutuals: user.showMutuals,
            showFollowing: user.showFollowing,
            showFollowers: user.showFollowers,
            showReadReceipts: user.showReadReceipts,
            showBadge: user.showBadge,
            showPlusBadge: user.showPlusBadge,
            primaryBadgeId: user.primaryBadgeId,
            selectedProfileTheme: user.selectedProfileTheme,
            followersCount: user.followersCount,
            followingCount: user.followingCount,
            momentsCount: user.momentsCount,
            interestsData: try? encoder.encode(user.interests),

            blockedUsersData: try? encoder.encode(user.blockedUsers),
            bestFriendsData: try? encoder.encode(user.bestFriends),
            ownedBadgesData: try? encoder.encode(user.ownedBadges),
            lastSyncedAt: Date(),
            cacheSection: section
        )
    }
    
    /// Convierte un `CachedUser` de SwiftData a `AppUser` para usar en las Views
    func toAppUser() -> AppUser {
        let decoder = JSONDecoder()
        
        let interests: [String] = {
            guard let data = interestsData else { return [] }
            return (try? decoder.decode([String].self, from: data)) ?? []
        }()
        
        let blockedUsers: [String] = {
            guard let data = blockedUsersData else { return [] }
            return (try? decoder.decode([String].self, from: data)) ?? []
        }()
        
        let bestFriends: [String] = {
            guard let data = bestFriendsData else { return [] }
            return (try? decoder.decode([String].self, from: data)) ?? []
        }()
        
        let ownedBadges: [UserBadge] = {
            guard let data = ownedBadgesData else { return [] }
            return (try? decoder.decode([UserBadge].self, from: data)) ?? []
        }()
        
        return AppUser(
            id: userId,
            username: username,
            email: email,
            interests: interests,
            isPlusSubscriber: isPlusSubscriber ?? false,
            profileImagePath: profileImagePath,
            bio: bio,
            blockedUsers: blockedUsers,
            isPrivate: isPrivate ?? false,
            showMutuals: showMutuals ?? true,
            showFollowing: showFollowing ?? true,
            showFollowers: showFollowers ?? true,
            activeHoursStart: nil,
            activeHoursEnd: nil,
            notificationPreferences: nil,
            bestFriends: bestFriends,
            websiteUrl: websiteUrl,
            profileNote: profileNote,
            followersCount: followersCount ?? 0,
            followingCount: followingCount ?? 0,
            momentsCount: momentsCount ?? 0,
            isActive: isActive ?? true,

            ownedBadges: ownedBadges,
            primaryBadgeId: primaryBadgeId,
            showBadge: showBadge ?? true,
            showPlusBadge: showPlusBadge ?? true,
            selectedProfileTheme: selectedProfileTheme,
            isVerified: isVerified ?? false,
            showReadReceipts: showReadReceipts ?? true
        )
    }
}
