import Foundation
import FirebaseFirestore

// MARK: - 🎯 TIPOS DE HECHOS PARA CATEGORIZACIÓN
enum NovaFactType: String, CaseIterable {
    case preference = "preference"      // "Llámame Pepito", "Prefiero comunicación casual"
    case personal = "personal"          // "Vivo en Madrid", "Tengo un gato"
    case professional = "professional"  // "Trabajo como dev", "Estudio medicina"
    case interest = "interest"          // "Me gusta el fútbol", "Soy fan de Marvel"
    case general = "general"            // Otros hechos
    
    var priority: Int {
        switch self {
        case .preference: return 5      // Máxima prioridad
        case .personal: return 4
        case .professional: return 3
        case .interest: return 2
        case .general: return 1         // Mínima prioridad
        }
    }
    
    var emoji: String {
        switch self {
        case .preference: return "⚙️"
        case .personal: return "👤"
        case .professional: return "💼"
        case .interest: return "❤️"
        case .general: return "💭"
        }
    }
}

// MARK: - 🧠 HECHO CATEGORIZADO
struct NovaFact: Identifiable{
    let id: String
    let content: String
    let type: NovaFactType
    let timestamp: Date
    let importance: Int  // 1-5, donde 5 es más importante
    
    init(content: String, type: NovaFactType, importance: Int = 3) {
        self.id = UUID().uuidString
        self.content = content
        self.type = type
        self.timestamp = Date()
        self.importance = max(1, min(5, importance)) // Clamp entre 1-5
    }
    
    // Para compatibilidad con Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "content": content,
            "type": type.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "importance": importance
        ]
    }
    
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let content = dictionary["content"] as? String,
              let typeString = dictionary["type"] as? String,
              let type = NovaFactType(rawValue: typeString),
              let timestamp = dictionary["timestamp"] as? Timestamp,
              let importance = dictionary["importance"] as? Int else {
            return nil
        }
        
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp.dateValue()
        self.importance = importance
    }
    
    // Score para ordenamiento (mayor = más importante)
    var relevanceScore: Int {
        return (type.priority * 10) + importance
    }
}

// MARK: - 🎯 MEMORIA MEJORADA CON CATEGORIZACIÓN
struct NovaMemory: Identifiable {
    let id: String
    let userId: String
    let facts: [NovaFact]            // Hechos categorizados
    let lastUpdated: Date
    let createdAt: Date
    
    init(userId: String) {
        self.id = UUID().uuidString
        self.userId = userId
        self.facts = []
        self.lastUpdated = Date()
        self.createdAt = Date()
    }
    
