import Foundation

// MARK: - Helper centralizado para emojis de intereses
struct InterestEmojiHelper {
    
    /// Retorna el emoji correspondiente para un interés dado
    /// - Parameter interest: El nombre del interés
    /// - Returns: El emoji correspondiente o ✨ como fallback
    static func emoji(for interest: String) -> String {
        switch interest.lowercased() {
        // Arte & Cultura
        case "escritura", "writing": return "✍️"
        case "cine", "movies": return "🎬"
        case "libros", "books", "lectura", "reading": return "📚"
        case "teatro", "theater": return "🎭"
        case "arte", "art": return "🎨"
        case "diseño", "design": return "🎨"
        case "baile", "dance": return "💃"
        
        // Bienestar & Salud
        case "meditación", "meditation": return "🕯️"
        case "yoga": return "🧘"
        case "fitness": return "💪"
        case "deportes", "sports": return "⚽"
        
        // Naturaleza & Vida
        case "naturaleza", "nature": return "🌿"
        case "fotografía", "photography": return "📸"
        case "mascotas", "pets": return "🐾"
        case "astronomía", "astronomy": return "⭐"
        
        // Estilo & Lifestyle
        case "moda", "fashion": return "👗"
        case "café", "coffee": return "☕"
        case "cocina", "cooking": return "👨‍🍳"
        case "viajar", "travel": return "✈️"
        
        // Tecnología & Entretenimiento
        case "gaming", "gamer": return "🎮"
        case "tecnología", "technology": return "💻"
        case "programación", "programming", "programacion": return "💻"
        case "podcasts": return "🎧"
        case "kpop", "k-pop": return "🎤"
        
        // Negocios
        case "emprendimiento", "entrepreneurship": return "🚀"
        
        // Música
        case "música", "music": return "🎵"
        
        // Fallback
        default: return "✨"
        }
    }
    
    /// Lista completa de intereses soportados con sus emojis
    static let supportedInterests: [(name: String, emoji: String)] = [
        (NSLocalizedString("interest.escritura", comment: "Writing interest"), "✍️"),
        (NSLocalizedString("interest.cine", comment: "Movies interest"), "🎬"),
        (NSLocalizedString("interest.libros", comment: "Books interest"), "📚"),
        (NSLocalizedString("interest.teatro", comment: "Theater interest"), "🎭"),
        (NSLocalizedString("interest.meditacion", comment: "Meditation interest"), "🕯️"),
        (NSLocalizedString("interest.naturaleza", comment: "Nature interest"), "🌿"),
        (NSLocalizedString("interest.fotografia", comment: "Photography interest"), "📸"),
        (NSLocalizedString("interest.moda", comment: "Fashion interest"), "👗"),
        (NSLocalizedString("interest.emprendimiento", comment: "Entrepreneurship interest"), "🚀"),
        (NSLocalizedString("interest.yoga", comment: "Yoga interest"), "🧘"),
        (NSLocalizedString("interest.historia", comment: "History interest"), "📜"),
        (NSLocalizedString("interest.cafe", comment: "Coffee interest"), "☕"),
        (NSLocalizedString("interest.fitness", comment: "Fitness interest"), "💪"),
        (NSLocalizedString("interest.musica", comment: "Music interest"), "🎵"),
        (NSLocalizedString("interest.gaming", comment: "Gaming interest"), "🎮"),
        (NSLocalizedString("interest.tecnologia", comment: "Technology interest"), "💻"),
        (NSLocalizedString("interest.viajar", comment: "Travel interest"), "✈️"),
        (NSLocalizedString("interest.astronomia", comment: "Astronomy interest"), "⭐"),
        (NSLocalizedString("interest.podcasts", comment: "Podcasts interest"), "🎧"),
        (NSLocalizedString("interest.deportes", comment: "Sports interest"), "⚽"),
        (NSLocalizedString("interest.cocina", comment: "Cooking interest"), "👨‍🍳"),
        (NSLocalizedString("interest.mascotas", comment: "Pets interest"), "🐾"),
        (NSLocalizedString("interest.diseno", comment: "Design interest"), "🎨"),
        (NSLocalizedString("interest.baile", comment: "Dance interest"), "💃"),
        (NSLocalizedString("interest.programacion", comment: "Programming interest"), "💻"),
        (NSLocalizedString("interest.kpop", comment: "Kpop interest"), "🎤")
    ]
    
    /// Obtiene un interés aleatorio para sugerencias
    static func randomInterest() -> (name: String, emoji: String) {
        supportedInterests.randomElement() ?? ("Interés", "✨")
    }
}


