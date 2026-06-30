import Foundation
import SwiftData
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ✅ Servicio de persistencia local con SwiftData
// Patrón LOCAL-FIRST: Siempre lee del caché local, luego sincroniza con Firestore en background.

@MainActor
final class LocalPersistenceService: ObservableObject {
    static let shared = LocalPersistenceService()

    static let appGroupID = "group.com.glowsyapp"
    private static let storeFileName = "MomentsLocalCache.store"
    private static let didMigrateStoreKey = "didMigrateSwiftDataToAppGroup"
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    // MARK: - Configuración
    private let maxFeedMoments = 100      // Máximo moments del feed en caché
    private let maxExploreMoments = 50    // Máximo moments del explorar en caché
    private let maxCachedUsers = 200      // Máximo usuarios en caché
    private let maxDataAgeDays = 7        // Datos más viejos se limpian
    private let maxConversations = 50     // Máximo conversaciones en caché
    private let maxMessagesPerChat = 200  // Máximo mensajes por chat en caché (disco)
    
    // MARK: - Init
    init() {
        setupContainer()
    }
    
    private func setupContainer() {
        let schema = Schema([
            CachedMoment.self,
            CachedUser.self,
            CachedStory.self,
            CachedConversation.self,
            CachedMessage.self,
            CachedNotification.self,
            CachedConnection.self,
            CachedSearch.self,
            CachedAction.self,
            UserAffinity.self
        ])

        migrateLegacyStoreToAppGroupIfNeeded()
        let storeURL = Self.appGroupStoreURL() ?? Self.defaultStoreURL()

        let config = ModelConfiguration(
            Self.storeFileName,
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
            AppLog.debug("✅ LocalPersistence: SwiftData inicializado correctamente")
        } catch {
            AppLog.debug("⚠️ LocalPersistence: Error de migración, reintentando con reset: \(error)")
            // FALLBACK: Si hay un error de migración (NSCocoaErrorDomain 134110), borrar el cache y reintentar
            resetAndRetry(schema: schema, config: config)
        }
    }

