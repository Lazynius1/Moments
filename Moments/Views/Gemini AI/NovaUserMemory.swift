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
    let importance: Int
    var lastVerified: Date
    var lastProbedAt: Date? // 🆕 Para rastrear cuándo Nova mencionó esto por última vez
    var embedding: [Double]? // 🔍 RAG: Vector semántico
    
    init(id: String = UUID().uuidString, content: String, type: NovaFactType, timestamp: Date = Date(), importance: Int = 3, lastVerified: Date = Date(), lastProbedAt: Date? = nil, embedding: [Double]? = nil) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.importance = max(1, min(5, importance)) // Clamp entre 1-5
        self.lastVerified = lastVerified
        self.lastProbedAt = lastProbedAt
        self.embedding = embedding
    }
    
    // Para compatibilidad con Firestore
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "content": content,
            "type": type.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "importance": importance,
            "lastVerified": Timestamp(date: lastVerified),
            "lastProbedAt": lastProbedAt != nil ? Timestamp(date: lastProbedAt!) : NSNull()
        ]
        
        if let embedding = embedding {
            dict["embedding"] = embedding
        }
        
        return dict
    }
    
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let content = dictionary["content"] as? String,
              let typeString = dictionary["type"] as? String,
              let type = NovaFactType(rawValue: typeString),
              let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.importance = dictionary["importance"] as? Int ?? 3
        self.lastVerified = (dictionary["lastVerified"] as? Timestamp)?.dateValue() ?? timestamp
        self.lastProbedAt = (dictionary["lastProbedAt"] as? Timestamp)?.dateValue()
        self.embedding = dictionary["embedding"] as? [Double]
    }
    
    // Score para ordenamiento (mayor = más importante)
    var relevanceScore: Int {
        return (type.priority * 10) + importance
    }
    
    // Contenido normalizado para comparaciones (sin indicadores de categoría o prefijos comunes)
    var normalizedContent: String {
        let text = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Prefijos comunes a eliminar en varios idiomas
        let prefixes = [
            "vive en ", "viu a ", "lives in ",
            "trabaja de ", "trabaja como ", "treballa de ", "works as ",
            "le gusta ", "li agrada ", "likes ",
            "es un ", "es una ", "és un ", "és una ", "is a ", "is an ",
            "tiene ", "té ", "has "
        ]
        
        var normalized = text
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
            }
        }
        
        // Eliminar puntuación al final
        while normalized.hasSuffix(".") || normalized.hasSuffix("!") || normalized.hasSuffix("?") {
            normalized = String(normalized.dropLast())
        }
        
        return normalized.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 🎭 PERFIL DE COMPORTAMIENTO (NUEVO)
struct NovaBehaviorProfile: Codable {
    var averageMessageLength: Double // Palabras por mensaje
    var emojiFrequency: Double       // Emojis por mensaje
    var vocabularyComplexity: Int    // 1-10 (Simple -> Complejo)
    var sentimentTrend: Double       // -1.0 (Negativo) a 1.0 (Positivo)
    var lastUpdated: Date
    
    // Valores por defecto (Usuario promedio)
    static var `default`: NovaBehaviorProfile {
        return NovaBehaviorProfile(
            averageMessageLength: 10.0,
            emojiFrequency: 0.2,
            vocabularyComplexity: 5,
            sentimentTrend: 0.2, // Ligeramente positivo por defecto
            lastUpdated: Date()
        )
    }
    
