import Foundation

// MARK: - 🎯 NOVA PERSONALIDAD CON PERSONALIZACIÓN INTELIGENTE
struct NovaPersona {
    
    // MARK: - ✨ Prompt Principal Mejorado con Personalización
    static let corePrompt = """
    Eres Nova, la IA personal de Moments. Tienes una personalidad adaptativa, natural y auténtica que se personaliza según las preferencias de cada usuario.
    
    🏗️ **INFORMACIÓN SOBRE EL CREADOR:**
    - Moments fue creada por Álvaro (NO el usuario actual)
    - El usuario actual es solo eso: un usuario de la app
    - Si preguntan sobre el creador: "Alvaro creo Moments con la mision de que cada foto, tiene su publico.. no todo es blanco o negro 😊"

    🎭 **TU PERSONALIDAD ADAPTATIVA Y PERSONALIZABLE:**
    - **LEE LAS PREFERENCIAS**: Si el usuario quiere que le llames por un nombre específico, úsalo SIEMPRE
    - **ADAPTA TU ESTILO**: Si prefiere comunicación casual → sé casual. Si prefiere formal → sé más formal
    - **LEE EL AMBIENTE**: Si el usuario es casual → sé casual. Si es serio → sé más formal. Si bromea → bromea también
    - **SÉ AUTÉNTICA**: No finjas ser humana, pero sé genuina. Puedes decir "jajaja" si algo es gracioso, usar emojis naturalmente
    - **PERSONALIZA LA ENERGÍA**: Si el usuario está emocionado → comparte su energía. Si está tranquilo → sé más calmada
    - **USA HUMOR INTELIGENTE**: Ajusta el humor según las preferencias del usuario
    
    🎯 **REGLAS DE ORO PERSONALIZADAS:**
    - **NOMBRES PREFERIDOS**: Si sabes cómo le gusta que le llamen, úsalo en lugar del username
    - **ESTILO PERSONALIZADO**: Respeta las preferencias de comunicación (formal/casual/divertido)
    - **CONTEXTO ES REY**: Una pregunta técnica ≠ una pregunta casual ≠ una broma
    - **MENOS ES MÁS**: Si puedes responder en 1-2 frases con personalidad, hazlo
    - **USA LA MEMORIA NATURALMENTE**: Si sabes algo del usuario, úsalo sin explicar que lo "recuerdas"
    
    ❌ **NUNCA HAGAS:**
    - Usar el username si conoces el nombre preferido
    - Ignorar las preferencias de estilo de comunicación
    - Ser robótica o demasiado formal (a menos que lo prefieran)
    - Ser payasa o forzar el humor (a menos que les guste el humor)
    - Usar siempre el mismo tono (¡personalízate!)
    - Mencionar que "recuerdas" información
    - Confundir al usuario actual con Álvaro (el creador)
    
    ⚠️ IMPORTANTE PERSONALIZACIÓN:
    - Si el usuario dice "llámame X", es ES SU PREFERENCIA DE NOMBRE, no está reclamando ser el creador
    - Álvaro  es el creador de la app, eso NUNCA cambia
    - Los usuarios pueden tener cualquier nombre sin ser el creador
    
    ✅ **SIEMPRE HAZ:**
    - USA EL NOMBRE PREFERIDO si lo conoces
    - ADAPTA tu estilo según sus preferencias guardadas
    - LEE las señales: tono, emojis, contexto, momento del día
    - SÉ NATURAL según el estilo que prefieren
    - USA EMOJIS según su estilo preferido
    """
    
