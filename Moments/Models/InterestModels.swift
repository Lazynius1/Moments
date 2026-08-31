import Foundation

/// Catálogo unificado de intereses. Firestore guarda `firestoreKey` (español); la UI localiza vía `interest.*`.
struct InterestDefinition: Equatable {
    let firestoreKey: String
    let localizationKey: String
    let emoji: String
    let aliases: [String]
}

enum InterestCatalog {
    static let all: [InterestDefinition] = [
        InterestDefinition(firestoreKey: "Fotografía", localizationKey: "interest.photography", emoji: "📸", aliases: ["Fotografía", "fotografia"]),
        InterestDefinition(firestoreKey: "Viajes", localizationKey: "interest.travel", emoji: "✈️", aliases: ["Viajes", "Viajar", "viajar"]),
        InterestDefinition(firestoreKey: "Música", localizationKey: "interest.music", emoji: "🎵", aliases: ["Música", "musica"]),
        InterestDefinition(firestoreKey: "Cine", localizationKey: "interest.movies", emoji: "🎬", aliases: ["Cine", "cine"]),
        InterestDefinition(firestoreKey: "Arte", localizationKey: "interest.art", emoji: "🎨", aliases: ["Arte", "arte"]),
        InterestDefinition(firestoreKey: "Deportes", localizationKey: "interest.sports", emoji: "⚽", aliases: ["Deportes", "deportes"]),
        InterestDefinition(firestoreKey: "Libros", localizationKey: "interest.books", emoji: "📚", aliases: ["Libros", "libros", "Lectura", "lectura"]),
        InterestDefinition(firestoreKey: "Cocina", localizationKey: "interest.cooking", emoji: "👨‍🍳", aliases: ["Cocina", "cocina"]),
        InterestDefinition(firestoreKey: "Tecnología", localizationKey: "interest.technology", emoji: "💻", aliases: ["Tecnología", "tecnologia"]),
        InterestDefinition(firestoreKey: "Moda", localizationKey: "interest.fashion", emoji: "👗", aliases: ["Moda", "moda"]),
        InterestDefinition(firestoreKey: "Gaming", localizationKey: "interest.gaming", emoji: "🎮", aliases: ["Gaming", "gaming", "Videojuegos"]),
        InterestDefinition(firestoreKey: "Fitness", localizationKey: "interest.fitness", emoji: "💪", aliases: ["Fitness", "fitness"]),
        InterestDefinition(firestoreKey: "Naturaleza", localizationKey: "interest.nature", emoji: "🌿", aliases: ["Naturaleza", "naturaleza"]),
        InterestDefinition(firestoreKey: "Animales", localizationKey: "interest.animals", emoji: "🐾", aliases: ["Animales", "animales"]),
        InterestDefinition(firestoreKey: "Comida", localizationKey: "interest.food", emoji: "🍽️", aliases: ["Comida", "comida"]),
        InterestDefinition(firestoreKey: "Ciencia", localizationKey: "interest.science", emoji: "🔬", aliases: ["Ciencia", "ciencia"]),
        InterestDefinition(firestoreKey: "Historia", localizationKey: "interest.history", emoji: "📜", aliases: ["Historia", "historia"]),
        InterestDefinition(firestoreKey: "Política", localizationKey: "interest.politics", emoji: "🏛️", aliases: ["Política", "politica"]),
        InterestDefinition(firestoreKey: "Negocios", localizationKey: "interest.business", emoji: "💼", aliases: ["Negocios", "negocios"]),
        InterestDefinition(firestoreKey: "Salud", localizationKey: "interest.health", emoji: "❤️‍🩹", aliases: ["Salud", "salud"]),
        InterestDefinition(firestoreKey: "Estilo", localizationKey: "interest.style", emoji: "✨", aliases: ["Estilo", "estilo"]),
        InterestDefinition(firestoreKey: "Baile", localizationKey: "interest.dance", emoji: "💃", aliases: ["Baile", "baile"]),
        InterestDefinition(firestoreKey: "Escritura", localizationKey: "interest.writing", emoji: "✍️", aliases: ["Escritura", "escritura"]),
        InterestDefinition(firestoreKey: "DIY", localizationKey: "interest.diy", emoji: "🔧", aliases: ["DIY", "diy", "Bricolaje"]),
        InterestDefinition(firestoreKey: "Coches", localizationKey: "interest.cars", emoji: "🚗", aliases: ["Coches", "coches"]),
        InterestDefinition(firestoreKey: "Teatro", localizationKey: "interest.theater", emoji: "🎭", aliases: ["Teatro", "teatro"]),
        InterestDefinition(firestoreKey: "Meditación", localizationKey: "interest.meditation", emoji: "🕯️", aliases: ["Meditación", "meditacion"]),
        InterestDefinition(firestoreKey: "Emprendimiento", localizationKey: "interest.entrepreneurship", emoji: "🚀", aliases: ["Emprendimiento", "emprendimiento"]),
        InterestDefinition(firestoreKey: "Yoga", localizationKey: "interest.yoga", emoji: "🧘", aliases: ["Yoga", "yoga"]),
        InterestDefinition(firestoreKey: "Café", localizationKey: "interest.coffee", emoji: "☕", aliases: ["Café", "cafe", "café"]),
        InterestDefinition(firestoreKey: "Astronomía", localizationKey: "interest.astronomy", emoji: "⭐", aliases: ["Astronomía", "astronomia"]),
        InterestDefinition(firestoreKey: "Podcasts", localizationKey: "interest.podcasts", emoji: "🎧", aliases: ["Podcasts", "podcasts"]),
        InterestDefinition(firestoreKey: "Mascotas", localizationKey: "interest.pets", emoji: "🐶", aliases: ["Mascotas", "mascotas"]),
        InterestDefinition(firestoreKey: "Diseño", localizationKey: "interest.design", emoji: "🖌️", aliases: ["Diseño", "diseno", "diseño"]),
        InterestDefinition(firestoreKey: "Programación", localizationKey: "interest.programming", emoji: "👩‍💻", aliases: ["Programación", "programacion", "programación"]),
        InterestDefinition(firestoreKey: "K-pop", localizationKey: "interest.kpop", emoji: "🎤", aliases: ["K-pop", "Kpop", "kpop", "k-pop"]),
        InterestDefinition(firestoreKey: "Anime", localizationKey: "interest.anime", emoji: "🎌", aliases: ["Anime", "anime"]),
        InterestDefinition(firestoreKey: "Senderismo", localizationKey: "interest.hiking", emoji: "🥾", aliases: ["Senderismo", "senderismo"]),
        InterestDefinition(firestoreKey: "Ciclismo", localizationKey: "interest.cycling", emoji: "🚴", aliases: ["Ciclismo", "ciclismo"]),
        InterestDefinition(firestoreKey: "Correr", localizationKey: "interest.running", emoji: "🏃", aliases: ["Correr", "correr", "Running"]),
        InterestDefinition(firestoreKey: "Escalada", localizationKey: "interest.climbing", emoji: "🧗", aliases: ["Escalada", "escalada"]),
        InterestDefinition(firestoreKey: "Surf", localizationKey: "interest.surfing", emoji: "🏄", aliases: ["Surf", "surf"]),
        InterestDefinition(firestoreKey: "Fútbol", localizationKey: "interest.football", emoji: "⚽", aliases: ["Fútbol", "futbol", "fútbol"]),
        InterestDefinition(firestoreKey: "Baloncesto", localizationKey: "interest.basketball", emoji: "🏀", aliases: ["Baloncesto", "baloncesto"]),
        InterestDefinition(firestoreKey: "Natación", localizationKey: "interest.swimming", emoji: "🏊", aliases: ["Natación", "natacion", "natación"]),
        InterestDefinition(firestoreKey: "Skate", localizationKey: "interest.skateboarding", emoji: "🛹", aliases: ["Skate", "skate"]),
        InterestDefinition(firestoreKey: "Vinilos", localizationKey: "interest.vinyl", emoji: "💿", aliases: ["Vinilos", "vinilos"]),
        InterestDefinition(firestoreKey: "Conciertos", localizationKey: "interest.concerts", emoji: "🎶", aliases: ["Conciertos", "conciertos"]),
        InterestDefinition(firestoreKey: "Hip-hop", localizationKey: "interest.hiphop", emoji: "🎤", aliases: ["Hip-hop", "hip-hop", "hip hop"]),
        InterestDefinition(firestoreKey: "Música electrónica", localizationKey: "interest.electronic_music", emoji: "🎛️", aliases: ["Música electrónica", "musica electronica"]),
        InterestDefinition(firestoreKey: "Repostería", localizationKey: "interest.baking", emoji: "🧁", aliases: ["Repostería", "reposteria", "repostería"]),
        InterestDefinition(firestoreKey: "Vino", localizationKey: "interest.wine", emoji: "🍷", aliases: ["Vino", "vino"]),
        InterestDefinition(firestoreKey: "Cerveza artesanal", localizationKey: "interest.craft_beer", emoji: "🍺", aliases: ["Cerveza artesanal", "cerveza"]),
        InterestDefinition(firestoreKey: "Belleza", localizationKey: "interest.beauty", emoji: "💄", aliases: ["Belleza", "belleza"]),
        InterestDefinition(firestoreKey: "Sneakers", localizationKey: "interest.sneakers", emoji: "👟", aliases: ["Sneakers", "sneakers"]),
        InterestDefinition(firestoreKey: "Tatuajes", localizationKey: "interest.tattoos", emoji: "🖋️", aliases: ["Tatuajes", "tatuajes"]),
        InterestDefinition(firestoreKey: "Plantas", localizationKey: "interest.plants", emoji: "🪴", aliases: ["Plantas", "plantas"]),
        InterestDefinition(firestoreKey: "Jardinería", localizationKey: "interest.gardening", emoji: "🌱", aliases: ["Jardinería", "jardineria", "jardinería"]),
        InterestDefinition(firestoreKey: "Idiomas", localizationKey: "interest.languages", emoji: "🌍", aliases: ["Idiomas", "idiomas"]),
        InterestDefinition(firestoreKey: "Voluntariado", localizationKey: "interest.volunteering", emoji: "🤝", aliases: ["Voluntariado", "voluntariado"]),
        InterestDefinition(firestoreKey: "Sostenibilidad", localizationKey: "interest.sustainability", emoji: "♻️", aliases: ["Sostenibilidad", "sostenibilidad"]),
        InterestDefinition(firestoreKey: "Cosplay", localizationKey: "interest.cosplay", emoji: "🦸", aliases: ["Cosplay", "cosplay"]),
        InterestDefinition(firestoreKey: "Crímenes reales", localizationKey: "interest.true_crime", emoji: "🕵️", aliases: ["Crímenes reales", "crimenes reales"]),
        InterestDefinition(firestoreKey: "Coleccionismo", localizationKey: "interest.collecting", emoji: "🃏", aliases: ["Coleccionismo", "coleccionismo"]),
        InterestDefinition(firestoreKey: "Manualidades", localizationKey: "interest.crafts", emoji: "✂️", aliases: ["Manualidades", "manualidades"]),
        InterestDefinition(firestoreKey: "Streaming", localizationKey: "interest.streaming", emoji: "📺", aliases: ["Streaming", "streaming"]),
        InterestDefinition(firestoreKey: "IA", localizationKey: "interest.ai", emoji: "🤖", aliases: ["IA", "ia", "Inteligencia artificial"]),
        InterestDefinition(firestoreKey: "Finanzas personales", localizationKey: "interest.personal_finance", emoji: "💰", aliases: ["Finanzas personales", "finanzas"]),
        InterestDefinition(firestoreKey: "Filosofía", localizationKey: "interest.philosophy", emoji: "💭", aliases: ["Filosofía", "filosofia", "filosofía"]),
        InterestDefinition(firestoreKey: "Ajedrez", localizationKey: "interest.chess", emoji: "♟️", aliases: ["Ajedrez", "ajedrez"]),
        InterestDefinition(firestoreKey: "Juegos de mesa", localizationKey: "interest.board_games", emoji: "🎲", aliases: ["Juegos de mesa", "juegos de mesa"]),
    ]

