import SwiftUI


// MARK: - Sistema Completo de Temas de Perfil MEJORADO
enum ProfileTheme: String, CaseIterable {
    case `default` = "default"
    case supporter = "supporter"
    case earlyAdopter = "early_adopter"
    case champion = "champion"
    case vip = "vip"
    case plus = "plus"
    
    var displayName: String {
        switch self {
        case .default: return "Clásico"
        case .supporter: return "Supporter"
        case .earlyAdopter: return "Early Adopter"
        case .champion: return "Champion"
        case .vip: return "VIP"
        case .plus: return "Plus"
        }
    }
    
    var description: String {
        switch self {
        case .default: return "Tema clásico de Moments"
        case .supporter: return "Gradiente rojo elegante + partículas de corazones sutiles"
        case .earlyAdopter: return "Fondo con gradiente azul y púrpura + efectos de partículas + aura azul"
        case .champion: return "Fondo con gradiente dorado y naranja + efectos de brillo + aura dorada"
        case .vip: return "Fondo con gradiente púrpura e índigo + efectos de diamante + aura púrpura"
        case .plus: return "Fondo premium con gradiente dorado + efectos de corona + aura premium"
        }
    }
    
    var emoji: String {
        switch self {
        case .default: return "🎨"
        case .supporter: return "❤️"
        case .earlyAdopter: return "🚀"
        case .champion: return "🏆"
        case .vip: return "💎"
        case .plus: return "👑"
        }
    }
    
