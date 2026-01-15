import Foundation
import FirebaseFirestore
import FirebaseVertexAI
import FirebaseAuth

// MARK: - 🔥 NUEVAS ESTRUCTURAS DE DATOS PARA ANÁLISIS DE CONVERSACIÓN

// 🎯 Nivel de engagement en la conversación
enum EngagementLevel {
    case low
    case medium
    case high
    
    var description: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch (self, lang) {
        case (.low, .es): return "Bajo"
        case (.medium, .es): return "Medio"
        case (.high, .es): return "Alto"
        case (.low, .en): return "Low"
        case (.medium, .en): return "Medium"
        case (.high, .en): return "High"
        case (.low, .ca): return "Baix"
        case (.medium, .ca): return "Mitjà"
        case (.high, .ca): return "Alt"
        }
    }
}

// 📊 Métricas de engagement de la conversación
struct ConversationEngagement {
    let level: EngagementLevel
    let userParticipation: Double      // 0.0 - 1.0
    let topicConsistency: Double       // 0.0 - 1.0
    
    var isEngaged: Bool {
        return level == .high || userParticipation > 0.5
    }
}

// 🎭 Patrones de comunicación del usuario
struct CommunicationPatterns {
    var averageMessageLength: Double = 0.0
    var prefersLongMessages: Bool = false
    var usesEmojis: Bool = false
    var emojiFrequency: Double = 0.0
    var isFormal: Bool = false
    var asksQuestions: Bool = false
    var questionFrequency: Double = 0.0
}

// 🔍 Extensión para detectar emojis
extension Character {
    var isEmoji: Bool {
        if let firstScalar = unicodeScalars.first, firstScalar.properties.isEmoji {
            return (firstScalar.value >= 0x238C || unicodeScalars.count > 1)
        }
        return false
    }
}

class NovaMemoryService {
    private let db = Firestore.firestore()
    private let vertexAI = VertexAI.vertexAI(location: "global")
    private lazy var model = vertexAI.generativeModel(modelName: "gemini-3-flash-preview")
    
    // ✅ Control de procesamiento múltiple
    private var isProcessingMemory = false
    private var lastProcessingTime: Date?
    private let minimumProcessingInterval: TimeInterval = 5.0
    
    // MARK: - 📁 Colección de Firestore (sin cambios)
    private func userMemoryCollection(for userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("novaMemory")
    }