    // Para compatibilidad con Firestore
    var dictionary: [String: Any] {
        return [
            "averageMessageLength": averageMessageLength,
            "emojiFrequency": emojiFrequency,
            "vocabularyComplexity": vocabularyComplexity,
            "sentimentTrend": sentimentTrend,
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
    }
    
    init(averageMessageLength: Double, emojiFrequency: Double, vocabularyComplexity: Int, sentimentTrend: Double, lastUpdated: Date) {
        self.averageMessageLength = averageMessageLength
        self.emojiFrequency = emojiFrequency
        self.vocabularyComplexity = vocabularyComplexity
        self.sentimentTrend = sentimentTrend
        self.lastUpdated = lastUpdated
    }
    
    init?(dictionary: [String: Any]) {
        guard let avgMsgLen = dictionary["averageMessageLength"] as? Double,
              let emojiFreq = dictionary["emojiFrequency"] as? Double,
              let vocabComp = dictionary["vocabularyComplexity"] as? Int,
              let sentiment = dictionary["sentimentTrend"] as? Double,
              let updatedTimestamp = dictionary["lastUpdated"] as? Timestamp else {
            return nil
        }
        
        self.averageMessageLength = avgMsgLen
        self.emojiFrequency = emojiFreq
        self.vocabularyComplexity = vocabComp
        self.sentimentTrend = sentiment
        self.lastUpdated = updatedTimestamp.dateValue()
    }
}

// MARK: - 🎯 MEMORIA MEJORADA CON CATEGORIZACIÓN
struct NovaMemory: Identifiable {
    let id: String
    let userId: String
    var facts: [NovaFact]            // Hechos categorizados
    var lastUpdated: Date
    let createdAt: Date
    
    // 🎭 Perfil de Comportamiento (NUEVO)
    var behaviorProfile: NovaBehaviorProfile?
    
    // Spark activo para esta sesión (transitorio)
    var activeSpark: NovaFact? = nil
    
    init(id: String = UUID().uuidString, userId: String, facts: [NovaFact] = [], lastUpdated: Date = Date(), createdAt: Date = Date(), behaviorProfile: NovaBehaviorProfile? = nil) {
        self.id = id
        self.userId = userId
        self.facts = facts
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
        self.behaviorProfile = behaviorProfile
    }

    init(userId: String) {
        self.id = UUID().uuidString
        self.userId = userId
        self.facts = []
        self.lastUpdated = Date()
        self.createdAt = Date()
        self.behaviorProfile = .default
    }
    
    // Para Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "userId": userId,
            "facts": facts.map { $0.dictionary },
            "lastUpdated": Timestamp(date: lastUpdated),
            "createdAt": Timestamp(date: createdAt),
            "behaviorProfile": behaviorProfile?.dictionary ?? NovaBehaviorProfile.default.dictionary
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
        