    private static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(storeFileName)
    }

    private static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent(storeFileName)
    }

    private static func legacyDefaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("default.store")
    }

    private func migrateLegacyStoreToAppGroupIfNeeded() {
        let sharedDefaults = UserDefaults(suiteName: Self.appGroupID)
        guard sharedDefaults?.bool(forKey: Self.didMigrateStoreKey) != true else { return }
        guard let destination = Self.appGroupStoreURL() else { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let candidates = [
            Self.defaultStoreURL(),
            Self.legacyDefaultStoreURL(),
            appSupport.appendingPathComponent("MomentsLocalCache.store")
        ]

        for source in candidates where FileManager.default.fileExists(atPath: source.path) {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: source, to: destination)
                for suffix in ["shm", "wal"] {
                    let sidecar = source.appendingPathExtension(suffix)
                    if FileManager.default.fileExists(atPath: sidecar.path) {
                        try? FileManager.default.copyItem(
                            at: sidecar,
                            to: destination.appendingPathExtension(suffix)
                        )
                    }
                }
                sharedDefaults?.set(true, forKey: Self.didMigrateStoreKey)
                AppLog.debug("✅ LocalPersistence: SwiftData migrado al App Group")
                return
            } catch {
                AppLog.debug("⚠️ LocalPersistence: Fallo migrando store al App Group: \(error)")
            }
        }

        sharedDefaults?.set(true, forKey: Self.didMigrateStoreKey)
    }
    
    private func resetAndRetry(schema: Schema, config: ModelConfiguration) {
        do {
            // 1. Borrar archivo SQLite
            if let storeURL = config.url.absoluteString.hasPrefix("file") ? config.url : nil {
                try FileManager.default.removeItem(at: storeURL)
                // También borrar archivos -shm y -wal
                let shmURL = storeURL.appendingPathExtension("shm")
                let walURL = storeURL.appendingPathExtension("wal")
                try? FileManager.default.removeItem(at: shmURL)
                try? FileManager.default.removeItem(at: walURL)
                AppLog.debug("🧹 LocalPersistence: Archivos de cache borrados para recuperación")
            }
            
            // 2. Reintentar inicializar
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
            AppLog.debug("✅ LocalPersistence: SwiftData recuperado tras reset")
        } catch {
            AppLog.debug("❌ LocalPersistence: Error fatal recreando SwiftData: \(error)")
        }
    }
    
    /// Obtiene el ModelContainer para inyectar en el entorno de SwiftUI
    var container: ModelContainer? {
        return modelContainer
    }
    
    // MARK: - 📝 MOMENTS: Save & Load
    
    /// Guarda un array de Moments del feed en el caché local
    func saveFeedMoments(_ moments: [Moment], sync: Bool = false) {
        guard let context = modelContext else { return }
        
        let section = "feed"
        
        // ✅ SYNC: Si es sincronización completa, borrar lo anterior de esta sección
        if sync {
            let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
            try? context.delete(model: CachedMoment.self, where: predicate)
        }
        
        let momentIds = moments.compactMap { $0.id }
        let predicate = #Predicate<CachedMoment> { momentIds.contains($0.momentId) && $0.feedSection == section }
        let descriptor = FetchDescriptor<CachedMoment>(predicate: predicate)
        let existingMoments = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingMoments.map { ($0.momentId, $0) })
        
        for moment in moments {
            let cached = CachedMoment.from(moment, section: section)
            
            if let existing = existingMap[cached.momentId] {
                updateCachedMoment(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
        trimFeedMoments()
    }
    
    /// Guarda moments del Explorar en el caché local
    func saveExploreMoments(_ moments: [Moment], sync: Bool = false) {
        guard let context = modelContext else { return }
        
        let section = "explore"
        
        // ✅ SYNC: Borrar lo anterior de esta sección
        if sync {
            let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
            try? context.delete(model: CachedMoment.self, where: predicate)
        }
        
        let momentIds = moments.compactMap { $0.id }
        let predicate = #Predicate<CachedMoment> { momentIds.contains($0.momentId) && $0.feedSection == section }
        let descriptor = FetchDescriptor<CachedMoment>(predicate: predicate)
        let existingMoments = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingMoments.map { ($0.momentId, $0) })
        
        for moment in moments {
            let cached = CachedMoment.from(moment, section: section)
            
            if let existing = existingMap[cached.momentId] {
                updateCachedMoment(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
        trimExploreMoments()
    }
    
    /// Guarda moments del perfil de un usuario
    func saveProfileMoments(_ moments: [Moment], userId: String, sync: Bool = true) {
        guard let context = modelContext else { return }
        
        let section = "profile_\(userId)"
        
        // ✅ SYNC: Borrar lo anterior de este perfil (por defecto true para perfiles)
        if sync {
            let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
            try? context.delete(model: CachedMoment.self, where: predicate)
        }
        
        let momentIds = moments.compactMap { $0.id }
        let predicate = #Predicate<CachedMoment> { momentIds.contains($0.momentId) && $0.feedSection == section }
        let descriptor = FetchDescriptor<CachedMoment>(predicate: predicate)
        let existingMoments = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingMoments.map { ($0.momentId, $0) })
        
        for moment in moments {
            let cached = CachedMoment.from(moment, section: section)
            
            if let existing = existingMap[cached.momentId] {
                updateCachedMoment(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
    }
    
    /// Carga moments del feed desde el caché local
    func loadFeedMoments() -> [Moment] {
        guard let context = modelContext else { return [] }
        
        let section = "feed"
        let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
        var descriptor = FetchDescriptor<CachedMoment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = maxFeedMoments
        
        do {
            let cached = try context.fetch(descriptor)
            return cached.compactMap { $0.toMoment() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar feed: \(error)")
            return []
        }
    }
    
    /// Carga moments del Explorar desde el caché local
    func loadExploreMoments() -> [Moment] {
        guard let context = modelContext else { return [] }
        
        let section = "explore"
        let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
        var descriptor = FetchDescriptor<CachedMoment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = maxExploreMoments
        
        do {
            let cached = try context.fetch(descriptor)
            return cached.compactMap { $0.toMoment() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar explore: \(error)")
            return []
        }
    }
    
    /// Carga moments del perfil de un usuario
    func loadProfileMoments(userId: String) -> [Moment] {
        guard let context = modelContext else { return [] }
        
        let section = "profile_\(userId)"
        let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
        var descriptor = FetchDescriptor<CachedMoment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        
        do {
            let cached = try context.fetch(descriptor)
            return cached.compactMap { $0.toMoment() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar perfil: \(error)")
            return []
        }
    }
    
    // MARK: - 👤 USERS: Save & Load
    
    /// Guarda un usuario en el caché local
    func saveUser(_ user: AppUser, section: String = "profile") {
        guard let context = modelContext else { return }
        
        let cached = CachedUser.from(user, section: section)
        
        let userId = cached.userId
        let predicate = #Predicate<CachedUser> { $0.userId == userId }
        let descriptor = FetchDescriptor<CachedUser>(predicate: predicate)
        
        if let existing = try? context.fetch(descriptor).first {
            updateCachedUser(existing, from: cached)
        } else {
            context.insert(cached)
        }
        
        saveContext()
    }
    
    /// Guarda el usuario actual (currentUser) con prioridad
    func saveCurrentUser(_ user: AppUser) {
        saveUser(user, section: "currentUser")
    }
    
    /// Carga un usuario del caché local
    func loadUser(userId: String) -> AppUser? {
        guard let context = modelContext else { return nil }
        
        let predicate = #Predicate<CachedUser> { $0.userId == userId }
        let descriptor = FetchDescriptor<CachedUser>(predicate: predicate)
        
        do {
            if let cached = try context.fetch(descriptor).first {
                return cached.toAppUser()
            }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar usuario: \(error)")
        }
        
        return nil
    }
    
    /// Carga el usuario actual del caché
    func loadCurrentUser() -> AppUser? {
        guard let context = modelContext else { return nil }
        
        let section = "currentUser"
        let predicate = #Predicate<CachedUser> { $0.cacheSection == section }
        let descriptor = FetchDescriptor<CachedUser>(predicate: predicate)
        
        do {
            if let cached = try context.fetch(descriptor).first {
                return cached.toAppUser()
            }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar usuario actual: \(error)")
        }
        
        return nil
    }
    
    // MARK: - STORIES
    
    func saveStories(_ stories: [Story], sync: Bool = false) {
        guard let context = modelContext else { return }
        
        // ✅ SYNC: Si es sincronización completa, borrar todo lo anterior
        if sync {
            try? context.delete(model: CachedStory.self)
        }
        
        // Batch fetch existing stories to avoid duplicates
        let storyIds = stories.compactMap { $0.id }
        let predicate = #Predicate<CachedStory> { storyIds.contains($0.id) }
        let descriptor = FetchDescriptor<CachedStory>(predicate: predicate)
        let existingStories = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingStories.map { ($0.id, $0) })
        
        for story in stories {
            if let cached = CachedStory.fromStory(story) {
                if let existing = existingMap[story.id ?? ""] {
                    // Update existing story if needed (though stories are mostly static)
                    context.delete(existing)
                }
                context.insert(cached)
            }
        }
        saveContext()
    }
    
    /// Borra una historia específica de forma global por su ID
    func deleteStory(storyId: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedStory> { $0.id == storyId }
        try? context.delete(model: CachedStory.self, where: predicate)
        saveContext()
    }
    
    /// Borra todas las historias de un usuario específico del caché
    func deleteStories(for userId: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedStory> { $0.authorId == userId }
        try? context.delete(model: CachedStory.self, where: predicate)
        saveContext()
    }
    
    func loadStories(userId: String) -> [Story] {
        guard let context = modelContext else { return [] }
        
        let predicate = #Predicate<CachedStory> { $0.authorId == userId }
        let descriptor = FetchDescriptor<CachedStory>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        
        do {
            let cachedStories = try context.fetch(descriptor)
            // Filtrar las que ya expiraron localmente por si acaso
            let now = Date()
            return cachedStories.filter { $0.expirationDate > now }.map { $0.toStory() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar historias: \(error)")
            return []
        }
    }
    
    func cleanupOldStories() {
        guard let context = modelContext else { return }
        
        let now = Date()
        let predicate = #Predicate<CachedStory> { $0.expirationDate < now }
        
        do {
            try context.delete(model: CachedStory.self, where: predicate)
            saveContext()
        } catch {
            AppLog.debug("❌ LocalPersistence: Error limpiando historias antiguas: \(error)")
        }
    }

    // MARK: - 💬 MESSAGING: Save & Load
    
    /// Guarda una lista de conversaciones en el caché local
    func saveConversations(_ conversations: [Conversation], sync: Bool = false) {
        guard let context = modelContext else { return }
        
        // ✅ SYNC: Borrar conversaciones antiguas si es sync completo
        if sync {
            try? context.delete(model: CachedConversation.self)
        }
        
        let conversationIds = conversations.compactMap { $0.id }
        let predicate = #Predicate<CachedConversation> { conversationIds.contains($0.id) }
        let descriptor = FetchDescriptor<CachedConversation>(predicate: predicate)
        let existingConversations = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingConversations.map { ($0.id, $0) })
        
        for conversation in conversations {
            guard let conversationId = conversation.id else { continue }
            
            let cached = CachedConversation.from(conversation)
            
            if let existing = existingMap[conversationId] {
                updateCachedConversation(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
        trimConversations()
    }
    
    /// Carga la lista de conversaciones desde el caché local
    func loadConversations() -> [Conversation] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<CachedConversation>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let cached = try context.fetch(descriptor)
            // ✅ Sort by isPinned in memory since Foundation's SortDescriptor for Bool 
            // often requires NSObject inheritance which conflicts with SwiftData macros.
            return cached
                .sorted { ($0.isPinned ? 1 : 0) > ($1.isPinned ? 1 : 0) }
                .map { $0.toConversation() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar conversaciones: \(error)")
            return []
        }
    }
    
    func markMessageDeletedForEveryone(conversationId: String, messageId: String) {
        guard let context = modelContext else { return }

        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        var descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let existing = (try? context.fetch(descriptor))?.first else { return }

        existing.isDeleted = true
        existing.deletedAt = Date()
        existing.content = nil
        existing.mediaUrl = nil
        existing.thumbnailUrl = nil
        existing.mediaObjectPath = nil
        existing.thumbnailObjectPath = nil
        existing.mediaEncryptionData = nil
        existing.thumbnailEncryptionData = nil
        existing.lastSyncedAt = Date()

        saveContext()
        ChatCacheStore.deleteMessageFiles(conversationId: conversationId, messageId: messageId)
    }

    func removeCachedMessage(conversationId: String, messageId: String) {
        guard let context = modelContext else { return }

        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        var descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let existing = (try? context.fetch(descriptor))?.first else { return }
        context.delete(existing)
        saveContext()
    }

    /// Guarda mensajes de una conversación en el caché local
    func saveMessages(_ messages: [EnhancedMessage], conversationId: String, sync: Bool = false) {
        guard let context = modelContext else { return }
        
        // ✅ SYNC: Si es sincronización completa, borrar lo anterior de esta conversación
        if sync {
            let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
            try? context.delete(model: CachedMessage.self, where: predicate)
        }
        
        let messageIds = messages.map { $0.id }
        let predicate = #Predicate<CachedMessage> { messageIds.contains($0.id) }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        let existingMessages = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingMessages.map { ($0.id, $0) })
        let messagesToSave = warmDiskMediaURLs(in: messages)
        
        for message in messagesToSave {
            let cached = CachedMessage.from(message)
            
            if let existing = existingMap[message.id] {
                updateCachedMessage(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
        trimMessages(for: conversationId)
    }

    /// Añade mensajes antiguos (paginación) sin borrar el caché existente.
    func appendMessages(_ messages: [EnhancedMessage], conversationId: String) {
        guard !messages.isEmpty else { return }
        saveMessages(messages, conversationId: conversationId, sync: false)
    }

    /// Reconciles a known remote window while preserving older cached history outside that window.
    func reconcileMessages(_ messages: [EnhancedMessage], conversationId: String) {
        guard let context = modelContext else { return }
        saveMessages(messages, conversationId: conversationId, sync: false)
        guard let oldestRemoteTimestamp = messages.map(\.timestamp).min() else { return }

        let remoteIds = Set(messages.map(\.id))
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.timestamp >= oldestRemoteTimestamp
        }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        let cachedWindow = (try? context.fetch(descriptor)) ?? []

        for cached in cachedWindow where !remoteIds.contains(cached.id) {
            context.delete(cached)
        }

        saveContext()
        trimMessages(for: conversationId)
    }
    
    func messageExists(conversationId: String, messageId: String) -> Bool {
        guard let context = modelContext else { return false }

        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        var descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        descriptor.fetchLimit = 1

        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    func lastMessageTimestamp(for conversationId: String) -> Date? {
        lastMessageSyncCursor(for: conversationId)?.timestamp
    }

    func lastMessageSyncCursor(for conversationId: String) -> MessageSyncCursor? {
        guard let context = modelContext else { return nil }

        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1

        guard let message = (try? context.fetch(descriptor))?.first else { return nil }
        return MessageSyncCursor(timestamp: message.timestamp, messageId: message.id)
    }

    func upsertConversationPreview(from message: EnhancedMessage) {
        guard let context = modelContext else { return }

        let conversationId = message.conversationId
        let predicate = #Predicate<CachedConversation> { $0.id == conversationId }
        let descriptor = FetchDescriptor<CachedConversation>(predicate: predicate)
        let existing = (try? context.fetch(descriptor))?.first

        if let existing {
            existing.lastMessage = message.preview
            existing.timestamp = message.timestamp
            existing.lastSyncedAt = Date()

            if let currentUserId = Auth.auth().currentUser?.uid,
               message.senderId != currentUserId {
                var readStatus = (try? JSONDecoder().decode([String: Bool].self, from: existing.readStatusData ?? Data()))
                    ?? [:]
                readStatus[currentUserId] = false
                existing.readStatusData = try? JSONEncoder().encode(readStatus)
            }
        } else {
            let currentUserId = Auth.auth().currentUser?.uid ?? ""
            var readStatus: [String: Bool] = [:]
            if !currentUserId.isEmpty {
                readStatus[currentUserId] = message.senderId == currentUserId
            }

            let cached = CachedConversation(
                id: conversationId,
                participants: [],
                lastMessage: message.preview,
                timestamp: message.timestamp,
                readStatusData: try? JSONEncoder().encode(readStatus),
                otherParticipantId: message.senderId == currentUserId ? "" : message.senderId,
                otherParticipantUsername: nil,
                otherParticipantProfileImagePath: nil,
                isPinned: false,
                isMuted: false,
                isArchived: false,
                lastSyncedAt: Date()
            )
            context.insert(cached)
        }

        saveContext()
        trimConversations()
    }

    /// Carga rápida sin I/O de disco por mensaje (local-first: warm/ingest/listeners).
    func loadMessagesFast(conversationId: String) -> [EnhancedMessage] {
        guard let context = modelContext else { return [] }

        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            let cached = try context.fetch(descriptor)
            return cached.map { $0.toEnhancedMessage() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar mensajes (fast): \(error)")
            return []
        }
    }

    /// Últimos N mensajes desde SwiftData (sin cargar todo el historial en RAM).
    func loadRecentMessagesFast(
        conversationId: String,
        limit: Int,
        cutoffDate: Date? = nil
    ) -> [EnhancedMessage] {
        guard limit > 0, let context = modelContext else { return [] }

        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        guard var cached = try? context.fetch(descriptor) else { return [] }
        if let cutoffDate {
            cached = cached.filter { $0.timestamp > cutoffDate }
        }
        return cached.reversed().map { $0.toEnhancedMessage() }
    }

    /// Página de mensajes estrictamente anteriores al cursor (paginación lazy desde disco).
    func loadMessagesBefore(
        conversationId: String,
        cursor: MessageSyncCursor,
        cutoffDate: Date? = nil,
        limit: Int
    ) -> [EnhancedMessage] {
        guard limit > 0, let context = modelContext else { return [] }

        let cutoff = cutoffDate
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId
                && (cutoff == nil || $0.timestamp > cutoff!)
                && (
                    $0.timestamp < cursor.timestamp
                        || ($0.timestamp == cursor.timestamp && $0.id < cursor.messageId)
                )
        }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        guard let cached = try? context.fetch(descriptor) else { return [] }
        return cached.reversed().map { $0.toEnhancedMessage() }
    }

    /// Búsqueda local en caché SwiftData (texto descifrado ya persistido).
    func searchMessageIds(conversationId: String, query: String, limit: Int = 100) -> [String] {
        guard limit > 0, let context = modelContext else { return [] }

        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return [] }

        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        guard let cached = try? context.fetch(descriptor) else { return [] }

        var matches: [String] = []
        matches.reserveCapacity(min(limit, cached.count))

        for message in cached {
            guard message.typeString == MessageType.text.rawValue else { continue }
            let searchable = (message.content ?? "")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard searchable.contains(normalizedQuery) else { continue }
            matches.append(message.id)
            if matches.count >= limit { break }
        }

        return matches
    }

    func markVanishMessagesDismissed(conversationId: String, messageIds: [String], userId: String) {
        guard let context = modelContext, !messageIds.isEmpty else { return }
        let ids = messageIds
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && ids.contains($0.id) && $0.isVanishModeMessage == true
        }
        if let cached = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: predicate)) {
            for message in cached where !message.vanishedFor.contains(userId) {
                message.vanishedFor.append(userId)
            }
            saveContext()
        }
    }

    /// Re-enlaza URLs locales desde App Group (puede ejecutarse fuera del main).
    nonisolated static func applyDiskWarm(to message: EnhancedMessage) -> (mediaUrl: String?, thumbnailUrl: String?, changed: Bool) {
        let warmed = ChatCacheStore.localURLsIfPresent(for: message)
        var changed = false

        if let mediaUrl = warmed.mediaUrl,
           message.mediaUrl != mediaUrl || message.hasMissingLocalMedia {
            changed = true
        }
        if let thumbnailUrl = warmed.thumbnailUrl,
           message.thumbnailUrl != thumbnailUrl || message.hasMissingLocalThumbnail {
            changed = true
        }

        return (warmed.mediaUrl, warmed.thumbnailUrl, changed)
    }

    /// Warm de disco en background; persiste y notifica mensajes actualizados.
    func scheduleWarmDiskMediaURLs(
        conversationId: String,
        onUpdated: @escaping (_ updatedMessages: [EnhancedMessage]) -> Void
    ) {
        Task.detached(priority: .utility) {
            let loaded = await MainActor.run {
                LocalPersistenceService.shared.loadMessagesFast(conversationId: conversationId)
            }
            guard !loaded.isEmpty else { return }

            var relinked: [EnhancedMessage] = []
            var results = loaded

            for index in results.indices {
                let warm = Self.applyDiskWarm(to: results[index])
                guard warm.changed else { continue }

                if let mediaUrl = warm.mediaUrl {
                    results[index].mediaUrl = mediaUrl
                }
                if let thumbnailUrl = warm.thumbnailUrl {
                    results[index].thumbnailUrl = thumbnailUrl
                }
                relinked.append(results[index])
            }

            await MainActor.run {
                if !relinked.isEmpty {
                    LocalPersistenceService.shared.saveMessages(relinked, conversationId: conversationId, sync: false)
                }
                onUpdated(results)
            }
        }
    }

    /// Warm síncrono antes de persistir (ingest / save batch).
    func warmDiskMediaURLs(in messages: [EnhancedMessage]) -> [EnhancedMessage] {
        var results = messages
        for index in results.indices {
            let warm = Self.applyDiskWarm(to: results[index])
            guard warm.changed else { continue }
            if let mediaUrl = warm.mediaUrl {
                results[index].mediaUrl = mediaUrl
            }
            if let thumbnailUrl = warm.thumbnailUrl {
                results[index].thumbnailUrl = thumbnailUrl
            }
        }
        return results
    }

    /// Carga el historial de mensajes de una conversación desde el caché local
    func loadMessages(conversationId: String) -> [EnhancedMessage] {
        let results = loadMessagesFast(conversationId: conversationId)
        guard !results.isEmpty else { return [] }

        var relinked: [EnhancedMessage] = []
        var warmedResults = results

        for index in warmedResults.indices {
            let warm = Self.applyDiskWarm(to: warmedResults[index])
            guard warm.changed else { continue }

            if let mediaUrl = warm.mediaUrl {
                warmedResults[index].mediaUrl = mediaUrl
            }
            if let thumbnailUrl = warm.thumbnailUrl {
                warmedResults[index].thumbnailUrl = thumbnailUrl
            }
            relinked.append(warmedResults[index])
        }

        if !relinked.isEmpty {
            saveMessages(relinked, conversationId: conversationId, sync: false)
        }

        return warmedResults
    }

    /// Elimina del caché local una conversación y su historial de mensajes.
    func deleteConversationCache(conversationId: String) {
        guard let context = modelContext else { return }

        let messageIds = loadMessages(conversationId: conversationId).map(\.id)
        ChatCacheStore.deleteConversation(conversationId, messageIds: messageIds)

        let conversationPredicate = #Predicate<CachedConversation> { $0.id == conversationId }
        let messagePredicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }

        try? context.delete(model: CachedConversation.self, where: conversationPredicate)
        try? context.delete(model: CachedMessage.self, where: messagePredicate)
        saveContext()
    }

    func cachedMessageCount() -> Int {
        guard let context = modelContext else { return 0 }
        return (try? context.fetchCount(FetchDescriptor<CachedMessage>())) ?? 0
    }

    func unreadMessageCount(for conversationId: String, currentUserId: String) -> Int {
        guard let context = modelContext else { return 0 }
        let predicate = #Predicate<CachedMessage> { message in
            message.conversationId == conversationId && message.senderId != currentUserId && !message.isRead
        }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func markMessagesAsRead(conversationId: String, messageIds: [String]) {
        guard let context = modelContext, !messageIds.isEmpty else { return }
        let predicate = #Predicate<CachedMessage> { message in
            message.conversationId == conversationId
        }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        if let cached = try? context.fetch(descriptor) {
            let idSet = Set(messageIds)
            var didUpdate = false
            for message in cached {
                if idSet.contains(message.id) && !message.isRead {
                    message.isRead = true
                    didUpdate = true
                }
            }
            if didUpdate {
                saveContext()
            }
        }
    }

    func updateMessageVanishExpiresAt(conversationId: String, messageId: String, expiresAt: Date) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        if let message = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: predicate)).first {
            message.vanishExpiresAt = expiresAt
            saveContext()
        }
    }

    func updateMessageNoticeContent(conversationId: String, messageId: String, content: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        if let message = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: predicate)).first {
            message.content = content
            saveContext()
        }
    }

    func markConversationReadLocally(conversationId: String, currentUserId: String) {
        guard let context = modelContext else { return }
        var didUpdate = false

        let conversationPredicate = #Predicate<CachedConversation> { conversation in
            conversation.id == conversationId
        }
        let conversationDescriptor = FetchDescriptor<CachedConversation>(predicate: conversationPredicate)
        if let cached = try? context.fetch(conversationDescriptor).first {
            var readStatus: [String: Bool] = [:]
            if let existingData = cached.readStatusData {
                readStatus = (try? JSONDecoder().decode([String: Bool].self, from: existingData)) ?? [:]
            }
            if readStatus[currentUserId] != true {
                readStatus[currentUserId] = true
                cached.readStatusData = try? JSONEncoder().encode(readStatus)
                didUpdate = true
            }
        }

        let messagePredicate = #Predicate<CachedMessage> { message in
            message.conversationId == conversationId
                && message.senderId != currentUserId
                && !message.isRead
        }
        if let unreadMessages = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: messagePredicate)) {
            for message in unreadMessages {
                message.isRead = true
                didUpdate = true
            }
        }

        if didUpdate {
            saveContext()
        }
    }

    func cachedMessageKeys(since date: Date) -> Set<String> {
        guard let context = modelContext else { return [] }

        let predicate = #Predicate<CachedMessage> { $0.timestamp >= date }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)

        guard let messages = try? context.fetch(descriptor) else { return [] }
        return Set(messages.map { "\($0.conversationId):\($0.id)" })
    }

    /// Claves de mensajes con media cifrada — protegidas de eviction por cuota.
    func cachedMessageKeysWithMedia() -> Set<String> {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedMessage>()
        guard let messages = try? context.fetch(descriptor) else { return [] }

        return Set(
            messages.compactMap { message -> String? in
                guard message.mediaEncryptionData != nil else { return nil }
                return "\(message.conversationId):\(message.id)"
            }
        )
    }

    /// Borra metadatos de chat en SwiftData y toda la media descifrada en disco.
    func clearAllChatCache() {
        guard let context = modelContext else { return }

        try? context.delete(model: CachedConversation.self)
        try? context.delete(model: CachedMessage.self)
        saveContext()
        ChatCacheStore.clearAllMedia()
    }
    
    // MARK: - 🔔 NOTIFICATIONS: Save & Load
    
    /// Guarda una lista de notificaciones en el caché local
    func saveNotifications(_ notifications: [Notification], sync: Bool = false) {
        guard let context = modelContext else { return }
        
        // ✅ SYNC: Borrar notificaciones antiguas si es sync completo
        if sync {
            try? context.delete(model: CachedNotification.self)
        }
        
        let notificationIds = notifications.compactMap { $0.id }
        let predicate = #Predicate<CachedNotification> { notificationIds.contains($0.id) }
        let descriptor = FetchDescriptor<CachedNotification>(predicate: predicate)
        let existingNotifications = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingNotifications.map { ($0.id, $0) })
        
        for notification in notifications {
            guard let notificationId = notification.id else { continue }
            
            let cached = CachedNotification.from(notification)
            
            if let existing = existingMap[notificationId] {
                updateCachedNotification(existing, from: cached)
            } else {
                context.insert(cached)
            }
        }
        
        saveContext()
        trimNotifications()
    }
    
    /// Elimina notificaciones del caché local por ID.
    func deleteNotifications(ids: [String]) {
        guard let context = modelContext, !ids.isEmpty else { return }

        let idSet = Set(ids)
        let descriptor = FetchDescriptor<CachedNotification>()
        guard let cached = try? context.fetch(descriptor) else { return }

        for notification in cached where idSet.contains(notification.id) {
            context.delete(notification)
        }
        saveContext()
    }

    /// Carga notificaciones desde el caché local
    func loadNotifications() -> [Notification] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<CachedNotification>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let cached = try context.fetch(descriptor)
            return cached.map { $0.toNotification() }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar notificaciones: \(error)")
            return []
        }
    }
    
    private func trimNotifications() {
        guard let context = modelContext else { return }
        let maxNotifications = 100
        
        let descriptor = FetchDescriptor<CachedNotification>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxNotifications {
                let toDelete = all.suffix(from: maxNotifications)
                for notification in toDelete {
                    context.delete(notification)
                }
                saveContext()
            }
        } catch { }
    }
    
    // MARK: - 🤝 CONNECTIONS: Save & Load
    
    /// Guarda seguidores de un usuario
    func saveFollowers(userId: String, followers: [AppUser]) {
        saveConnectionList(userId: userId, users: followers, type: "follower")
    }
    
    /// Guarda seguidos de un usuario
    func saveFollowing(userId: String, following: [AppUser]) {
        saveConnectionList(userId: userId, users: following, type: "following")
    }

    /// Guarda mutuas de un usuario
    func saveMutuals(userId: String, mutuals: [AppUser]) {
        saveConnectionList(userId: userId, users: mutuals, type: "mutual")
    }
    
    private func saveConnectionList(userId: String, users: [AppUser], type: String) {
        guard let context = modelContext else { return }
        
        // 1. Eliminar conexiones antiguas de este tipo para el usuario
        let predicate = #Predicate<CachedConnection> { $0.userId == userId && $0.type == type }
        try? context.delete(model: CachedConnection.self, where: predicate)
        
        // 2. Guardar nuevas conexiones
        for user in users {
            let conn = CachedConnection(userId: userId, targetId: user.id, type: type)
            context.insert(conn)
            saveUser(user) // Asegurar que el usuario está en caché
        }
        
        saveContext()
    }
    
    /// Carga las conexiones de un usuario desde el caché local
    func loadConnections(userId: String) -> (followers: [AppUser], following: [AppUser], mutuals: [AppUser]) {
        guard let context = modelContext else { return ([], [], []) }
        
        let predicate = #Predicate<CachedConnection> { $0.userId == userId }
        let descriptor = FetchDescriptor<CachedConnection>(predicate: predicate)
        
        do {
            let connections = try context.fetch(descriptor)
            
            var followers: [AppUser] = []
            var following: [AppUser] = []
            var mutuals: [AppUser] = []
            
            for conn in connections {
                if let user = loadUser(userId: conn.targetId) {
                    switch conn.type {
                    case "follower":
                        followers.append(user)
                    case "mutual":
                        mutuals.append(user)
                    default:
                        following.append(user)
                    }
                }
            }
            
            return (followers, following, mutuals)
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar conexiones: \(error)")
            return ([], [], [])
        }
    }
    
    /// Comprueba si el usuario actual sigue a un usuario específico (Offline)
    func isFollowing(targetUserId: String) -> Bool {
        guard let context = modelContext, let currentUserId = Auth.auth().currentUser?.uid else { return false }
        
        let predicate = #Predicate<CachedConnection> {
            $0.userId == currentUserId && $0.targetId == targetUserId && $0.type == "following"
        }
        
        let descriptor = FetchDescriptor<CachedConnection>(predicate: predicate)
        
        do {
            let count = try context.fetchCount(descriptor)
            return count > 0 
        } catch {
            return false
        }
    }
    
    // MARK: - 🔎 SEARCH HISTORY: Save & Load
    
    /// Guarda una búsqueda reciente
    func saveSearch(query: String, type: String, targetId: String? = nil) {
        guard let context = modelContext else { return }
        
        let search = CachedSearch(query: query, type: type, targetId: targetId)
        let searchId = search.id
        
        // Evitaremos duplicados borrando si ya existía (mismo id)
        let sameSearchPredicate = #Predicate<CachedSearch> { $0.id == searchId }
        try? context.delete(model: CachedSearch.self, where: sameSearchPredicate)
        
        context.insert(search)
        
        trimSearchHistory()
        saveContext()
    }
    
    /// Borra una búsqueda específica por su ID
    func deleteSearch(id: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedSearch> { $0.id == id }
        try? context.delete(model: CachedSearch.self, where: predicate)
        saveContext()
    }
    
    /// Carga las búsquedas recientes
    func loadRecentSearches() -> [CachedSearch] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<CachedSearch>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al cargar búsquedas: \(error)")
            return []
        }
    }
    
    /// Limpia el historial de búsqueda
    func clearSearchHistory() {
        guard let context = modelContext else { return }
        try? context.delete(model: CachedSearch.self)
        saveContext()
    }
    
    private func trimSearchHistory() {
        guard let context = modelContext else { return }
        let maxSearches = 20
        
        let descriptor = FetchDescriptor<CachedSearch>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxSearches {
                let toDelete = all.suffix(from: maxSearches)
                for item in toDelete {
                    context.delete(item)
                }
            }
        } catch { }
    }


    
    private func trimConversations() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<CachedConversation>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxConversations {
                let toDelete = all.suffix(from: maxConversations)
                for conversation in toDelete {
                    context.delete(conversation)
                }
                saveContext()
            }
        } catch { }
    }
    
    private func trimMessages(for conversationId: String) {
        guard let context = modelContext else { return }
        
        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxMessagesPerChat {
                let toDelete = all.suffix(from: maxMessagesPerChat)
                for message in toDelete {
                    ChatCacheStore.deleteMessageFiles(
                        conversationId: conversationId,
                        messageId: message.id
                    )
                    context.delete(message)
                }
                saveContext()
            }
        } catch { }
    }

    // MARK: - 🚀 ACTIONS: Queue management
    
    /// Guarda una nueva acción en la cola persistente
    func saveAction(_ action: CachedAction) {
        guard let context = modelContext else { return }
        context.insert(action)
        saveContext()
        // ✅ TRIGGER: Si hay conexión, intentar procesar la cola inmediatamente.
        // Las subidas ya tienen su propio proceso en vivo; sincronizarlas al guardarlas
        // puede detectar un falso duplicado y perder la acción de recuperación.
        let isUploadAction = action.type == CachedAction.ActionType.momentUpload.rawValue ||
            action.type == CachedAction.ActionType.storyUpload.rawValue
        if NetworkMonitor.shared.isConnected && !isUploadAction {
            Task { @MainActor in
                await OfflineSyncService.shared.syncPendingActions()
            }
        }
    }
    
    /// Carga todas las acciones pendientes
    func loadPendingActions() -> [CachedAction] {
        guard let context = modelContext else { return [] }
        
        let pendingStatus = CachedAction.ActionStatus.pending.rawValue
        let executingStatus = CachedAction.ActionStatus.executing.rawValue
        
        // SwiftData Predicates are limited, so we might need to filter in memory if complex
        let descriptor = FetchDescriptor<CachedAction>(
            predicate: #Predicate<CachedAction> { 
                $0.status == pendingStatus || $0.status == executingStatus 
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Elimina una acción (cuando se completa o se cancela)
    func deleteAction(id: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedAction> { $0.id == id }
        try? context.delete(model: CachedAction.self, where: predicate)
        saveContext()
    }
    
    /// Actualiza el estado de una acción
    func updateActionStatus(id: String, status: CachedAction.ActionStatus, error: String? = nil) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<CachedAction> { $0.id == id }
        let descriptor = FetchDescriptor<CachedAction>(predicate: predicate)
        
        if let action = (try? context.fetch(descriptor))?.first {
            action.status = status.rawValue
            action.lastError = error
            if status == .failed {
                action.retryCount += 1
            }
            saveContext()
        }
    }
    
    // MARK: - 🧹 AUTOMATIC CLEANUP
    
    // MARK: - 🧹 Cleanup
    
    /// Limpia datos antiguos del caché
    func cleanupOldData() {
        guard let context = modelContext else { return }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxDataAgeDays, to: Date()) ?? Date()
        
        // Limpiar historias expiradas
        cleanupOldStories()
        
        // Limpiar chats y mensajes antiguos
        cleanupOldChats()
        
        // Limpiar moments antiguos
        let momentPredicate = #Predicate<CachedMoment> { $0.lastSyncedAt < cutoffDate }
        let momentDescriptor = FetchDescriptor<CachedMoment>(predicate: momentPredicate)
        
        do {
            let oldMoments = try context.fetch(momentDescriptor)
            for moment in oldMoments {
                context.delete(moment)
            }
            
            if !oldMoments.isEmpty {
                AppLog.debug("🧹 LocalPersistence: Limpiados \(oldMoments.count) moments antiguos")
            }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error en cleanup: \(error)")
        }
        
        // Limpiar usuarios antiguos (excepto currentUser)
        let section = "currentUser"
        let userPredicate = #Predicate<CachedUser> {
            $0.lastSyncedAt < cutoffDate && $0.cacheSection != section
        }
        let userDescriptor = FetchDescriptor<CachedUser>(predicate: userPredicate)
        
        do {
            let oldUsers = try context.fetch(userDescriptor)
            for user in oldUsers {
                context.delete(user)
            }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error en cleanup usuarios: \(error)")
        }

        // Aplicar tope por conteo: conservar solo los usuarios más recientes.
        trimCachedUsersToLimit(context: context)
        
        saveContext()
    }

    /// Mantiene como máximo `maxCachedUsers` usuarios cacheados (excluyendo currentUser),
    /// expulsando los menos recientemente sincronizados.
    private func trimCachedUsersToLimit(context: ModelContext) {
        let currentUserSection = "currentUser"
        var descriptor = FetchDescriptor<CachedUser>(
            predicate: #Predicate<CachedUser> { $0.cacheSection != currentUserSection },
            sortBy: [SortDescriptor(\.lastSyncedAt, order: .reverse)]
        )
        descriptor.fetchLimit = nil
        do {
            let users = try context.fetch(descriptor)
            guard users.count > maxCachedUsers else { return }
            for user in users[maxCachedUsers...] {
                context.delete(user)
            }
        } catch {
            AppLog.debug("❌ LocalPersistence: Error aplicando tope de usuarios: \(error)")
        }
    }
    
    func cleanupOldChats() {
        guard let context = modelContext else { return }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxDataAgeDays, to: Date()) ?? Date()
        
        // 1. Limpiar mensajes antiguos (y su media en disco)
        let messagePredicate = #Predicate<CachedMessage> { $0.timestamp < cutoffDate }
        if let staleMessages = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: messagePredicate)) {
            for message in staleMessages {
                ChatCacheStore.deleteMessageFiles(
                    conversationId: message.conversationId,
                    messageId: message.id
                )
            }
        }
        do {
            try context.delete(model: CachedMessage.self, where: messagePredicate)
        } catch {
            AppLog.debug("❌ LocalPersistence: Error limpiando mensajes antiguos: \(error)")
        }
        
        // 2. Limpiar conversaciones que no han tenido actividad en X días
        let chatPredicate = #Predicate<CachedConversation> { $0.timestamp < cutoffDate && !$0.isPinned }
        do {
            try context.delete(model: CachedConversation.self, where: chatPredicate)
        } catch {
            AppLog.debug("❌ LocalPersistence: Error limpiando chats antiguos: \(error)")
        }
        
        saveContext()
        ChatCacheStore.enforceRetention()
    }
    
    /// Limpia todo el caché local
    func clearAll() {
        guard let context = modelContext else { return }
        
        do {
            try context.delete(model: CachedMoment.self)
            try context.delete(model: CachedUser.self)
            saveContext()
            AppLog.debug("🧹 LocalPersistence: Todo el caché local borrado")
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al borrar caché: \(error)")
        }
    }
    
    // MARK: - 📊 Stats
    
    /// Info de debug sobre el tamaño del caché
    func getCacheStats() -> String {
        guard let context = modelContext else { return "No context" }
        
        let momentCount = (try? context.fetchCount(FetchDescriptor<CachedMoment>())) ?? 0
        let userCount = (try? context.fetchCount(FetchDescriptor<CachedUser>())) ?? 0
        
        return "📊 Cache: \(momentCount) moments, \(userCount) usuarios"
    }
    
    // MARK: - Private Helpers
    
    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            AppLog.debug("❌ LocalPersistence: Error al guardar: \(error)")
        }
    }
    
    private func trimFeedMoments() {
        guard let context = modelContext else { return }
        
        let section = "feed"
        let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
        let descriptor = FetchDescriptor<CachedMoment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxFeedMoments {
                let toDelete = all.suffix(from: maxFeedMoments)
                for moment in toDelete {
                    context.delete(moment)
                }
                saveContext()
            }
        } catch { }
    }
    
    private func trimExploreMoments() {
        guard let context = modelContext else { return }
        
        let section = "explore"
        let predicate = #Predicate<CachedMoment> { $0.feedSection == section }
        let descriptor = FetchDescriptor<CachedMoment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let all = try context.fetch(descriptor)
            if all.count > maxExploreMoments {
                let toDelete = all.suffix(from: maxExploreMoments)
                for moment in toDelete {
                    context.delete(moment)
                }
                saveContext()
            }
        } catch { }
    }
    
    private func updateCachedMoment(_ existing: CachedMoment, from new: CachedMoment) {
        existing.username = new.username
        existing.content = new.content
        existing.imagePath = new.imagePath
        existing.videoUrl = new.videoUrl
        existing.commentCount = new.commentCount
        existing.profileImagePath = new.profileImagePath
        existing.location = new.location
        existing.audience = new.audience
        existing.aspectRatio = new.aspectRatio
        existing.thumbnailUrl = new.thumbnailUrl
        existing.videoDuration = new.videoDuration
        existing.videoFileSize = new.videoFileSize
        existing.videoResolution = new.videoResolution
        existing.disableComments = new.disableComments
        existing.hideLikeCounts = new.hideLikeCounts
        existing.allowSharing = new.allowSharing
        existing.scheduledDate = new.scheduledDate
        existing.isPinned = new.isPinned
        existing.pinnedAt = new.pinnedAt
        existing.gridPreviewScale = new.gridPreviewScale
        existing.gridPreviewOffsetX = new.gridPreviewOffsetX
        existing.gridPreviewOffsetY = new.gridPreviewOffsetY
        existing.gridPreviewFitMode = new.gridPreviewFitMode
        existing.gridPreviewBackground = new.gridPreviewBackground
        existing.hasHiddenLayers = new.hasHiddenLayers
        existing.hiddenLayerCount = new.hiddenLayerCount
        existing.reactionsData = new.reactionsData
        existing.mediaItemsData = new.mediaItemsData
        existing.taggedUsersData = new.taggedUsersData
        existing.mentionedUsersData = new.mentionedUsersData
        existing.lastSyncedAt = Date()
    }
    
    private func updateCachedUser(_ existing: CachedUser, from new: CachedUser) {
        existing.username = new.username
        existing.email = new.email
        existing.bio = new.bio
        existing.profileImagePath = new.profileImagePath
        existing.websiteUrl = new.websiteUrl
        existing.profileNote = new.profileNote
        existing.isPlusSubscriber = new.isPlusSubscriber
        existing.isVerified = new.isVerified
        existing.isPrivate = new.isPrivate
        existing.isActive = new.isActive
        existing.showBadge = new.showBadge
        existing.showPlusBadge = new.showPlusBadge
        existing.primaryBadgeId = new.primaryBadgeId
        existing.selectedProfileTheme = new.selectedProfileTheme
        existing.interestsData = new.interestsData
        existing.blockedUsersData = new.blockedUsersData
        existing.bestFriendsData = new.bestFriendsData
        existing.ownedBadgesData = new.ownedBadgesData
        existing.lastSyncedAt = Date()
    }
    
    private func updateCachedConversation(_ existing: CachedConversation, from new: CachedConversation) {
        existing.participants = new.participants
        existing.lastMessage = new.lastMessage
        existing.timestamp = new.timestamp
        existing.readStatusData = new.readStatusData
        existing.otherParticipantId = new.otherParticipantId
        existing.otherParticipantUsername = new.otherParticipantUsername
        existing.otherParticipantProfileImagePath = new.otherParticipantProfileImagePath
        existing.isPinned = new.isPinned
        existing.isMuted = new.isMuted
        existing.readReceiptPreferencesData = new.readReceiptPreferencesData
        existing.forwardingPreferencesData = new.forwardingPreferencesData
        existing.lastDeletedAtData = new.lastDeletedAtData
        existing.vanishModeActive = new.vanishModeActive
        existing.lastSyncedAt = Date()
    }
    
    private func shouldPreserveLocalMediaURL(existing: String?, incoming: String?, isDeleted: Bool) -> Bool {
        guard !isDeleted else { return false }
        guard let existing, !existing.isEmpty else { return false }
        guard let url = URL(string: existing), url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func updateCachedMessage(_ existing: CachedMessage, from new: CachedMessage) {
        existing.typeString = new.typeString
        existing.isDeleted = new.isDeleted
        existing.deletedAt = new.deletedAt

        if new.isDeleted {
            existing.content = nil
            existing.mediaUrl = nil
            existing.thumbnailUrl = nil
            existing.mediaObjectPath = nil
            existing.thumbnailObjectPath = nil
            existing.mediaEncryptionData = nil
            existing.thumbnailEncryptionData = nil
        } else {
            existing.content = new.content
            if shouldPreserveLocalMediaURL(existing: existing.mediaUrl, incoming: new.mediaUrl, isDeleted: new.isDeleted) {
                // Firestore no incluye rutas descifradas locales.
            } else {
                existing.mediaUrl = new.mediaUrl
            }
            if shouldPreserveLocalMediaURL(existing: existing.thumbnailUrl, incoming: new.thumbnailUrl, isDeleted: new.isDeleted) {
                // Firestore no incluye rutas descifradas locales.
            } else {
                existing.thumbnailUrl = new.thumbnailUrl
            }
            existing.mediaObjectPath = new.mediaObjectPath
            existing.thumbnailObjectPath = new.thumbnailObjectPath
            existing.mediaEncryptionData = new.mediaEncryptionData
            existing.thumbnailEncryptionData = new.thumbnailEncryptionData
        }

        existing.mediaBatchId = new.mediaBatchId
        existing.duration = new.duration
        existing.fileName = new.fileName
        existing.fileSize = new.fileSize
        existing.mediaWidth = new.mediaWidth
        existing.mediaHeight = new.mediaHeight
        existing.latitude = new.latitude
        existing.longitude = new.longitude
        existing.statusString = new.statusString
        // Una vez leído, permanece leído: re-cachear un mensaje (re-sync del listener) no debe
        // des-marcarlo. Sin esto, los mensajes ya leídos reaparecían como no leídos al reentrar.
        existing.isRead = existing.isRead || new.isRead
        existing.editedAt = new.editedAt
        existing.reactionsData = new.reactionsData
        existing.replyTo = new.replyTo
        existing.expirationDate = new.expirationDate
        existing.isViewed = new.isViewed
        existing.storyReplyDataEncoded = new.storyReplyDataEncoded
        existing.sharedMomentDataEncoded = new.sharedMomentDataEncoded
        existing.sharedStoryDataEncoded = new.sharedStoryDataEncoded
        existing.viewedBy = new.viewedBy
        existing.isVanishModeMessage = new.isVanishModeMessage
        existing.vanishedFor = Array(Set(existing.vanishedFor + new.vanishedFor))
        existing.vanishExpiresAt = new.vanishExpiresAt ?? existing.vanishExpiresAt
        existing.lastSyncedAt = Date()
    }
    
    private func updateCachedNotification(_ existing: CachedNotification, from new: CachedNotification) {
        existing.type = new.type
        existing.senderId = new.senderId
        existing.senderUsername = new.senderUsername
        existing.timestamp = new.timestamp
        existing.isPending = new.isPending
        existing.title = new.title
        existing.message = new.message
        existing.downloadURL = new.downloadURL
        existing.momentId = new.momentId
        existing.visitCount = new.visitCount
        existing.storyId = new.storyId
        existing.storyAuthorId = new.storyAuthorId
        existing.storyPreviewUrl = new.storyPreviewUrl
        existing.reaction = new.reaction
        existing.reactionCount = new.reactionCount
        existing.commentId = new.commentId
        existing.echoId = new.echoId
        existing.moderationScope = new.moderationScope
        existing.totalParts = new.totalParts
        existing.chainRole = new.chainRole
        existing.lastSyncedAt = Date()
    }
    
    // MARK: - ❤️ MOMENT REACTIONS (Optimistic)
    
    func toggleMomentReactionLocally(momentId: String, reaction: String, userId: String) {
        guard let context = modelContext else { return }
        
        // 1. Buscar el momento en TODAS las secciones para consistencia global
        let predicate = #Predicate<CachedMoment> { $0.momentId == momentId }
        let descriptor = FetchDescriptor<CachedMoment>(predicate: predicate)
        
        guard let existingMoments = try? context.fetch(descriptor), !existingMoments.isEmpty else { return }
        
        for moment in existingMoments {
            var reactions: [String: [String]] = [:]
            if let data = moment.reactionsData {
                reactions = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
            }
            
            var userIds = reactions[reaction] ?? []
            if let index = userIds.firstIndex(of: userId) {
                userIds.remove(at: index)
            } else {
                userIds.append(userId)
            }
            
            if userIds.isEmpty {
                reactions.removeValue(forKey: reaction)
            } else {
                reactions[reaction] = userIds
            }
            
            moment.reactionsData = try? JSONEncoder().encode(reactions)
            moment.lastSyncedAt = Date()
        }
        
        saveContext()
    }
    
    // MARK: - 💬 MESSAGE REACTIONS (Optimistic)
    
    func toggleMessageReactionLocally(messageId: String, emoji: String, userId: String) {
        guard let context = modelContext else { return }
        
        let predicate = #Predicate<CachedMessage> { $0.id == messageId }
        let descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        
        if let message = (try? context.fetch(descriptor))?.first {
            var reactions: [String: [String]] = [:]
            if let data = message.reactionsData {
                reactions = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
            }

            let updated = MessageReactionMutation.apply(to: reactions, emoji: emoji, userId: userId)
            message.reactionsData = updated.flatMap { try? JSONEncoder().encode($0) }
            message.lastSyncedAt = Date()
            saveContext()
        }
    }
    
    // MARK: - 📝 COMMENT COUNT (Optimistic)
    
    func updateCommentCountLocally(momentId: String, increment: Int) {
        guard let context = modelContext else { return }
        
        let predicate = #Predicate<CachedMoment> { $0.momentId == momentId }
        let descriptor = FetchDescriptor<CachedMoment>(predicate: predicate)
        
        if let moments = try? context.fetch(descriptor) {
            for moment in moments {
                let current = moment.commentCount ?? 0
                moment.commentCount = max(0, current + increment)
                moment.lastSyncedAt = Date()
            }
            saveContext()
        }
    }
    
    // MARK: - 🤝 FOLLOW ACTIONS (Optimistic)
    
    func toggleFollowLocally(currentUserId: String, targetUserId: String, isFollow: Bool) {
        guard let context = modelContext else { return }
        
        let id = "\(currentUserId)_\(targetUserId)_following"
        let predicate = #Predicate<CachedConnection> { $0.id == id }
        let descriptor = FetchDescriptor<CachedConnection>(predicate: predicate)
        
        let existing = (try? context.fetch(descriptor))?.first
        
        if isFollow {
            if existing == nil {
                let connection = CachedConnection(userId: currentUserId, targetId: targetUserId, type: "following")
                context.insert(connection)
            }
        } else {
            if let existing = existing {
                context.delete(existing)
            }

            let mutualId = "\(currentUserId)_\(targetUserId)_mutual"
            let mutualPredicate = #Predicate<CachedConnection> { $0.id == mutualId }
            let mutualDescriptor = FetchDescriptor<CachedConnection>(predicate: mutualPredicate)
            if let mutual = (try? context.fetch(mutualDescriptor))?.first {
                context.delete(mutual)
            }
        }
        
        saveContext()
    }
    
    // MARK: - 👤 PROFILE UPDATE (Optimistic)
    
    func updateProfile(userId: String, bio: String?, oldBio: String? = nil, website: String?, oldWebsite: String? = nil, interests: [String]?, profileImageLocalPath: String?) async {
        guard let context = modelContext else { return }
        
        var actualOldBio = oldBio
        var actualOldWebsite = oldWebsite
        
        // 1. Optimistic UI
        let userDescriptor = FetchDescriptor<CachedUser>(predicate: #Predicate { $0.userId == userId })
        if let currentUser = (try? context.fetch(userDescriptor))?.first {
            if actualOldBio == nil { actualOldBio = currentUser.bio }
            if actualOldWebsite == nil { actualOldWebsite = currentUser.websiteUrl }
            
            if let bio = bio { currentUser.bio = bio }
            if let website = website { currentUser.websiteUrl = website }
            if let interests = interests {
                currentUser.interestsData = try? JSONEncoder().encode(interests)
            }
            if let imagePath = profileImageLocalPath {
                currentUser.profileImagePath = imagePath
            }
            currentUser.lastSyncedAt = Date()
            saveContext()
        }
        
        // 2. Persistir acción
        let payload = ProfileUpdatePayload(
            userId: userId,
            bio: bio,
            oldBio: actualOldBio,
            websiteUrl: website,
            oldWebsiteUrl: actualOldWebsite,
            interests: interests,
            profileImageLocalPath: profileImageLocalPath,
            isImageUpdate: profileImageLocalPath != nil
        )
        
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.updateProfile.rawValue,
                payloadData: data
            )
            saveAction(action)
        }
    }
    
    // MARK: - 🤝 FOLLOW REQUESTS (Optimistic)
    
    func acceptFollowRequest(notificationId: String, senderId: String, recipientId: String) async {
        guard let context = modelContext else { return }
        // 1. Optimistic UI: Marcar notificación como NO pendiente (leída/aceptada)
        let descriptor = FetchDescriptor<CachedNotification>(predicate: #Predicate { $0.id == notificationId })
        if let notification = (try? context.fetch(descriptor))?.first {
            notification.isPending = false
            notification.lastSyncedAt = Date()
            saveContext()
        }
        
        // 2. Persistir acción
        let payload = FollowRequestActionPayload(
            notificationId: notificationId,
            senderId: senderId,
            recipientId: recipientId,
            isAccept: true
        )
        
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.acceptFollowRequest.rawValue,
                payloadData: data
            )
            saveAction(action)
        }
    }
    
    func rejectFollowRequest(notificationId: String, senderId: String, recipientId: String) async {
        guard let context = modelContext else { return }
        
        // 1. Optimistic UI: Eliminar la notificación
        let descriptor = FetchDescriptor<CachedNotification>(predicate: #Predicate { $0.id == notificationId })
        if let notification = (try? context.fetch(descriptor))?.first {
            context.delete(notification)
            saveContext()
        }
        
        // 2. Persistir acción
        let payload = FollowRequestActionPayload(
            notificationId: notificationId,
            senderId: senderId,
            recipientId: recipientId,
            isAccept: false
        )
        
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.rejectFollowRequest.rawValue,
                payloadData: data
            )
            saveAction(action)
        }
    }
    
    // MARK: - 🚩 REPORT CONTENT (Offline)
    
    func reportContent(
        reporterId: String,
        reportedUserId: String,
        reportedContentType: String,
        reportedContentId: String,
        category: String,
        description: String,
        priority: String
    ) async {
        let payload = ReportActionPayload(
            reporterId: reporterId,
            reportedUserId: reportedUserId,
            reportedContentType: reportedContentType,
            reportedContentId: reportedContentId,
            category: category,
            description: description,
            priority: priority
        )
        
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.reportContent.rawValue,
                payloadData: data
            )
            saveAction(action)
        }
    }
    
    // MARK: - 📬 NOTIFICATIONS (Offline)
    
    func markNotificationAsRead(notificationId: String, userId: String) async {
        guard let context = modelContext else { return }
        
        // 1. Optimistic UI
        let descriptor = FetchDescriptor<CachedNotification>(predicate: #Predicate { $0.id == notificationId })
        if let notification = (try? context.fetch(descriptor))?.first {
            notification.isPending = false
            notification.lastSyncedAt = Date()
            saveContext()
        }
        
        // 2. Persistir Acción
        let payload = MarkAsReadPayload(notificationId: notificationId, userId: userId)
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.markAsRead.rawValue,
                payloadData: data
            )
            saveAction(action)
        }

    }
    
    /// Borra un momento del caché local de forma global (todas las secciones)
    func deleteMoment(momentId: String) {
        guard let context = modelContext else { return }
        
        // Borramos TODAS las secciones donde este momento pueda estar cacheado
        let predicate = #Predicate<CachedMoment> { $0.momentId == momentId }
        try? context.delete(model: CachedMoment.self, where: predicate)
        saveContext()
    }
    
    // MARK: - 🗑️ DELETE MOMENT (Offline & Online Sync)
    
    func deleteMoment(momentId: String, userId: String, imagePath: String?, videoUrl: String?) async {
        // 1. Optimistic UI: Eliminar del caché local de forma global
        deleteMoment(momentId: momentId)
        
        // 2. Persistir Acción para Sincronización
        let payload = DeleteMomentPayload(
            momentId: momentId,
            userId: userId,
            imagePath: imagePath,
            videoUrl: videoUrl
        )
        
        if let data = try? JSONEncoder().encode(payload) {
            let action = CachedAction(
                id: UUID().uuidString,
                type: CachedAction.ActionType.deleteMoment.rawValue,
                payloadData: data
            )
            
            saveAction(action)
        }
    }
}