    // MARK: - Prompts multilingües
    private func categorizationPrompt(for conversationText: String, lang: NovaLanguage) -> String {
        switch lang {
        case .es:
            return """
            Analiza esta conversación y extrae hechos importantes sobre el usuario, categorizándolos:
            
            CATEGORÍAS Y EJEMPLOS:
            🔸 PREFERENCE: Preferencias de comunicación, nombres, estilos
               - "Llámame Pepito" → "Prefiere que le llamen Pepito"
               - "Háblame de forma casual" → "Prefiere comunicación casual"
               - "No me gusta el tono formal" → "Prefiere tono informal"
            
            🔸 PERSONAL: Información personal permanente
               - "Vivo en Madrid" → "Vive en Madrid"
               - "Tengo 25 años" → "Tiene 25 años"
               - "Tengo un perro" → "Tiene un perro"
            
            🔸 PROFESSIONAL: Trabajo, estudios, carrera
               - "Soy desarrollador" → "Trabaja como desarrollador"
               - "Estudio medicina" → "Estudia medicina"
               - "Trabajo en Google" → "Trabaja en Google"
            
            🔸 INTEREST: Hobbies, gustos, aficiones
               - "Me encanta el fútbol" → "Le gusta el fútbol"
               - "Soy fan de Marvel" → "Es fan de Marvel"
            
            FORMATO DE RESPUESTA:
            PREFERENCE: [hecho si existe]
            PERSONAL: [hecho si existe]
            PROFESSIONAL: [hecho si existe]
            INTEREST: [hecho si existe]
            
            Si no hay hechos de una categoría, escribe "NINGUNO".
            Máximo 2 hechos por categoría.
            
            CONVERSACIÓN:
            \(conversationText)
            """
        case .en:
            return """
            Analyze this conversation and extract important facts about the user, categorizing them:
            
            CATEGORIES AND EXAMPLES:
            🔸 PREFERENCE: Communication preferences, names, styles
               - "Call me Joey" → "Prefers to be called Joey"
               - "Talk to me casually" → "Prefers casual communication"
               - "I don't like formal tone" → "Prefers informal tone"
            
            🔸 PERSONAL: Permanent personal information
               - "I live in Madrid" → "Lives in Madrid"
               - "I'm 25" → "Is 25 years old"
               - "I have a dog" → "Has a dog"
            
            🔸 PROFESSIONAL: Job, studies, career
               - "I'm a developer" → "Works as a developer"
               - "I study medicine" → "Studies medicine"
               - "I work at Google" → "Works at Google"
            
            🔸 INTEREST: Hobbies, likes, passions
               - "I love football" → "Likes football"
               - "I'm a Marvel fan" → "Is a Marvel fan"
            
            RESPONSE FORMAT:
            PREFERENCE: [fact if any]
            PERSONAL: [fact if any]
            PROFESSIONAL: [fact if any]
            INTEREST: [fact if any]
            
            If no facts exist for a category, write "NONE".
            Maximum 2 facts per category.
            
            CONVERSATION:
            \(conversationText)
            """
        case .ca:
            return """
            Analitza aquesta conversa i extreu fets importants sobre l'usuari, categoritzant-los:
            
            CATEGORIES I EXEMPLES:
            🔸 PREFERENCE: Preferències de comunicació, noms, estils
               - "Digues-me Pep" → "Prefereix que li diguin Pep"
               - "Parla'm de forma casual" → "Prefereix comunicació casual"
               - "No m'agrada el to formal" → "Prefereix to informal"
            
            🔸 PERSONAL: Informació personal permanent
               - "Visc a Madrid" → "Viu a Madrid"
               - "Tinc 25 anys" → "Té 25 anys"
               - "Tinc un gos" → "Té un gos"
            
            🔸 PROFESSIONAL: Feina, estudis, carrera
               - "Sóc desenvolupador" → "Treballa com a desenvolupador"
               - "Estudio medicina" → "Estudia medicina"
               - "Treballo a Google" → "Treballa a Google"
            
            🔸 INTEREST: Aficions, gustos, passions
               - "M'encanta el futbol" → "Li agrada el futbol"
               - "Sóc fan de Marvel" → "És fan de Marvel"
            
            FORMAT DE RESPOSTA:
            PREFERENCE: [fet si existeix]
            PERSONAL: [fet si existeix]
            PROFESSIONAL: [fet si existeix]
            INTEREST: [fet si existeix]
            
            Si no hi ha fets d'una categoria, escriu "CAP".
            Màxim 2 fets per categoria.
            
            CONVERSA:
            \(conversationText)
            """
        }
    }
    
