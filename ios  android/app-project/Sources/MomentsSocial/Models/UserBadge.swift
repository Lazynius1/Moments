import Foundation
import SwiftUI

// MARK: - Badge Data Model
struct UserBadge: Codable, Identifiable, Equatable {
    let id: String
    let badgeId: String
    let name: String
    let emoji: String
    let colors: [String] // Hex colors for serialization
    let purchaseDate: Date
    let isVisible: Bool
    let price: String
    
    // Computed property para convertir hex a Color
    var swiftUIColors: [Color] {
        return colors.compactMap { Color(hex: $0) }
    }
    
    init(id: String = UUID().uuidString, badgeId: String, name: String, emoji: String, colors: [Color], purchaseDate: Date = Date(), isVisible: Bool = true, price: String) {
        self.id = id
        self.badgeId = badgeId
        self.name = name
        self.emoji = emoji
        self.colors = colors.map { $0.toHex() } // Convertir a hex para serialización
        self.purchaseDate = purchaseDate
        self.isVisible = isVisible
        self.price = price
    }
    
    static func == (lhs: UserBadge, rhs: UserBadge) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Plus Subscription Info
struct PlusSubscription: Codable {
    let isActive: Bool
    let startDate: Date?
    let expiryDate: Date?
    let autoRenew: Bool
    let plan: String // "monthly", "yearly"
    
    var isExpired: Bool {
        guard let expiryDate = expiryDate else { return false }
        return Date() > expiryDate
    }
    
    var daysRemaining: Int? {
        guard let expiryDate = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
    }
}

// Las extensiones de AppUser están en User.swift

// MARK: - Supporter Levels
enum SupporterLevel: String, CaseIterable {
    case none = "none"
    case supporter = "supporter"
    case earlyAdopter = "early_adopter"
    case champion = "champion"
    case vip = "vip"
    
    var displayName: String {
        switch self {
        case .none: return "Usuario"
        case .supporter: return "Supporter"
        case .earlyAdopter: return "Early Adopter"
        case .champion: return "Champion"
        case .vip: return "VIP"
        }
    }
    
    var emoji: String {
        switch self {
        case .none: return "👤"
        case .supporter: return "❤️"
        case .earlyAdopter: return "🚀"
        case .champion: return "🏆"
        case .vip: return "💎"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .none: return [.gray]
        case .supporter: return [.red, .pink]
        case .earlyAdopter: return [.blue, .purple]
        case .champion: return [.yellow, .orange]
        case .vip: return [.purple, .indigo]
        }
    }
    
    // ✅ NUEVO: Temas de fondo para el perfil
    var profileTheme: ProfileTheme {
        switch self {
        case .none: return .default
        case .supporter: return .supporter
        case .earlyAdopter: return .earlyAdopter
        case .champion: return .champion
        case .vip: return .vip
        }
    }
}

// MARK: - Sistema de Temas movido a ProfileTheme.swift

// La lógica de temas está en ProfileTheme.swift

// MARK: - Badge Model (para compras)
struct Badge: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    let price: String
    let colors: [Color]
    let productId: String // Para StoreKit
    
    static let supportBadges: [Badge] = [
        Badge(
            id: "supporter",
            name: "Supporter",
            emoji: "❤️",
            description: "Apoya el proyecto",
            price: "€2.99",
            colors: [Color.red, Color.pink],
            productId: "com.moments.badge.supporter"
        ),
        Badge(
            id: "early_adopter",
            name: "Early Adopter",
            emoji: "🚀",
            description: "Usuario pionero",
            price: "€4.99",
            colors: [Color.blue, Color.purple],
            productId: "com.moments.badge.early_adopter"
        ),
        Badge(
            id: "champion",
            name: "Champion",
            emoji: "🏆",
            description: "Campeón de la comunidad",
            price: "€7.99",
            colors: [Color.yellow, Color.orange],
            productId: "com.moments.badge.champion"
        ),
        Badge(
            id: "vip",
            name: "VIP",
            emoji: "💎",
            description: "Badge premium",
            price: "€9.99",
            colors: [Color.purple, Color.indigo],
            productId: "com.moments.badge.vip"
        )
    ]
}

// MARK: - Badge Service para manejar compras y estado
class BadgeService: ObservableObject {
    @Published var ownedBadges: [UserBadge] = []
    @Published var plusSubscription: PlusSubscription?
    
    private let firestoreService = FirestoreService()
    
    func loadUserBadges(userId: String) {
        // Cargar badges del usuario desde Firestore
        firestoreService.fetchUser(userId: userId) { [weak self] result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    self?.ownedBadges = user.ownedBadges
                    self?.plusSubscription = user.plusSubscription
                }
            case .failure(_):
                break
            }
        }
    }
    
    func purchaseBadge(_ badge: Badge, completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        
        // Simular compra exitosa
        let userBadge = UserBadge(
            badgeId: badge.id,
            name: badge.name,
            emoji: badge.emoji,
            colors: badge.colors,
            price: badge.price
        )
        
        
        // Actualizar en Firestore
        var updatedBadges = ownedBadges
        updatedBadges.append(userBadge)
        
        
        updateUserBadges(userId: userId, badges: updatedBadges) { [weak self] success in
            
            if success {
                DispatchQueue.main.async {
                    self?.ownedBadges = updatedBadges
                }
            }
            completion(success)
        }
    }
    
    func toggleBadgeVisibility(_ badge: UserBadge, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid,
              let index = ownedBadges.firstIndex(where: { $0.id == badge.id }) else { 
            completion(false)
            return 
        }
        
        ownedBadges[index] = UserBadge(
            id: badge.id,
            badgeId: badge.badgeId,
            name: badge.name,
            emoji: badge.emoji,
            colors: badge.swiftUIColors,
            purchaseDate: badge.purchaseDate,
            isVisible: !badge.isVisible,
            price: badge.price
        )
        
        updateUserBadges(userId: userId, badges: ownedBadges) { success in
            if !success {
            }
            completion(success)
        }
    }
    
    private func updateUserBadges(userId: String, badges: [UserBadge], completion: @escaping (Bool) -> Void) {
        
        let db = Firestore.firestore()
        
        do {
            let encoder = Firestore.Encoder()
            let badgesData = try badges.map { try encoder.encode($0) }
            
            
            db.collection("users").document(userId).updateData([
                "ownedBadges": badgesData,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(false)
                } else {
                    completion(true)
                }
            }
        } catch {
            completion(false)
        }
    }
    
    func purchasePlusSubscription(completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        // Simular compra de suscripción exitosa
        let subscription = PlusSubscription(
            isActive: true,
            startDate: Date(),
            expiryDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            autoRenew: true,
            plan: "monthly"
        )
        
        // Actualizar en Firestore
        let db = Firestore.firestore()
        
        do {
            let encoder = Firestore.Encoder()
            let subscriptionData = try encoder.encode(subscription)
            
            db.collection("users").document(userId).updateData([
                "isPlusSubscriber": true,
                "plusSubscription": subscriptionData,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { [weak self] error in
                if error == nil {
                    DispatchQueue.main.async {
                        self?.plusSubscription = subscription
                    }
                }
                completion(error == nil)
            }
        } catch {
            completion(false)
        }
    }
}