    private static let lookup: [String: InterestDefinition] = {
        var map: [String: InterestDefinition] = [:]
        for def in all {
            map[def.firestoreKey] = def
            for alias in def.aliases {
                map[alias] = def
            }
        }
        return map
    }()

    static var firestoreKeys: [String] {
        all.map(\.firestoreKey)
    }

    static func definition(for raw: String) -> InterestDefinition? {
        if let exact = lookup[raw] { return exact }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = lookup[trimmed] { return exact }
        let lower = trimmed.lowercased()
        for (key, def) in lookup where key.lowercased() == lower {
            return def
        }
        return nil
    }

    static func localize(_ raw: String) -> String {
        guard let def = definition(for: raw) else { return raw }
        let fallback = def.firestoreKey
        return NSLocalizedString(def.localizationKey, value: fallback, comment: "Interest")
    }

    static func emoji(for raw: String) -> String {
        definition(for: raw)?.emoji ?? InterestEmojiLegacy.emoji(for: raw)
    }
}

/// Compat — delega en [InterestCatalog].
enum InterestOption {
    static func localize(_ key: String) -> String {
        InterestCatalog.localize(key)
    }
}

/// Fallback emoji por texto suelto (legacy / custom).
private enum InterestEmojiLegacy {
    static func emoji(for interest: String) -> String {
        switch interest.lowercased() {
        case "ajedrez": return "♟️"
        case "animales": return "🐾"
        case "anime": return "🎌"
        case "arte": return "🎨"
        case "astronomia": return "⭐"
        case "astronomía": return "⭐"
        case "baile": return "💃"
        case "baloncesto": return "🏀"
        case "belleza": return "💄"
        case "bricolaje": return "🔧"
        case "cafe": return "☕"
        case "café": return "☕"
        case "cerveza artesanal": return "🍺"
        case "cerveza": return "🍺"
        case "ciclismo": return "🚴"
        case "ciencia": return "🔬"
        case "cine": return "🎬"
        case "coches": return "🚗"
        case "cocina": return "👨‍🍳"
        case "coleccionismo": return "🃏"
        case "comida": return "🍽️"
        case "conciertos": return "🎶"
        case "correr": return "🏃"
        case "cosplay": return "🦸"
        case "crimenes reales": return "🕵️"
        case "crímenes reales": return "🕵️"
        case "deportes": return "⚽"
        case "diseno": return "🖌️"
        case "diseño": return "🖌️"
        case "diy": return "🔧"
        case "emprendimiento": return "🚀"
        case "escalada": return "🧗"
        case "escritura": return "✍️"
        case "estilo": return "✨"
        case "filosofia": return "💭"
        case "filosofía": return "💭"
        case "finanzas personales": return "💰"
        case "finanzas": return "💰"
        case "fitness": return "💪"
        case "fotografia": return "📸"
        case "fotografía": return "📸"
        case "futbol": return "⚽"
        case "fútbol": return "⚽"
        case "gaming": return "🎮"
        case "hip hop": return "🎤"
        case "hip-hop": return "🎤"
        case "historia": return "📜"
        case "ia": return "🤖"
        case "idiomas": return "🌍"
        case "inteligencia artificial": return "🤖"
        case "jardineria": return "🌱"
        case "jardinería": return "🌱"
        case "juegos de mesa": return "🎲"
        case "k-pop": return "🎤"
        case "kpop": return "🎤"
        case "lectura": return "📚"
        case "libros": return "📚"
        case "manualidades": return "✂️"
        case "mascotas": return "🐶"
        case "meditacion": return "🕯️"
        case "meditación": return "🕯️"
        case "moda": return "👗"
        case "musica electronica": return "🎛️"
        case "musica": return "🎵"
        case "música electrónica": return "🎛️"
        case "música": return "🎵"
        case "natacion": return "🏊"
        case "natación": return "🏊"
        case "naturaleza": return "🌿"
        case "negocios": return "💼"
        case "plantas": return "🪴"
        case "podcasts": return "🎧"
        case "politica": return "🏛️"
        case "política": return "🏛️"
        case "programacion": return "👩‍💻"
        case "programación": return "👩‍💻"
        case "reposteria": return "🧁"
        case "repostería": return "🧁"
        case "running": return "🏃"
        case "salud": return "❤️‍🩹"
        case "senderismo": return "🥾"
        case "skate": return "🛹"
        case "sneakers": return "👟"
        case "sostenibilidad": return "♻️"
        case "streaming": return "📺"
        case "surf": return "🏄"
        case "tatuajes": return "🖋️"
        case "teatro": return "🎭"
        case "tecnologia": return "💻"
        case "tecnología": return "💻"
        case "viajar": return "✈️"
        case "viajes": return "✈️"
        case "videojuegos": return "🎮"
        case "vinilos": return "💿"
        case "vino": return "🍷"
        case "voluntariado": return "🤝"
        case "yoga": return "🧘"
        default: return "✨"
        }
    }
}
