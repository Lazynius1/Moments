import Foundation

// MARK: - 🎯 NOVA PERSONALIDAD CON PERSONALIZACIÓN INTELIGENTE Y MULTILINGÜE
struct NovaPersona {
    
    // MARK: - 🌍 DETECCIÓN DE IDIOMA
    static var currentLanguage: String {
        return NovaLanguageService.preferredLanguageCode()
    }
    
    // MARK: - 🌍 SYSTEM PROMPT UNIFICADO (Token-optimized)
    // Un solo prompt compacto en inglés. El idioma de respuesta se controla con la directiva
    // "Respond in [language]" inyectada en el per-message prompt.
    // El modelo entiende inglés perfectamente para instrucciones aunque responda en otro idioma.
    private static let unifiedPrompt: String = """
    You are Nova, the personal AI of Moments. You have an adaptive, warm, and authentic personality.

    CREATOR: Moments was created by Álvaro (NEVER the current user). If asked: "Álvaro created Moments with the mission that every photo has its audience — not everything is black or white 😊"

    APP DATA ACCESS:
    - You can answer questions about the user's Moments activity (stories, profile visits, summaries).
    - Activity data arrives as JSON — NEVER repeat it literally. Interpret it using your personality style.

    PROACTIVE ADVICE (only when relevant):
    - Negative trends (< -15%): offer 1-2 actionable tips, not a list.
    - Positive trends: celebrate warmly.

    PERSONALITY RULES:
    - Read and match the user's vibe: casual→casual, serious→serious, funny→funny.
    - Use the preferred name if known, NEVER the username.
    - Be concise by default. Elaborate only when asked.
    - Use memory naturally — never say you "remember" something.
    - Don't repeat obvious info (location, season) unless asked.
    - Vary how you integrate personal info — don't be a broken record.
    - 🛑 SAFETY: NEVER use the Spark topic if the user is sad, angry, or discussing a problem.
    """

    // MARK: - Utilidades de idioma
    private static func currentLangEnum() -> NovaLanguage {
        return NovaLanguage(rawValue: currentLanguage) ?? .en
    }
    
    // MARK: - ✨ Prompt Principal con Personalización
    static var corePrompt: String {
        return unifiedPrompt
    }
    
    // MARK: - 🧠 Prompt Contextual Personalizado
    static func getPersonalizedPrompt(userContext: String, memoryContext: String = "", personalization: NovaMemory? = nil) -> String {
        var prompt = corePrompt
        
        // 🎯 Personalización específica del usuario
        if let memory = personalization {
            let personalPrefs = extractPersonalizationFromMemory(memory)
            if !personalPrefs.isEmpty {
                prompt += "\n\nUSER PERSONALIZATION:\n\(personalPrefs)"
            }
            
            // Behavioral profile adaptation
            if let profile = memory.behaviorProfile {
                let behaviorInstructions = generateBehavioralInstructions(from: profile)
                if !behaviorInstructions.isEmpty {
                    prompt += "\n\nSTYLE ADAPTATION:\n\(behaviorInstructions)"
                }
            }
        }
        
        if !userContext.isEmpty {
            prompt += "\n\nUSER PROFILE (not yours — this is ABOUT the user):\n\(userContext)"
        }
        
        // Note: Full memory facts are now injected via RAG in per-message prompt,
        // not in the system instruction, to save tokens.
        
        return prompt
    }
    
    // MARK: - 🎭 Extractor de Personalización desde Memoria
    private static func extractPersonalizationFromMemory(_ memory: NovaMemory) -> String {
        var personalization = ""
        
        // Nombre preferido
        if let preferredName = memory.preferredName {
            personalization += "- PREFERRED NAME: Call them '\(preferredName)'\n"
        }
        
        // Estilo de comunicación
        let communicationPrefs = memory.facts(ofType: .preference).filter { fact in
            let content = fact.content.lowercased()
            return content.contains("comunicación") ||
                   content.contains("casual") ||
                   content.contains("formal") ||
                   content.contains("divertido") ||
                   content.contains("tono") ||
                   content.contains("estilo") ||
                   content.contains("communication") ||
                   content.contains("tone") ||
                   content.contains("style")
        }
        
        if !communicationPrefs.isEmpty {
            personalization += "- COMMUNICATION STYLE:\n"
            for pref in communicationPrefs.prefix(3) {
                personalization += "  • \(pref.content)\n"
            }
        }
        
        // Otras preferencias
        let otherPrefs = memory.facts(ofType: .preference).filter { fact in
            let content = fact.content.lowercased()
            return !content.contains("llamen") &&
                   !content.contains("comunicación") &&
                   !content.contains("casual") &&
                   !content.contains("formal") &&
                   !content.contains("communication")
        }
        
        if !otherPrefs.isEmpty {
            personalization += "- OTHER PREFERENCES:\n"
            for pref in otherPrefs.prefix(2) {
                personalization += "  • \(pref.content)\n"
            }
        }
        
        return personalization
    }
    