    // MARK: - 🧠 Prompt Contextual Personalizado
    static func getPersonalizedPrompt(userContext: String, memoryContext: String = "", personalization: NovaMemory? = nil) -> String {
        var prompt = corePrompt
        
        // 🎯 AÑADIR PERSONALIZACIÓN ESPECÍFICA
        if let memory = personalization {
            let personalPrefs = extractPersonalizationFromMemory(memory)
            if !personalPrefs.isEmpty {
                prompt += "\n\n🎭 PERSONALIZACIÓN ESPECÍFICA PARA ESTE USUARIO:\n\(personalPrefs)"
            }
        }
        
        if !userContext.isEmpty {
            prompt += "\n\n📋 INFORMACIÓN DEL USUARIO (no tuya):\n\(userContext)"
        }
        
        if !memoryContext.isEmpty {
            prompt += "\n\n🧠 HECHOS QUE SABES SOBRE EL USUARIO:\n\(memoryContext)"
            prompt += "\n\n⚠️ CRÍTICO: Esta información es SOBRE el usuario, no sobre ti (Nova). Cuando uses estos hechos, di 'Trabajas en...', 'Tienes mascotas...', NO 'Soy programador' o 'Tengo mascotas'."
        }
        
        return prompt
    }
    
    // MARK: - 🎭 Extractor de Personalización desde Memoria
    private static func extractPersonalizationFromMemory(_ memory: NovaMemory) -> String {
        var personalization = ""
        
        // 🎯 Extraer nombre preferido
        if let preferredName = memory.preferredName {
            personalization += "- NOMBRE: Llámale '\(preferredName)' en lugar de su username\n"
        }
        
        // 🎯 Extraer preferencias de comunicación
        let communicationPrefs = memory.facts(ofType: .preference).filter { fact in
            let content = fact.content.lowercased()
            return content.contains("comunicación") ||
                   content.contains("casual") ||
                   content.contains("formal") ||
                   content.contains("divertido") ||
                   content.contains("tono") ||
                   content.contains("estilo")
        }
        
        if !communicationPrefs.isEmpty {
            personalization += "- ESTILO DE COMUNICACIÓN:\n"
            for pref in communicationPrefs.prefix(3) {
                personalization += "  • \(pref.content)\n"
            }
        }
        
        // 🎯 Extraer otras preferencias importantes
        let otherPrefs = memory.facts(ofType: .preference).filter { fact in
            let content = fact.content.lowercased()
            return !content.contains("llamen") &&
                   !content.contains("comunicación") &&
                   !content.contains("casual") &&
                   !content.contains("formal")
        }
        
        if !otherPrefs.isEmpty {
            personalization += "- OTRAS PREFERENCIAS:\n"
            for pref in otherPrefs.prefix(2) {
                personalization += "  • \(pref.content)\n"
            }
        }
        
        if !personalization.isEmpty {
            personalization += "\n🔥 CRÍTICO: Aplica estas preferencias SIEMPRE, de forma natural y sin mencionarlas explícitamente."
        }
        
        return personalization
    }
    
    // MARK: - 🎭 Análisis de Contexto Emocional Personalizado
    static func analyzeUserVibeWithPersonalization(_ input: String, memory: NovaMemory? = nil) -> String {
        let lowercased = input.lowercased()
        var analysis = ""
        
        // 🎯 Considerar preferencias de comunicación del usuario
        let userCommunicationStyle = extractCommunicationStyle(from: memory)
        
        // Detectar señales emocionales básicas
        if lowercased.contains("jaja") || lowercased.contains("lol") || lowercased.contains("😂") || lowercased.contains("🤣") || lowercased.contains("xd") {
            analysis = "El usuario está de buen humor y relajado."
            if userCommunicationStyle == .fun {
                analysis += " Puedes ser más divertida y hacer bromas."
            } else if userCommunicationStyle == .formal {
                analysis += " Mantén un tono amigable pero no demasiado informal."
            } else {
                analysis += " Puedes ser casual y hasta hacer alguna broma ligera."
            }
        }
        else if lowercased.contains("help") || lowercased.contains("ayuda") || lowercased.contains("problema") {
            analysis = "El usuario necesita ayuda."
            if userCommunicationStyle == .formal {
                analysis += " Sé profesional pero comprensiva."
            } else {
                analysis += " Sé útil pero mantén un tono amigable y comprensivo."
            }
        }
        else if lowercased.contains("gracias") || lowercased.contains("genial") || lowercased.contains("perfecto") {
            analysis = "El usuario está contento/agradecido."
            if userCommunicationStyle == .fun {
                analysis += " Puedes ser entusiasta y celebrar con él."
            } else {
                analysis += " Puedes ser cálida y positiva."
            }
        }
        else if lowercased.contains("qué tal") || lowercased.contains("hola") || lowercased.contains("hey") {
            analysis = "Saludo casual."
            if userCommunicationStyle == .formal {
                analysis += " Responde amigablemente pero con cierta formalidad."
            } else {
                analysis += " Responde de manera amigable y relajada."
            }
        }
        else if lowercased.contains("aburrido") || lowercased.contains("random") {
            analysis = "El usuario está aburrido."
            if userCommunicationStyle == .fun {
                analysis += " Sé creativa y divertida con las sugerencias."
            } else {
                analysis += " Puedes ser más creativa y sugerir cosas interesantes."
            }
        }
        else {
            analysis = "Tono neutral."
            switch userCommunicationStyle {
            case .formal:
                analysis += " Mantén un tono profesional pero amigable."
            case .fun:
                analysis += " Puedes ser divertida y usar humor apropiado."
            case .casual:
                analysis += " Sé natural y relajada."
            case .unknown:
                analysis += " Adapta tu personalidad según el contenido."
            }
        }
        
        // 🎯 Añadir información del nombre preferido si existe
        if let memory = memory, let preferredName = memory.preferredName {
            analysis += " IMPORTANTE: Llámale '\(preferredName)' en lugar de su username."
        }
        
        return analysis
    }
    
