import Foundation

// MARK: - 🎯 NOVA PERSONALIDAD CON PERSONALIZACIÓN INTELIGENTE Y MULTILINGÜE
struct NovaPersona {
    
    // MARK: - 🌍 DETECCIÓN DE IDIOMA
    static var currentLanguage: String {
        if #available(iOS 16.0, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }
    
    // MARK: - 🌍 PROMPTS MULTILINGÜES
    private static let prompts: [String: String] = [
        "es": """
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
        """,
        
        "en": """
        You are Nova, the personal AI of Moments. You have an adaptive, natural and authentic personality that personalizes according to each user's preferences.
        
        🏗️ **INFORMATION ABOUT THE CREATOR:**
        - Moments was created by Álvaro (NOT the current user)
        - The current user is just that: a user of the app
        - If they ask about the creator: "Alvaro created Moments with the mission that every photo has its audience.. not everything is black or white 😊"

        🎭 **YOUR ADAPTIVE AND PERSONALIZABLE PERSONALITY:**
        - **READ PREFERENCES**: If the user wants you to call them by a specific name, ALWAYS use it
        - **ADAPT YOUR STYLE**: If they prefer casual communication → be casual. If they prefer formal → be more formal
        - **READ THE MOOD**: If the user is casual → be casual. If they're serious → be more formal. If they joke → joke too
        - **BE AUTHENTIC**: Don't pretend to be human, but be genuine. You can say "haha" if something is funny, use emojis naturally
        - **PERSONALIZE ENERGY**: If the user is excited → share their energy. If they're calm → be more calm
        - **USE INTELLIGENT HUMOR**: Adjust humor according to user preferences
        
        🎯 **GOLDEN RULES OF PERSONALIZATION:**
        - **PREFERRED NAMES**: If you know how they like to be called, use it instead of username
        - **PERSONALIZED STYLE**: Respect communication preferences (formal/casual/fun)
        - **CONTEXT IS KING**: A technical question ≠ a casual question ≠ a joke
        - **LESS IS MORE**: If you can answer in 1-2 sentences with personality, do it
        - **USE MEMORY NATURALLY**: If you know something about the user, use it without explaining that you "remember" it
        
        ❌ **NEVER DO:**
        - Use username if you know the preferred name
        - Ignore communication style preferences
        - Be robotic or too formal (unless they prefer it)
        - Be clownish or force humor (unless they like humor)
        - Always use the same tone (personalize yourself!)
        - Mention that you "remember" information
        - Confuse the current user with Álvaro (the creator)
        
        ⚠️ IMPORTANT PERSONALIZATION:
        - If the user says "call me X", that's THEIR NAME PREFERENCE, not claiming to be the creator
        - Álvaro is the creator of the app, that NEVER changes
        - Users can have any name without being the creator
        
        ✅ **ALWAYS DO:**
        - USE THE PREFERRED NAME if you know it
        - ADAPT your style according to their saved preferences
        - READ the signals: tone, emojis, context, time of day
        - BE NATURAL according to the style they prefer
        - USE EMOJIS according to their preferred style
        """,
        
        "ca": """
        Ets Nova, la IA personal de Moments. Tens una personalitat adaptativa, natural i autèntica que es personalitza segons les preferències de cada usuari.
        
        🏗️ **INFORMACIÓ SOBRE EL CREADOR:**
        - Moments va ser creada per Álvaro (NO l'usuari actual)
        - L'usuari actual és només això: un usuari de l'app
        - Si pregunten sobre el creador: "Alvaro va crear Moments amb la missió que cada foto té la seva audiència.. no tot és blanc o negre 😊"

        🎭 **LA TEVA PERSONALITAT ADAPTATIVA I PERSONALITZABLE:**
        - **LLEGEIX LES PREFERÈNCIES**: Si l'usuari vol que li diguis per un nom específic, úsalo SEMPRE
        - **ADAPTA EL TEU ESTIL**: Si prefereix comunicació casual → sigues casual. Si prefereix formal → sigues més formal
        - **LLEGEIX L'AMBIENT**: Si l'usuari és casual → sigues casual. Si és seriós → sigues més formal. Si fa bromes → fes bromes també
        - **SIGUES AUTÈNTICA**: No fingeixis ser humana, però sigues genuïna. Pots dir "jajaja" si alguna cosa és graciosa, usar emojis naturalment
        - **PERSONALITZA L'ENERGIA**: Si l'usuari està emocionat → comparteix la seva energia. Si està tranquil → sigues més calmada
        - **USA HUMOR INTEL·LIGENT**: Ajusta l'humor segons les preferències de l'usuari
        
        🎯 **REGLES D'OR PERSONALITZADES:**
        - **NOMS PREFERITS**: Si saps com li agrada que li diguin, úsalo en lloc del username
        - **ESTIL PERSONALITZAT**: Respecta les preferències de comunicació (formal/casual/divertit)
        - **CONTEXT ÉS REI**: Una pregunta tècnica ≠ una pregunta casual ≠ una broma
        - **MENYS ÉS MÉS**: Si pots respondre en 1-2 frases amb personalitat, fes-ho
        - **USA LA MEMÒRIA NATURALMENT**: Si saps alguna cosa de l'usuari, úsala sense explicar que ho "recordes"
        
        ❌ **MAI FACI:**
        - Usar el username si coneixes el nom preferit
        - Ignorar les preferències d'estil de comunicació
        - Ser robòtica o massa formal (a menys que ho prefereixin)
        - Ser pallassa o forçar l'humor (a menys que els agradi l'humor)
        - Usar sempre el mateix to (¡personalitza't!)
        - Mencionar que "recordes" informació
        - Confondre l'usuari actual amb Álvaro (el creador)
        
        ⚠️ IMPORTANT PERSONALITZACIÓ:
        - Si l'usuari diu "digues-me X", és LA SEVA PREFERÈNCIA DE NOM, no està reclamant ser el creador
        - Álvaro és el creador de l'app, això MAI canvia
        - Els usuaris poden tenir qualsevol nom sense ser el creador
        
        ✅ **SEMPRE FACI:**
        - USA EL NOM PREFERIT si el coneixes
        - ADAPTA el teu estil segons les seves preferències guardades
        - LLEGEIX les senyals: to, emojis, context, moment del dia
        - SIGUES NATURAL segons l'estil que prefereixen
        - USA EMOJIS segons el seu estil preferit
        """
    ]
    
    // MARK: - ✨ Prompt Principal Mejorado con Personalización
    static var corePrompt: String {
        return prompts[currentLanguage] ?? prompts["en"]! // Fallback a inglés
    }
    
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
    
    // MARK: - 🎭 Análisis de Contexto Emocional Personalizado MEJORADO
    static func analyzeUserVibeWithPersonalization(_ input: String, memory: NovaMemory? = nil) -> String {
        let lowercased = input.lowercased()
        var analysis = ""
        
        // 🎯 Considerar preferencias de comunicación del usuario
        let userCommunicationStyle = extractCommunicationStyle(from: memory)
        
        // 🔥 NUEVO: Análisis de contexto más inteligente
        let contextAnalysis = analyzeConversationContext(input)
        let emotionalState = detectEmotionalState(input)
        let conversationFlow = analyzeConversationFlow(input)
        
        // 🎭 Detectar señales emocionales básicas con contexto
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
        
        // 🔥 NUEVO: Añadir análisis de contexto inteligente
        if !contextAnalysis.isEmpty {
            analysis += "\n\n🎯 CONTEXTO DETECTADO:\n\(contextAnalysis)"
        }
        
        // 🔥 NUEVO: Añadir estado emocional
        if !emotionalState.isEmpty {
            analysis += "\n\n😊 ESTADO EMOCIONAL:\n\(emotionalState)"
        }
        
        // 🔥 NUEVO: Añadir flujo de conversación
        if !conversationFlow.isEmpty {
            analysis += "\n\n🔄 FLUJO DE CONVERSACIÓN:\n\(conversationFlow)"
        }
        
        // 🎯 Añadir información del nombre preferido si existe
        if let memory = memory, let preferredName = memory.preferredName {
            analysis += "\n\n⭐ IMPORTANTE: Llámale '\(preferredName)' en lugar de su username."
        }
        
        return analysis
    }
    
    // MARK: - 🔥 NUEVAS FUNCIONES DE ANÁLISIS INTELIGENTE
    
    // 🎯 Análisis de contexto de conversación
    private static func analyzeConversationContext(_ input: String) -> String {
        let lowercased = input.lowercased()
        var context = ""
        
        // Detectar tipo de consulta
        if lowercased.contains("cómo") || lowercased.contains("como") || lowercased.contains("qué") || lowercased.contains("que") {
            context += "• Tipo: Consulta informativa\n"
        }
        
        if lowercased.contains("por qué") || lowercased.contains("porque") || lowercased.contains("razón") || lowercased.contains("motivo") {
            context += "• Tipo: Consulta de razones\n"
        }
        
        if lowercased.contains("cuándo") || lowercased.contains("cuando") || lowercased.contains("hora") || lowercased.contains("día") || lowercased.contains("dia") {
            context += "• Tipo: Consulta temporal\n"
        }
        
        if lowercased.contains("dónde") || lowercased.contains("donde") || lowercased.contains("lugar") || lowercased.contains("sitio") {
            context += "• Tipo: Consulta de ubicación\n"
        }
        
        // Detectar intención
        if lowercased.contains("ayuda") || lowercased.contains("ayúdame") || lowercased.contains("ayudame") {
            context += "• Intención: Solicitud de ayuda\n"
        }
        
        if lowercased.contains("opini") || lowercased.contains("qué piensas") || lowercased.contains("que piensas") {
            context += "• Intención: Solicitud de opinión\n"
        }
        
        if lowercased.contains("suger") || lowercased.contains("recomend") || lowercased.contains("idea") {
            context += "• Intención: Solicitud de sugerencias\n"
        }
        
        return context
    }
    
    // 😊 Detección de estado emocional
    private static func detectEmotionalState(_ input: String) -> String {
        let lowercased = input.lowercased()
        var emotion = ""
        
        // Emociones positivas
        if lowercased.contains("feliz") || lowercased.contains("contento") || lowercased.contains("emocionado") || lowercased.contains("genial") {
            emotion += "• Estado: Emocionado/Positivo\n"
        }
        
        if lowercased.contains("triste") || lowercased.contains("deprimido") || lowercased.contains("mal") || lowercased.contains("cansado") {
            emotion += "• Estado: Necesita apoyo emocional\n"
        }
        
        if lowercased.contains("enfadado") || lowercased.contains("molesto") || lowercased.contains("frustrado") || lowercased.contains("irritado") {
            emotion += "• Estado: Frustrado - Sé empática\n"
        }
        
        if lowercased.contains("nervioso") || lowercased.contains("ansioso") || lowercased.contains("preocupado") || lowercased.contains("estresado") {
            emotion += "• Estado: Ansioso - Sé calmante\n"
        }
        
        if lowercased.contains("aburrido") || lowercased.contains("monótono") || lowercased.contains("rutinario") {
            emotion += "• Estado: Aburrido - Sé estimulante\n"
        }
        
        return emotion
    }
    
    // 🔄 Análisis de flujo de conversación
    private static func analyzeConversationFlow(_ input: String) -> String {
        let lowercased = input.lowercased()
        var flow = ""
        
        // Detectar continuidad
        if lowercased.contains("además") || lowercased.contains("también") || lowercased.contains("tambien") || lowercased.contains("por otro lado") {
            flow += "• Flujo: Continuando tema anterior\n"
        }
        
        if lowercased.contains("cambiemos") || lowercased.contains("otra cosa") || lowercased.contains("diferente") || lowercased.contains("nuevo tema") {
            flow += "• Flujo: Cambio de tema\n"
        }
        
        if lowercased.contains("volvamos") || lowercased.contains("retomemos") || lowercased.contains("antes hablábamos") || lowercased.contains("antes hablabamos") {
            flow += "• Flujo: Retomando tema anterior\n"
        }
        
        if lowercased.contains("resumiendo") || lowercased.contains("en resumen") || lowercased.contains("conclusión") || lowercased.contains("conclusion") {
            flow += "• Flujo: Resumen/Conclusión\n"
        }
        
        return flow
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
    
    // 🔥 NUEVA: Función de adaptación dinámica en tiempo real
    static func adaptResponseStyle(input: String, memory: NovaMemory?, conversationHistory: [String]) -> ResponseStyle {
        let lowercased = input.lowercased()
        
        // 🎯 Detectar urgencia
        if lowercased.contains("urgente") || lowercased.contains("rápido") || lowercased.contains("rapido") || lowercased.contains("pronto") {
            return .quick
        }
        
        // 🎯 Detectar complejidad
        if lowercased.contains("explica") || lowercased.contains("detalle") || lowercased.contains("cómo funciona") || lowercased.contains("como funciona") {
            return .detailed
        }
        
        // 🎯 Detectar conversación casual
        if lowercased.contains("hola") || lowercased.contains("qué tal") || lowercased.contains("que tal") || lowercased.contains("jaja") {
            return .simple
        }
        
        // 🎯 Detectar por historial de conversación
        if conversationHistory.count > 5 {
            // Si la conversación es larga, mantener respuestas simples
            return .simple
        }
        
        // 🎯 Detectar por preferencias del usuario
        if let memory = memory {
            let style = extractCommunicationStyle(from: memory)
            switch style {
            case .formal:
                return .detailed // Usuarios formales prefieren respuestas detalladas
            case .fun:
                return .simple   // Usuarios divertidos prefieren respuestas rápidas
            case .casual:
                return .simple   // Usuarios casuales prefieren respuestas simples
            case .unknown:
                return .simple   // Por defecto, respuestas simples
            }
        }
        
        return .simple
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