// MARK: - 👁️ Story Seen State (Local)

/// Cache local de último timestamp de story vista por autor y viewer.
/// Reduce lecturas de `viewers` en historias antiguas ya vistas.
final class StorySeenStateService {
    static let shared = StorySeenStateService()

    private let queue = DispatchQueue(label: "story.seen.state.sync")
    private let defaults = UserDefaults.standard
    private let storageKey = "story_last_seen_by_author_v1"
    private let maxAge: TimeInterval = 60 * 60 * 6 // 6 horas
    private let remoteCacheTTL: TimeInterval = 60

    private var loaded = false
    private var lastSeenMap: [String: TimeInterval] = [:]
    private var remoteCache: [String: (date: Date?, expiresAt: Date)] = [:]
    private var inFlightRemoteFetches: [String: [(Date?) -> Void]] = [:]

    private init() {}

    private func compositeKey(viewerId: String, authorId: String) -> String {
        "\(viewerId)|\(authorId)"
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        if let stored = defaults.dictionary(forKey: storageKey) as? [String: TimeInterval] {
            lastSeenMap = stored
        } else if let storedAny = defaults.dictionary(forKey: storageKey) {
            var normalized: [String: TimeInterval] = [:]
            for (key, value) in storedAny {
                if let number = value as? NSNumber {
                    normalized[key] = number.doubleValue
                }
            }
            lastSeenMap = normalized
        }
        loaded = true
    }

