import Foundation

// MARK: - 🎯 NOVA PERSONALIDAD CON PERSONALIZACIÓN INTELIGENTE Y MULTILINGÜE
struct NovaPersona {
    
    // MARK: - 🌍 DETECCIÓN DE IDIOMA
    static var currentLanguage: String {
        // Usar preferencia persistida si existe, si no, fallback al sistema
        return NovaLanguageService.preferredLanguageCode()
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

    // MARK: - Utilidades de idioma
    private static func currentLangEnum() -> NovaLanguage {
        return NovaLanguage(rawValue: currentLanguage) ?? .en
    }

    private struct LocalizedLabels {
        let personalizationHeader: String
        let userInfoHeader: String
        let userFactsHeader: String
        let criticalNote: String
        let contextDetected: String
        let emotionalState: String
        let conversationFlow: String
        let usePreferredName: String
        // Vibe
        let goodMood: String
        let goodMoodFun: String
        let goodMoodFormal: String
        let goodMoodCasual: String
        let needsHelp: String
        let helpFormal: String
        let helpCasual: String
        let grateful: String
        let gratefulFun: String
        let gratefulNeutral: String
        let greeting: String
        let greetingFormal: String
        let greetingCasual: String
        let bored: String
        let boredFun: String
        let boredNeutral: String
        let neutral: String
        let neutralFormal: String
        let neutralFun: String
        let neutralCasual: String
        let neutralUnknown: String
        // Context types
        let contextTypeInfo: String
        let contextTypeReason: String
        let contextTypeTime: String
        let contextTypeLocation: String
        let intentHelp: String
        let intentOpinion: String
        let intentSuggestion: String
        // Emotions
        let emotionPositive: String
        let emotionSupport: String
        let emotionFrustrated: String
        let emotionAnxious: String
        let emotionBored: String
        // Flow
        let flowContinue: String
        let flowChange: String
        let flowResume: String
        let flowSummary: String
        
        init(lang: NovaLanguage) {
            switch lang {
            case .es:
                personalizationHeader = "PERSONALIZACIÓN ESPECÍFICA PARA ESTE USUARIO:"
                userInfoHeader = "INFORMACIÓN DEL USUARIO (no tuya):"
                userFactsHeader = "HECHOS QUE SABES SOBRE EL USUARIO:"
                criticalNote = "Esta información es SOBRE el usuario, no sobre ti (Nova). Cuando uses estos hechos, di 'Trabajas en...', 'Tienes mascotas...', NO 'Soy programador' o 'Tengo mascotas'."
                contextDetected = "CONTEXTO DETECTADO"
                emotionalState = "ESTADO EMOCIONAL"
                conversationFlow = "FLUJO DE CONVERSACIÓN"
                usePreferredName = "IMPORTANTE: Llámale"
                goodMood = "El usuario está de buen humor y relajado."
                goodMoodFun = "Puedes ser más divertida y hacer bromas."
                goodMoodFormal = "Mantén un tono amigable pero no demasiado informal."
                goodMoodCasual = "Puedes ser casual y hasta hacer alguna broma ligera."
                needsHelp = "El usuario necesita ayuda."
                helpFormal = "Sé profesional pero comprensiva."
                helpCasual = "Sé útil pero mantén un tono amigable y comprensivo."
                grateful = "El usuario está contento/agradecido."
                gratefulFun = "Puedes ser entusiasta y celebrar con él."
                gratefulNeutral = "Puedes ser cálida y positiva."
                greeting = "Saludo casual."
                greetingFormal = "Responde amigablemente pero con cierta formalidad."
                greetingCasual = "Responde de manera amigable y relajada."
                bored = "El usuario está aburrido."
                boredFun = "Sé creativa y divertida con las sugerencias."
                boredNeutral = "Puedes ser más creativa y sugerir cosas interesantes."
                neutral = "Tono neutral."
                neutralFormal = "Mantén un tono profesional pero amigable."
                neutralFun = "Puedes ser divertida y usar humor apropiado."
                neutralCasual = "Sé natural y relajada."
                neutralUnknown = "Adapta tu personalidad según el contenido."
                contextTypeInfo = "Tipo: Consulta informativa"
                contextTypeReason = "Tipo: Consulta de razones"
                contextTypeTime = "Tipo: Consulta temporal"
                contextTypeLocation = "Tipo: Consulta de ubicación"
                intentHelp = "Intención: Solicitud de ayuda"
                intentOpinion = "Intención: Solicitud de opinión"
                intentSuggestion = "Intención: Solicitud de sugerencias"
                emotionPositive = "Estado: Emocionado/Positivo"
                emotionSupport = "Estado: Necesita apoyo emocional"
                emotionFrustrated = "Estado: Frustrado - Sé empática"
                emotionAnxious = "Estado: Ansioso - Sé calmante"
                emotionBored = "Estado: Aburrido - Sé estimulante"
                flowContinue = "Flujo: Continuando tema anterior"
                flowChange = "Flujo: Cambio de tema"
                flowResume = "Flujo: Retomando tema anterior"
                flowSummary = "Flujo: Resumen/Conclusión"
            case .en:
                personalizationHeader = "SPECIFIC PERSONALIZATION FOR THIS USER:"
                userInfoHeader = "USER INFORMATION (not yours):"
                userFactsHeader = "FACTS YOU KNOW ABOUT THE USER:"
                criticalNote = "This information is ABOUT the user, not about you (Nova). When using these facts, say 'You work at...', 'You have pets...', NOT 'I'm a developer' or 'I have pets'."
                contextDetected = "DETECTED CONTEXT"
                emotionalState = "EMOTIONAL STATE"
                conversationFlow = "CONVERSATION FLOW"
                usePreferredName = "IMPORTANT: Call them"
                goodMood = "The user is in a good mood and relaxed."
                goodMoodFun = "You can be more playful and make jokes."
                goodMoodFormal = "Keep a friendly tone but not too informal."
                goodMoodCasual = "You can be casual and even make a light joke."
                needsHelp = "The user needs help."
                helpFormal = "Be professional but understanding."
                helpCasual = "Be helpful while keeping a friendly and empathetic tone."
                grateful = "The user is happy/grateful."
                gratefulFun = "You can be enthusiastic and celebrate with them."
                gratefulNeutral = "You can be warm and positive."
                greeting = "Casual greeting."
                greetingFormal = "Respond in a friendly way but with some formality."
                greetingCasual = "Respond in a friendly and relaxed way."
                bored = "The user is bored."
                boredFun = "Be creative and fun with suggestions."
                boredNeutral = "You can be more creative and suggest interesting things."
                neutral = "Neutral tone."
                neutralFormal = "Maintain a professional but friendly tone."
                neutralFun = "You can be fun and use appropriate humor."
                neutralCasual = "Be natural and relaxed."
                neutralUnknown = "Adapt your personality according to the content."
                contextTypeInfo = "Type: Informative query"
                contextTypeReason = "Type: Reason-seeking query"
                contextTypeTime = "Type: Temporal query"
                contextTypeLocation = "Type: Location query"
                intentHelp = "Intent: Request for help"
                intentOpinion = "Intent: Request for opinion"
                intentSuggestion = "Intent: Request for suggestions"
                emotionPositive = "State: Excited/Positive"
                emotionSupport = "State: Needs emotional support"
                emotionFrustrated = "State: Frustrated - Be empathetic"
                emotionAnxious = "State: Anxious - Be calming"
                emotionBored = "State: Bored - Be stimulating"
                flowContinue = "Flow: Continuing previous topic"
                flowChange = "Flow: Topic change"
                flowResume = "Flow: Resuming previous topic"
                flowSummary = "Flow: Summary/Conclusion"
            case .ca:
                personalizationHeader = "PERSONALITZACIÓ ESPECÍFICA PER A AQUEST USUARI:"
                userInfoHeader = "INFORMACIÓ DE L'USUARI (no teva):"
                userFactsHeader = "FETS QUE SAPS SOBRE L'USUARI:"
                criticalNote = "Aquesta informació és SOBRE l'usuari, no sobre tu (Nova). Quan utilitzis aquests fets, digues 'Treballes a...', 'Tens mascotes...', NO 'Sóc programador' o 'Tinc mascotes'."
                contextDetected = "CONTEXT DETECTAT"
                emotionalState = "ESTAT EMOCIONAL"
                conversationFlow = "FLUX DE CONVERSA"
                usePreferredName = "IMPORTANT: Digues-li"
                goodMood = "L'usuari està de bon humor i relaxat."
                goodMoodFun = "Pots ser més divertida i fer bromes."
                goodMoodFormal = "Mantén un to amigable però no massa informal."
                goodMoodCasual = "Pots ser casual i fins i tot fer alguna broma lleugera."
                needsHelp = "L'usuari necessita ajuda."
                helpFormal = "Sigues professional però comprensiva."
                helpCasual = "Sigues útil però mantén un to amigable i comprensiu."
                grateful = "L'usuari està content/agrait."
                gratefulFun = "Pots ser entusiasta i celebrar amb ell/ella."
                gratefulNeutral = "Pots ser càlida i positiva."
                greeting = "Salutació casual."
                greetingFormal = "Respon de manera amigable però amb certa formalitat."
                greetingCasual = "Respon de manera amigable i relaxada."
                bored = "L'usuari està avorrit."
                boredFun = "Sigues creativa i divertida amb les suggerències."
                boredNeutral = "Pots ser més creativa i suggerir coses interessants."
                neutral = "To neutral."
                neutralFormal = "Mantén un to professional però amigable."
                neutralFun = "Pots ser divertida i usar humor apropiat."
                neutralCasual = "Sigues natural i relaxada."
                neutralUnknown = "Adapta la teva personalitat segons el contingut."
                contextTypeInfo = "Tipus: Consulta informativa"
                contextTypeReason = "Tipus: Consulta de raons"
                contextTypeTime = "Tipus: Consulta temporal"
                contextTypeLocation = "Tipus: Consulta d'ubicació"
                intentHelp = "Intenció: Sol·licitud d'ajuda"
                intentOpinion = "Intenció: Sol·licitud d'opinió"
                intentSuggestion = "Intenció: Sol·licitud de suggerències"
                emotionPositive = "Estat: Emocionat/Positiu"
                emotionSupport = "Estat: Necessita suport emocional"
                emotionFrustrated = "Estat: Frustrat - Sigues empàtica"
                emotionAnxious = "Estat: Ansiós - Sigues calmant"
                emotionBored = "Estat: Avorrit - Sigues estimulant"
                flowContinue = "Flux: Continuant tema anterior"
                flowChange = "Flux: Canvi de tema"
                flowResume = "Flux: Reprenent tema anterior"
                flowSummary = "Flux: Resum/Conclusions"
            }
        }
    }
    
    // MARK: - ✨ Prompt Principal Mejorado con Personalización
    static var corePrompt: String {
        return prompts[currentLanguage] ?? prompts["en"]! // Fallback a inglés
    }
    
    // MARK: - 🧠 Prompt Contextual Personalizado
    static func getPersonalizedPrompt(userContext: String, memoryContext: String = "", personalization: NovaMemory? = nil) -> String {
        var prompt = corePrompt
        let lang = currentLangEnum()
        let L = LocalizedLabels(lang: lang)
        
        // 🎯 AÑADIR PERSONALIZACIÓN ESPECÍFICA
        if let memory = personalization {
            let personalPrefs = extractPersonalizationFromMemory(memory)
            if !personalPrefs.isEmpty {
                prompt += "\n\n🎭 \(L.personalizationHeader)\n\(personalPrefs)"
            }
        }
        
        if !userContext.isEmpty {
            prompt += "\n\n📋 \(L.userInfoHeader)\n\(userContext)"
        }
        
        if !memoryContext.isEmpty {
            prompt += "\n\n🧠 \(L.userFactsHeader)\n\(memoryContext)"
            prompt += "\n\n⚠️ \(L.criticalNote)"
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
        let lang = currentLangEnum()
        let L = LocalizedLabels(lang: lang)
        
        // 🎯 Considerar preferencias de comunicación del usuario
        let userCommunicationStyle = extractCommunicationStyle(from: memory)
        
        // 🔥 NUEVO: Análisis de contexto más inteligente
        let contextAnalysis = analyzeConversationContext(input)
        let emotionalState = detectEmotionalState(input)
        let conversationFlow = analyzeConversationFlow(input)
        
        // 🎭 Detectar señales emocionales básicas con contexto
        if lowercased.contains("jaja") || lowercased.contains("lol") || lowercased.contains("😂") || lowercased.contains("🤣") || lowercased.contains("xd") {
            analysis = L.goodMood
            if userCommunicationStyle == .fun {
                analysis += " " + L.goodMoodFun
            } else if userCommunicationStyle == .formal {
                analysis += " " + L.goodMoodFormal
            } else {
                analysis += " " + L.goodMoodCasual
            }
        }
        else if lowercased.contains("help") || lowercased.contains("ayuda") || lowercased.contains("problema") {
            analysis = L.needsHelp
            if userCommunicationStyle == .formal {
                analysis += " " + L.helpFormal
            } else {
                analysis += " " + L.helpCasual
            }
        }
        else if lowercased.contains("gracias") || lowercased.contains("genial") || lowercased.contains("perfecto") {
            analysis = L.grateful
            if userCommunicationStyle == .fun {
                analysis += " " + L.gratefulFun
            } else {
                analysis += " " + L.gratefulNeutral
            }
        }
        else if lowercased.contains("qué tal") || lowercased.contains("hola") || lowercased.contains("hey") {
            analysis = L.greeting
            if userCommunicationStyle == .formal {
                analysis += " " + L.greetingFormal
            } else {
                analysis += " " + L.greetingCasual
            }
        }
        else if lowercased.contains("aburrido") || lowercased.contains("random") {
            analysis = L.bored
            if userCommunicationStyle == .fun {
                analysis += " " + L.boredFun
            } else {
                analysis += " " + L.boredNeutral
            }
        }
        else {
            analysis = L.neutral
            switch userCommunicationStyle {
            case .formal:
                analysis += " " + L.neutralFormal
            case .fun:
                analysis += " " + L.neutralFun
            case .casual:
                analysis += " " + L.neutralCasual
            case .unknown:
                analysis += " " + L.neutralUnknown
            }
        }
        
        // 🔥 NUEVO: Añadir análisis de contexto inteligente
        if !contextAnalysis.isEmpty {
            analysis += "\n\n🎯 \(L.contextDetected):\n\(contextAnalysis)"
        }
        
        // 🔥 NUEVO: Añadir estado emocional
        if !emotionalState.isEmpty {
            analysis += "\n\n😊 \(L.emotionalState):\n\(emotionalState)"
        }
        
        // 🔥 NUEVO: Añadir flujo de conversación
        if !conversationFlow.isEmpty {
            analysis += "\n\n🔄 \(L.conversationFlow):\n\(conversationFlow)"
        }
        
        // 🎯 Añadir información del nombre preferido si existe
        if let memory = memory, let preferredName = memory.preferredName {
            analysis += "\n\n⭐ \(L.usePreferredName) '\(preferredName)'."
        }
        
        return analysis
    }
    
    // MARK: - 🔥 NUEVAS FUNCIONES DE ANÁLISIS INTELIGENTE
    
    // 🎯 Análisis de contexto de conversación
    private static func analyzeConversationContext(_ input: String) -> String {
        let lowercased = input.lowercased()
        var context = ""
        let L = LocalizedLabels(lang: currentLangEnum())
        
        // Detectar tipo de consulta
        if lowercased.contains("cómo") || lowercased.contains("como") || lowercased.contains("qué") || lowercased.contains("que") {
            context += "• \(L.contextTypeInfo)\n"
        }
        
        if lowercased.contains("por qué") || lowercased.contains("porque") || lowercased.contains("razón") || lowercased.contains("motivo") {
            context += "• \(L.contextTypeReason)\n"
        }
        
        if lowercased.contains("cuándo") || lowercased.contains("cuando") || lowercased.contains("hora") || lowercased.contains("día") || lowercased.contains("dia") {
            context += "• \(L.contextTypeTime)\n"
        }
        
        if lowercased.contains("dónde") || lowercased.contains("donde") || lowercased.contains("lugar") || lowercased.contains("sitio") {
            context += "• \(L.contextTypeLocation)\n"
        }
        
        // Detectar intención
        if lowercased.contains("ayuda") || lowercased.contains("ayúdame") || lowercased.contains("ayudame") {
            context += "• \(L.intentHelp)\n"
        }
        
        if lowercased.contains("opini") || lowercased.contains("qué piensas") || lowercased.contains("que piensas") {
            context += "• \(L.intentOpinion)\n"
        }
        
        if lowercased.contains("suger") || lowercased.contains("recomend") || lowercased.contains("idea") {
            context += "• \(L.intentSuggestion)\n"
        }
        
        return context
    }
    
    // 😊 Detección de estado emocional
    private static func detectEmotionalState(_ input: String) -> String {
        let lowercased = input.lowercased()
        var emotion = ""
        let L = LocalizedLabels(lang: currentLangEnum())
        
        // Emociones positivas
        if lowercased.contains("feliz") || lowercased.contains("contento") || lowercased.contains("emocionado") || lowercased.contains("genial") {
            emotion += "• \(L.emotionPositive)\n"
        }
        
        if lowercased.contains("triste") || lowercased.contains("deprimido") || lowercased.contains("mal") || lowercased.contains("cansado") {
            emotion += "• \(L.emotionSupport)\n"
        }
        
        if lowercased.contains("enfadado") || lowercased.contains("molesto") || lowercased.contains("frustrado") || lowercased.contains("irritado") {
            emotion += "• \(L.emotionFrustrated)\n"
        }
        
        if lowercased.contains("nervioso") || lowercased.contains("ansioso") || lowercased.contains("preocupado") || lowercased.contains("estresado") {
            emotion += "• \(L.emotionAnxious)\n"
        }
        
        if lowercased.contains("aburrido") || lowercased.contains("monótono") || lowercased.contains("rutinario") {
            emotion += "• \(L.emotionBored)\n"
        }
        
        return emotion
    }
    
    // 🔄 Análisis de flujo de conversación
    private static func analyzeConversationFlow(_ input: String) -> String {
        let lowercased = input.lowercased()
        var flow = ""
        let L = LocalizedLabels(lang: currentLangEnum())
        
        // Detectar continuidad
        if lowercased.contains("además") || lowercased.contains("también") || lowercased.contains("tambien") || lowercased.contains("por otro lado") {
            flow += "• \(L.flowContinue)\n"
        }
        
        if lowercased.contains("cambiemos") || lowercased.contains("otra cosa") || lowercased.contains("diferente") || lowercased.contains("nuevo tema") {
            flow += "• \(L.flowChange)\n"
        }
        
        if lowercased.contains("volvamos") || lowercased.contains("retomemos") || lowercased.contains("antes hablábamos") || lowercased.contains("antes hablabamos") {
            flow += "• \(L.flowResume)\n"
        }
        
        if lowercased.contains("resumiendo") || lowercased.contains("en resumen") || lowercased.contains("conclusión") || lowercased.contains("conclusion") {
            flow += "• \(L.flowSummary)\n"
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