    // MARK: - 💾 Cargar/Guardar Memoria (actualizados para nueva estructura)
    func loadMemory(for userId: String, completion: @escaping (Result<NovaMemory, Error>) -> Void) {
        LogConfig.log("🧠 Cargando memoria mejorada para usuario: \(userId)", category: "Memory")
        
        userMemoryCollection(for: userId).document("memory").getDocument { document, error in
            if let error = error {
                LogConfig.log("❌ Error cargando memoria: \(error.localizedDescription)", category: "Memory")
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists else {
                LogConfig.log("📝 No existe memoria previa, creando nueva...", category: "Memory")
                let newMemory = NovaMemory(userId: userId)
                completion(.success(newMemory))
                return
            }
            
            guard let data = document.data() else {
                completion(.failure(NSError(domain: "NovaMemory", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data found"])))
                return
            }
            
            // 🔄 MIGRACIÓN AUTOMÁTICA de memoria antigua a nueva estructura
            if let memory = NovaMemory(dictionary: data) {
                LogConfig.log("✅ Memoria nueva cargada: \(memory.facts.count) hechos categorizados", category: "Memory")
                completion(.success(memory))
            } else if let oldFacts = data["facts"] as? [String] {
                // Migrar memoria antigua (array de strings) a nueva estructura
                LogConfig.log("🔄 Migrando memoria antigua a nueva estructura...", category: "Memory")
                let migratedMemory = self.migrateOldMemory(userId: userId, oldFacts: oldFacts)
                completion(.success(migratedMemory))
            } else {
                LogConfig.log("❌ Error parseando memoria", category: "Memory")
                completion(.failure(NSError(domain: "NovaMemory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error parsing memory"])))
            }
        }
    }
    
    func saveMemory(_ memory: NovaMemory, completion: @escaping (Result<Void, Error>) -> Void) {
        LogConfig.log("💾 Guardando memoria mejorada: \(memory.facts.count) hechos", category: "Memory")
        
        // 🔍 DEBUG: Verificar estructura de datos antes de enviar
        LogConfig.log("🔍 DEBUG - Estructura de memoria:", category: "Memory")
        LogConfig.log("  - ID: \(memory.id)", category: "Memory")
        LogConfig.log("  - UserID: \(memory.userId)", category: "Memory")
        LogConfig.log("  - Facts count: \(memory.facts.count)", category: "Memory")
        LogConfig.log("  - Last updated: \(memory.lastUpdated)", category: "Memory")
        LogConfig.log("  - Created at: \(memory.createdAt)", category: "Memory")
        
        // 🔍 DEBUG: Verificar si los datos son válidos según las reglas
        if let firstFact = memory.facts.first {
            LogConfig.log("🔍 DEBUG - Primer hecho:", category: "Memory")
            LogConfig.log("  - Content: \(firstFact.content)", category: "Memory")
            LogConfig.log("  - Type: \(firstFact.type)", category: "Memory")
            LogConfig.log("  - Importance: \(firstFact.importance)", category: "Memory")
        }
        
        userMemoryCollection(for: memory.userId).document("memory").setData(memory.dictionary) { error in
            if let error = error {
                LogConfig.log("❌ Error guardando memoria: \(error.localizedDescription)", category: "Memory")
                
                // 🔍 DEBUG: Información adicional del error
                if let nsError = error as NSError? {
                    LogConfig.log("🔍 DEBUG - Código de error: \(nsError.code)", category: "Memory")
                    LogConfig.log("🔍 DEBUG - Dominio: \(nsError.domain)", category: "Memory")
                    if let userInfo = nsError.userInfo as? [String: Any] {
                        LogConfig.log("🔍 DEBUG - UserInfo: \(userInfo)", category: "Memory")
                    }
                }
                
                completion(.failure(error))
            } else {
                LogConfig.log("✅ Memoria guardada exitosamente", category: "Memory")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - 🧠 EXTRACCIÓN INTELIGENTE MEJORADA
    func extractFactsFromConversation(_ messages: [ChatMessage], userId: String, completion: @escaping ([NovaFact]) -> Void) {
        // ✅ PREVENIR MÚLTIPLES LLAMADAS SIMULTÁNEAS
        guard !isProcessingMemory else {
            LogConfig.log("⚠️ Ya se está procesando memoria - evitando duplicado", category: "Memory")
            completion([])
            return
        }
        
        // ✅ PREVENIR LLAMADAS MUY FRECUENTES
        let now = Date()
        if let lastTime = lastProcessingTime,
           now.timeIntervalSince(lastTime) < minimumProcessingInterval {
            LogConfig.log("⚠️ Memoria procesada recientemente - saltando", category: "Memory")
            completion([])
            return
        }
        
        guard messages.count >= 3 else {
            LogConfig.log("🚫 Conversación muy corta - no se extraerán hechos", category: "Memory")
            completion([])
            return
        }
        
        isProcessingMemory = true
        lastProcessingTime = now
        
        LogConfig.log("🔍 Extrayendo hechos categorizados de conversación con \(messages.count) mensajes", category: "Memory")
        
        // 🎯 DETECCIÓN RÁPIDA DE PREFERENCIAS (sin IA)
        let quickPreferences = detectPreferencesQuickly(from: messages)
        if !quickPreferences.isEmpty {
            LogConfig.log("⚡ Preferencias detectadas rápidamente: \(quickPreferences.count)", category: "Memory")
            isProcessingMemory = false
            completion(quickPreferences)
            return
        }
        
        // Preparar conversación para análisis con IA
        let recentMessages = Array(messages.suffix(8))
        let langForLabels = NovaLanguageService.getPreferredLanguage() ?? .es
        let userLabel: String = { switch langForLabels { case .es: return "Usuario"; case .en: return "User"; case .ca: return "Usuari" } }()
        let assistantLabel = "Nova"
        let conversationText = recentMessages.map { message in
            "\(message.isUser ? userLabel : assistantLabel): \(message.text)"
        }.joined(separator: "\n")
        
        // Pre-filtrar conversaciones casuales
        if isConversationCasual(conversationText) {
            LogConfig.log("💬 Conversación casual detectada - no se guardarán hechos", category: "Memory")
            isProcessingMemory = false
            completion([])
            return
        }
        
        // PROMPT MEJORADO para categorización automática (multilingüe)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let prompt = categorizationPrompt(for: conversationText, lang: lang)
        
        Task {
            do {
                let response = try await model.generateContent(prompt)
                guard let responseText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    DispatchQueue.main.async {
                        self.isProcessingMemory = false
                    }
                    completion([])
                    return
                }
                
                // Parsear respuesta categorizada
                let facts = self.parseCategorizatedResponse(responseText)
                
                DispatchQueue.main.async {
                    self.isProcessingMemory = false
                    LogConfig.log("✅ Extraídos \(facts.count) hechos categorizados", category: "Memory")
                    completion(facts)
                }
            } catch {
                LogConfig.log("❌ Error extrayendo hechos: \(error.localizedDescription)", category: "Memory")
                DispatchQueue.main.async {
                    self.isProcessingMemory = false
                    completion([])
                }
            }
        }
    }
    
    // MARK: - ⚡ DETECCIÓN RÁPIDA DE PREFERENCIAS (sin IA)
    private func detectPreferencesQuickly(from messages: [ChatMessage]) -> [NovaFact] {
        var preferences: [NovaFact] = []
        
        // Patrones para detectar preferencias comunes
        let namePatterns = [
            "llámame ([a-záéíóúñ]+)",
            "dime ([a-záéíóúñ]+)",
            "prefiero que me digas ([a-záéíóúñ]+)",
            "mi nombre es ([a-záéíóúñ]+)"
        ]
        
        let stylePatterns = [
            "háblame (de forma |)casual": localizedPreference("style.casual"),
            "háblame (de forma |)formal": localizedPreference("style.formal"),
            "sé más (divertido|gracioso)": localizedPreference("style.fun"),
            "no seas tan (formal|serio)": localizedPreference("style.informal"),
            "tutéame": localizedPreference("style.tuteo")
        ]
        
        // Buscar en mensajes del usuario
        for message in messages where message.isUser {
            let text = message.text.lowercased()
            
            // 🎯 Detectar preferencias de nombre
            for pattern in namePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: range) {
                        if let nameRange = Range(match.range(at: 1), in: text) {
                            let name = String(text[nameRange]).capitalized
                            let preference = NovaFact(
                                content: localizedPreferenceName(name),
                                type: .preference,
                                importance: 5
                            )
                            preferences.append(preference)
                            LogConfig.log("⚡ Preferencia de nombre detectada: \(name)", category: "Memory")
                        }
                    }
                }
            }
            
            // 🎯 Detectar preferencias de estilo
            for (pattern, preferenceText) in stylePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if regex.firstMatch(in: text, options: [], range: range) != nil {
                        let preference = NovaFact(
                            content: preferenceText,
                            type: .preference,
                            importance: 4
                        )
                        preferences.append(preference)
                        LogConfig.log("⚡ Preferencia de estilo detectada: \(preferenceText)", category: "Memory")
                    }
                }
            }
        }
        
        return preferences
    }
    