        if let behaviorData = dictionary["behaviorProfile"] as? [String: Any] {
            self.behaviorProfile = NovaBehaviorProfile(dictionary: behaviorData)
        } else {
            self.behaviorProfile = .default
        }
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
            createdAt: createdAt,
            behaviorProfile: behaviorProfile
        )
    }
    
    /// Elimina un hecho específico por ID
    func removingFact(withId id: String) -> NovaMemory {
        let updatedFacts = facts.filter { $0.id != id }
        return NovaMemory(
            id: self.id,
            userId: self.userId,
            facts: updatedFacts,
            lastUpdated: Date(),
            createdAt: self.createdAt,
            behaviorProfile: self.behaviorProfile
        )
    }
    
    /// Elimina múltiples hechos por sus IDs
    func removingFacts(withIds ids: [String]) -> NovaMemory {
        let updatedFacts = facts.filter { !ids.contains($0.id) }
        return NovaMemory(
            id: self.id,
            userId: self.userId,
            facts: updatedFacts,
            lastUpdated: Date(),
            createdAt: self.createdAt,
            behaviorProfile: self.behaviorProfile
        )
    }
    
    /// Reemplaza un hecho existente conservando sus metadatos semánticos.
    func replacingFact(withId id: String, withNewContent content: String) -> NovaMemory {
        updatingFact(withId: id, content: content)
    }

    /// Actualiza un hecho existente conservando embeddings y trazabilidad.
    func updatingFact(withId id: String, content: String? = nil, importance: Int? = nil) -> NovaMemory {
        let updatedFacts = facts.map { fact in
            if fact.id == id {
                let resolvedContent = content ?? fact.content
                return NovaFact(
                    id: fact.id,
                    content: resolvedContent,
                    type: fact.type,
                    timestamp: fact.timestamp,
                    importance: importance ?? fact.importance,
                    lastVerified: Date(),
                    lastProbedAt: fact.lastProbedAt,
                    embedding: resolvedContent == fact.content ? fact.embedding : nil
                )
            }
            return fact
        }
        return NovaMemory(
            id: self.id,
            userId: self.userId,
            facts: updatedFacts,
            lastUpdated: Date(),
            createdAt: self.createdAt,
            behaviorProfile: self.behaviorProfile
        )
    }
    
    /// Actualiza el timestamp de la última vez que se usó un hecho
    func markingFactAsProbed(id: String) -> NovaMemory {
        let updatedFacts = facts.map { fact in
            if fact.id == id {
                var newFact = fact
                newFact.lastProbedAt = Date()
                return newFact
            }
            return fact
        }
        return NovaMemory(
            id: self.id,
            userId: self.userId,
            facts: updatedFacts,
            lastUpdated: Date(),
            createdAt: self.createdAt,
            behaviorProfile: self.behaviorProfile
        )
    }
    
    /// Obtener el nombre preferido del usuario
    var preferredName: String? {
        // Buscar preferencias de nombre
        let namePreferences = facts.filter { fact in
            fact.type == .preference &&
            (fact.content.lowercased().contains("llámame") ||
             fact.content.lowercased().contains("dime") ||
             fact.content.lowercased().contains("prefiere que le llamen") ||
             fact.content.lowercased().contains("prefiero que me digas") ||
             fact.content.lowercased().contains("prefers to be called") ||
             fact.content.lowercased().contains("call me") ||
             fact.content.lowercased().contains("my name is") ||
             fact.content.lowercased().contains("you can call me") ||
             fact.content.lowercased().contains("prefereix que li diguin") ||
             fact.content.lowercased().contains("digues-me") ||
             fact.content.lowercased().contains("digue'm") ||
             fact.content.lowercased().contains("em dic"))
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
        
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let labels: (userInfo: String, prefs: String, personal: String, work: String, interests: String, rules: String, rule1: String, rule2: String, rule3: String, rule4: String)
        switch lang {
        case .es:
            labels = ("MATICES DE TU ESENCIA:", "⚙️ VIBRAS:", "👤 ESENCIA:", "💼 CAMINO:", "❤️ PASIONES:", "INSTRUCCIONES PARA FLUIR:", "- Integra estos matices con naturalidad y calidez, como un amigo", "- Usa el nombre preferido SIEMPRE, es tu identidad aquí", "- Adapta tu ritmo a estas preferencias sin ser evidente", "- Evita repetir datos fríos; prefiere evocar sensaciones y apoyo.")
        case .en:
            labels = ("NUANCES OF YOUR ESSENCE:", "⚙️ VIBES:", "👤 ESSENCE:", "💼 PATH:", "❤️ PASSIONS:", "INSTRUCTIONS TO FLOW:", "- Integrate these nuances naturally and with warmth, like a friend", "- ALWAYS use the preferred name, it's your identity here", "- Adapt your rhythm to these preferences seamlessly", "- Avoid repeating cold facts; prefer evoking feelings and support.")
        case .ca:
            labels = ("MATISOS DE LA TEVA ESSÈNCIA:", "⚙️ VIBRES:", "👤 ESSÈNCIA:", "💼 CAMÍ:", "❤️ PASSIONS:", "INSTRUCCIONS PER FLUIR:", "- Integra aquests matisos amb naturalitat i calidesa, com un amic", "- Fes servir el nom preferit SEMPRE, és l'identitat de l'usuari", "- Adapta el teu ritme a aquestes preferències de forma fluida", "- Evita repetir dades fredes; prefereix evocar sensacions i suport.")
        }
        
        
        // 🔍 SELECCIONAR UN "SPARK" CONVERSACIONAL (Usar el activo)
        let spark = activeSpark
        
        var context = "\(labels.userInfo)\n\n"
        
        // 🎯 PREFERENCIAS PRIMERO (muy importante)
        let preferences = facts.filter { $0.type == .preference }
        if !preferences.isEmpty {
            context += "\(labels.prefs)\n"
            for pref in preferences.sorted(by: { $0.timestamp > $1.timestamp }) {
                context += "- \(pref.content)\n"
            }
            context += "\n"
        }
        
        // 👤 INFORMACIÓN PERSONAL
        let personalFacts = facts.filter { $0.type == .personal }
        if !personalFacts.isEmpty {
            context += "\(labels.personal)\n"
            // Variar los hechos personales que se muestran si hay muchos
            let selectedFacts = personalFacts.count > 3 ? Array(personalFacts.shuffled().prefix(3)) : personalFacts
            for fact in selectedFacts {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        // 💼 INFORMACIÓN PROFESIONAL
        let professionalFacts = facts.filter { $0.type == .professional }
        if !professionalFacts.isEmpty {
            context += "\(labels.work)\n"
            for fact in professionalFacts.prefix(3) {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        // ❤️ INTERESES
        let interestFacts = facts.filter { $0.type == .interest }
        if !interestFacts.isEmpty {
            context += "\(labels.interests)\n"
            for fact in interestFacts.prefix(2) {
                context += "- \(fact.content)\n"
            }
            context += "\n"
        }
        
        context += """
        \(labels.rules)
        \(labels.rule1)
        \(labels.rule2)
        \(labels.rule3)
        \(labels.rule4)
        """
        
        // 🔥 INYECTAR EL SPARK SI EXISTE
        if let spark = spark {
            let refinedContent = refineSparkContent(spark.content, lang: lang)
            let sparkInstruction = lang == .es ? "🔥 TEMA DE CONVERSACIÓN SUGERIDO: '\(refinedContent)'. Si la conversación decae o es relevante, menciona esto CASUALMENTE (ej: 'Por cierto, ¿cómo va lo de...?'). No lo fuerces." : (lang == .ca ? "🔥 TEMA DE CONVERSA SUGGERIT: '\(refinedContent)'. Si la conversa decau o és rellevant, esmenta això CASUALMENT. No ho forcis." : "🔥 SUGGESTED CONVERSATION TOPIC: '\(refinedContent)'. If the conversation lulls or it fits, mention this CASUALLY (e.g., 'By the way, how is...?'). Don't force it.")
            context += "\n\n\(sparkInstruction)"
        }
        
        return context
    }
    
    /// Selecciona un hecho aleatorio para ser el Spark activo
    mutating func selectRandomSpark() {
        // Solo hechos personales, profesionales o intereses
        let candidates = facts.filter {
            ($0.type == .personal || $0.type == .professional || $0.type == .interest) &&
            $0.importance >= 3
        }
        
        // Filtrar los que ya se han usado recientemente (últimas 24h)
        let freshCandidates = candidates.filter {
            guard let lastProbed = $0.lastProbedAt else { return true }
            return Date().timeIntervalSince(lastProbed) > 86400 // 24 horas
        }
        
        // 🛡️ FILTRO DE SENSIBILIDAD Y COMPLEJIDAD
        let safeCandidates = freshCandidates.filter {
            isContentSafeForProactiveRecall($0.content) &&
            !isGrammaticallyComplex($0.content)
        }
        
        // Devolver uno aleatorio de los top 5 más relevantes
        self.activeSpark = safeCandidates.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(5).randomElement()
    }
    
    /// 🛡️ Comprueba si el contenido es seguro para sacar como tema de conversación
    func isContentSafeForProactiveRecall(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        
        let blacklist = [
            // Salud / Muerte / Dolor
            "broken", "pain", "sick", "hospital", "died", "death", "kill", "hurt", "injury",
            "enfermo", "dolor", "hospital", "muerte", "murió", "matar", "herida", "lesión", "falleció",
            "malalt", "mort", "ferida", "lesió",
            
            // Emociones Negativas Fuertes
            "hate", "furious", "depressed", "anxiety", "lonely", "suicide",
            "odio", "furioso", "deprimido", "ansiedad", "solo", "suicidio", "triste",
            "odi", "furiós", "deprimit", "ansietat", "sol",
            
            // Situaciones Complejas / Crisis
            "breakup", "divorce", "fired", "broke up", "ex-",
            "ruptura", "divorcio", "despedido", "cortamos", "exnovi", "exmarido", "exmujer",
            "trencament", "divorci", "acomiadat"
        ]
        
        for term in blacklist {
            if lowercased.contains(term) {
                print("🚫 Spark rechazado por seguridad ('\(term)'): \(content)")
                return false
            }
        }
        
        return true
    }
    
    /// 🛡️ Evitar hechos gramaticalmente complejos o demasiado largos
    func isGrammaticallyComplex(_ content: String) -> Bool {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        
        // 1. Demasiado largo (> 12 palabras es difícil de meter casualmente)
        if words.count > 12 { return true }
        
        // 2. Conectores complejos que sugieren múltiples oraciones
        let complexConnectors = [" y ", " and ", " i ", " pero ", " but ", " aunque ", " although ", " porque ", " because "]
        for connector in complexConnectors {
            if content.lowercased().contains(connector) {
                // Si tiene conectores, mejor evitarlo para spark (puede ser una frase compuesta rara)
                return true
            }
        }
        
        return false
    }
    
    /// 🎨 Refina el contenido del hecho para que suene mejor en una frase "Por cierto, qué tal..."
    private func refineSparkContent(_ content: String, lang: NovaLanguage) -> String {
        var text = content
        let lower = text.lowercased()
        
        // Prefijos comunes a eliminar para convertir oración en "tópico"
        // Ej: "Juego al tenis" -> "el tenis"
        // Ej: "Trabajo en Apple" -> "tu trabajo en Apple"
        
        switch lang {
        case .es:
            if lower.hasPrefix("me gusta ") { text = String(text.dropFirst(9)) }
            else if lower.hasPrefix("odio ") { text = String(text.dropFirst(5)) }
            else if lower.hasPrefix("juego a ") { text = String(text.dropFirst(8)) }
            else if lower.hasPrefix("soy ") { text = "tu faceta de " + String(text.dropFirst(4)) }
            else if lower.hasPrefix("trabajo en ") { text = "tu trabajo en " + String(text.dropFirst(11)) }
            else if lower.hasPrefix("vivo en ") { text = "la vida en " + String(text.dropFirst(8)) }
            
        case .en:
            if lower.hasPrefix("i like ") { text = String(text.dropFirst(7)) }
            else if lower.hasPrefix("i hate ") { text = String(text.dropFirst(7)) }
            else if lower.hasPrefix("i play ") { text = String(text.dropFirst(7)) }
            else if lower.hasPrefix("i am ") { text = "being " + String(text.dropFirst(5)) }
            else if lower.hasPrefix("i work at ") { text = "your work at " + String(text.dropFirst(10)) }
            else if lower.hasPrefix("i live in ") { text = "life in " + String(text.dropFirst(10)) }
            
        case .ca:
            if lower.hasPrefix("m'agrada ") { text = String(text.dropFirst(9)) }
            else if lower.hasPrefix("odio ") { text = String(text.dropFirst(5)) }
            else if lower.hasPrefix("jugo a ") { text = String(text.dropFirst(7)) }
            else if lower.hasPrefix("soc ") { text = "la teva faceta de " + String(text.dropFirst(4)) }
            else if lower.hasPrefix("treballo a ") { text = "la teva feina a " + String(text.dropFirst(11)) }
            else if lower.hasPrefix("visc a ") { text = "la vida a " + String(text.dropFirst(7)) }
        }
        
        return text
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
        
        // 🎯 PATRONES MULTILINGÜES (ES/EN/CA)
        let spanishPatterns = [
            // Directas
            "llámame ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "llamame ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "dime ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "mi nombre es ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "me llamo ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "soy ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            // Indirectas
            "prefiero que me digas ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "prefiere que le llamen ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "puedes decirme ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "me gusta que me digan ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            "me dicen ([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1})",
            // Casuales
            "([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1}) está bien",
            "([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1}) sin más",
            "([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1}) es mi nombre",
            "([a-záéíóúñ]+(?:\\s+[a-záéíóúñ]+){0,1}), para servirte"
        ]
        let englishPatterns = [
            // Direct
            "call me ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            "my name is ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            "i am ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            "i'm ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            // Indirect
            "you can call me ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            "people call me ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            "i like being called ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})",
            // Casual
            "([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1}) is fine",
            "just ([a-zA-Z\\-']+(?:\\s+[a-zA-Z\\-']+){0,1})"
        ]
        let catalanPatterns = [
            // Directes
            "digues-me ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            "digue'm ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            "em dic ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            "sóc ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            // Indirectes
            "pots dir-me ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            "m'agrada que em diguin ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            "em diuen ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})",
            // Informals
            "([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1}) està bé",
            "només ([a-zàèéíïòóúüç'-]+(?:\\s+[a-zàèéíïòóúüç'-]+){0,1})"
        ]
        let patterns = spanishPatterns + englishPatterns + catalanPatterns
        
        // 🔍 INTENTAR PATRONES REGEX PRIMERO
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(pref.startIndex..<pref.endIndex, in: pref)
                if let match = regex.firstMatch(in: pref, options: [], range: range) {
                    if let nameRange = Range(match.range(at: 1), in: pref) {
                        let extractedName = String(pref[nameRange]).capitalized
                        LogConfig.log("🎯 Nombre extraído con regex: \(extractedName)", category: "Memory")
                        return extractedName
                    }
                }
            }
        }
        
        // 🧠 FALLBACK INTELIGENTE: Buscar palabras que parezcan nombres
        let words = pref.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            
            // ✅ CRITERIOS PARA UN NOMBRE VÁLIDO:
            if cleanWord.count >= 2 && cleanWord.count <= 20 && // Longitud razonable
               cleanWord.range(of: "^[a-zA-Zàèéíïòóúüçáéíóúñ'-]+$", options: .regularExpression) != nil && // Solo letras (ES/EN/CA)
               ![ // Stopwords comunes ES/EN/CA
                 // ES
                 "mi","me","es","está","esta","bien","sin","más","mas","para","servirte","prefiero","gusta","dicen","llamen","llamó","llamo","nombre","soy",
                 // EN
                 "my","name","is","i","am","i'm","just","call","me","you","can","people","like","being","called","it's",
                 // CA
                 "em","dic","sóc","soc","és","es","nom","només","està","be","bé","pots","dir-me","digue'm","digues-me","m'agrada","que","em","diuen"
               ].contains(cleanWord.lowercased()) {
                
                LogConfig.log("🎯 Nombre extraído con fallback inteligente: \(cleanWord.capitalized)", category: "Memory")
                return cleanWord.capitalized
            }
        }
        
        LogConfig.log("❌ No se pudo extraer nombre de: \(pref)", category: "Memory")
        return nil
    }
    
}

// MARK: - 🔧 EXTENSIONES ÚTILES
extension Array where Element == NovaFact {
    func removingDuplicatesByContent() -> [NovaFact] {
        var result: [NovaFact] = []
        
        for fact in self {
            let normalized = fact.normalizedContent
            
            // Si el contenido es demasiado corto, probablemente sea basura
            if normalized.count < 3 { continue }
            
            // Verificar si ya existe algo muy similar en el resultado
            let exists = result.contains { existing in
                // Si son del mismo tipo, ser más estrictos con la similitud
                if existing.type == fact.type {
                    let similarity = normalized.similarityScore(to: existing.normalizedContent)
                    return similarity > 0.7 // 70% de similitud es suficiente con normalización
                }
                return false
            }
            
            if !exists {
                result.append(fact)
            }
        }
        
        return result
    }
}

extension String {
    /// Calcula similitud básica entre strings (0.0 a 1.0)
    func similarityScore(to other: String) -> Double {
        let longer = self.count > other.count ? self : other
        _ = self.count > other.count ? other : self
        
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