    // Para Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "userId": userId,
            "facts": facts.map { $0.dictionary },
            "lastUpdated": Timestamp(date: lastUpdated),
            "createdAt": Timestamp(date: createdAt)
        ]
    }
    
    // Desde Firestore
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let userId = dictionary["userId"] as? String,
              let factsData = dictionary["facts"] as? [[String: Any]],
              let createdTimestamp = dictionary["createdAt"] as? Timestamp,
              let lastUpdatedTimestamp = dictionary["lastUpdated"] as? Timestamp else {
            return nil
        }
        
        self.id = id
        self.userId = userId
        self.facts = factsData.compactMap { NovaFact(dictionary: $0) }
        self.createdAt = createdTimestamp.dateValue()
        self.lastUpdated = lastUpdatedTimestamp.dateValue()
    }
    
    // MARK: - 🔧 Métodos Mejorados
    
    /// Añade nuevos hechos manteniendo solo los más relevantes
    func addingFacts(_ newFacts: [NovaFact]) -> NovaMemory {
        let maxMemoryItems = 20  // Aumentamos el límite
        
        // Combinar hechos existentes con nuevos
        let combinedFacts = (facts + newFacts)
            .removingDuplicatesByContent()
            .sorted { $0.relevanceScore > $1.relevanceScore }  // Los más importantes primero
        
        // Mantener balance por categorías
        let balancedFacts = maintainCategoryBalance(combinedFacts, maxItems: maxMemoryItems)
        
        return NovaMemory(
            id: id,
            userId: userId,
            facts: balancedFacts,
            lastUpdated: Date(),
            createdAt: createdAt
        )
    }
    
    /// Obtener el nombre preferido del usuario
    var preferredName: String? {
        // Buscar preferencias de nombre
        let namePreferences = facts.filter { fact in
            fact.type == .preference &&
            (fact.content.lowercased().contains("llámame") ||
             fact.content.lowercased().contains("dime") ||
             fact.content.lowercased().contains("prefiero que me digas"))
        }
        
        // Obtener el más reciente
        let mostRecentNamePref = namePreferences.sorted { $0.timestamp > $1.timestamp }.first
        
        return extractNameFromPreference(mostRecentNamePref?.content)
    }
    
    /// Contexto mejorado para Nova
    var contextString: String {
        if facts.isEmpty {
            return ""
        }
        
        var context = "INFORMACIÓN SOBRE EL USUARIO:\n\n"
        
        // 🎯 PREFERENCIAS PRIMERO (muy importante)
        let preferences = facts.filter { $0.type == .preference }
        if !preferences.isEmpty {
            context += "⚙️ PREFERENCIAS:\n"
            for pref in preferences.sorted(by: { $0.timestamp > $1.timestamp }) {
                context += "- \(pref.content)\n"
            }
            context += "\n"
        }
        
        // 👤 INFORMACIÓN PERSONAL
        let personalFacts = facts.filter { $0.type == .personal }
        if !personalFacts.isEmpty {
            context += "👤 PERSONAL:\n"
            for fact in personalFacts.prefix(3) {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        // 💼 INFORMACIÓN PROFESIONAL
        let professionalFacts = facts.filter { $0.type == .professional }
        if !professionalFacts.isEmpty {
            context += "💼 TRABAJO/ESTUDIOS:\n"
            for fact in professionalFacts.prefix(3) {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        // ❤️ INTERESES
        let interestFacts = facts.filter { $0.type == .interest }
        if !interestFacts.isEmpty {
            context += "❤️ INTERESES:\n"
            for fact in interestFacts.prefix(2) {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        context += """
        INSTRUCCIONES IMPORTANTES:
        - Usa esta información naturalmente, sin mencionar que la "recuerdas"
        - Si hay un nombre preferido, úsalo SIEMPRE en lugar del username
        - Aplica las preferencias de comunicación automáticamente
        - Esta información es SOBRE el usuario, no sobre ti (Nova)
        """
        
        return context
    }
    
    /// Verificar si está vacía
    var isEmpty: Bool {
        return facts.isEmpty
    }
    
    /// Obtener hechos por categoría
    func facts(ofType type: NovaFactType) -> [NovaFact] {
        return facts.filter { $0.type == type }.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Obtener los hechos más importantes
    var mostImportantFacts: [NovaFact] {
        return facts.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(5).map { $0 }
    }
    
    // MARK: - 🔧 Métodos Privados
    
    /// Mantener balance entre categorías para no saturar con un solo tipo
    private func maintainCategoryBalance(_ sortedFacts: [NovaFact], maxItems: Int) -> [NovaFact] {
        var result: [NovaFact] = []
        var factsByType: [NovaFactType: [NovaFact]] = [:]
        
        // Agrupar por tipo
        for fact in sortedFacts {
            factsByType[fact.type, default: []].append(fact)
        }
        
        // Límites por categoría (asegurar diversidad)
        let limits: [NovaFactType: Int] = [
            .preference: 6,     // Máximo 5 preferencias
            .personal: 6,       // Máximo 4 hechos personales
            .professional: 6,   // Máximo 4 profesionales
            .interest: 6,       // Máximo 3 intereses
            .general: 6         // Máximo 4 generales
        ]
        
        // Añadir hechos respetando límites y prioridades
        for type in NovaFactType.allCases.sorted(by: { $0.priority > $1.priority }) {
            let factsOfType = factsByType[type] ?? []
            let limit = limits[type] ?? 2
            let toAdd = Array(factsOfType.prefix(limit))
            result.append(contentsOf: toAdd)
            
            if result.count >= maxItems {
                break
            }
        }
        
        return Array(result.prefix(maxItems))
    }
    
    /// Extraer nombre de una preferencia como "Llámame Pepito"
    private func extractNameFromPreference(_ preference: String?) -> String? {
        guard let pref = preference?.lowercased() else { return nil }
        
        // Patrones comunes para detectar nombres
        let patterns = [
            "llámame ([a-záéíóúñ]+)",
            "dime ([a-záéíóúñ]+)",
            "prefiero que me digas ([a-záéíóúñ]+)",
            "mi nombre es ([a-záéíóúñ]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(pref.startIndex..<pref.endIndex, in: pref)
                if let match = regex.firstMatch(in: pref, options: [], range: range) {
                    if let nameRange = Range(match.range(at: 1), in: pref) {
                        return String(pref[nameRange]).capitalized
                    }
                }
            }
        }
        
        return nil
    }
    
    // Inicializador interno para actualizaciones
    private init(id: String, userId: String, facts: [NovaFact], lastUpdated: Date, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.facts = facts
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
    }
}

// MARK: - 🔧 EXTENSIONES ÚTILES
extension Array where Element == NovaFact {
    func removingDuplicatesByContent() -> [NovaFact] {
        var seen = Set<String>()
        return compactMap { fact in
            let normalized = fact.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Considerar duplicados si el contenido es muy similar
            let similarExists = seen.contains { existingContent in
                let similarity = normalized.similarityScore(to: existingContent)
                return similarity > 0.8  // 80% de similitud = duplicado
            }
            
            if similarExists {
                return nil
            }
            
            seen.insert(normalized)
            return fact
        }
    }
}

extension String {
    /// Calcula similitud básica entre strings (0.0 a 1.0)
    func similarityScore(to other: String) -> Double {
        let longer = self.count > other.count ? self : other
        let shorter = self.count > other.count ? other : self
        
        if longer.count == 0 {
            return 1.0
        }
        
        let editDistance = levenshteinDistance(to: other)
        return (Double(longer.count) - Double(editDistance)) / Double(longer.count)
    }
    
    /// Distancia de Levenshtein simplificada
    private func levenshteinDistance(to other: String) -> Int {
        let selfArray = Array(self)
        let otherArray = Array(other)
        let selfCount = selfArray.count
        let otherCount = otherArray.count
        
        if selfCount == 0 { return otherCount }
        if otherCount == 0 { return selfCount }
        
        var matrix = Array(repeating: Array(repeating: 0, count: otherCount + 1), count: selfCount + 1)
        
        for i in 0...selfCount {
            matrix[i][0] = i
        }
        
        for j in 0...otherCount {
            matrix[0][j] = j
        }
        
        for i in 1...selfCount {
            for j in 1...otherCount {
                let cost = selfArray[i-1] == otherArray[j-1] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[selfCount][otherCount]
    }
}