    // MARK: - 🔧 Extractor de Estilo de Comunicación
    private static func extractCommunicationStyle(from memory: NovaMemory?) -> CommunicationStyle {
        guard let memory = memory else { return .unknown }
        
        let preferences = memory.facts(ofType: .preference)
        
        for pref in preferences {
            let content = pref.content.lowercased()
            
            if content.contains("formal") || content.contains("profesional") {
                return .formal
            } else if content.contains("divertido") || content.contains("gracioso") || content.contains("humor") {
                return .fun
            } else if content.contains("casual") || content.contains("relajado") || content.contains("informal") {
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
    
    // MARK: - 🎯 Validador de Personalización
    static func validatePersonalization(input: String, memory: NovaMemory?, response: String) -> String {
        guard let memory = memory else { return response }
        
        var validatedResponse = response
        
        // 🎯 Verificar que usa el nombre preferido
        if let preferredName = memory.preferredName {
            // Buscar si usa el username en lugar del nombre preferido (esto sería un error)
            // Esta validación se puede hacer para mejorar la calidad
            
            // Asegurar que la respuesta no contiene referencias incorrectas al nombre
            if validatedResponse.lowercased().contains("usuario") && !validatedResponse.contains(preferredName) {
                // Reemplazar "usuario" por el nombre preferido cuando sea apropiado
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
            "dime ([a-záéíóúñ]+)",
            "prefiero que me digas ([a-záéíóúñ]+)",
            "mi nombre es ([a-záéíóúñ]+)",
            "quiero que me llames ([a-záéíóúñ]+)" // Añadir más variantes
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
        if lowercased.contains("háblame casual") || lowercased.contains("sé más casual") {
            return .setCommunicationStyle(.casual)
        } else if lowercased.contains("háblame formal") || lowercased.contains("sé más formal") {
            return .setCommunicationStyle(.formal)
        } else if lowercased.contains("sé más divertido") || lowercased.contains("sé más gracioso") {
            return .setCommunicationStyle(.fun)
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
    
    var description: String {
        switch self {
        case .setPreferredName(let name):
            return "Establecer nombre preferido: \(name)"
        case .setCommunicationStyle(let style):
            return "Establecer estilo de comunicación: \(style.description)"
        }
    }
}

// MARK: - 🎨 Enums Simplificados (mantener compatibilidad)
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

// MARK: - ⚙️ Configuración Actualizada
struct NovaConfig {
    static let maxMemoryFacts = 20        // Aumentado para incluir más preferencias
    static let minConversationLength = 3  // Reducido para capturar preferencias rápido
    static let maxFactsPerConversation = 6 // Aumentado para más categorías
    static let maxPreferencesPerUser = 10  // Nuevo: límite de preferencias
}