    private func localLastSeenDateLocked(viewerId: String, authorId: String) -> Date? {
        ensureLoaded()
        let key = compositeKey(viewerId: viewerId, authorId: authorId)
        guard let timestamp = lastSeenMap[key] else { return nil }
        if Date().timeIntervalSince1970 - timestamp > maxAge {
            lastSeenMap.removeValue(forKey: key)
            defaults.set(lastSeenMap, forKey: storageKey)
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    func lastSeenDate(viewerId: String, authorId: String) -> Date? {
        queue.sync {
            localLastSeenDateLocked(viewerId: viewerId, authorId: authorId)
        }
    }

    func fetchEffectiveLastSeen(viewerId: String, authorId: String, completion: @escaping (Date?) -> Void) {
        let key = compositeKey(viewerId: viewerId, authorId: authorId)

        queue.async {
            self.ensureLoaded()
            let localDate = self.localLastSeenDateLocked(viewerId: viewerId, authorId: authorId)

            if let cached = self.remoteCache[key], cached.expiresAt > Date() {
                let effective = self.maxDate(localDate, cached.date)
                DispatchQueue.main.async {
                    completion(effective)
                }
                return
            }

            if self.inFlightRemoteFetches[key] != nil {
                self.inFlightRemoteFetches[key]?.append(completion)
                return
            }

            self.inFlightRemoteFetches[key] = [completion]

            Firestore.firestore()
                .collection("users").document(viewerId)
                .collection("storySeen").document(authorId)
                .getDocument { snapshot, _ in
                    let remoteDate = (snapshot?.data()?["lastSeenAt"] as? Timestamp)?.dateValue()

                    self.queue.async {
                        if let remoteDate = remoteDate {
                            let currentValue = self.lastSeenMap[key] ?? 0
                            let remoteValue = remoteDate.timeIntervalSince1970
                            if remoteValue > currentValue {
                                self.lastSeenMap[key] = remoteValue
                                self.defaults.set(self.lastSeenMap, forKey: self.storageKey)
                            }
                        }

                        self.remoteCache[key] = (
                            date: remoteDate,
                            expiresAt: Date().addingTimeInterval(self.remoteCacheTTL)
                        )

                        let localAfterMerge = self.localLastSeenDateLocked(viewerId: viewerId, authorId: authorId)
                        let effective = self.maxDate(localAfterMerge, remoteDate)
                        let callbacks = self.inFlightRemoteFetches.removeValue(forKey: key) ?? []

                        DispatchQueue.main.async {
                            callbacks.forEach { $0(effective) }
                        }
                    }
                }
        }
    }

    func markSeen(viewerId: String, authorId: String, timestamp: Date, syncRemote: Bool = false) {
        let key = compositeKey(viewerId: viewerId, authorId: authorId)
        var shouldSyncRemote = false
        var timestampToSync = timestamp

        queue.sync {
            ensureLoaded()
            let newValue = timestamp.timeIntervalSince1970
            let currentValue = lastSeenMap[key] ?? 0
            let effectiveValue = max(newValue, currentValue)

            if effectiveValue > currentValue {
                lastSeenMap[key] = effectiveValue
                defaults.set(lastSeenMap, forKey: storageKey)
            }

            timestampToSync = Date(timeIntervalSince1970: effectiveValue)
            remoteCache[key] = (date: timestampToSync, expiresAt: Date().addingTimeInterval(remoteCacheTTL))
            shouldSyncRemote = syncRemote
        }

        guard shouldSyncRemote else { return }

        Firestore.firestore()
            .collection("users").document(viewerId)
            .collection("storySeen").document(authorId)
            .setData([
                "lastSeenAt": Timestamp(date: timestampToSync)
            ], merge: true) { error in
                #if DEBUG
                if let error = error {
                    AppLog.debug("⚠️ storySeen sync failed viewer:\(viewerId) author:\(authorId) -> \(error.localizedDescription)")
                }
                #endif
            }
    }

    func invalidate(viewerId: String, authorId: String) {
        queue.sync {
            ensureLoaded()
            let key = compositeKey(viewerId: viewerId, authorId: authorId)
            lastSeenMap.removeValue(forKey: key)
            remoteCache.removeValue(forKey: key)
            defaults.set(lastSeenMap, forKey: storageKey)
        }
    }

    func supportsShortcut(forAudience audience: String?) -> Bool {
        guard let normalized = audience?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return true // legacy sin audience -> everyone
        }

        switch normalized {
        case "everyone", "mutuals":
            return true
        default:
            return false
        }
    }
}