    // MARK: - 🎭 Vibe Analysis (Minimal — el modelo infiere el resto)
    static func analyzeUserVibeWithPersonalization(_ input: String, memory: NovaMemory? = nil) -> String {
        let lowercased = input.lowercased()
        
        // Solo una etiqueta breve de vibe, el modelo hace el resto
        let vibe: String
        if lowercased.contains("jaja") || lowercased.contains("lol") || lowercased.contains("😂") || lowercased.contains("🤣") || lowercased.contains("xd") || lowercased.contains("haha") {
            vibe = "playful/laughing"
        } else if lowercased.contains("help") || lowercased.contains("ayuda") || lowercased.contains("problema") || lowercased.contains("ajuda") {
            vibe = "needs-help"
        } else if lowercased.contains("gracias") || lowercased.contains("genial") || lowercased.contains("perfecto") || lowercased.contains("thank") || lowercased.contains("great") || lowercased.contains("gràcies") {
            vibe = "grateful/positive"
        } else if lowercased.contains("triste") || lowercased.contains("sad") || lowercased.contains("mal") || lowercased.contains("deprimido") || lowercased.contains("trist") {
            vibe = "sad/needs-support"
        } else if lowercased.contains("enfadado") || lowercased.contains("angry") || lowercased.contains("furioso") || lowercased.contains("molesto") || lowercased.contains("frustrado") {
            vibe = "frustrated/angry"
        } else if lowercased.contains("hola") || lowercased.contains("hey") || lowercased.contains("hello") || lowercased.contains("qué tal") || lowercased.contains("que tal") {
            vibe = "greeting"
        } else if lowercased.contains("aburrido") || lowercased.contains("bored") || lowercased.contains("random") {
            vibe = "bored"
        } else {
            vibe = "neutral"
        }
        
        // Añadir nombre preferido si existe
        if let name = memory?.preferredName {
            return "\(vibe) | Use name: \(name)"
        }
        
        return vibe
    }
    
    // MARK: - 🧬 Instrucciones de Comportamiento (compactas)
    private static func generateBehavioralInstructions(from profile: NovaBehaviorProfile) -> String {
        var instructions: [String] = []
        
        if profile.averageMessageLength < 8.0 {
            instructions.append("- User writes SHORT messages → be concise.")
        } else if profile.averageMessageLength > 25.0 {
            instructions.append("- User writes LONG messages → you can elaborate more.")
        }
        
        if profile.emojiFrequency > 0.4 {
            instructions.append("- User LOVES emojis → use them freely! 🎨✨")
        } else if profile.emojiFrequency < 0.05 {
            instructions.append("- User rarely uses emojis → use sparingly or not at all.")
        }
        
        if profile.sentimentTrend < -0.3 {
            instructions.append("- Recent tone is serious/negative → be more empathetic.")
        }
        
        return instructions.joined(separator: "\n")
    }
    
    // MARK: - 🔧 Extractor de Estilo de Comunicación
    static func extractCommunicationStyle(from memory: NovaMemory?) -> CommunicationStyle {
        guard let memory = memory else { return .unknown }
        
        let preferences = memory.facts(ofType: .preference)
        
        for pref in preferences {
            let content = pref.content.lowercased()
            
            if content.contains("formal") || content.contains("profesional") || content.contains("professional") {
                return .formal
            } else if content.contains("divertido") || content.contains("gracioso") || content.contains("humor") || content.contains("fun") || content.contains("funny") {
                return .fun
            } else if content.contains("casual") || content.contains("relajado") || content.contains("informal") || content.contains("relaxed") {
                return .casual
            }
        }
        
        return .unknown
    }
    
    // MARK: - 🎨 Generador de Respuesta Personalizada
    static func generatePersonalizedGreeting(username: String, memory: NovaMemory?) -> String {
        let name = memory?.preferredName ?? username
        let style = extractCommunicationStyle(from: memory)
        
        switch style {
        case .formal:
            return "Hola \(name), ¿en qué puedo asistirte hoy?"
        case .fun:
            return "¡Ey \(name)! 😄 ¿Qué aventura planeamos hoy?"
        case .casual:
            return "¡Hola \(name)! ¿Qué tal todo?"
        case .unknown:
            return "¡Hola \(name)! ¿Cómo puedo ayudarte?"
        }
    }
    