    // MARK: - 🔧 PARSER MEJORADO PARA RESPUESTAS CATEGORIZADAS
    private func parseCategorizatedResponse(_ response: String) -> [NovaFact] {
        var facts: [NovaFact] = []
        let lines = response.components(separatedBy: .newlines)
        
        var currentCategory: NovaFactType?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Detectar categorías
            if trimmed.hasPrefix("PREFERENCE:") {
                currentCategory = .preference
                let content = trimmed.replacingOccurrences(of: "PREFERENCE:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !isNoneToken(content) {
                    facts.append(NovaFact(content: content, type: .preference, importance: 5))
                }
            } else if trimmed.hasPrefix("PERSONAL:") {
                currentCategory = .personal
                let content = trimmed.replacingOccurrences(of: "PERSONAL:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !isNoneToken(content) {
                    facts.append(NovaFact(content: content, type: .personal, importance: 4))
                }
            } else if trimmed.hasPrefix("PROFESSIONAL:") {
                currentCategory = .professional
                let content = trimmed.replacingOccurrences(of: "PROFESSIONAL:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !isNoneToken(content) {
                    facts.append(NovaFact(content: content, type: .professional, importance: 3))
                }
            } else if trimmed.hasPrefix("INTEREST:") {
                currentCategory = .interest
                let content = trimmed.replacingOccurrences(of: "INTEREST:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !isNoneToken(content) {
                    facts.append(NovaFact(content: content, type: .interest, importance: 2))
                }
            } else if !trimmed.isEmpty && currentCategory != nil {
                // Línea adicional para la categoría actual
                if !isNoneToken(trimmed) && trimmed.count > 10 {
                    facts.append(NovaFact(content: trimmed, type: currentCategory!, importance: currentCategory!.priority))
                }
            }
        }
        