    // MARK: - Gradientes Mejorados
    var backgroundGradient: LinearGradient {
        switch self {
        case .default:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),
                    Color(hex: "E3F2FD").opacity(0.9),
                    Color(hex: "F1F8E9").opacity(0.8),
                    Color(hex: "F8F9FA")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .supporter:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),           // Blanco sutil
                    Color(hex: "FFE6E6").opacity(0.9),  // Rojo muy claro
                    Color(hex: "FFD6D6").opacity(0.8),  // Rosa claro
                    Color(hex: "F8F9FA")            // Blanco sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .earlyAdopter:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),           // Blanco sutil
                    Color(hex: "E3F2FD").opacity(0.9),  // Azul muy claro
                    Color(hex: "E8F4FD").opacity(0.8),  // Azul pálido
                    Color(hex: "F8F9FA")            // Blanco sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .champion:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),           // Blanco sutil
                    Color(hex: "FFE066").opacity(0.9),  // Dorado intenso
                    Color(hex: "FFA500").opacity(0.8),  // Naranja vibrante
                    Color(hex: "F8F9FA")            // Blanco sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .vip:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),           // Blanco sutil
                    Color(hex: "F3E5F5").opacity(0.9),  // Púrpura muy claro
                    Color(hex: "E1BEE7").opacity(0.8),  // Púrpura pálido
                    Color(hex: "F8F9FA")            // Blanco sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .plus:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F9FA"),           // Blanco sutil
                    Color(hex: "F5F5DC").opacity(0.9),  // Dorado sutil (beige)
                    Color(hex: "DEB887").opacity(0.8),  // Beige suave
                    Color(hex: "F8F9FA")            // Blanco sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var darkBackgroundGradient: LinearGradient {
        switch self {
        case .default:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(hex: "1a1a2e").opacity(0.9),
                    Color(hex: "16213e").opacity(0.8),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .supporter:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "1a0000"),           // Negro con toque rojo
                    Color(hex: "8B0000").opacity(0.9),  // Rojo oscuro intenso
                    Color(hex: "DC143C").opacity(0.8),  // Rojo vibrante
                    Color(hex: "1a0000")            // Negro con toque rojo
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .earlyAdopter:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "001a2e"),           // Negro con toque azul
                    Color(hex: "006994").opacity(0.9),  // Azul oscuro intenso
                    Color(hex: "1E90FF").opacity(0.8),  // Azul vibrante
                    Color(hex: "001a2e")            // Negro con toque azul
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .champion:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "2a1a00"),           // Negro con toque dorado
                    Color(hex: "DAA520").opacity(0.9),  // Dorado oscuro intenso
                    Color(hex: "FFD700").opacity(0.8),  // Dorado vibrante
                    Color(hex: "2a1a00")            // Negro con toque dorado
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .vip:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "1a002e"),           // Negro con toque púrpura
                    Color(hex: "4B0082").opacity(0.9),  // Púrpura oscuro intenso
                    Color(hex: "8A2BE2").opacity(0.8),  // Púrpura vibrante
                    Color(hex: "1a002e")            // Negro con toque púrpura
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
        case .plus:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "1a1a1a"),           // Negro sutil
                    Color(hex: "8B7355").opacity(0.9),  // Marrón suave
                    Color(hex: "D2B48C").opacity(0.8),  // Beige suave
                    Color(hex: "1a1a1a")            // Negro sutil
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Efectos de Partículas
    var particleEffect: ParticleEffect {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - Efectos de Brillo
    var glowEffect: GlowEffect {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - Animaciones
    var animation: ThemeAnimation {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Aura alrededor del perfil
    var profileAura: ProfileAura {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Borde dinámico
    var dynamicBorder: DynamicBorder {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Partículas alrededor del perfil
    var profileParticles: ProfileParticles {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Rayos de Luz desde el perfil
    var lightRays: LightRays {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Ondas de Energía
    var energyWaves: EnergyWaves {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Chispas Dinámicas
    var dynamicSparks: DynamicSparks {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos Atmosféricos
    var atmosphericEffects: AtmosphericEffects {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Iluminación Volumétrica
    var volumetricLighting: VolumetricLighting {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Orbes Flotantes
    var floatingOrbs: FloatingOrbs {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - ✅ NUEVO: Efectos de Respiración para Avatar
    var breathingEffect: BreathingEffect {
        switch self {
        case .default: return .none
        case .supporter: return .none
        case .earlyAdopter: return .none
        case .champion: return .none
        case .vip: return .none
        case .plus: return .none
        }
    }
    
    // MARK: - Lógica de Negocio
    func isAvailableForUser(_ user: AppUser) -> Bool {
        switch self {
        case .default: return true
        case .supporter: return user.hasBadge("supporter")
        case .earlyAdopter: return user.hasBadge("early_adopter")
        case .champion: return user.hasBadge("champion")
        case .vip: return user.hasBadge("vip")
        case .plus: return user.isPlusSubscriber
        }
    }
    
    var price: String? {
        switch self {
        case .default: return nil
        case .supporter: return "€2.99"
        case .earlyAdopter: return "€4.99"
        case .champion: return "€7.99"
        case .vip: return "€9.99"
        case .plus: return "€2.99/mes"
        }
    }
}

// MARK: - Efectos de Partículas
enum ParticleEffect {
    case none
    case hearts
    case stars
    case sparkles
    case diamonds
    case crowns
    
    var emoji: String {
        switch self {
        case .none: return ""
        case .hearts: return "❤️"
        case .stars: return "⭐"
        case .sparkles: return "✨"
        case .diamonds: return "💎"
        case .crowns: return "👑"
        }
    }
    
    var count: Int {
        switch self {
        case .none: return 0
        case .hearts: return 8
        case .stars: return 12
        case .sparkles: return 15
        case .diamonds: return 10
        case .crowns: return 6
        }
    }
}

// MARK: - Efectos de Brillo
enum GlowEffect {
    case none
    case soft
    case medium
    case strong
    case intense
    case premium
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .soft: return 5
        case .medium: return 10
        case .strong: return 15
        case .intense: return 20
        case .premium: return 25
        }
    }
    
    var opacity: Double {
        switch self {
        case .none: return 0
        case .soft: return 0.3
        case .medium: return 0.5
        case .strong: return 0.7
        case .intense: return 0.8
        case .premium: return 0.9
        }
    }
}

// MARK: - Animaciones de Tema
enum ThemeAnimation {
    case none
    case pulse
    case float
    case rotate
    case wave
    case premium
    
    var duration: Double {
        switch self {
        case .none: return 0
        case .pulse: return 2.0
        case .float: return 3.0
        case .rotate: return 4.0
        case .wave: return 2.5
        case .premium: return 1.5
        }
    }
}

// MARK: - ✅ NUEVO: Efectos de Aura alrededor del perfil
enum ProfileAura {
    case none
    case pink
    case blue
    case gold
    case purple
    case premium
    
    var colors: [Color] {
        switch self {
        case .none: return []
        case .pink: return [Color(hex: "FF69B4"), Color(hex: "FF1493"), Color(hex: "FFB6C1")]
        case .blue: return [Color(hex: "00BFFF"), Color(hex: "1E90FF"), Color(hex: "87CEEB")]
        case .gold: return [Color(hex: "FFD700"), Color(hex: "FFA500"), Color(hex: "FFE4B5")]
        case .purple: return [Color(hex: "9370DB"), Color(hex: "8A2BE2"), Color(hex: "DDA0DD")]
        case .premium: return [Color(hex: "FFD700"), Color(hex: "FFA500"), Color(hex: "FF4500")]
        }
    }
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .pink: return 80
        case .blue: return 90
        case .gold: return 100
        case .purple: return 110
        case .premium: return 120
        }
    }
    
    var intensity: Double {
        switch self {
        case .none: return 0
        case .pink: return 0.4
        case .blue: return 0.5
        case .gold: return 0.6
        case .purple: return 0.7
        case .premium: return 0.8
        }
    }
}

// MARK: - ✅ NUEVO: Bordes dinámicos
enum DynamicBorder {
    case none
    case heartbeat
    case pulse
    case sparkle
    case diamond
    case crown
    
    var colors: [Color] {
        switch self {
        case .none: return []
        case .heartbeat: return [Color(hex: "FF69B4"), Color(hex: "FF1493")]
        case .pulse: return [Color(hex: "00BFFF"), Color(hex: "1E90FF")]
        case .sparkle: return [Color(hex: "FFD700"), Color(hex: "FFA500")]
        case .diamond: return [Color(hex: "9370DB"), Color(hex: "8A2BE2")]
        case .crown: return [Color(hex: "FFD700"), Color(hex: "FF4500")]
        }
    }
    
    var width: CGFloat {
        switch self {
        case .none: return 0
        case .heartbeat: return 3
        case .pulse: return 4
        case .sparkle: return 5
        case .diamond: return 6
        case .crown: return 7
        }
    }
    
    var animationDuration: Double {
        switch self {
        case .none: return 0
        case .heartbeat: return 1.2
        case .pulse: return 2.0
        case .sparkle: return 1.5
        case .diamond: return 2.5
        case .crown: return 1.8
        }
    }
}

// MARK: - ✅ NUEVO: Partículas alrededor del perfil
enum ProfileParticles {
    case none
    case hearts
    case stars
    case sparkles
    case diamonds
    case crowns
    
    var emoji: String {
        switch self {
        case .none: return ""
        case .hearts: return "❤️"
        case .stars: return "⭐"
        case .sparkles: return "✨"
        case .diamonds: return "💎"
        case .crowns: return "👑"
        }
    }
    
    var count: Int {
        switch self {
        case .none: return 0
        case .hearts: return 6
        case .stars: return 8
        case .sparkles: return 10
        case .diamonds: return 7
        case .crowns: return 5
        }
    }
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .hearts: return 70
        case .stars: return 80
        case .sparkles: return 90
        case .diamonds: return 100
        case .crowns: return 110
        }
    }
}

// MARK: - ✅ NUEVO: Efectos de Rayos de Luz desde el perfil
enum LightRays {
    case none
    case pink
    case blue
    case gold
    case purple
    case premium
    
    var colors: [Color] {
        switch self {
        case .none: return []
        case .pink: return [Color(hex: "FF69B4"), Color(hex: "FF1493"), Color(hex: "FFB6C1")]
        case .blue: return [Color(hex: "00BFFF"), Color(hex: "1E90FF"), Color(hex: "87CEEB")]
        case .gold: return [Color(hex: "FFD700"), Color(hex: "FFA500"), Color(hex: "FFE4B5")]
        case .purple: return [Color(hex: "9370DB"), Color(hex: "8A2BE2"), Color(hex: "DDA0DD")]
        case .premium: return [Color(hex: "FFD700"), Color(hex: "FFA500"), Color(hex: "FF4500")]
        }
    }
    
    var count: Int {
        switch self {
        case .none: return 0
        case .pink: return 8
        case .blue: return 10
        case .gold: return 12
        case .purple: return 14
        case .premium: return 16
        }
    }
    
    var length: CGFloat {
        switch self {
        case .none: return 0
        case .pink: return 120
        case .blue: return 140
        case .gold: return 160
        case .purple: return 180
        case .premium: return 200
        }
    }
    
    var width: CGFloat {
        switch self {
        case .none: return 0
        case .pink: return 2
        case .blue: return 3
        case .gold: return 4
        case .purple: return 5
        case .premium: return 6
        }
    }
}

// MARK: - ✅ NUEVO: Ondas de Energía
enum EnergyWaves {
    case none
    case gentle
    case moderate
    case strong
    case intense
    case epic
    
    var colors: [Color] {
        switch self {
        case .none: return []
        case .gentle: return [Color(hex: "FF69B4").opacity(0.6), Color(hex: "FF1493").opacity(0.4)]
        case .moderate: return [Color(hex: "00BFFF").opacity(0.7), Color(hex: "1E90FF").opacity(0.5)]
        case .strong: return [Color(hex: "FFD700").opacity(0.8), Color(hex: "FFA500").opacity(0.6)]
        case .intense: return [Color(hex: "9370DB").opacity(0.9), Color(hex: "8A2BE2").opacity(0.7)]
        case .epic: return [Color(hex: "FFD700").opacity(1.0), Color(hex: "FF4500").opacity(0.8)]
        }
    }
    
    var count: Int {
        switch self {
        case .none: return 0
        case .gentle: return 3
        case .moderate: return 4
        case .strong: return 5
        case .intense: return 6
        case .epic: return 8
        }
    }
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .gentle: return 80
        case .moderate: return 100
        case .strong: return 120
        case .intense: return 140
        case .epic: return 160
        }
    }
    
    var speed: Double {
        switch self {
        case .none: return 0
        case .gentle: return 3.0
        case .moderate: return 2.5
        case .strong: return 2.0
        case .intense: return 1.5
        case .epic: return 1.0
        }
    }
}

// MARK: - ✅ NUEVO: Chispas Dinámicas
enum DynamicSparks {
    case none
    case hearts
    case stars
    case sparkles
    case diamonds
    case crowns
    
    var emoji: String {
        switch self {
        case .none: return ""
        case .hearts: return "❤️"
        case .stars: return "⭐"
        case .sparkles: return "✨"
        case .diamonds: return "💎"
        case .crowns: return "👑"
        }
    }
    
    var count: Int {
        switch self {
        case .none: return 0
        case .hearts: return 15
        case .stars: return 20
        case .sparkles: return 25
        case .diamonds: return 18
        case .crowns: return 12
        }
    }
    
    var spreadRadius: CGFloat {
        switch self {
        case .none: return 0
        case .hearts: return 150
        case .stars: return 180
        case .sparkles: return 200
        case .diamonds: return 170
        case .crowns: return 160
        }
    }
    
    var speed: Double {
        switch self {
        case .none: return 0
        case .hearts: return 4.0
        case .stars: return 3.5
        case .sparkles: return 3.0
        case .diamonds: return 2.5
        case .crowns: return 2.0
        }
    }
}

// MARK: - ✅ NUEVO: Efectos Atmosféricos
enum AtmosphericEffects {
    case none
    case gentle
    case moderate
    case strong
    case intense
    case epic
    
    var orbCount: Int {
        switch self {
        case .none: return 0
        case .gentle: return 3
        case .moderate: return 5
        case .strong: return 7
        case .intense: return 9
        case .epic: return 12
        }
    }
    
    var particleCount: Int {
        switch self {
        case .none: return 0
        case .gentle: return 8
        case .moderate: return 12
        case .strong: return 16
        case .intense: return 20
        case .epic: return 25
        }
    }
    
    var intensity: Double {
        switch self {
        case .none: return 0
        case .gentle: return 0.3
        case .moderate: return 0.5
        case .strong: return 0.7
        case .intense: return 0.8
        case .epic: return 1.0
        }
    }
}

// MARK: - ✅ NUEVO: Iluminación Volumétrica
enum VolumetricLighting {
    case none
    case soft
    case medium
    case bright
    case intense
    case premium
    
    var layerCount: Int {
        switch self {
        case .none: return 0
        case .soft: return 2
        case .medium: return 3
        case .bright: return 4
        case .intense: return 5
        case .premium: return 6
        }
    }
    
    var opacity: Double {
        switch self {
        case .none: return 0
        case .soft: return 0.2
        case .medium: return 0.3
        case .bright: return 0.4
        case .intense: return 0.5
        case .premium: return 0.6
        }
    }
    
    var blurRadius: CGFloat {
        switch self {
        case .none: return 0
        case .soft: return 15
        case .medium: return 20
        case .bright: return 25
        case .intense: return 30
        case .premium: return 35
        }
    }
}

// MARK: - ✅ NUEVO: Orbes Flotantes
enum FloatingOrbs {
    case none
    case few
    case moderate
    case many
    case abundant
    case premium
    
    var count: Int {
        switch self {
        case .none: return 0
        case .few: return 3
        case .moderate: return 5
        case .many: return 7
        case .abundant: return 9
        case .premium: return 12
        }
    }
    
    var size: CGFloat {
        switch self {
        case .none: return 0
        case .few: return 60
        case .moderate: return 70
        case .many: return 80
        case .abundant: return 90
        case .premium: return 100
        }
    }
    
    var opacity: Double {
        switch self {
        case .none: return 0
        case .few: return 0.3
        case .moderate: return 0.4
        case .many: return 0.5
        case .abundant: return 0.6
        case .premium: return 0.7
        }
    }
}

// MARK: - ✅ NUEVO: Efecto de Respiración
enum BreathingEffect {
    case none
    case gentle
    case moderate
    case strong
    case intense
    case premium
    
    var scale: CGFloat {
        switch self {
        case .none: return 0
        case .gentle: return 0.02
        case .moderate: return 0.04
        case .strong: return 0.06
        case .intense: return 0.08
        case .premium: return 0.1
        }
    }
    
    var duration: Double {
        switch self {
        case .none: return 0
        case .gentle: return 4.0
        case .moderate: return 3.5
        case .strong: return 3.0
        case .intense: return 2.5
        case .premium: return 2.0
        }
    }
    
    var intensity: Double {
        switch self {
        case .none: return 0
        case .gentle: return 0.8
        case .moderate: return 1.0
        case .strong: return 1.2
        case .intense: return 1.4
        case .premium: return 1.6
        }
    }
}
