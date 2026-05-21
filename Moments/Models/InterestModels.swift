import Foundation

/// Modelo para gestionar la localización de intereses sin alterar la base de datos (que usa español como keys/IDs)
enum InterestOption: String, CaseIterable, Identifiable {
    // Keys EXACTOS de la base de datos (Español)
    case photography = "Fotografía"
    case travel = "Viajes"
    case music = "Música"
    case movies = "Cine"
    case art = "Arte"
    case sports = "Deportes"
    case books = "Libros"
    case cooking = "Cocina"
    case technology = "Tecnología"
    case fashion = "Moda"
    case gaming = "Gaming"
    case fitness = "Fitness"
    case nature = "Naturaleza"
    case animals = "Animales"
    case food = "Comida"
    case science = "Ciencia"
    case history = "Historia"
    case politics = "Política"
    case business = "Negocios"
    case health = "Salud"
    case style = "Estilo"
    case dance = "Baile"
    case writing = "Escritura"
    case diy = "DIY"
    case cars = "Coches"
    
    // Fallback para casos desconocidos
    case unknown
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .photography: return NSLocalizedString("interest.photography", value: "Photography", comment: "Interest: Photography")
        case .travel: return NSLocalizedString("interest.travel", value: "Travel", comment: "Interest: Travel")
        case .music: return NSLocalizedString("interest.music", value: "Music", comment: "Interest: Music")
        case .movies: return NSLocalizedString("interest.movies", value: "Movies", comment: "Interest: Movies")
        case .art: return NSLocalizedString("interest.art", value: "Art", comment: "Interest: Art")
        case .sports: return NSLocalizedString("interest.sports", value: "Sports", comment: "Interest: Sports")
        case .books: return NSLocalizedString("interest.books", value: "Books", comment: "Interest: Books")
        case .cooking: return NSLocalizedString("interest.cooking", value: "Cooking", comment: "Interest: Cooking")
        case .technology: return NSLocalizedString("interest.technology", value: "Technology", comment: "Interest: Technology")
        case .fashion: return NSLocalizedString("interest.fashion", value: "Fashion", comment: "Interest: Fashion")
        case .gaming: return NSLocalizedString("interest.gaming", value: "Gaming", comment: "Interest: Gaming")
        case .fitness: return NSLocalizedString("interest.fitness", value: "Fitness", comment: "Interest: Fitness")
        case .nature: return NSLocalizedString("interest.nature", value: "Nature", comment: "Interest: Nature")
        case .animals: return NSLocalizedString("interest.animals", value: "Animals", comment: "Interest: Animals")
        case .food: return NSLocalizedString("interest.food", value: "Food", comment: "Interest: Food")
        case .science: return NSLocalizedString("interest.science", value: "Science", comment: "Interest: Science")
        case .history: return NSLocalizedString("interest.history", value: "History", comment: "Interest: History")
        case .politics: return NSLocalizedString("interest.politics", value: "Politics", comment: "Interest: Politics")
        case .business: return NSLocalizedString("interest.business", value: "Business", comment: "Interest: Business")
        case .health: return NSLocalizedString("interest.health", value: "Health", comment: "Interest: Health")
        case .style: return NSLocalizedString("interest.style", value: "Style", comment: "Interest: Style")
        case .dance: return NSLocalizedString("interest.dance", value: "Dance", comment: "Interest: Dance")
        case .writing: return NSLocalizedString("interest.writing", value: "Writing", comment: "Interest: Writing")
        case .diy: return NSLocalizedString("interest.diy", value: "DIY", comment: "Interest: DIY")
        case .cars: return NSLocalizedString("interest.cars", value: "Cars", comment: "Interest: Cars")
        case .unknown: return ""
        }
    }
    
    // Función estática para localizar cualquier string
    static func localize(_ key: String) -> String {
        // Intentar encontrar el caso exacto
        if let option = InterestOption(rawValue: key) {
            return option.localizedName
        }
        
        // Si no coincide exactamente, intentar normalizar (quitar espacios, minúsculas, etc) o devolver el key original
        // Esto permite que si la DB tiene "Fotografía " con espacio, o "fotografia" sin tilde, podamos mapearlo si quisiéramos
        // Por ahora, devolvemos el key original si no se encuentra, asumiendo que es un "custom interest" o algo nuevo
        return key
    }
}