        return Array(facts.prefix(6)) // Máximo 6 hechos por conversación
    }

    private func isNoneToken(_ text: String) -> Bool {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return upper.contains("NINGUNO") || upper.contains("NONE") || upper.contains("CAP")
    }
    
    // MARK: - 🔄 MIGRACIÓN DE MEMORIA ANTIGUA
    private func migrateOldMemory(userId: String, oldFacts: [String]) -> NovaMemory {
        LogConfig.log("🔄 Migrando \(oldFacts.count) hechos antiguos...", category: "Memory")
        
        var migratedFacts: [NovaFact] = []
        
        for oldFact in oldFacts {
            // Categorizar hechos antiguos basándose en contenido
            let type = categorizeOldFact(oldFact)
            let importance = type.priority
            
            let fact = NovaFact(content: oldFact, type: type, importance: importance)
            migratedFacts.append(fact)
        }
        
        let memory = NovaMemory(userId: userId).addingFacts(migratedFacts)
        
        // Guardar memoria migrada
        saveMemory(memory) { result in
            switch result {
            case .success:
                LogConfig.log("✅ Memoria migrada y guardada exitosamente", category: "Memory")
            case .failure(let error):
                LogConfig.log("❌ Error guardando memoria migrada: \(error.localizedDescription)", category: "Memory")
            }
        }
        
        return memory
    }
    
    private func categorizeOldFact(_ fact: String) -> NovaFactType {
        let lowercased = fact.lowercased()
        
        // Detectar preferencias (ES/EN/CA)
        if lowercased.contains("prefiere") || lowercased.contains("llama") || lowercased.contains("gusta que") ||
           lowercased.contains("prefers") || lowercased.contains("call me") || lowercased.contains("likes being called") ||
           lowercased.contains("prefereix") || lowercased.contains("digues-me") || lowercased.contains("m'agrada que") {
            return .preference
        }
        
        // Detectar información profesional (ES/EN/CA)
        if lowercased.contains("trabaja") || lowercased.contains("estudia") || lowercased.contains("empresa") ||
           lowercased.contains("works") || lowercased.contains("study") || lowercased.contains("company") ||
           lowercased.contains("treballa") || lowercased.contains("estudia") || lowercased.contains("empresa") {
            return .professional
        }
        
        // Detectar información personal (ES/EN/CA)
        if lowercased.contains("vive") || lowercased.contains("tiene") || lowercased.contains("edad") ||
           lowercased.contains("lives") || lowercased.contains("age") || lowercased.contains("have") ||
           lowercased.contains("viu") || lowercased.contains("té") || lowercased.contains("edat") {
            return .personal
        }
        
        // Detectar intereses (ES/EN/CA)
        if lowercased.contains("le gusta") || lowercased.contains("aficionado") || lowercased.contains("hobby") ||
           lowercased.contains("likes") || lowercased.contains("fan") || lowercased.contains("hobby") ||
           lowercased.contains("li agrada") || lowercased.contains("aficionat") {
            return .interest
        }
        
        return .general
    }
    
    // MARK: - 🔄 Actualizar Memoria con Nuevos Hechos (actualizado)
    func updateMemoryWithFacts(_ facts: [NovaFact], userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !facts.isEmpty else {
            completion(.success(()))
            return
        }
        
        LogConfig.log("🔄 Actualizando memoria con \(facts.count) nuevos hechos categorizados", category: "Memory")
        
        loadMemory(for: userId) { [weak self] result in
            switch result {
            case .success(let memory):
                let updatedMemory = memory.addingFacts(facts)
                self?.saveMemory(updatedMemory, completion: completion)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 🔥 NUEVAS FUNCIONES DE ANÁLISIS DE FLUJO DE CONVERSACIÓN
    
    // 🎯 Análisis de engagement y participación del usuario
    func analyzeConversationEngagement(_ messages: [ChatMessage]) -> ConversationEngagement {
        guard messages.count >= 3 else {
            return ConversationEngagement(level: .low, userParticipation: 0.0, topicConsistency: 0.0)
        }
        
        let userMessages = messages.filter { $0.isUser }
        let totalMessages = messages.count
        
        // Calcular participación del usuario
        let userParticipation = Double(userMessages.count) / Double(totalMessages)
        
        // Calcular consistencia de temas
        let topicConsistency = calculateTopicConsistency(messages)
        
        // Determinar nivel de engagement
        let engagementLevel: EngagementLevel
        if userParticipation > 0.6 && topicConsistency > 0.7 {
            engagementLevel = .high
        } else if userParticipation > 0.4 && topicConsistency > 0.5 {
            engagementLevel = .medium
        } else {
            engagementLevel = .low
        }
        
        return ConversationEngagement(
            level: engagementLevel,
            userParticipation: userParticipation,
            topicConsistency: topicConsistency
        )
    }
    
    // 🔍 Calcular consistencia de temas en la conversación
    private func calculateTopicConsistency(_ messages: [ChatMessage]) -> Double {
        guard messages.count >= 2 else { return 0.0 }
        
        var topicChanges = 0
        let userMessages = messages.filter { $0.isUser }
        
        for i in 1..<userMessages.count {
            let previousMessage = userMessages[i-1].text.lowercased()
            let currentMessage = userMessages[i].text.lowercased()
            
            // Detectar cambios de tema
            if isTopicChange(previousMessage, currentMessage) {
                topicChanges += 1
            }
        }
        
        let totalTransitions = max(userMessages.count - 1, 1)
        return 1.0 - (Double(topicChanges) / Double(totalTransitions))
    }
    
    // 🔄 Detectar si hay cambio de tema entre dos mensajes
    private func isTopicChange(_ message1: String, _ message2: String) -> Bool {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let topicKeywordsES = ["trabajo","estudio","hobby","familia","amigos","viaje","música","deporte","tecnología","arte","cocina","libros","películas","juegos","salud","finanzas"]
        let topicKeywordsEN = ["work","study","hobby","family","friends","trip","travel","music","sport","technology","art","cooking","books","movies","games","health","finance","finances"]
        let topicKeywordsCA = ["feina","estudi","hobby","família","amics","viatge","música","esport","tecnologia","art","cuina","llibres","pel·lícules","jocs","salut","finances"]
        let topicKeywords: [String]
        switch lang { case .es: topicKeywords = topicKeywordsES; case .en: topicKeywords = topicKeywordsEN; case .ca: topicKeywords = topicKeywordsCA }
        
        let message1Topics = topicKeywords.filter { message1.contains($0) }
        let message2Topics = topicKeywords.filter { message2.contains($0) }
        
        // Si no hay temas en común, es un cambio de tema
        return message1Topics.isEmpty || message2Topics.isEmpty || Set(message1Topics).isDisjoint(with: Set(message2Topics))
    }
    
    // 🎭 Análisis de patrones de comunicación del usuario
    func analyzeCommunicationPatterns(_ messages: [ChatMessage]) -> CommunicationPatterns {
        let userMessages = messages.filter { $0.isUser }
        
        var patterns = CommunicationPatterns()
        
        // Analizar longitud de mensajes
        let messageLengths = userMessages.map { $0.text.count }
        patterns.averageMessageLength = Double(messageLengths.reduce(0, +)) / Double(messageLengths.count)
        patterns.prefersLongMessages = patterns.averageMessageLength > 50
        
        // Analizar uso de emojis
        let emojiCount = userMessages.filter { $0.text.contains { $0.isEmoji } }.count
        patterns.usesEmojis = emojiCount > 0
        patterns.emojiFrequency = Double(emojiCount) / Double(userMessages.count)
        
        // Analizar formalidad (ES/EN/CA)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let formalWordsES = ["usted","por favor","gracias","disculpe","permíteme","permiteme"]
        let formalWordsEN = ["sir","please","thank you","excuse me","pardon","would you"]
        let formalWordsCA = ["vostè","si us plau","gràcies","disculpi","permeti"]
        let formalWords: [String]
        switch lang { case .es: formalWords = formalWordsES; case .en: formalWords = formalWordsEN; case .ca: formalWords = formalWordsCA }
        let formalCount = userMessages.filter { message in
            formalWords.contains { message.text.lowercased().contains($0) }
        }.count
        patterns.isFormal = Double(formalCount) / Double(userMessages.count) > 0.3
        
        // Analizar preguntas
        let questionCount = userMessages.filter { $0.text.contains("?") || $0.text.contains("¿") }.count
        patterns.asksQuestions = questionCount > 0
        patterns.questionFrequency = Double(questionCount) / Double(userMessages.count)
        
        return patterns
    }
    
    // 🧠 Aprendizaje automático de preferencias de conversación
    func learnConversationPreferences(_ messages: [ChatMessage], userId: String) {
        let patterns = analyzeCommunicationPatterns(messages)
        let engagement = analyzeConversationEngagement(messages)
        
        var newPreferences: [NovaFact] = []
        
        // Aprender preferencias de estilo
        if patterns.isFormal {
            newPreferences.append(NovaFact(
                content: localizedLearning("pref.formal_respectful"),
                type: .preference,
                importance: 4
            ))
        }
        
        if patterns.usesEmojis && patterns.emojiFrequency > 0.5 {
            newPreferences.append(NovaFact(
                content: localizedLearning("pref.emojis"),
                type: .preference,
                importance: 3
            ))
        }
        
        if patterns.prefersLongMessages {
            newPreferences.append(NovaFact(
                content: localizedLearning("pref.long_conversations"),
                type: .preference,
                importance: 4
            ))
        }
        
        if patterns.asksQuestions && patterns.questionFrequency > 0.4 {
            newPreferences.append(NovaFact(
                content: localizedLearning("pref.curiosity_questions"),
                type: .preference,
                importance: 3
            ))
        }
        
        // Aprender preferencias de engagement
        if engagement.level == .high {
            newPreferences.append(NovaFact(
                content: localizedLearning("pref.high_engagement"),
                type: .preference,
                importance: 4
            ))
        }
        
        // Guardar nuevas preferencias si existen
        if !newPreferences.isEmpty {
            updateMemoryWithFacts(newPreferences, userId: userId) { result in
                switch result {
                case .success:
                    LogConfig.log("✅ Nuevas preferencias de conversación aprendidas: \(newPreferences.count)", category: "Learning")
                case .failure(let error):
                    LogConfig.log("❌ Error guardando preferencias aprendidas: \(error.localizedDescription)", category: "Learning")
                }
            }
        }
    }
    
    // MARK: - 🔧 Métodos Auxiliares (sin cambios significativos)
    private func isConversationCasual(_ text: String) -> Bool {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let casualES = ["hola","qué tal","como estas","cómo estás","buenos días","gracias","de nada","adiós","hasta luego","perfecto","genial","ok","vale","claro","entiendo","jaja","jeje"]
        let casualEN = ["hi","hello","what's up","how are you","good morning","thanks","thank you","you're welcome","bye","see you","perfect","great","ok","sure","got it","haha","lol"]
        let casualCA = ["hola","què tal","com estàs","bon dia","gràcies","de res","adéu","fins després","perfecte","genial","ok","d'acord","entenc","jaja","jeje"]
        let casualIndicators: [String]
        switch lang { case .es: casualIndicators = casualES; case .en: casualIndicators = casualEN; case .ca: casualIndicators = casualCA }
        
        let lowercaseText = text.lowercased()
        let casualWords = casualIndicators.filter { lowercaseText.contains($0) }.count
        let totalWords = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        
        return totalWords > 0 && Double(casualWords) / Double(totalWords) > 0.4
    }
    
    // MARK: - 🗑️ Limpiar Memoria (sin cambios)
    func clearMemory(for userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        LogConfig.log("🗑️ Limpiando memoria para usuario: \(userId)", category: "Memory")
        
        userMemoryCollection(for: userId).document("memory").delete { error in
            if let error = error {
                LogConfig.log("❌ Error limpiando memoria: \(error.localizedDescription)", category: "Memory")
                completion(.failure(error))
            } else {
                LogConfig.log("✅ Memoria limpiada exitosamente", category: "Memory")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - 🔧 Métodos de Estado (sin cambios)
    func resetProcessingState() {
        isProcessingMemory = false
        lastProcessingTime = nil
        LogConfig.log("🔄 Estado de procesamiento de memoria reseteado", category: "Memory")
    }
    
    var isCurrentlyProcessing: Bool {
        return isProcessingMemory
    }

    // Localización helpers (no logs)
    private func localizedPreference(_ key: String) -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch (key, lang) {
        case ("style.casual", .es): return "Prefiere comunicación casual"
        case ("style.casual", .en): return "Prefers casual communication"
        case ("style.casual", .ca): return "Prefereix comunicació casual"
        case ("style.formal", .es): return "Prefiere comunicación formal"
        case ("style.formal", .en): return "Prefers formal communication"
        case ("style.formal", .ca): return "Prefereix comunicació formal"
        case ("style.fun", .es): return "Prefiere tono divertido"
        case ("style.fun", .en): return "Prefers a fun tone"
        case ("style.fun", .ca): return "Prefereix un to divertit"
        case ("style.informal", .es): return "Prefiere tono informal"
        case ("style.informal", .en): return "Prefers an informal tone"
        case ("style.informal", .ca): return "Prefereix un to informal"
        case ("style.tuteo", .es): return "Prefiere tuteo"
        case ("style.tuteo", .en): return "Prefers informal address"
        case ("style.tuteo", .ca): return "Prefereix tracte informal"
        default: return key
        }
    }

    private func localizedPreferenceName(_ name: String) -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch lang {
        case .es: return "Prefiere que le llamen \(name)"
        case .en: return "Prefers to be called \(name)"
        case .ca: return "Prefereix que li diguin \(name)"
        }
    }

    private func localizedLearning(_ key: String) -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch (key, lang) {
        case ("pref.formal_respectful", .es): return "Prefiere comunicación formal y respetuosa"
        case ("pref.formal_respectful", .en): return "Prefers formal and respectful communication"
        case ("pref.formal_respectful", .ca): return "Prefereix comunicació formal i respectuosa"
        case ("pref.emojis", .es): return "Le gusta usar emojis y comunicación visual"
        case ("pref.emojis", .en): return "Likes using emojis and visual communication"
        case ("pref.emojis", .ca): return "Li agrada usar emojis i comunicació visual"
        case ("pref.long_conversations", .es): return "Prefiere conversaciones detalladas y extensas"
        case ("pref.long_conversations", .en): return "Prefers detailed and extensive conversations"
        case ("pref.long_conversations", .ca): return "Prefereix converses detallades i extenses"
        case ("pref.curiosity_questions", .es): return "Es curioso y hace muchas preguntas"
        case ("pref.curiosity_questions", .en): return "Is curious and asks many questions"
        case ("pref.curiosity_questions", .ca): return "És curiós i fa moltes preguntes"
        case ("pref.high_engagement", .es): return "Se involucra mucho en las conversaciones"
        case ("pref.high_engagement", .en): return "Is highly engaged in conversations"
        case ("pref.high_engagement", .ca): return "S'involucra molt en les converses"
        default: return key
        }
    }
}
