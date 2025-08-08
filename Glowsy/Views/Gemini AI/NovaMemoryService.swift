import Foundation
import FirebaseFirestore
import FirebaseVertexAI
import FirebaseAuth

class NovaMemoryService {
    private let db = Firestore.firestore()
    private let vertexAI = VertexAI.vertexAI()
    private lazy var model = vertexAI.generativeModel(modelName: "gemini-2.5-flash-lite")
    
    // ✅ Control de procesamiento múltiple
    private var isProcessingMemory = false
    private var lastProcessingTime: Date?
    private let minimumProcessingInterval: TimeInterval = 5.0
    
    // MARK: - 📁 Colección de Firestore (sin cambios)
    private func userMemoryCollection(for userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("novaMemory")
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
        
        userMemoryCollection(for: memory.userId).document("memory").setData(memory.dictionary) { error in
            if let error = error {
                LogConfig.log("❌ Error guardando memoria: \(error.localizedDescription)", category: "Memory")
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
        let conversationText = recentMessages.map { message in
            "\(message.isUser ? "Usuario" : "Nova"): \(message.text)"
        }.joined(separator: "\n")
        
        // Pre-filtrar conversaciones casuales
        if isConversationCasual(conversationText) {
            LogConfig.log("💬 Conversación casual detectada - no se guardarán hechos", category: "Memory")
            isProcessingMemory = false
            completion([])
            return
        }
        
        // PROMPT MEJORADO para categorización automática
        let prompt = """
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
            "háblame (de forma |)casual": "Prefiere comunicación casual",
            "háblame (de forma |)formal": "Prefiere comunicación formal",
            "sé más (divertido|gracioso)": "Prefiere tono divertido",
            "no seas tan (formal|serio)": "Prefiere tono informal",
            "tutéame": "Prefiere tuteo"
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
                                content: "Prefiere que le llamen \(name)",
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
                if !content.isEmpty && !content.uppercased().contains("NINGUNO") {
                    facts.append(NovaFact(content: content, type: .preference, importance: 5))
                }
            } else if trimmed.hasPrefix("PERSONAL:") {
                currentCategory = .personal
                let content = trimmed.replacingOccurrences(of: "PERSONAL:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !content.uppercased().contains("NINGUNO") {
                    facts.append(NovaFact(content: content, type: .personal, importance: 4))
                }
            } else if trimmed.hasPrefix("PROFESSIONAL:") {
                currentCategory = .professional
                let content = trimmed.replacingOccurrences(of: "PROFESSIONAL:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !content.uppercased().contains("NINGUNO") {
                    facts.append(NovaFact(content: content, type: .professional, importance: 3))
                }
            } else if trimmed.hasPrefix("INTEREST:") {
                currentCategory = .interest
                let content = trimmed.replacingOccurrences(of: "INTEREST:", with: "").trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !content.uppercased().contains("NINGUNO") {
                    facts.append(NovaFact(content: content, type: .interest, importance: 2))
                }
            } else if !trimmed.isEmpty && currentCategory != nil {
                // Línea adicional para la categoría actual
                if !trimmed.uppercased().contains("NINGUNO") && trimmed.count > 10 {
                    facts.append(NovaFact(content: trimmed, type: currentCategory!, importance: currentCategory!.priority))
                }
            }
        }
        
        return Array(facts.prefix(6)) // Máximo 6 hechos por conversación
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
        
        // Detectar preferencias
        if lowercased.contains("prefiere") || lowercased.contains("llama") || lowercased.contains("gusta que") {
            return .preference
        }
        
        // Detectar información profesional
        if lowercased.contains("trabaja") || lowercased.contains("estudia") || lowercased.contains("empresa") {
            return .professional
        }
        
        // Detectar información personal
        if lowercased.contains("vive") || lowercased.contains("tiene") || lowercased.contains("edad") {
            return .personal
        }
        
        // Detectar intereses
        if lowercased.contains("le gusta") || lowercased.contains("aficionado") || lowercased.contains("hobby") {
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
    
    // MARK: - 🔧 Métodos Auxiliares (sin cambios significativos)
    private func isConversationCasual(_ text: String) -> Bool {
        let casualIndicators = [
            "hola", "qué tal", "cómo estás", "buenos días", "gracias",
            "de nada", "adiós", "hasta luego", "perfecto", "genial",
            "ok", "vale", "claro", "entiendo", "jaja", "jeje"
        ]
        
        let lowercaseText = text.lowercased()
        let casualWords = casualIndicators.filter { lowercaseText.contains($0) }.count
        let totalWords = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        
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
}