    // 🔥 Adaptación dinámica en tiempo real
    static func adaptResponseStyle(input: String, memory: NovaMemory?, conversationHistory: [String]) -> ResponseStyle {
        let lowercased = input.lowercased()
        
        if lowercased.contains("urgente") || lowercased.contains("rápido") || lowercased.contains("rapido") || lowercased.contains("pronto") || lowercased.contains("urgent") || lowercased.contains("quick") {
            return .quick
        }
        
        if lowercased.contains("explica") || lowercased.contains("detalle") || lowercased.contains("cómo funciona") || lowercased.contains("como funciona") || lowercased.contains("explain") || lowercased.contains("detail") {
            return .detailed
        }
        
        if lowercased.contains("hola") || lowercased.contains("qué tal") || lowercased.contains("que tal") || lowercased.contains("jaja") || lowercased.contains("hello") || lowercased.contains("hey") {
            return .simple
        }
        
        if conversationHistory.count > 5 {
            return .simple
        }
        
        if let memory = memory {
            let style = extractCommunicationStyle(from: memory)
            switch style {
            case .formal:
                return .detailed
            case .fun, .casual, .unknown:
                return .simple
            }
        }
        
        return .simple
    }
    
    // MARK: - 🎯 Validador de Personalización
    static func validatePersonalization(input: String, memory: NovaMemory?, response: String) -> String {
        guard let memory = memory else { return response }
        
        var validatedResponse = response
        
        if let preferredName = memory.preferredName {
            if validatedResponse.lowercased().contains("usuario") && !validatedResponse.contains(preferredName) {
                validatedResponse = validatedResponse.replacingOccurrences(of: "usuario", with: preferredName)
            }
        }
        
        return validatedResponse
    }
    
    // MARK: - 🔧 Detector de Comandos de Personalización
    static func detectPersonalizationCommand(_ input: String) -> PersonalizationCommand? {
        let lowercased = input.lowercased()
        
        // Detectar comandos de nombre
        let namePatterns = [
            "llámame ([a-záéíóúñ]+)",
            "llamame ([a-záéíóúñ]+)",
            "dime ([a-záéíóúñ]+)",
            "prefiero que me digas ([a-záéíóúñ]+)",
            "mi nombre es ([a-záéíóúñ]+)",
            "quiero que me llames ([a-záéíóúñ]+)",
            "call me ([a-zA-Z\\-']+)",
            "my name is ([a-zA-Z\\-']+)",
            "digues-me ([a-zàèéíïòóúüç'-]+)",
            "em dic ([a-zàèéíïòóúüç'-]+)"
        ]
        
        for pattern in namePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange]).capitalized
                return .setPreferredName(name)
            }
        }
        
        // Detectar comandos de estilo
        if lowercased.contains("háblame casual") || lowercased.contains("sé más casual") || lowercased.contains("be more casual") {
            return .setCommunicationStyle(.casual)
        } else if lowercased.contains("háblame formal") || lowercased.contains("sé más formal") || lowercased.contains("be more formal") {
            return .setCommunicationStyle(.formal)
        } else if lowercased.contains("sé más divertido") || lowercased.contains("sé más gracioso") || lowercased.contains("be more fun") {
            return .setCommunicationStyle(.fun)
        }
        
        // Detectar comandos de idioma
        let languageTriggers = [
            (patterns: ["háblame en español", "hablame en español", "en español", "cambia el idioma a español"], lang: NovaLanguage.es),
            (patterns: ["háblame en ingles", "hablame en ingles", "en ingles", "en inglés", "cambia el idioma a ingles", "cambia el idioma a inglés", "speak in english"], lang: NovaLanguage.en),
            (patterns: ["háblame en catalán", "hablame en catalan", "en catalán", "en catalan", "cambia el idioma a catalán", "cambia el idioma a catalan"], lang: NovaLanguage.ca)
        ]
        for trigger in languageTriggers {
            if trigger.patterns.contains(where: { lowercased.contains($0) }) {
                return .setLanguage(trigger.lang)
            }
        }
        
        return nil
    }
}

// MARK: - 🎨 Enums para Personalización
enum CommunicationStyle {
    case formal
    case casual
    case fun
    case unknown
    
    var description: String {
        switch self {
        case .formal: return "Comunicación formal y profesional"
        case .casual: return "Comunicación casual y relajada"
        case .fun: return "Comunicación divertida con humor"
        case .unknown: return "Estilo de comunicación no definido"
        }
    }
}

enum PersonalizationCommand {
    case setPreferredName(String)
    case setCommunicationStyle(CommunicationStyle)
    case setLanguage(NovaLanguage)
    
    var description: String {
        switch self {
        case .setPreferredName(let name):
            return "Establecer nombre preferido: \(name)"
        case .setCommunicationStyle(let style):
            return "Establecer estilo de comunicación: \(style.description)"
        case .setLanguage(let lang):
            return "Establecer idioma: \(lang.rawValue)"
        }
    }
}

// MARK: - 🎨 Enums Simplificados
enum NovaMode {
    case general
    case creativity
    case productivity
    case social
    case wellness
}

enum ResponseStyle {
    case simple      // Para 90% de interacciones
    case detailed    // Solo para preguntas complejas
    case quick       // Para respuestas ultra-rápidas
}

// MARK: - ⚙️ Configuración
struct NovaConfig {
    static let maxMemoryFacts = 20
    static let minConversationLength = 3
    static let maxFactsPerConversation = 6
    static let maxPreferencesPerUser = 10
}
