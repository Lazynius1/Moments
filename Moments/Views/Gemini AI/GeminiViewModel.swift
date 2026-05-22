import SwiftUI
import Firebase
import FirebaseVertexAI
@preconcurrency import FirebaseFirestore
import FirebaseAuth
import UIKit
import PhotosUI
import Photos

// MARK: - GeminiViewModel Mejorado
@MainActor
class GeminiViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var selectedImage: UIImage? = nil
    @Published var responseText = ""
    @Published var isLoading = false
    @Published var conversationHistory: [ChatMessage] = []
    @Published var conversationTitles: [ConversationTitle] = []
    @Published var photoAuthorizationStatus: PHAuthorizationStatus = .notDetermined // ✅ NUEVO: Estado de permisos
    @Published var followUpSuggestions: [SmartSuggestion] = [] // ✅ NUEVO: Sugerencias contextuales
    @Published var isLoadingFollowUps = false // ✅ NUEVO: Estado de carga de sugerencias
    @Published var showSuggestedOptions = true // ✅ MOVIDO DESDE LA VISTA
    @Published var showCelebration = false // 🎉 NUEVO: Efecto de confeti

    private(set) var userData: AppUser?
    private(set) var recentMoments: [Moment] = []
    private(set) var mutualConnections: [AppUser] = []
    private(set) var usersWithSharedInterests: [AppUser] = []
    private(set) var suggestedUsers: [AppUser] = []
    private(set) var profileVisits: [AppUser] = []

    private var currentConversationId: String?
    private var conversationService: ConversationService?
    private let firestoreService = FirestoreService()
    private let vertexAI: VertexAI
    private var model: GenerativeModel
    private var chatSession: Chat?

    private let memoryService = NovaMemoryService()
    // ✅ LAZY: Solo inicializar cuando realmente se necesite (cuando el usuario haga una consulta de actividad)
    private lazy var activityService: NovaActivityService = {
        LogConfig.log("🔧 NovaActivityService inicializado (lazy)", category: "Activity")
        return NovaActivityService.shared
    }()
    @Published var userMemory: NovaMemory?
    @Published var hasMemoryLoaded = false
    // Detectar idioma del input del usuario (heurística ligera)
    private func detectInputLanguage(_ text: String) -> NovaLanguage? {
        let lower = text.lowercased()
        // Señales de catalán
        let caSignals = ["què", "gràcies", "adéu", "ben", "perquè", "noi", "noia"]
        if caSignals.contains(where: { lower.contains($0) }) || lower.contains("à") || lower.contains("è") || lower.contains("ò") {
            return .ca
        }
        // Señales de inglés
        let enSignals = ["the ", "and ", "what", "how ", "please", "thank you", "you're", "you are"]
        if enSignals.contains(where: { lower.contains($0) }) {
            return .en
        }
        // Señales de español
        let esSignals = ["qué", "como", "cómo", "gracias", "hola", "por favor", "adiós", "porque"]
        if esSignals.contains(where: { lower.contains($0) }) || lower.contains("ñ") || lower.contains("á") || lower.contains("é") || lower.contains("í") || lower.contains("ó") || lower.contains("ú") {
            return .es
        }
        return nil
    }

    // ✅ NUEVO: Variables para controlar logs y conexiones
    private var memoryProcessingTimer: Timer?
    private var lastMemoryProcessTime: Date?
    private let minimumMemoryInterval: TimeInterval = 5.0

    var currentUserDisplayName: String {
        if let preferredName = userMemory?.preferredName, !preferredName.isEmpty {
            return preferredName
        }
        return userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
    }

    init() {
        self.vertexAI = VertexAI.vertexAI(location: "global")

        // Inicialización básica (se actualizará cuando carguen los datos del usuario)
        self.model = vertexAI.generativeModel(modelName: "gemini-3.1-flash-lite-preview")

        Task {
            await MainActor.run {
                self.conversationService = ConversationService()
            }
            await self.loadConversationTitles()
        }
    }

    // ✅ NUEVA: Configurar el modelo con instrucciones del sistema y sesión de chat
    private func setupModelAndSession(excluding messageId: UUID? = nil) {
        guard userData != nil else { return }

        let config = GenerationConfig(
            temperature: 0.7,
            topP: 0.8,
            topK: 40,
            candidateCount: 1,
            maxOutputTokens: 2048,
            stopSequences: [],
            responseMIMEType: "text/plain"
        )

        let safetySettings = [
            SafetySetting(harmCategory: .harassment, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .hateSpeech, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .dangerousContent, threshold: .blockMediumAndAbove)
        ]

        // Construir instrucciones del sistema (System Instruction)
        // 🔥 Conversational Spark: Seleccionar y marcar
        self.userMemory?.selectRandomSpark()
        let systemInstruction = buildSystemInstruction()

        // Si hay un spark activo, marcarlo como usado para que no se repita pronto
        if let spark = self.userMemory?.activeSpark {
            Task {
                await self.markSparkAsProbed(id: spark.id)
            }
        }

        self.model = vertexAI.generativeModel(
            modelName: "gemini-3.1-flash-lite-preview",
            generationConfig: config,
            safetySettings: safetySettings,
            systemInstruction: ModelContent(role: "system", parts: [systemInstruction])
        )

        // ✅ INICIAR SESIÓN DE CHAT (OPTIMIZADO: Sliding Window)
        // Convertimos el historial existente al formato de Gemini
        // Limitamos a los últimos 12 mensajes para ahorrar tokens (aprox. 6 turnos)
        let relevantHistory = conversationHistory
            .filter { !$0.isSystem && $0.id != messageId }
            .suffix(12)

        let history = relevantHistory.map { msg in
            ModelContent(role: msg.isUser ? "user" : "model", parts: [msg.text])
        }

        self.chatSession = model.startChat(history: history)
        LogConfig.log("🚀 Sesión de Chat iniciada con \(history.count) mensajes de historial (Ventana deslizante)", category: "Gemini")

        // ✅ Verificar permisos al iniciar el VM
        checkPhotoLibraryPermission()
    }

    // MARK: - 🔐 PERMISOS DE GALERÍA (Consistente con Stories/Moments)
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.photoAuthorizationStatus = status

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    self.photoAuthorizationStatus = newStatus
                }
            }
        }
    }

    private func buildSystemInstruction() -> String {
        guard let userData = userData else { return "" }

        let userContext = buildSimpleContext()

        // Token-optimized: no inyectar memoryContext completo aquí.
        // Los facts relevantes se inyectan via RAG en el per-message prompt.
        let instruction = NovaPersona.getPersonalizedPrompt(
            userContext: userContext,
            memoryContext: "",
            personalization: userMemory
        )

        return """
        \(instruction)

        TIME: \(getCurrentTimeContext())
        CURRENT USER:
        - Preferred display name: \(currentUserDisplayName)
        - Moments username: \(userData.username)
        - Never call the current user Álvaro.
        """
    }
    // MARK: - 🧠 Helper de Memoria Conversacional
    func markSparkAsProbed(id: String) async {
        guard let memory = userMemory else { return }

        // 1. Actualizar memoria localmente (para esta sesión)
        self.userMemory = memory.markingFactAsProbed(id: id)

        // 2. Persistir en Firestore
        // Aseguramos que usamos la versión actualizada para guardar
        if let updatedMemory = self.userMemory {
            self.memoryService.saveMemory(updatedMemory) { result in
                switch result {
                case .success:
                    LogConfig.log("✅ Spark marcado como 'probed' exitosamente: \(id)", category: "Memory")
                case .failure(let error):
                    LogConfig.log("❌ Error marcando spark como probed: \(error.localizedDescription)", category: "Memory")
                }
            }
        }
    }


    // MARK: - Funciones originales sin cambios
    func fetchUserData() {
        guard let userId = Auth.auth().currentUser?.uid else {
            LogConfig.log("Error: No se encontró el ID del usuario autenticado", category: "Auth")
            return
        }

        isLoading = true
        firestoreService.fetchUserDataForGemini(userId: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let user):
                    self.userData = user
                    LogConfig.log("Datos del usuario obtenidos para Gemini: \(user.username)", category: "Data")
                    self.fetchRecentMoments(userId: userId)
                    self.fetchMutualConnections(userId: userId)
                    self.fetchUsersWithSharedInterests(userId: userId)
                    self.fetchProfileVisits(userId: userId)
                    self.fetchSuggestedUsers()
                    // Cargar memoria silencisamente
                    self.loadMemoryContextSilently(userId: userId)
                case .failure(let error):
                    LogConfig.log("Error al obtener datos del usuario: \(error.localizedDescription)", category: "Error")
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Memoria de Nova
    private func loadMemoryContextSilently(userId: String) {
        memoryService.loadMemory(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let memory):
                    self.userMemory = memory
                    // 🎯 Log del nombre preferido si existe
                    if let preferredName = memory.preferredName {
                        LogConfig.log("🎭 Nombre preferido detectado: \(preferredName)", category: "Personalization")
                    }
                    LogConfig.log("🧠 Memoria personalizada cargada: \(memory.facts.count) hechos", category: "Memory")
                    // ✅ NUEVO: Marcar que la memoria está lista y configurar sesión
                    self.hasMemoryLoaded = true
                    self.setupModelAndSession()
                case .failure(_):
                    self.userMemory = NovaMemory(userId: userId)
                    self.hasMemoryLoaded = true
                    self.setupModelAndSession()
                }
            }
        }
    }

    func fetchRecentMoments(userId: String) {
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let moments):
                    self.recentMoments = Array(moments.prefix(3))
                    LogConfig.log("Momentos recientes obtenidos: \(self.recentMoments.count)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener momentos: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }

    func fetchMutualConnections(userId: String) {

        // Obtener following directamente de Firestore
        nonisolated(unsafe) let db = firestoreService.db
        nonisolated(unsafe) let fsService = firestoreService
        db.collection("users").document(userId).collection("following")
            .getDocuments { [weak self] followingSnapshot, error in
                guard let self = self else { return }

                if error != nil {
                    return
                }

                let followingIds = followingSnapshot?.documents.compactMap { doc in
                    doc.data()["userId"] as? String
                } ?? []


                // Obtener followers
                db.collection("users").document(userId).collection("followers")
                    .getDocuments { [weak self] followersSnapshot, error in
                        guard let self = self else { return }

                        if error != nil {
                            return
                        }

                        let followerIds = followersSnapshot?.documents.compactMap { doc in
                            doc.data()["userId"] as? String
                        } ?? []


                        // Calcular conexiones mutuas
                        let followingSet = Set(followingIds)
                        let followersSet = Set(followerIds)
                        let mutualIds = Array(followingSet.intersection(followersSet))


                        if mutualIds.isEmpty {
                            Task { @MainActor in
                                self.mutualConnections = []
                                self.objectWillChange.send() // ✅ Forzar actualización de UI
                            }
                            return
                        }

                        // Obtener usuarios mutuos
                        fsService.fetchUsers(userIds: mutualIds) { result in
                            Task { @MainActor in
                                switch result {
                                case .success(let users):
                                    self.mutualConnections = users
                                    self.objectWillChange.send() // ✅ Forzar actualización de UI
                                    LogConfig.log("Conexiones mutuas obtenidas: \(users.count)", category: "Data")
                                case .failure(let error):
                                    LogConfig.log("Error al obtener usuarios mutuos: \(error.localizedDescription)", category: "Error")
                                }
                            }
                        }
                    }
            }
    }


    func fetchUsersWithSharedInterests(userId: String) {
        guard let userData = userData else {
            LogConfig.log("Error: Datos del usuario no disponibles.", category: "Error")
            return
        }

        let interests = userData.interests
        guard !interests.isEmpty else {
            LogConfig.log("No hay intereses para buscar usuarios compartidos", category: "Data")
            return
        }

        firestoreService.fetchUsersWithSharedInterests(interests: interests, excludingUserId: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let users):
                    self.usersWithSharedInterests = Array(users.prefix(3))
                    LogConfig.log("Usuarios con intereses compartidos obtenidos: \(self.usersWithSharedInterests.count)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener usuarios con intereses compartidos: \(error.localizedDescription)", category: "Error")
                }
                self.isLoading = false
            }
        }
    }

    func fetchProfileVisits(userId: String) {
        firestoreService.fetchVisits(userId: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let visits):
                    let visitorIds = visits.map { $0.visitorId }

                    if visitorIds.isEmpty {
                        self.profileVisits = []
                        self.objectWillChange.send()
                        return
                    }

                    // Obtener usuarios visitantes usando fetchUsersInBatches como ProfileView
                    self.fetchUsersInBatches(userIds: visitorIds) { users in
                        Task { @MainActor in
                            self.profileVisits = users
                            self.objectWillChange.send()
                            LogConfig.log("Visitas al perfil obtenidas: \(users.count)", category: "Data")
                        }
                    }
                case .failure(let error):
                    LogConfig.log("Error al obtener visitas: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }

    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            firestoreService.fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                switch result {
                case .success(let users):
                    allUsers.append(contentsOf: users)
                case .failure(_):
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
    }

    func fetchSuggestedUsers() {
        firestoreService.fetchSuggestedUsers { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let users):
                    self.suggestedUsers = users
                    LogConfig.log("Usuarios sugeridos obtenidos: \(users.count)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener usuarios sugeridos: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }

    // MARK: - Gestión de conversaciones (sin cambios)
    func loadConversationTitles() async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }

        let titles = await conversationService.loadConversationTitles(for: userId)
        await MainActor.run {
            self.conversationTitles = titles
        }
    }

    func startNewConversation() {
        currentConversationId = nil
        conversationHistory.removeAll()
        memoryProcessingTimer?.invalidate()

        // ✅ AÑADIR MENSAJE DEL SISTEMA (estilo WhatsApp)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let systemMessage: String
        switch lang {
        case .es:
            systemMessage = "Los mensajes están protegidos con cifrado de extremo a extremo. Nadie fuera de esta conversación puede leerlos, ni siquiera Moments."
        case .en:
            systemMessage = "Messages are protected with end-to-end encryption. No one outside of this conversation can read them, not even Moments."
        case .ca:
            systemMessage = "Els missatges estan protegits amb xifratge d'extrem a extrem. Ningú fora d'aquesta conversa pot llegir-los, ni tan sols Moments."
        }
        conversationHistory.append(ChatMessage(text: systemMessage, isUser: false, isSystem: true))

        if let userId = Auth.auth().currentUser?.uid {
            loadMemoryContextSilently(userId: userId)

            // 🎯 AÑADIR ESTE DELAY PEQUEÑO
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                // Forzar actualización de la UI para reflejar la memoria cargada
                self.objectWillChange.send()
            }
        }
    }

    func loadConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }

        LogConfig.log("🔄 Cargando conversación: \(conversationId)", category: "Conversation")
        isLoading = true

        let messages = await conversationService.loadConversation(conversationId, for: userId)
        self.conversationHistory = messages
        self.currentConversationId = conversationId
        self.isLoading = false
        self.objectWillChange.send()

        // Recargar contexto silenciosamente
        if let userId = Auth.auth().currentUser?.uid {
            self.loadMemoryContextSilently(userId: userId)
        }
    }

    func deleteConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }

        let success = await conversationService.deleteConversation(conversationId, for: userId)
        if success {
            self.conversationTitles.removeAll { $0.id == conversationId }
            if self.currentConversationId == conversationId {
                self.startNewConversation()
            }
        }
    }

    private func saveCurrentConversation() async {
        guard let userId = Auth.auth().currentUser?.uid,
              !conversationHistory.isEmpty,
              let conversationService = conversationService else { return }

        if let conversationId = currentConversationId {
            // Actualizar conversación existente
            let success = await conversationService.updateConversation(
                conversationId,
                for: userId,
                messages: conversationHistory
            )
            if success {
                await loadConversationTitles()
            }
        } else {
            // Crear nueva conversación
            let conversationId = await conversationService.saveConversation(
                for: userId,
                messages: conversationHistory
            )
            if let id = conversationId {
                await MainActor.run {
                    self.currentConversationId = id
                }
                await loadConversationTitles()
            }
        }
    }

    // MARK: - ✅ sendMessage() MEJORADO CON MANEJO DE ERRORES
    func sendMessage() {
        // ✅ VALIDACIONES BÁSICAS
        guard !inputText.isEmpty else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Por favor, escribe un mensaje."
            case .en: responseText = "Please, write a message."
            case .ca: responseText = "Si us plau, escriu un missatge."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        guard let userId = Auth.auth().currentUser?.uid, userData != nil else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Error: No se pudieron cargar los datos del usuario. Por favor, intenta de nuevo."
            case .en: responseText = "Error: Could not load user data. Please try again."
            case .ca: responseText = "Error: No s'han pogut carregar les dades de l'usuari. Si us plau, torna-ho a provar."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        // ✅ NUEVO: Asegurar que la memoria esté cargada antes de enviar
        guard hasMemoryLoaded else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Cargando tu memoria personalizada... Por favor, espera un momento."
            case .en: responseText = "Loading your personalized memory... Please wait a moment."
            case .ca: responseText = "Carregant la teva memòria personalitzada... Si us plau, espera un moment."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        // 🎯 DETECTAR COMANDOS DE PERSONALIZACIÓN ANTES DE ENVIAR
        if let personalizationCommand = NovaPersona.detectPersonalizationCommand(inputText) {
            handlePersonalizationCommand(personalizationCommand, userId: userId)
            return
        }

        // 🔥 NUEVO: Detectar preguntas sobre actividad de la app
        // ✅ SOLO ACTIVAR SI EL USUARIO REALMENTE PREGUNTA SOBRE ACTIVIDAD
        if let activityQuery = NovaActivityService.isActivityQuery(inputText) {
            // ✅ FORZAR INICIALIZACIÓN LAZY DEL SERVICIO SOLO AQUÍ
            _ = activityService // Esto activa el lazy var
            handleActivityQuery(activityQuery, userId: userId, userInput: inputText)
            return
        }

        // ✅ AÑADIR MENSAJE DEL SISTEMA SI ES LA PRIMERA VEZ (estilo WhatsApp)
        if conversationHistory.isEmpty && currentConversationId == nil {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            let systemMessage: String
            switch lang {
            case .es:
                systemMessage = "Los mensajes están protegidos con cifrado de extremo a extremo. Nadie fuera de esta conversación puede leerlos, ni siquiera Moments."
            case .en:
                systemMessage = "Messages are protected with end-to-end encryption. No one outside of this conversation can read them, not even Moments."
            case .ca:
                systemMessage = "Els missatges estan protegits amb xifratge d'extrem a extrem. Ningú fora d'aquesta conversa pot llegir-los, ni tan sols Moments."
            }
            conversationHistory.append(ChatMessage(text: systemMessage, isUser: false, isSystem: true))
        }

        // ✅ PREPARAR MENSAJE DEL USUARIO (con imagen si existe)
        let currentImage = selectedImage
        let userMessage = ChatMessage(text: inputText, isUser: true, image: currentImage)
        conversationHistory.append(userMessage)

        let currentInput = inputText
        inputText = ""

        // 🎭 ACTUALIZAR PERFIL DE COMPORTAMIENTO (sin pisar edits hechos desde el sheet)
        if let memory = self.userMemory {
            // Capturar textos recientes (incluyendo el actual)
            let recentTexts = conversationHistory
                .filter { $0.isUser }
                .suffix(10)
                .map { $0.text }
            let memoryCopy = memory

            Task.detached(priority: .background) {
                let updatedMemory = NovaBehaviorService.shared.updateBehaviorProfile(memory: memoryCopy, recentMessages: Array(recentTexts))

                await MainActor.run { [weak self] in
                    self?.saveBehaviorProfileSafely(updatedMemory.behaviorProfile)
                }
            }
        }
        selectedImage = nil
        isLoading = true

        // ✅ ANÁLISIS DINÁMICO (Token-optimized: minimal vibe + RAG only)
        let vibeLabel = NovaPersona.analyzeUserVibeWithPersonalization(currentInput, memory: userMemory)
        let lang = detectInputLanguage(currentInput) ?? (NovaLanguageService.getPreferredLanguage() ?? .es)

        let isSimpleGreeting = self.isSimpleGreeting(currentInput)

        // 🔍 RAG: solo si la consulta realmente lo merece
        var ragContext = ""
        if !isSimpleGreeting, let memory = userMemory {
            let relevantFacts = NovaEmbeddingService.shared.findSimilarFacts(query: currentInput, facts: memory.facts)
            if !relevantFacts.isEmpty {
                let contextContent = relevantFacts.map { "• \($0.content)" }.joined(separator: "\n")
                ragContext = "\nMemory: \(contextContent)"
                LogConfig.log("🔍 RAG: Inyectados \(relevantFacts.count) hechos relevantes", category: "Memory")
            }
        }

        // ✅ CONSTRUIR PROMPT ULTRA-LIGERO
        let langName: String = {
            switch lang {
            case .es: return "Español"
            case .en: return "English"
            case .ca: return "Català"
            }
        }()

        let creatorContext = NovaPersona.isCreatorQuestion(currentInput)
            ? "\nCreator fact: Moments was created by Álvaro. Never confuse Álvaro with the current user."
            : ""

        let greetingGuardrail = isSimpleGreeting
            ? "\nThis is low-context small talk. Reply briefly and naturally. Use the preferred display name if known. Do not bring up old interests, habits, media tastes, day-of-week commentary, recommendations, or proactive suggestions unless the user asks."
            : ""

        let minimalPrompt = """
        [\(langName)] Vibe: \(vibeLabel)\(ragContext)
        \(creatorContext)
        \(greetingGuardrail)

        \(currentInput)
        """

        Task {
            do {
                // ✅ Asegurar sesión inicializada
                if chatSession == nil { setupModelAndSession(excluding: userMessage.id) }

                // 1. Añadimos un mensaje vacío para el bot que iremos llenando
                let botMessage = ChatMessage(text: "", isUser: false)
                self.conversationHistory.append(botMessage)
                let botMessageIndex = self.conversationHistory.count - 1

                var fullResponseText = ""
                let stream = sendMessageStreamWithRetry(prompt: minimalPrompt, image: currentImage, maxRetries: 2)

                for try await chunk in stream {
                    if let newText = chunk.text {
                        fullResponseText += newText
                        // Actualizamos el mensaje en el historial en tiempo real
                        self.conversationHistory[botMessageIndex].text = fullResponseText
                        self.responseText = fullResponseText // Para otros usos de la UI si existen
                    }
                }

                // 🎯 VALIDAR PERSONALIZACIÓN FINAL
                let validatedResponse = NovaPersona.validatePersonalization(
                    input: currentInput,
                    memory: userMemory,
                    response: fullResponseText
                )
                let identitySafeResponse = self.enforceIdentitySafety(on: validatedResponse, input: currentInput)

                // Actualizar con la versión validada si hubo cambios
                if identitySafeResponse != fullResponseText {
                    self.conversationHistory[botMessageIndex].text = identitySafeResponse
                    self.responseText = identitySafeResponse
                }

                self.isLoading = false
                HapticManager.shared.notification(.success)

                await self.saveCurrentConversation()
                self.scheduleMemoryProcessing(userId: userId)
                self.analyzeConversationIntelligently(userId: userId)

                // 🎉 DETECTAR CELEBRACIÓN
                if self.shouldTriggerCelebration(text: validatedResponse) {
                    self.showCelebration = true
                    HapticManager.shared.notification(.success) // Doble feedback para enfatizar
                }

                // ✅ GENERAR SUGERENCIAS CONTEXTUALES
                await self.generateFollowUpSuggestions()

            } catch {
                await handleSendMessageError(error)
            }
        }
    }

    // 🔥 Generar sugerencias inteligentes (con cooldown para ahorrar tokens)
    private var lastFollowUpTime: Date = .distantPast
    private let followUpCooldown: TimeInterval = 30 // Solo cada 30 segundos

    private func generateFollowUpSuggestions() async {
        // ⏱️ Cooldown: no generar si la última fue hace menos de 30s
        guard Date().timeIntervalSince(lastFollowUpTime) > followUpCooldown else {
            LogConfig.log("⏱️ Follow-up suggestions en cooldown, saltando", category: "Gemini")
            return
        }
        // Solo generar si hay al menos 2 mensajes del usuario
        let userMessageCount = conversationHistory.filter { $0.isUser }.count
        guard userMessageCount >= 2 else { return }

        let lastUserMessage = conversationHistory.last { $0.isUser }?.text ?? ""
        let lang = detectInputLanguage(lastUserMessage) ?? (NovaLanguageService.getPreferredLanguage() ?? .es)
        let langName = lang == .es ? "Español" : (lang == .ca ? "Català" : "English")

        await MainActor.run {
            self.isLoadingFollowUps = true
            self.followUpSuggestions = []
        }

        // 🧠 Prompt compacto
        let recentContext = conversationHistory.suffix(4).map { "\($0.isUser ? "U" : "N"): \($0.text.prefix(100))" }.joined(separator: "\n")
        let suggestionPrompt = """
        Generate 3 follow-up messages the USER could send next. Written from the user's perspective (things they'd say TO the AI, not what the AI would ask).
        Examples: "Cuéntame más", "¿Qué me recomiendas?", "Explícame eso mejor".
        JSON array: [{"text": "short phrase", "icon": "SF Symbol name"}].
        Keep them useful for Moments, personal context, or the current conversation. Avoid generic life-coaching prompts.
        Language: \(langName). Context:
        \(recentContext)
        """

        do {
            let result = try await model.generateContent(suggestionPrompt)

            if let text = result.text {
                let cleanedJSON = text.replacingOccurrences(of: "```json", with: "")
                                     .replacingOccurrences(of: "```", with: "")
                                     .trimmingCharacters(in: .whitespacesAndNewlines)

                if let data = cleanedJSON.data(using: .utf8) {
                    let decodedSuggestions = try JSONDecoder().decode([SmartSuggestion].self, from: data)

                    await MainActor.run {
                        self.followUpSuggestions = decodedSuggestions
                        self.isLoadingFollowUps = false
                        self.lastFollowUpTime = Date()
                        withAnimation(.spring()) {
                            self.showSuggestedOptions = true
                        }
                    }
                }
            }
        } catch {
            LogConfig.log("❌ Error generando sugerencias contextuales: \(error.localizedDescription)", category: "Gemini")
            await MainActor.run {
                self.isLoadingFollowUps = false
            }
        }
    }

    // 🎉 DETECTOR DE CELEBRACIONES
    private func shouldTriggerCelebration(text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let keywords = [
            "felicidades", "enhorabuena", "genial", "fantástico", "celebrar",
            "increíble", "fiesta", "éxito", "congratulations", "amazing",
            "hooray", "party", "success", "great job", "awesome",
            "felicitats", "enhorabona", "fantàstic"
        ]

        return keywords.contains { lowercasedText.contains($0) }
    }

    private func enforceIdentitySafety(on response: String, input: String) -> String {
        guard !NovaPersona.isCreatorQuestion(input) else { return response }

        var safeResponse = response
        let displayName = currentUserDisplayName

        if safeResponse.contains("Álvaro") || safeResponse.contains("alvaro") {
            safeResponse = safeResponse
                .replacingOccurrences(of: "Álvaro", with: displayName)
                .replacingOccurrences(of: "alvaro", with: displayName)
        }

        return safeResponse
    }

    private func isSimpleGreeting(_ input: String) -> Bool {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "¿", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "¡", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        let greetings: Set<String> = [
            "hola", "holaa", "hey", "hello", "hi", "buenas",
            "qué tal", "que tal", "ei", "ey", "bon dia", "bona tarda", "hola nova",
            "todo bien", "todo bien y tú", "todo bien y tu", "bien y tú", "bien y tu",
            "yo bien y tú", "yo bien y tu", "muy bien y tú", "muy bien y tu",
            "cómo estás", "como estas", "como vas", "cómo vas", "qué haces", "que haces",
            "tot bé", "tot be", "tot bé i tu", "tot be i tu", "bé i tu", "be i tu"
        ]

        let smallTalkFragments = [
            "y tú", "y tu", "i tu", "how are you", "and you", "todo bien", "tot bé", "tot be"
        ]

        return greetings.contains(normalized) ||
            normalized.count <= 8 && ["hola", "hey", "hi"].contains(normalized) ||
            normalized.count <= 40 && smallTalkFragments.contains { normalized.contains($0) }
    }

    func reloadMemoryFromStore() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        memoryService.loadMemory(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                if case .success(let memory) = result {
                    self.userMemory = memory
                    self.setupModelAndSession()
                }
            }
        }
    }

    private func saveBehaviorProfileSafely(_ behaviorProfile: NovaBehaviorProfile?) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        memoryService.loadMemory(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                let latestMemory: NovaMemory
                if case .success(let memory) = result {
                    latestMemory = memory
                } else if let current = self.userMemory {
                    latestMemory = current
                } else {
                    latestMemory = NovaMemory(userId: userId)
                }

                var mergedMemory = latestMemory
                mergedMemory.behaviorProfile = behaviorProfile ?? latestMemory.behaviorProfile
                self.userMemory = mergedMemory
                self.memoryService.saveMemory(mergedMemory) { _ in }
            }
        }
    }

    // 🔥 NUEVA: Función de análisis inteligente de conversación en tiempo real
    private func analyzeConversationIntelligently(userId: String) {
        guard conversationHistory.count >= 3 else { return }

        // 🎯 Analizar engagement y patrones de la conversación
        let engagement = memoryService.analyzeConversationEngagement(conversationHistory)
        let patterns = memoryService.analyzeCommunicationPatterns(conversationHistory)

        // 🧠 Aprender preferencias automáticamente
        memoryService.learnConversationPreferences(conversationHistory, userId: userId)

        // 📊 Log de métricas para debugging
        LogConfig.log("🎭 Análisis de conversación - Engagement: \(engagement.level.description), Participación: \(String(format: "%.2f", engagement.userParticipation))", category: "Intelligence")
        LogConfig.log("📊 Patrones detectados - Formal: \(patterns.isFormal), Emojis: \(patterns.usesEmojis), Preguntas: \(patterns.asksQuestions)", category: "Intelligence")

        // 🎯 Adaptar el comportamiento de Nova según el análisis
        adaptNovaBehavior(engagement: engagement, patterns: patterns)
    }

    // 🎭 Adaptar el comportamiento de Nova según el análisis (logging only, actual adaptation in behavioral profile)
    private func adaptNovaBehavior(engagement: ConversationEngagement, patterns: CommunicationPatterns) {
        LogConfig.log("🎭 Engagement: \(engagement.level.description), Formal: \(patterns.isFormal), Emojis: \(patterns.usesEmojis)", category: "Adaptation")
    }

    // ✅ NUEVA: Envío de mensaje usando la sesión de chat con STREAMING (soporta Imágenes)
    private func sendMessageStreamWithRetry(prompt: String, image: UIImage?, maxRetries: Int) -> AsyncThrowingStream<GenerateContentResponse, Error> {
        return AsyncThrowingStream(GenerateContentResponse.self) { continuation in
            Task {
                var lastError: Error?

                for attempt in 0...maxRetries {
                    do {
                        if attempt > 0 {
                            let delay = pow(2.0, Double(attempt)) * 0.5
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            LogConfig.log("🔄 Reintentando envío multimodal con stream (intento \(attempt + 1))", category: "Retry")
                        }

                        // ✅ USAR SESIÓN SI ESTÁ DISPONIBLE
                        guard let session = chatSession else {
                            continuation.finish(throwing: NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sesión no inicializada"]))
                            return
                        }

                        // En FirebaseVertexAI, sendMessageStream puede aceptar variadic arguments o un array de Parts
                        // El objeto UIImage es PartsRepresentable por defecto
                        let stream: AsyncThrowingStream<GenerateContentResponse, Error>
                        if let image = image {
                            stream = try session.sendMessageStream(prompt, image)
                        } else {
                            stream = try session.sendMessageStream(prompt)
                        }

                        for try await response in stream {
                            continuation.yield(response)
                        }

                        continuation.finish()
                        return

                    } catch {
                        lastError = error
                        LogConfig.log("❌ Error en streaming multimodal (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")

                        if !isNetworkError(error) && attempt == 0 {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "GeminiError", code: -1))
            }
        }
    }

    // ✅ ANTIGUA: Envío de mensaje usando la sesión de chat (con historial, NO stream)
    private func sendMessageWithRetry(prompt: String, maxRetries: Int) async throws -> GenerateContentResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    LogConfig.log("🔄 Reintentando envío de mensaje (intento \(attempt + 1))", category: "Retry")
                }

                if let session = chatSession {
                    return try await session.sendMessage(prompt)
                } else {
                    return try await model.generateContent(prompt)
                }

            } catch {
                lastError = error
                LogConfig.log("❌ Error en envío de mensaje (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")

                if !isNetworkError(error) && attempt == 0 {
                    throw error
                }
            }
        }

        throw lastError ?? NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error desconocido"])
    }

    // ✅ ANTIGUA: Generación de contenido simple (sin historial de sesión)
    // Se usa para cosas puntuales como regenerar bio, títulos, etc.
    private func generateContentWithRetry(prompt: String, maxRetries: Int) async throws -> GenerateContentResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    LogConfig.log("🔄 Reintentando generación simple (intento \(attempt + 1))", category: "Retry")
                }

                return try await model.generateContent(prompt)

            } catch {
                lastError = error
                LogConfig.log("❌ Error en generación simple (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")

                if !isNetworkError(error) && attempt == 0 {
                    throw error
                }
            }
        }

        throw lastError ?? NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error desconocido"])
    }

    // ✅ FUNCIÓN PARA DETECTAR ERRORES DE RED
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain ||
               nsError.code == NSURLErrorTimedOut ||
               nsError.code == NSURLErrorNetworkConnectionLost ||
               error.localizedDescription.contains("network") ||
               error.localizedDescription.contains("connection") ||
               error.localizedDescription.contains("Reporter disconnected")
    }

    // ✅ MANEJO MEJORADO DE ERRORES (multilingüe)
    private func handleSendMessageError(_ error: Error) async {
        LogConfig.log("🚨 Error en sendMessage: \(error.localizedDescription)", category: "Error")

        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let userFriendlyMessage: String

        if isNetworkError(error) {
            switch lang {
            case .es:
                userFriendlyMessage = """
                🌐 Parece que hay un problema de conexión.

                ¿Puedes verificar tu internet e intentar de nuevo?
                """
            case .en:
                userFriendlyMessage = """
                🌐 It seems there's a connection problem.

                Can you check your internet and try again?
                """
            case .ca:
                userFriendlyMessage = """
                🌐 Sembla que hi ha un problema de connexió.

                Pots verificar la teva internet i tornar-ho a provar?
                """
            }
        } else if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
            switch lang {
            case .es:
                userFriendlyMessage = """
                ⏰ He alcanzado mi límite de consultas por el momento.

                Intenta de nuevo en unos minutos, por favor.
                """
            case .en:
                userFriendlyMessage = """
                ⏰ I've reached my query limit for the moment.

                Please try again in a few minutes.
                """
            case .ca:
                userFriendlyMessage = """
                ⏰ He arribat al meu límit de consultes per ara.

                Si us plau, torna-ho a provar en uns minuts.
                """
            }
        } else {
            switch lang {
            case .es:
                userFriendlyMessage = """
                🤖 Tuve un pequeño problema técnico.

                ¿Puedes reformular tu pregunta?
                """
            case .en:
                userFriendlyMessage = """
                🤖 I had a small technical problem.

                Can you rephrase your question?
                """
            case .ca:
                userFriendlyMessage = """
                🤖 He tingut un petit problema tècnic.

                Pots reformular la teva pregunta?
                """
            }
        }

        self.isLoading = false
        self.responseText = userFriendlyMessage
        self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
        Task {
            await self.saveCurrentConversation()
        }
    }

    // ✅ NUEVA FUNCIÓN: PROGRAMAR PROCESAMIENTO DE MEMORIA CON DEBOUNCE
    private func scheduleMemoryProcessing(userId: String) {
        // Cancelar timer anterior si existe
        memoryProcessingTimer?.invalidate()

        // ✅ VERIFICAR SI YA SE PROCESÓ RECIENTEMENTE
        let now = Date()
        if let lastTime = lastMemoryProcessTime,
           now.timeIntervalSince(lastTime) < minimumMemoryInterval {
            LogConfig.log("⚠️ Memoria procesada recientemente - saltando", category: "Memory")
            return
        }

        // ✅ CREAR NUEVO TIMER CON DELAY
        memoryProcessingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                self?.lastMemoryProcessTime = Date()
            }

            Task.detached { [weak self] in
                await self?.processMemoryAfterConversationSafely(userId: userId)
            }
        }
    }

    private func buildSimpleContext() -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        guard let userData = userData else {
            switch lang { case .es: return "Usuario sin datos específicos"; case .en: return "User without specific data"; case .ca: return "Usuari sense dades específiques" }
        }
        switch lang {
        case .es:
            return """
            PERFIL DEL USUARIO:
            - Nombre preferido: \(currentUserDisplayName)
            - Username en la app: \(userData.username)
            - Intereses: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "No especificada")
            """
        case .en:
            return """
            USER PROFILE:
            - Preferred name: \(currentUserDisplayName)
            - App username: \(userData.username)
            - Interests: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "Not specified")
            """
        case .ca:
            return """
            PERFIL DE L'USUARI:
            - Nom preferit: \(currentUserDisplayName)
            - Nom d'usuari a l'app: \(userData.username)
            - Interessos: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "No especificada")
            """
        }
    }

    // MARK: - 🔧 FUNCIÓN DE MEMORIA SEGURA MEJORADA
    private func processMemoryAfterConversationSafely(userId: String) async {
        guard !conversationHistory.isEmpty else { return }

        LogConfig.log("🧠 Iniciando procesamiento seguro de memoria", category: "Memory")

        let currentHistory = conversationHistory.filter { message in
            !message.isSystem && !shouldExcludeFromMemory(message)
        }
        let existingFacts = self.userMemory?.facts ?? []

        await withCheckedContinuation { continuation in
            memoryService.extractFactsFromConversation(currentHistory, userId: userId, existingFacts: existingFacts) { facts in
                if !facts.isEmpty {
                    self.memoryService.updateMemoryWithFacts(facts, userId: userId) { result in
                        if case .success = result {
                            LogConfig.log("🧠 Nuevos hechos guardados: \(facts.count)", category: "Memory")

                            // 🔥 NUEVO: Feedback háptico cuando se guarda un hecho importante
                            let importantFacts = facts.filter { $0.importance >= 4 }
                            if !importantFacts.isEmpty {
                                HapticManager.shared.mediumImpact()
                            }

                            // Recargar memoria
                            self.loadMemoryContextSilently(userId: userId)
                        }
                    }
                }
                continuation.resume()
            }
        }
    }

    private func shouldExcludeFromMemory(_ message: ChatMessage) -> Bool {
        let lowercased = message.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let excludedFragments = [
            "cifrado de extremo a extremo",
            "end-to-end encryption",
            "xifratge d'extrem a extrem",
            "cargando tu memoria personalizada",
            "loading your personalized memory",
            "carregant la teva memòria personalitzada",
            "por favor, escribe un mensaje",
            "please, write a message",
            "si us plau, escriu un missatge",
            "he tenido un pequeño problema técnico",
            "i've run into a small technical issue",
            "he tingut un petit problema tècnic"
        ]

        return excludedFragments.contains { lowercased.contains($0) }
    }

    // MARK: - 🔥 NUEVO: Manejo de consultas de actividad
    private func handleActivityQuery(_ queryType: ActivityQueryType, userId: String, userInput: String) {
        let userMessage = ChatMessage(text: userInput, isUser: true)
        conversationHistory.append(userMessage)

        let currentInput = userInput
        inputText = ""
        isLoading = true

        Task {
            do {
                // Preparar variables de contexto (necesarias para todos los casos)
                let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                let memoryContext = userMemory?.contextString ?? ""
                let displayName = userMemory?.preferredName ?? userData?.username ?? "Usuario"

                let activityData: String

                switch queryType {
                case .storyChainViewers:
                    // Obtener el último chain y sus viewers (usando resumen optimizado)
                    if let chainInfo = try await getLatestStoryChain(userId: userId) {
                        let viewersSummary = try await getStoryChainViewersSummary(chainId: chainInfo.chainId, userId: userId)
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es:
                            activityData = "Story Chain \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        case .en:
                            activityData = "Story Chain \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        case .ca:
                            activityData = "Cadena d'històries \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        }
                    } else {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es: activityData = "No tienes Story Chains publicados aún."
                        case .en: activityData = "You don't have any Story Chains published yet."
                        case .ca: activityData = "No tens cadenes d'històries publicades encara."
                        }
                    }

                case .latestStoryChain:
                    if let chainInfo = try await getLatestStoryChain(userId: userId) {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es:
                            activityData = "Tu último Story Chain es \"\(chainInfo.chainTitle)\" con \(chainInfo.storyCount) partes, publicado \(timeAgoString(from: chainInfo.createdAt))."
                        case .en:
                            activityData = "Your latest Story Chain is \"\(chainInfo.chainTitle)\" with \(chainInfo.storyCount) parts, published \(timeAgoString(from: chainInfo.createdAt))."
                        case .ca:
                            activityData = "La teva última cadena d'històries és \"\(chainInfo.chainTitle)\" amb \(chainInfo.storyCount) parts, publicada \(timeAgoString(from: chainInfo.createdAt))."
                        }
                    } else {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es: activityData = "No tienes Story Chains publicados aún."
                        case .en: activityData = "You don't have any Story Chains published yet."
                        case .ca: activityData = "No tens cadenes d'històries publicades encara."
                        }
                    }

                case .profileVisits:
                    // Usar resumen optimizado (5 más recientes + conteo total)
                    let visitsSummary = try await getProfileVisitsSummary(userId: userId)
                    activityData = visitsSummary.formattedSummary

                case .weeklySummary:
                    // Resumen semanal comparativo (usando datos crudos)
                    let weeklySummary = try await getWeeklySummary(userId: userId)
                    // Obtener insights proactivos
                    let insights = weeklySummary.proactiveInsights
                    // Convertir datos crudos a JSON string para Nova
                    if let jsonData = try? JSONSerialization.data(withJSONObject: weeklySummary.rawData, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        activityData = jsonString

                        // Construir respuesta con insights proactivos
                        let prompt = buildActivityResponsePrompt(
                            userInput: currentInput,
                            activityData: activityData,
                            memoryContext: memoryContext,
                            displayName: displayName,
                            lang: lang,
                            proactiveInsights: insights
                        )

                        let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                        let responseText = response.text ?? weeklySummary.formattedSummary

                        self.isLoading = false
                        self.responseText = responseText
                        self.conversationHistory.append(ChatMessage(text: responseText, isUser: false))

                        // 🔥 Feedback háptico diferenciado según tipo de insight y tendencias
                        let negativeInsights = insights.filter { $0.type != .positiveTrend && ($0.severity == .high || $0.severity == .medium) }
                        let positiveInsights = insights.filter { $0.type == .positiveTrend }

                        // Detectar tendencias positivas directamente de los datos
                        let rawData = weeklySummary.rawData
                        var hasPositiveTrends = false
                        if let visitsData = rawData["profileVisits"] as? [String: Any],
                           let visitsChange = visitsData["change"] as? Int,
                           visitsChange > 15 {
                            hasPositiveTrends = true
                        }
                        if let engagementData = rawData["engagement"] as? [String: Any],
                           let reachChange = engagementData["reachChange"] as? Int,
                           reachChange > 20 {
                            hasPositiveTrends = true
                        }
                        if let momentsData = rawData["moments"] as? [String: Any],
                           let momentsChange = momentsData["change"] as? Int,
                           momentsChange > 20 {
                            hasPositiveTrends = true
                        }

                        if !positiveInsights.isEmpty || hasPositiveTrends {
                            // Celebrar éxito con vibración de éxito (condicionamiento positivo)
                            HapticManager.shared.notification(.success)
                        } else if !negativeInsights.isEmpty {
                            // Consejo proactivo sobre tendencia negativa con vibración media
                            HapticManager.shared.mediumImpact()
                        } else {
                            // Respuesta normal con vibración ligera
                            HapticManager.shared.lightImpact()
                        }

                        Task {
                            await self.saveCurrentConversation()
                        }
                        return
                    } else {
                        activityData = weeklySummary.formattedSummary // Fallback
                    }

                case .activitySummary:
                    // Resumen general de actividad (usando datos crudos)
                    let summary = try await getActivitySummary(userId: userId)
                    if let jsonData = try? JSONSerialization.data(withJSONObject: summary.rawData, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        activityData = jsonString
                    } else {
                        activityData = summary.formattedSummary // Fallback
                    }
                }

                // Construir respuesta con contexto (para todos los casos excepto weeklySummary que ya tiene su propio flujo)
                if queryType != .weeklySummary {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    let memoryContext = userMemory?.contextString ?? ""
                    let displayName = userMemory?.preferredName ?? userData?.username ?? "Usuario"

                    let prompt = buildActivityResponsePrompt(
                        userInput: currentInput,
                        activityData: activityData,
                        memoryContext: memoryContext,
                        displayName: displayName,
                        lang: lang
                    )

                    let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                    let responseText = response.text ?? activityData

                    self.isLoading = false
                    self.responseText = responseText
                    self.conversationHistory.append(ChatMessage(text: responseText, isUser: false))

                    // 🔥 Feedback háptico
                    HapticManager.shared.notification(.success)

                    Task {
                        await self.saveCurrentConversation()
                    }
                }

            } catch {
                await handleSendMessageError(error)
            }
        }
    }

    // MARK: - 🔧 Helpers para consultas de actividad
    private func getLatestStoryChain(userId: String) async throws -> StoryChainInfo? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StoryChainInfo?, Error>) in
            activityService.getLatestStoryChain(userId: userId) { result in
                switch result {
                case .success(let chain):
                    continuation.resume(returning: chain)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getStoryChainViewersSummary(chainId: String, userId: String) async throws -> StoryChainViewersSummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StoryChainViewersSummary, Error>) in
            activityService.getStoryChainViewersSummary(chainId: chainId, userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getProfileVisitsSummary(userId: String) async throws -> ProfileVisitsSummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProfileVisitsSummary, Error>) in
            activityService.getProfileVisitsSummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getActivitySummary(userId: String) async throws -> NovaActivitySummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NovaActivitySummary, Error>) in
            activityService.getActivitySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getWeeklySummary(userId: String) async throws -> WeeklyActivitySummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WeeklyActivitySummary, Error>) in
            activityService.getWeeklySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func buildActivityResponsePrompt(userInput: String, activityData: String, memoryContext: String, displayName: String, lang: NovaLanguage, proactiveInsights: [ProactiveInsight]? = nil) -> String {
        let basePrompt = NovaPersona.getPersonalizedPrompt(
            userContext: "",
            memoryContext: memoryContext,
            personalization: userMemory
        )

        // Convertir insights proactivos a JSON si existen
        var insightsJSON = ""
        if let insights = proactiveInsights, !insights.isEmpty {
            let insightsData = insights.map { $0.rawData }
            if let jsonData = try? JSONSerialization.data(withJSONObject: insightsData, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                insightsJSON = "\n\nPROACTIVE INSIGHTS:\n\(jsonString)\n"
            }
        }

        switch lang {
        case .es:
            return """
            \(basePrompt)

            El usuario preguntó: "\(userInput)"

            DATOS DE ACTIVIDAD DE MOMENTS (JSON):
            \(activityData)
            \(insightsJSON)
            INSTRUCCIONES:
            - Los datos vienen en JSON crudo. Interprétalos y responde con lenguaje natural.
            - No repitas el JSON ni enumeres métricas si no aportan valor.
            - Sé clara, breve y útil por defecto.
            - Si hay insights importantes, intégralos de forma natural.
            - Si detectas tendencias negativas, ofrece 1 o 2 recomendaciones concretas.
            - Si detectas tendencias positivas, reconoce el buen momento sin sobreactuar.
            """
        case .en:
            return """
            \(basePrompt)

            The user asked: "\(userInput)"

            MOMENTS ACTIVITY DATA (JSON):
            \(activityData)
            \(insightsJSON)
            INSTRUCTIONS:
            - The data is raw JSON. Interpret it and answer in natural language.
            - Do not repeat the JSON or list metrics unless they genuinely help.
            - Be clear, brief, and useful by default.
            - If there are important insights, weave them in naturally.
            - If you detect negative trends, offer 1 or 2 concrete recommendations.
            - If you detect positive trends, acknowledge them without overplaying it.
            """
        case .ca:
            return """
            \(basePrompt)

            L'usuari ha preguntat: "\(userInput)"

            DADES D'ACTIVITAT DE MOMENTS (JSON):
            \(activityData)
            \(insightsJSON)
            INSTRUCCIONS:
            - Les dades venen en JSON cru. Interpreta-les i respon amb llenguatge natural.
            - No repeteixis el JSON ni enumeris mètriques si no aporten valor.
            - Sigues clara, breu i útil per defecte.
            - Si hi ha insights importants, integra'ls de manera natural.
            - Si detectes tendències negatives, ofereix 1 o 2 recomanacions concretes.
            - Si detectes tendències positives, reconeix-les sense exagerar.
            """
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es

        switch lang {
        case .es:
            if interval < 60 {
                return "hace un momento"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "hace \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "hace \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "hace \(days)d"
            }
        case .en:
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "\(minutes) min ago"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            } else {
                let days = Int(interval / 86400)
                return "\(days)d ago"
            }
        case .ca:
            if interval < 60 {
                return "fa un moment"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "fa \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "fa \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "fa \(days)d"
            }
        }
    }

    // MARK: - 🔧 MANTENER ESTA FUNCIÓN (no cambiar)
    private func generateTempConversationId() -> String {
        return "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Comandos Específicos Refactorizados (funciones privadas nuevas)

    private func handleCreateMomentCommand(userId: String) {
        let content = inputText.replacingOccurrences(of: "crea un momento con esta frase", with: "").trimmingCharacters(in: .whitespaces)

        guard !content.isEmpty else {
            responseText = "## ❌ Error\nPor favor, especifica el contenido del momento después del comando."
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        isLoading = true
        inputText = ""

        firestoreService.createMoment(userId: userId, content: content, mediaItems: []) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    switch lang {
                    case .es:
                        self.responseText = """
                        ## ❌ Error al Crear Momento

                        No pude crear el momento: \(error.localizedDescription)

                        **¿Te ayudo con algo más?**
                        """
                    case .en:
                        self.responseText = """
                        ## ❌ Error Creating Moment

                        I couldn't create the moment: \(error.localizedDescription)

                        **Want help with something else?**
                        """
                    case .ca:
                        self.responseText = """
                        ## ❌ Error en Crear Moment

                        No he pogut crear el moment: \(error.localizedDescription)

                        **Vols ajuda amb alguna altra cosa?**
                        """
                    }
                } else {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    switch lang {
                    case .es:
                        self.responseText = """
                        ## ✅ Momento Creado

                        **Contenido:** "\(content)"

                        Tu momento ha sido publicado exitosamente.

                        **¿Te gustaría:**
                        • Crear otro momento
                        • Ver consejos para contenido viral
                        • Optimizar tu perfil
                        """
                    case .en:
                        self.responseText = """
                        ## ✅ Moment Created

                        **Content:** "\(content)"

                        Your moment has been published successfully.

                        **Would you like to:**
                        • Create another moment
                        • See tips for viral content
                        • Optimize your profile
                        """
                    case .ca:
                        self.responseText = """
                        ## ✅ Moment Creat

                        **Contingut:** "\(content)"

                        El teu moment s'ha publicat correctament.

                        **T'agradaria:**
                        • Crear un altre moment
                        • Veure consells per a contingut viral
                        • Optimitzar el teu perfil
                        """
                    }
                }

                self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                await self.saveCurrentConversation()
                self.isLoading = false
            }
        }
    }

    private func handleConnectionSuggestionsCommand() {
        let langConn = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langConn {
        case .es:
            let recommendations = suggestedUsers.isEmpty ?
            "No tengo sugerencias específicas en este momento." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Sugerencias de Conexión

            **Usuarios recomendados:** \(recommendations)

            ## 💡 Tips para conectar mejor:
            • Revisa perfiles con intereses similares
            • Comenta en momentos que te interesen
            • Comparte contenido auténtico y personal

            **¿Te ayudo con estrategias específicas de networking?**
            """
        case .en:
            let recommendations = suggestedUsers.isEmpty ?
            "I don't have specific suggestions right now." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Connection Suggestions

            **Recommended users:** \(recommendations)

            ## 💡 Tips to connect better:
            • Check profiles with similar interests
            • Comment on moments you find interesting
            • Share authentic, personal content

            **Want specific networking strategies?**
            """
        case .ca:
            let recommendations = suggestedUsers.isEmpty ?
            "No tinc suggeriments específics en aquest moment." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Suggeriments de Connexió

            **Usuaris recomanats:** \(recommendations)

            ## 💡 Consells per connectar millor:
            • Revisa perfils amb interessos similars
            • Comenta en moments que t'interessin
            • Comparteix contingut autèntic i personal

            **Vols estratègies de networking específiques?**
            """
        }

        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }

    private func handleBioImprovementCommand(userId: String, userData: AppUser) {
        let currentBio = userData.bio ?? "Sin biografía"
        let userInterests = userData.interests.joined(separator: ", ")

        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let prompt: String
        switch lang {
        case .es:
            prompt = """
            Eres Nova, experta en perfiles de redes sociales.

            TAREA: Mejora esta biografía para que sea más atractiva y efectiva.

            BIO ACTUAL: "\(currentBio)"
            INTERESES: \(userInterests)
            NOMBRE: \(userData.username)

            REQUISITOS:
            - Máximo 150 caracteres
            - Incluye personalidad e intereses
            - Usa emojis estratégicamente (máximo 3)
            - Que sea memorable y auténtica
            - Optimizada para generar conexiones

            Responde SOLO con la nueva biografía, sin explicaciones adicionales.
            """
        case .en:
            prompt = """
            You are Nova, an expert in social media profiles.

            TASK: Improve this bio to make it more attractive and effective.

            CURRENT BIO: "\(currentBio)"
            INTERESTS: \(userInterests)
            NAME: \(userData.username)

            REQUIREMENTS:
            - Maximum 150 characters
            - Include personality and interests
            - Use emojis strategically (max 3)
            - Memorable and authentic
            - Optimized to generate connections

            Respond ONLY with the new bio, no additional explanations.
            """
        case .ca:
            prompt = """
            Ets Nova, experta en perfils de xarxes socials.

            TASCA: Millora aquesta biografia perquè sigui més atractiva i efectiva.

            BIO ACTUAL: "\(currentBio)"
            INTERESSOS: \(userInterests)
            NOM: \(userData.username)

            REQUISITS:
            - Màxim 150 caràcters
            - Inclou personalitat i interessos
            - Usa emojis estratègicament (màxim 3)
            - Que sigui memorable i autèntica
            - Optimitzada per generar connexions

            Respon NOMÉS amb la nova biografia, sense explicacions addicionals.
            """
        }

        isLoading = true
        inputText = ""

        Task {
            do {
                let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                if let newBio = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    self.firestoreService.updateBio(userId: userId, newBio: newBio) { error in
                        Task { @MainActor in

                            if let error = error {
                                    self.responseText = """
                                    ## ❌ Error al Actualizar

                                    No pude actualizar tu biografía: \(error.localizedDescription)

                                    **Bio sugerida:** "\(newBio)"

                                    ¿Quieres que lo intente de nuevo?
                                    """
                                } else {
                                    self.responseText = """
                                    ## ✅ Biografía Actualizada

                                    **Nueva bio:** "\(newBio)"

                                    ## 🚀 Próximos pasos:
                                    • Actualiza tu foto de perfil si es necesario
                                    • Revisa que tus intereses estén actualizados
                                    • Crea contenido que refleje tu nueva personalidad

                                    **¿Te ayudo con algo más para optimizar tu perfil?**
                                    """
                                    self.fetchUserData() // Actualizar datos
                                }

                                self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                                Task {
                                    await self.saveCurrentConversation()
                                }
                                self.isLoading = false
                            }
                        }
                }
            } catch {
                await MainActor.run {
                    self.responseText = """
                    ## ❌ Error de Generación

                    No pude generar una biografía mejorada en este momento.

                    **Consejos manuales:**
                    • Incluye tus pasiones principales
                    • Menciona qué te hace único
                    • Usa un tono auténtico y cercano
                    • Añade una llamada a la acción sutil

                    ¿Quieres intentar de nuevo o prefieres que te dé más consejos específicos?
                    """
                    self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                    Task {
                        await self.saveCurrentConversation()
                    }
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Nuevos Comandos Avanzados

    private func handleProfileAnalysisCommand(userData: AppUser) {
        let profileCompleteness = calculateProfileCompleteness(userData)

        let langProfile = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langProfile {
        case .es:
            responseText = """
            ## 📊 Análisis de tu Perfil

            **Completitud:** \(profileCompleteness)%

            ## 🎯 Fortalezas:
            \(getProfileStrengths(userData))

            ## 🔧 Áreas de mejora:
            \(getProfileImprovements(userData))

            ## 🚀 Recomendaciones personalizadas:
            \(getPersonalizedRecommendations(userData))

            **¿Te ayudo a implementar alguna de estas mejoras?**
            """
        case .en:
            responseText = """
            ## 📊 Your Profile Analysis

            **Completeness:** \(profileCompleteness)%

            ## 🎯 Strengths:
            \(getProfileStrengths(userData))

            ## 🔧 Areas for improvement:
            \(getProfileImprovements(userData))

            ## 🚀 Personalized recommendations:
            \(getPersonalizedRecommendations(userData))

            **Want help implementing any of these improvements?**
            """
        case .ca:
            responseText = """
            ## 📊 Anàlisi del teu Perfil

            **Completitud:** \(profileCompleteness)%

            ## 🎯 Fortaleses:
            \(getProfileStrengths(userData))

            ## 🔧 Àrees de millora:
            \(getProfileImprovements(userData))

            ## 🚀 Recomanacions personalitzades:
            \(getPersonalizedRecommendations(userData))

            **Vols ajuda per implementar alguna d'aquestes millores?**
            """
        }

        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }

    private func handleContentSuggestionsCommand(userData: AppUser) {
        let interests = userData.interests
        let suggestions = generateContentSuggestions(based: interests)

        let langContent = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langContent {
        case .es:
            responseText = """
            ## 🎨 Ideas de Contenido Personalizadas

            Basado en tus intereses: \(interests.prefix(3).joined(separator: ", "))

            ## 💡 Sugerencias para esta semana:
            \(suggestions)

            ## 📈 Tips para engagement:
            • Publica en horarios de mayor actividad (7-9 PM)
            • Usa preguntas para generar comentarios
            • Comparte historias personales auténticas
            • Incluye calls-to-action sutiles

            **¿Te ayudo a desarrollar alguna de estas ideas específicamente?**
            """
        case .en:
            responseText = """
            ## 🎨 Personalized Content Ideas

            Based on your interests: \(interests.prefix(3).joined(separator: ", "))

            ## 💡 Suggestions for this week:
            \(suggestions)

            ## 📈 Tips for engagement:
            • Post during peak hours (7-9 PM)
            • Use questions to spark comments
            • Share authentic personal stories
            • Include subtle calls-to-action

            **Want help developing any of these ideas specifically?**
            """
        case .ca:
            responseText = """
            ## 🎨 Idees de Contingut Personalitzades

            Basat en els teus interessos: \(interests.prefix(3).joined(separator: ", "))

            ## 💡 Suggeriments per a aquesta setmana:
            \(suggestions)

            ## 📈 Consells per a l'engagement:
            • Publica en hores de més activitat (7-9 PM)
            • Usa preguntes per generar comentaris
            • Comparteix històries personals autèntiques
            • Inclou crides a l'acció subtils

            **Vols ajuda per desenvolupar alguna d'aquestes idees en concret?**
            """
        }

        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }

    // MARK: - Nuevas Funciones Auxiliares

    func detectUserIntent(_ input: String) -> NovaMode {
        let lowercased = input.lowercased()

        if lowercased.contains("crear") || lowercased.contains("idea") || lowercased.contains("creativo") {
            return .creativity
        } else if lowercased.contains("productiv") || lowercased.contains("organiz") || lowercased.contains("tiempo") {
            return .productivity
        } else if lowercased.contains("social") || lowercased.contains("amigos") || lowercased.contains("conectar") {
            return .social
        } else if lowercased.contains("bienestar") || lowercased.contains("salud") || lowercased.contains("estrés") {
            return .wellness
        }

        return .general
    }

    private func buildEnhancedContext() -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        guard let userData = userData else {
            switch lang {
            case .es: return "Usuario sin datos específicos"
            case .en: return "User without specific data"
            case .ca: return "Usuari sense dades específiques"
            }
        }

        let labels: (profileHeader: String, username: String, interests: String, bio: String, connections: String, visits: String, mutualsHeader: String, noMutuals: String, visitorsHeader: String, noVisitors: String, activityHeader: String, moments: String, lastActivity: String, convoHeader: String, messages: String, lastInteraction: String, reminderHeader: String, reminder1: String, reminder2: String, reminder3: String, notAvailable: String, convoStart: String)
        switch lang {
        case .es:
            labels = ("PERFIL DEL USUARIO ACTUAL:", "- Nombre de usuario en la app:", "- Intereses del usuario:", "- Bio del usuario:", "- Conexiones del usuario:", "- Visitas al perfil:", "CONEXIONES MUTUAS:", "No hay conexiones mutuas", "VISITANTES DEL PERFIL:", "No hay visitas registradas", "ACTIVIDAD DEL USUARIO:", "- Momentos publicados:", "- Última actividad:", "CONTEXTO DE ESTA CONVERSACIÓN:", "- Mensajes en la sesión:", "- Última interacción:", "RECORDATORIO CRÍTICO PARA NOVA:", "- El usuario \"\(userData.username)\" es la persona con la que estás hablando", "- Usa el nombre preferido si lo conoces", "- No confundas identidad de usuario con información de la app", "No disponible", "Inicio de conversación")
        case .en:
            labels = ("CURRENT USER PROFILE:", "- App username:", "- User interests:", "- User bio:", "- User connections:", "- Profile visits:", "MUTUAL CONNECTIONS:", "No mutual connections", "PROFILE VISITORS:", "No recorded visits", "USER ACTIVITY:", "- Moments posted:", "- Last activity:", "CONTEXT OF THIS CONVERSATION:", "- Messages in session:", "- Last interaction:", "CRITICAL REMINDER FOR NOVA:", "- The user \"\(userData.username)\" is the person you're talking to", "- Use the preferred display name if you know it", "- Do not confuse user identity with app information", "Not available", "Conversation start")
        case .ca:
            labels = ("PERFIL DE L'USUARI ACTUAL:", "- Nom d'usuari a l'app:", "- Interessos de l'usuari:", "- Bio de l'usuari:", "- Connexions de l'usuari:", "- Visites al perfil:", "CONNEXIONS MÚTUES:", "No hi ha connexions mútues", "VISITANTS DEL PERFIL:", "No hi ha visites registrades", "ACTIVITAT DE L'USUARI:", "- Moments publicats:", "- Última activitat:", "CONTEXT D'AQUESTA CONVERSA:", "- Missatges a la sessió:", "- Última interacció:", "RECORDATORI CRÍTIC PER A NOVA:", "- L'usuari \"\(userData.username)\" és la persona amb qui estàs parlant", "- Fes servir el nom preferit si el coneixes", "- No confonguis la identitat de l'usuari amb la informació de l'app", "No disponible", "Inici de conversa")
        }

        var context = """
        \(labels.profileHeader)
        \(labels.username) \(userData.username)
        \(labels.interests) \(userData.interests.joined(separator: ", "))
        \(labels.bio) \(userData.bio ?? labels.notAvailable)
        \(labels.connections) \(mutualConnections.count)
        \(labels.visits) \(profileVisits.count)

        \(labels.mutualsHeader)
        \(mutualConnections.isEmpty ? labels.noMutuals : mutualConnections.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))

        \(labels.visitorsHeader)
        \(profileVisits.isEmpty ? labels.noVisitors : profileVisits.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))

        \(labels.activityHeader)
        \(labels.moments) \(recentMoments.count)
        \(labels.lastActivity) \(recentMoments.first?.timestamp.timeAgoDisplay() ?? labels.notAvailable)

        \(labels.convoHeader)
        \(labels.messages) \(conversationHistory.count)
        \(labels.lastInteraction) \(conversationHistory.last?.timestamp.timeAgoDisplay() ?? labels.convoStart)

        \(labels.reminderHeader)
        \(labels.reminder1)
        \(labels.reminder2)
        \(labels.reminder3)
        """

        // Integrar memoria silenciosamente
        if let userMemory = userMemory, !userMemory.isEmpty {
            context += "\n\n" + userMemory.contextString
            switch lang {
            case .es: context += "\n\nIMPORTANTE: Usa esta información naturalmente, sin mencionar que la 'recuerdas'."
            case .en: context += "\n\nIMPORTANT: Use this information naturally, without mentioning that you 'remember' it."
            case .ca: context += "\n\nIMPORTANT: Fes servir aquesta informació de manera natural, sense esmentar que la 'recordes'."
            }
        }

        return context
    }

    private func enhanceResponseFormat(_ response: String, for mode: NovaMode) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { result, line in
                if line.isEmpty {
                    if result.last != "" {
                        result.append("")
                    }
                } else {
                    result.append(line)
                }
            }

        return normalizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addStructureToLongResponse(_ response: String) -> String {
        return response
    }

    private func titleForDetectedMode(_ mode: NovaMode) -> String {
        switch mode {
        case .creativity: return "Creatividad"
        case .productivity: return "Productividad"
        case .social: return "Social"
        case .wellness: return "Bienestar"
        case .general: return "General"
        }
    }

    private func getCurrentTimeContext() -> String {
        let now = Date()
        let calendar = Calendar.current

        // 🕐 Hora del día
        let hour = calendar.component(.hour, from: now)
        let timeOfDay: String
        switch hour {
        case 6..<12: timeOfDay = "Mañana"
        case 12..<18: timeOfDay = "Tarde"
        case 18..<22: timeOfDay = "Noche"
        default: timeOfDay = "Madrugada"
        }

        // 📅 Día del mes
        let day = calendar.component(.day, from: now)

        // 🌸 Mes
        let month = calendar.component(.month, from: now)
        let monthName = getMonthName(month)

        // 📅 Año
        let year = calendar.component(.year, from: now)

        // 🌟 Día de la semana
        let weekday = calendar.component(.weekday, from: now)
        let weekdayName = getWeekdayName(weekday)

        // 🌞 Estación
        let season = getSeason(month: month, day: day)

        return "\(timeOfDay) del \(weekdayName) \(day) de \(monthName) de \(year) (\(season))"
    }

    // 🌸 Obtener nombre del mes
    private func getMonthName(_ month: Int) -> String {
        let months = [
            1: "Enero", 2: "Febrero", 3: "Marzo", 4: "Abril",
            5: "Mayo", 6: "Junio", 7: "Julio", 8: "Agosto",
            9: "Septiembre", 10: "Octubre", 11: "Noviembre", 12: "Diciembre"
        ]
        return months[month] ?? "Mes"
    }

    // 🌟 Obtener nombre del día de la semana
    private func getWeekdayName(_ weekday: Int) -> String {
        let weekdays = [
            1: "Domingo", 2: "Lunes", 3: "Martes", 4: "Miércoles",
            5: "Jueves", 6: "Viernes", 7: "Sábado"
        ]
        return weekdays[weekday] ?? "Día"
    }

    // 🌞 Obtener estación del año (CORREGIDO CON FECHAS EXACTAS)
    private func getSeason(month: Int, day: Int) -> String {
        // ✅ LÓGICA CORRECTA: Fechas exactas de cambio de estaciones
        switch month {
        case 12: // Diciembre
            return day >= 21 ? "Invierno" : "Otoño"
        case 1, 2: // Enero y Febrero
            return "Invierno"
        case 3: // Marzo
            return day >= 20 ? "Primavera" : "Invierno"
        case 4, 5: // Abril y Mayo
            return "Primavera"
        case 6: // Junio
            return day >= 21 ? "Verano" : "Primavera"
        case 7, 8: // Julio y Agosto
            return "Verano"
        case 9: // Septiembre
            return day >= 23 ? "Otoño" : "Verano"
        case 10, 11: // Octubre y Noviembre
            return "Otoño"
        default:
            return "Estación"
        }
    }

    private func calculateProfileCompleteness(_ userData: AppUser) -> Int {
        var completeness = 0

        if !userData.username.isEmpty { completeness += 20 }
        if let bio = userData.bio, !bio.isEmpty { completeness += 25 }
        if !userData.interests.isEmpty { completeness += 25 }
        if recentMoments.count > 0 { completeness += 15 }
        if mutualConnections.count > 0 { completeness += 15 }

        return completeness
    }

    private func getProfileStrengths(_ userData: AppUser) -> String {
        var strengths: [String] = []

        if !userData.interests.isEmpty {
            strengths.append("• Tienes intereses definidos (\(userData.interests.count) temas)")
        }
        if let bio = userData.bio, !bio.isEmpty {
            strengths.append("• Biografía personalizada")
        }
        if recentMoments.count > 2 {
            strengths.append("• Actividad constante con \(recentMoments.count) momentos recientes")
        }
        if mutualConnections.count > 5 {
            strengths.append("• Buena red de conexiones (\(mutualConnections.count) contactos)")
        }

        return strengths.isEmpty ? "• Perfil en construcción - ¡gran potencial!" : strengths.joined(separator: "\n")
    }

    private func getProfileImprovements(_ userData: AppUser) -> String {
        var improvements: [String] = []

        if userData.interests.count < 3 {
            improvements.append("• Añadir más intereses para mejores conexiones")
        }
        if userData.bio?.isEmpty ?? true {
            improvements.append("• Crear una biografía atractiva")
        }
        if recentMoments.count < 3 {
            improvements.append("• Publicar más momentos para mayor visibilidad")
        }
        if mutualConnections.count < 5 {
            improvements.append("• Expandir tu red de conexiones")
        }

        return improvements.isEmpty ? "• ¡Tu perfil está muy completo!" : improvements.joined(separator: "\n")
    }

    private func getPersonalizedRecommendations(_ userData: AppUser) -> String {
        var recommendations: [String] = []

        if userData.interests.contains("tecnología") {
            recommendations.append("• Comparte tus proyectos tech y herramientas favoritas")
        }
        if userData.interests.contains("deporte") {
            recommendations.append("• Documenta tus rutinas y logros deportivos")
        }
        if userData.interests.contains("arte") {
            recommendations.append("• Muestra tu proceso creativo y obras")
        }

        // Recomendaciones generales
        recommendations.append("• Interactúa más con usuarios de intereses similares")
        recommendations.append("• Publica contenido que genere conversación")

        return recommendations.joined(separator: "\n")
    }

    private func generateContentSuggestions(based interests: [String]) -> String {
        var suggestions: [String] = []

        // Sugerencias basadas en intereses
        for interest in interests.prefix(2) {
            switch interest.lowercased() {
            case "tecnología":
                suggestions.append("• \"Mi app favorita esta semana y por qué\"")
                suggestions.append("• \"Predicción tech que me emociona para este año\"")
            case "deporte":
                suggestions.append("• \"Mi rutina de ejercicio favorita explicada\"")
                suggestions.append("• \"El momento que me motivó a mantenerme activo\"")
            case "arte":
                suggestions.append("• \"Proceso detrás de mi creación más reciente\"")
                suggestions.append("• \"Artista que me inspira y por qué\"")
            case "música":
                suggestions.append("• \"Canción que define mi estado de ánimo hoy\"")
                suggestions.append("• \"Mi descubrimiento musical de la semana\"")
            default:
                suggestions.append("• \"Lo que más me gusta de \(interest) y por qué\"")
                suggestions.append("• \"Consejo sobre \(interest) que me hubiera gustado saber antes\"")
            }
        }

        // Sugerencias generales
        suggestions.append("• \"Una lección importante que aprendí recientemente\"")
        suggestions.append("• \"Pregunta abierta sobre un tema que te apasiona\"")

        return suggestions.joined(separator: "\n")
    }
}

// MARK: - ✅ EXTENSIONES SIMPLIFICADAS
extension GeminiViewModel {
    var hasMemoryItems: Bool {
        guard let memory = userMemory else { return false }
        return !memory.facts.isEmpty
    }

    func clearMemoryContext() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        userMemory = NovaMemory(userId: userId)

        // Cancelar cualquier procesamiento pendiente
        memoryProcessingTimer?.invalidate()
        lastMemoryProcessTime = nil
    }

    // 🎯 NUEVA: Manejar comandos de personalización
    private func handlePersonalizationCommand(_ command: PersonalizationCommand, userId: String) {
        LogConfig.log("🎭 Procesando comando de personalización: \(command.description)", category: "Personalization")

        switch command {
        case .setPreferredName(let name):
            let nameFact = NovaFact(
                content: "Prefiere que le llamen \(name)",
                type: .preference,
                importance: 5
            )

            if let currentMemory = userMemory {
                let updatedMemory = currentMemory.addingFacts([nameFact])
                userMemory = updatedMemory

                memoryService.saveMemory(updatedMemory) { result in
                    switch result {
                    case .success:
                        LogConfig.log("✅ Nombre preferido guardado: \(name)", category: "Personalization")
                    case .failure(let error):
                        LogConfig.log("❌ Error guardando nombre: \(error.localizedDescription)", category: "Personalization")
                    }
                }
            }

            responseText = "¡Perfecto! A partir de ahora te llamaré \(name) 😊"

        case .setCommunicationStyle(let style):
            let styleFact = NovaFact(
                content: "Prefiere comunicación \(style.description.lowercased())",
                type: .preference,
                importance: 4
            )

            if let currentMemory = userMemory {
                let updatedMemory = currentMemory.addingFacts([styleFact])
                userMemory = updatedMemory

                memoryService.saveMemory(updatedMemory) { _ in }
            }

            let userName = userMemory?.preferredName ?? userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
            switch style {
            case .formal:
                responseText = "Entendido, \(userName). A partir de ahora mantendré una comunicación más formal."
            case .casual:
                responseText = "¡Vale \(userName)! Seré más casual y relajada contigo 😊"
            case .fun:
                responseText = "¡Genial \(userName)! 🎉 Seré más divertida y usaré más humor contigo"
            case .unknown:
                responseText = "Perfecto \(userName), he notado tu preferencia."
            }
        case .setLanguage(let lang):
            NovaLanguageService.setPreferredLanguage(lang)
            responseText = {
                switch lang {
                case .es: return "Listo. A partir de ahora te hablaré en Español."
                case .en: return "Done. I will speak in English from now on."
                case .ca: return "Fet. A partir d'ara et parlaré en Català."
                }
            }()
        }

        let userMessage = ChatMessage(text: inputText, isUser: true)
        conversationHistory.append(userMessage)
        conversationHistory.append(ChatMessage(text: responseText, isUser: false))

        inputText = ""
        Task {
            await saveCurrentConversation()
        }
    }
}
