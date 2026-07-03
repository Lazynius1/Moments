import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import Photos
import PhotosUI
import AVFoundation
import SwiftUI
import UIKit

@MainActor
class EnhancedChatViewModel: ObservableObject {
    enum HistoryLoadNotice: Equatable {
        case hidden
        case loadingRemote
        case offline
        case error
    }

    struct ChatTimelineMutation: Equatable {
        let kind: ChatListUpdateKind
        let reason: ChatTimelineUpdateReason
        let anchorMessageId: String?

        static let initial = ChatTimelineMutation(
            kind: .initial,
            reason: .layout,
            anchorMessageId: nil
        )
    }

    @Published var messages: [EnhancedMessage] = [] {
        didSet { rebuildMessageIndex() }
    }
    @Published private(set) var chatTimelineMutation: ChatTimelineMutation = .initial
    private var forcedNextTimelineMutation: ChatTimelineMutation?
    private(set) var messagesById: [String: EnhancedMessage] = [:]
    private(set) var messageIndexById: [String: Int] = [:]
    private(set) var unreadIncomingCount = 0

    private func rebuildMessageIndex() {
        var byId = [String: EnhancedMessage](minimumCapacity: messages.count)
        var indexById = [String: Int](minimumCapacity: messages.count)
        var unread = 0
        let selfId = currentUserId
        for (offset, message) in messages.enumerated() {
            byId[message.id] = message
            indexById[message.id] = offset
            if !message.isRead, message.senderId != selfId { unread += 1 }
        }
        messagesById = byId
        messageIndexById = indexById
        unreadIncomingCount = unread
    }

    @Published var typingUsers: Set<String> = []
    @Published var typingIndicatorEnabled = true
    @Published var isLoading = false
    @Published var error: String?
    @Published var uploadProgress: [String: Double] = [:] // ✅ Media upload progress (0.0 - 1.0)
    @Published var downloadProgress: [String: Double] = [:]

    private func setUploadProgress(_ progress: Double, for messageId: String) {
        var updated = uploadProgress
        updated[messageId] = progress
        uploadProgress = updated
    }

    private func clearUploadProgress(for messageId: String) {
        guard uploadProgress[messageId] != nil else { return }
        var updated = uploadProgress
        updated.removeValue(forKey: messageId)
        uploadProgress = updated
    }

    private func setDownloadProgress(_ progress: Double, for messageId: String) {
        var updated = downloadProgress
        updated[messageId] = progress
        downloadProgress = updated
    }

    private func clearDownloadProgress(for messageId: String) {
        guard downloadProgress[messageId] != nil else { return }
        var updated = downloadProgress
        updated.removeValue(forKey: messageId)
        downloadProgress = updated
    }

    private func pruneUploadProgress(for messages: [EnhancedMessage]) {
        let activeSendingIds = Set(messages.filter { $0.status == .sending }.map(\.id))
        var updated = uploadProgress
        for messageId in updated.keys where !activeSendingIds.contains(messageId) {
            updated.removeValue(forKey: messageId)
        }
        if updated != uploadProgress {
            uploadProgress = updated
        }
    }

    private func pruneLocalMessageStates(for messages: [EnhancedMessage]) {
        let statusPriority: [MessageStatus: Int] = [
            .sending: 0, .sent: 1, .delivered: 2, .read: 3, .failed: -1, .pending: -1
        ]
        for (messageId, localStatus) in localMessageStates {
            guard let remoteStatus = messages.first(where: { $0.id == messageId })?.status else { continue }
            let localPriority = statusPriority[localStatus] ?? 0
            let remotePriority = statusPriority[remoteStatus] ?? 0
            if remotePriority >= localPriority && localStatus != .failed {
                localMessageStates.removeValue(forKey: messageId)
            }
        }
    }

    private func commitMessagesPresentation(_ messages: [EnhancedMessage]) {
        let previousMessages = self.messages
        if let forcedNextTimelineMutation {
            chatTimelineMutation = forcedNextTimelineMutation
            self.forcedNextTimelineMutation = nil
        } else {
            chatTimelineMutation = deriveTimelineMutation(
                oldMessages: previousMessages,
                newMessages: messages
            )
        }
        self.messages = Array(messages)
        pruneUploadProgress(for: messages)
        pruneLocalMessageStates(for: messages)
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
    }

    private func deriveTimelineMutation(
        oldMessages: [EnhancedMessage],
        newMessages: [EnhancedMessage]
    ) -> ChatTimelineMutation {
        guard !newMessages.isEmpty else {
            return ChatTimelineMutation(kind: .replaceAll, reason: .layout, anchorMessageId: nil)
        }
        guard !oldMessages.isEmpty else {
            return .initial
        }

        let oldIds = oldMessages.map(\.id)
        let newIds = newMessages.map(\.id)

        if newIds == oldIds {
            return ChatTimelineMutation(kind: .reconfigureRows, reason: .layout, anchorMessageId: nil)
        }

        if newIds.count > oldIds.count {
            if Array(newIds.suffix(oldIds.count)) == oldIds {
                return ChatTimelineMutation(
                    kind: .prependHistory,
                    reason: .history,
                    anchorMessageId: oldMessages.first?.id
                )
            }

            if Array(newIds.prefix(oldIds.count)) == oldIds {
                let reason: ChatTimelineUpdateReason = newMessages.last?.senderId == currentUserId
                    ? .outgoing
                    : .incoming
                return ChatTimelineMutation(
                    kind: .appendMessages,
                    reason: reason,
                    anchorMessageId: nil
                )
            }
        }

        return ChatTimelineMutation(kind: .replaceAll, reason: .layout, anchorMessageId: nil)
    }
    @Published var isTyping = false {
        didSet {
            handleTypingIndicator()
        }
    }

    // ✅ NUEVO: Diccionario para estados locales con prioridad
    private var localMessageStates: [String: MessageStatus] = [:]
    /// Mensajes salientes aún no reflejados en Firestore; sobreviven a `rebuildMessagesList`.
    private var outgoingTempMessages: [String: EnhancedMessage] = [:]
    private var hydratingMediaIds = Set<String>()
    @Published private(set) var downloadingMediaIds = Set<String>()
    private var refreshingMetadataIds = Set<String>()

    // ✅ NUEVO: Flag para bloquear listener temporalmente
    private var isUpdatingLocalMessage = false

    // ✅ NUEVO: Flag para saber si el chat está visible (para marcar como leído solo cuando está visible)
    var isChatVisible = false

    // ✅ PAGINACIÓN
    @Published var isLoadingMore = false
    @Published var isLoadingOlderHistory = false
    @Published var canLoadMore = true
    @Published private(set) var historyLoadNotice: HistoryLoadNotice = .hidden
    private static let recentChatWindowSize = 20
    private static let staleChatWindowSize = 6
    private static let staleChatThresholdDays = 45
    private static let historyPageSize = 50
    private static let navigationWindowRadius = 25
    @Published private(set) var forwardingPreferences: [String: Bool] = [:]
    @Published private(set) var buzzPreferences: [String: Bool] = [:]
    @Published private(set) var vanishModeActive = false
    @Published private(set) var vanishMessageTimer: VanishMessageTimer = .default
    /// Fuente de verdad para pintar reacciones al instante (SwiftUI no siempre detecta cambios en `message.reactions`).
    @Published private(set) var liveReactionOverlays: [String: [String: [String]]] = [:]
    @Published var latestBuzzEvent: ChatBuzzEvent?
    @Published private(set) var buzzEvents: [ChatBuzzEvent] = []
    @Published private(set) var searchResults: [String] = []
    @Published private(set) var isSearchingHistory = false
    private var searchDebounceTask: Task<Void, Never>?
    private var activeSearchToken = UUID()
    private var historicalMessages: [EnhancedMessage] = []
    private var realTimeMessages: [EnhancedMessage] = []
    /// Ocultos con «Eliminar para mí» hasta que Firestore confirme `deletedFor`.
    private var hiddenForMeMessageIds = Set<String>()
    /// Ocultos optimistamente al cerrar sesión vanish antes de que Firestore confirme `vanishedFor`.
    private var optimisticallyHiddenVanishIds = Set<String>()
    /// IDs de mensajes entrantes vistos DE VERDAD en esta sesión (no por el mark-read en bloque al salir).
    /// Solo estos sellan expiración vanish `onceSeen`/timers; «visto al abrir» no debe expirar lo no leído.
    private var sessionSeenIncomingMessageIds = Set<String>()
    // Ids marcados leídos en local cuya escritura al servidor puede no haber aterrizado aún:
    // el eco del listener no debe revivirlos como no leídos (resucitaría el divisor).
    private var locallyReadMessageIds = Set<String>()
    private var seenBuzzEventIds = Set<String>()
    private var historyLoadNoticeTask: Task<Void, Never>?

    @Published var conversation: Conversation
    let currentUserId: String
    let chatService = ChatService.shared
    private let firestoreService = FirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var typingUsersCancellable: AnyCancellable?
    private var typingTimer: Timer?
    private var messageStatusObserver: NSObjectProtocol?
    private var mediaUploadObserver: NSObjectProtocol?

    // ✅ NUEVO: Flag para detectar la primera carga de Firestore (merge-first, sin wipe de caché)
    private var isFirstFetch = true

    enum ChatSessionMode: Equatable {
        case idle
        case active
    }

    private(set) var chatSessionMode: ChatSessionMode = .idle
    private var sessionListenersAttached = false
    private var listenerPauseTask: Task<Void, Never>?
    private var didLoadCacheFromSwiftData = false
    private var requestedHighlightMessageIds = Set<String>()
    private static let listenerPauseTTL: UInt64 = 180_000_000_000

    init(conversation: Conversation) {
        self.conversation = conversation
        self.currentUserId = Auth.auth().currentUser?.uid ?? ""
        self.forwardingPreferences = conversation.forwardingPreferences ?? [:]
        self.buzzPreferences = conversation.buzzPreferences ?? [:]
        self.vanishModeActive = conversation.vanishModeActive ?? false
        self.vanishMessageTimer = VanishMessageTimer(storedValue: conversation.vanishMessageTimer)

        // ✅ Configurar listener para actualizaciones de estado locales
        setupLocalStatusListener()
        setupConversationPreferenceListener()
        setupIngestListener()
        refreshTypingIndicatorPreference()
    }

    // ✅ NUEVA: Configurar listener para actualizaciones de estado locales
    private func setupLocalStatusListener() {
        messageStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MessageStatusUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  let messageId = userInfo["messageId"] as? String,
                  let statusString = userInfo["status"] as? String,
                  let status = MessageStatus(rawValue: statusString),
                  conversationId == self?.conversation.id else {
                return
            }


            // ✅ Usar la nueva función para actualizar el array
            Task { @MainActor [weak self] in
                self?.updateMessageInArray(messageId: messageId, newStatus: status)
            }
        }

        // ✅ Progress Listener
        mediaUploadObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MediaUploadProgress"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let messageId = userInfo["messageId"] as? String,
                  let progress = userInfo["progress"] as? Double else {
                return
            }

            DispatchQueue.main.async {
                self?.setUploadProgress(progress, for: messageId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MediaDownloadProgress"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let messageId = userInfo["messageId"] as? String,
                  let progress = userInfo["progress"] as? Double else {
                return
            }

            Task { @MainActor [weak self] in
                self?.setDownloadProgress(progress, for: messageId)
            }
        }
    }

    private func setupIngestListener() {
        NotificationCenter.default.addObserver(
            forName: .messagesIngested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let conversationId = notification.userInfo?["conversationId"] as? String,
                  conversationId == self.conversation.id else {
                return
            }

            Task { @MainActor [weak self] in
                self?.mergeMessagesFromLocalCache()
            }
        }
    }

    func mergeMessagesFromLocalCache() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }

        let cutoff = effectiveDeletedAtCutoff()
        let recent = LocalPersistenceService.shared.loadRecentMessagesFast(
            conversationId: conversationId,
            limit: 50,
            cutoffDate: cutoff
        )
        guard !recent.isEmpty else { return }

        let knownIds = Set((realTimeMessages + historicalMessages).map(\.id))
        let oldestVisible = historicalMessages.first?.timestamp
            ?? messages.first?.timestamp
            ?? Date.distantPast
        let incoming = recent
            .filter { !knownIds.contains($0.id) && $0.timestamp >= oldestVisible }
            .sorted { $0.timestamp < $1.timestamp }
        guard !incoming.isEmpty else { return }

        historicalMessages.append(contentsOf: incoming)
        historicalMessages.sort { $0.timestamp < $1.timestamp }
        rebuildMessagesList()
        prefetchUnresolvedMediaIfNeeded()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
    }

    private func setupConversationPreferenceListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConversationForwardingPreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  conversationId == self.conversation.id else { return }

            if let userId = userInfo["userId"] as? String,
               let allowsForwarding = userInfo["allowsForwarding"] as? Bool {
                var updated = self.forwardingPreferences
                updated[userId] = allowsForwarding
                self.forwardingPreferences = updated
            } else if let preferences = userInfo["forwardingPreferences"] as? [String: Bool] {
                self.forwardingPreferences = preferences
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConversationBuzzPreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  conversationId == self.conversation.id else { return }

            if let userId = userInfo["userId"] as? String,
               let allowsBuzz = userInfo["allowsBuzz"] as? Bool {
                var updated = self.buzzPreferences
                updated[userId] = allowsBuzz
                self.buzzPreferences = updated
            } else if let preferences = userInfo["buzzPreferences"] as? [String: Bool] {
                self.buzzPreferences = preferences
            }
        }
    }

    var canSendBuzz: Bool {
        ChatMessagePolicy.canSendBuzz(
            participants: conversation.participants,
            currentUserId: currentUserId,
            buzzPreferences: buzzPreferences
        )
    }

    func refreshForwardingPreference() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        let key = "chat_forwarding_enabled_\(conversationId)"
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            var updated = forwardingPreferences
            updated[currentUserId] = stored
            forwardingPreferences = updated
        }
    }

    private func typingIndicatorPreferenceKey(for conversationId: String) -> String {
        "chat_typing_indicator_enabled_\(conversationId)"
    }

    private func resolvedTypingIndicatorPreference(for conversationId: String) -> Bool {
        let defaults = UserDefaults.standard
        let perChatKey = typingIndicatorPreferenceKey(for: conversationId)

        if let perChatValue = defaults.object(forKey: perChatKey) as? Bool {
            return perChatValue
        }

        if let legacyGlobalValue = defaults.object(forKey: "chat_typing_indicator_enabled") as? Bool {
            return legacyGlobalValue
        }

        return true
    }

    private func setupTypingUsersSubscription(conversationId: String) {
        typingUsersCancellable?.cancel()
        typingUsersCancellable = chatService.$typingUsers
            .compactMap { $0[conversationId] }
            .sink { [weak self] typingUsers in
                guard let self = self else { return }

                guard self.typingIndicatorEnabled else {
                    self.typingUsers = []
                    return
                }

                let filteredUsers = typingUsers.filter { $0 != self.currentUserId }
                self.typingUsers = filteredUsers
            }
    }

    private func applyTypingPreference(conversationId: String) {
        if typingIndicatorEnabled {
            chatService.listenToTypingIndicators(conversationId: conversationId)
            setupTypingUsersSubscription(conversationId: conversationId)
        } else {
            typingUsers = []
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
            chatService.removeTypingListener(for: conversationId)
            typingUsersCancellable?.cancel()
            typingUsersCancellable = nil
        }
    }

    func refreshTypingIndicatorPreference() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        typingIndicatorEnabled = resolvedTypingIndicatorPreference(for: conversationId)
        applyTypingPreference(conversationId: conversationId)
    }

    // ✅ NUEVA: Función para preservar mensajes temporales
    private func preserveTemporaryMessages(_ newMessages: [EnhancedMessage]) -> [EnhancedMessage] {
        let temporaryMessages = self.messages.filter { $0.status == .sending }

        var mergedMessages = newMessages

        for tempMessage in temporaryMessages {
            // Solo agregar si NO existe ya en Firestore
            if !mergedMessages.contains(where: { $0.id == tempMessage.id }) {
                mergedMessages.append(tempMessage)
            }
        }

        for (_, tempMessage) in outgoingTempMessages {
            if let index = mergedMessages.firstIndex(where: { $0.id == tempMessage.id }) {
                if let localUrl = tempMessage.mediaUrl,
                   let url = URL(string: localUrl),
                   url.isFileURL,
                   mergedMessages[index].mediaUrl == nil {
                    mergedMessages[index].mediaUrl = localUrl
                }
            } else {
                mergedMessages.append(tempMessage)
            }
        }

        // ✅ CORREGIDO: Solo aplicar estado local si es MÁS AVANZADO que el de Firestore
        // Orden de prioridad: sending < sent < delivered < read
        // No sobrescribir un estado más avanzado con uno menos avanzado
        let statusPriority: [MessageStatus: Int] = [
            .sending: 0,
            .sent: 1,
            .delivered: 2,
            .read: 3,
            .failed: -1
        ]

        for (messageId, localStatus) in localMessageStates {
            if let index = mergedMessages.firstIndex(where: { $0.id == messageId }) {
                let firestoreStatus = mergedMessages[index].status
                let localPriority = statusPriority[localStatus] ?? 0
                let firestorePriority = statusPriority[firestoreStatus] ?? 0

                // Solo aplicar local si es más avanzado O si es failed
                if localPriority > firestorePriority || localStatus == .failed {
                    mergedMessages[index].status = localStatus
                }
            }
        }

        // Conservar URLs locales descifradas (Firestore no las persiste en el snapshot).
        for existing in messages {
            guard let index = mergedMessages.firstIndex(where: { $0.id == existing.id }) else { continue }
            guard !mergedMessages[index].isDeleted, !existing.isDeleted else { continue }

            if let localUrl = existing.mediaUrl,
               let url = URL(string: localUrl),
               url.isFileURL,
               FileManager.default.fileExists(atPath: url.path),
               mergedMessages[index].mediaUrl == nil || mergedMessages[index].hasMissingLocalMedia {
                mergedMessages[index].mediaUrl = localUrl
            }

            if let localThumb = existing.thumbnailUrl,
               let url = URL(string: localThumb),
               url.isFileURL,
               FileManager.default.fileExists(atPath: url.path),
               mergedMessages[index].thumbnailUrl == nil || mergedMessages[index].hasMissingLocalThumbnail {
                mergedMessages[index].thumbnailUrl = localThumb
            }
        }

        // Conservar reacciones en memoria si el snapshot de mensajes llega sin hidratar subcolección.
        for existing in messages {
            guard let index = mergedMessages.firstIndex(where: { $0.id == existing.id }),
                  existing.reactions != nil else { continue }
            mergedMessages[index].reactions = chatService.mergeLegacyAndLiveReactions(
                legacy: existing.reactions,
                live: mergedMessages[index].reactions
            )
        }

        return mergedMessages.sorted { $0.timestamp < $1.timestamp }
    }

    // ✅ NUEVA: Función para actualizar el array de manera que SwiftUI lo detecte
    func updateMessageInArray(messageId: String, newStatus: MessageStatus) {
        applyOutgoingMessageUpdate(messageId: messageId, status: newStatus, mediaUrl: nil, thumbnailUrl: nil)
    }

    func applyOutgoingMessageUpdate(
        messageId: String,
        status: MessageStatus,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        localMessageStates[messageId] = status
        clearUploadProgress(for: messageId)
        outgoingTempMessages.removeValue(forKey: messageId)

        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            if let momentsViewModel = self as? MomentsChatViewModel {
                momentsViewModel.syncMessagePresentation()
            }
            return
        }

        let apply = {
            let message = self.messages[index]
            message.status = status
            if let mediaUrl {
                message.mediaUrl = mediaUrl
            }
            if let thumbnailUrl {
                message.thumbnailUrl = thumbnailUrl
            }
            self.commitMessagesPresentation(self.messages)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func finalizeOutgoingMediaMessage(
        messageId: String,
        sentMessage: EnhancedMessage,
        fallbackMediaUrl: String? = nil,
        fallbackThumbnailUrl: String? = nil
    ) {
        localMessageStates[messageId] = sentMessage.status
        clearUploadProgress(for: messageId)
        outgoingTempMessages.removeValue(forKey: messageId)

        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let previous = messages[index]
        sentMessage.mediaUrl = sentMessage.mediaUrl ?? fallbackMediaUrl ?? previous.mediaUrl
        sentMessage.thumbnailUrl = sentMessage.thumbnailUrl ?? fallbackThumbnailUrl ?? previous.thumbnailUrl
        messages[index] = sentMessage

        commitMessagesPresentation(messages)

        if let conversationId = conversation.id {
            LocalPersistenceService.shared.saveMessages([sentMessage], conversationId: conversationId, sync: false)
        }
    }

    func localOutgoingPreviewURL(
        data: Data,
        conversationId: String,
        messageId: String,
        fileExtension: String
    ) -> String? {
        do {
            let url = try ChatCacheStore.writeDecryptedMedia(
                data,
                conversationId: conversationId,
                messageId: messageId,
                purpose: .primary,
                fileExtension: fileExtension
            )
            return url.absoluteString
        } catch {
            return nil
        }
    }

    func appendOutgoingMessage(_ message: EnhancedMessage) {
        outgoingTempMessages[message.id] = message
        messages.append(message)
        messages = Array(messages)
        objectWillChange.send()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
        if let conversationId = conversation.id,
           message.status == .sending || message.status == .pending || message.status == .failed {
            LocalPersistenceService.shared.saveMessages([message], conversationId: conversationId, sync: false)
        }
    }

    private func messageNeedsMediaHydration(_ message: EnhancedMessage) -> Bool {
        message.isMediaPendingResolution
    }

    func isDownloadingMedia(_ messageId: String) -> Bool {
        downloadingMediaIds.contains(messageId) || hydratingMediaIds.contains(messageId)
    }

    /// Mensajes del cache antiguo pueden carecer de metadata de Storage; re-fetch puntual desde Firestore.
    func refreshMediaMetadataIfNeeded(for message: EnhancedMessage) {
        guard message.type == .image || message.type == .video else { return }
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }

        let missingMain = message.mediaObjectPath == nil || message.mediaEncryption == nil
        let needsThumb = message.type == .video && message.needsVideoThumbnailForDisplay
        let missingThumbMeta = message.thumbnailObjectPath == nil || message.thumbnailEncryption == nil

        if message.type == .image {
            guard missingMain else { return }
        } else if missingMain {
            // Falta metadata del vídeo principal.
        } else if needsThumb && missingThumbMeta {
            // Falta metadata de la miniatura cifrada (p. ej. cache viejo).
        } else {
            if needsThumb { hydrateVideoThumbnailIfNeeded(for: message) }
            return
        }

        let messageId = message.id
        guard refreshingMetadataIds.insert(messageId).inserted else { return }

        chatService.fetchMessage(conversationId: conversationId, messageId: messageId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshingMetadataIds.remove(messageId)
                if case .success(let fresh?) = result {
                    self.applyRefreshedMediaMessage(fresh, conversationId: conversationId)
                }
            }
        }
    }

    private func applyRefreshedMediaMessage(_ fresh: EnhancedMessage, conversationId: String) {
        if let index = historicalMessages.firstIndex(where: { $0.id == fresh.id }) {
            historicalMessages[index] = fresh
        }
        if let index = realTimeMessages.firstIndex(where: { $0.id == fresh.id }) {
            realTimeMessages[index] = fresh
        }
        rebuildMessagesList()
        LocalPersistenceService.shared.saveMessages([fresh], conversationId: conversationId, sync: false)
        if let updated = messages.first(where: { $0.id == fresh.id }) {
            if updated.type == .video {
                hydrateVideoThumbnailIfNeeded(for: updated)
            } else {
                hydrateMediaIfNeeded(for: updated)
            }
        }
    }

    func hydrateMediaIfNeeded(for message: EnhancedMessage) {
        if message.isMediaAwaitingManualDownload {
            hydrateThumbnailPreviewIfNeeded(for: message)
            return
        }

        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }

        // Para vídeos resolvemos solo la miniatura (barato). El vídeo completo se
        // descarga al abrirlo, evitando bajar megas solo para mostrar la portada.
        if message.type == .video {
            hydrateVideoThumbnailIfNeeded(for: message)
            return
        }
        guard messageNeedsMediaHydration(message) else {
            if message.type == .image,
               message.mediaUrl == nil,
               message.mediaObjectPath == nil || message.mediaEncryption == nil {
                refreshMediaMetadataIfNeeded(for: message)
            }
            return
        }
        guard !hydratingMediaIds.contains(message.id) else { return }
        hydratingMediaIds.insert(message.id)
        setDownloadProgress(0.03, for: message.id)
        prepareMediaForViewing(message, forceDownload: false) { [weak self] _ in
            self?.hydratingMediaIds.remove(message.id)
            self?.clearDownloadProgress(for: message.id)
        }
    }

    func hydrateVideoThumbnailIfNeeded(for message: EnhancedMessage) {
        guard message.type == .video else { return }
        guard message.needsVideoThumbnailForDisplay else { return }
        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }

        // Caso 1: hay miniatura cifrada en Storage. Resolverla sola es barato.
        if message.thumbnailObjectPath != nil, message.thumbnailEncryption != nil {
            let thumbnailKey = "thumb_\(message.id)"
            guard !hydratingMediaIds.contains(thumbnailKey) else { return }
            hydratingMediaIds.insert(thumbnailKey)
            Task { [weak self] in
                guard let self else { return }
                let resolvedThumb = await self.chatService.resolveVideoThumbnail(for: message, forceDownload: false)
                await MainActor.run {
                    self.hydratingMediaIds.remove(thumbnailKey)
                    guard let resolvedThumb,
                          let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
                        return
                    }
                    self.messages[index].thumbnailUrl = resolvedThumb
                    if let conversationId = self.conversation.id {
                        LocalPersistenceService.shared.saveMessages([self.messages[index]], conversationId: conversationId, sync: false)
                    }
                }
            }
            return
        }

        // Caso 2: vídeo ya disponible local/remoto → generar poster sin bajar el .mp4 completo.
        if let mediaUrl = message.mediaUrl, URL(string: mediaUrl) != nil {
            generateVideoPosterIfPossible(for: message)
            return
        }

        // Caso 3: solo tenemos el vídeo cifrado → descargar y luego generar poster.
        if message.mediaObjectPath != nil, message.mediaEncryption != nil {
            guard !hydratingMediaIds.contains(message.id) else { return }
            hydratingMediaIds.insert(message.id)
            setDownloadProgress(0.03, for: message.id)
            prepareMediaForViewing(message, forceDownload: false) { [weak self] updated in
                self?.hydratingMediaIds.remove(message.id)
                self?.clearDownloadProgress(for: message.id)
                self?.generateVideoPosterIfPossible(for: updated)
            }
            return
        }

        refreshMediaMetadataIfNeeded(for: message)
    }

    /// Descarga solo la miniatura cifrada (~KB) para preview borroso.
    func hydrateThumbnailPreviewIfNeeded(for message: EnhancedMessage) {
        guard message.thumbnailObjectPath != nil, message.thumbnailEncryption != nil else { return }
        if let urlString = message.thumbnailUrl,
           let url = URL(string: urlString),
           message.localMediaFileIsReachable(url) {
            return
        }

        let previewKey = "thumb_preview_\(message.id)"
        guard !hydratingMediaIds.contains(previewKey) else { return }
        hydratingMediaIds.insert(previewKey)

        Task { [weak self] in
            guard let self else { return }
            let resolvedThumb = await self.chatService.resolveVideoThumbnail(for: message, forceDownload: false)
            await MainActor.run {
                self.hydratingMediaIds.remove(previewKey)
                guard let resolvedThumb,
                      let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
                    return
                }
                self.messages[index].thumbnailUrl = resolvedThumb
                if message.type == .image || message.type == .ephemeral || message.type == .viewOnceImage {
                    // Las imágenes usan thumbnailUrl como preview borroso; primary queda para el tap.
                }
                if let conversationId = self.conversation.id {
                    LocalPersistenceService.shared.saveMessages([self.messages[index]], conversationId: conversationId, sync: false)
                }
            }
        }
    }

    private func generateVideoPosterIfPossible(for message: EnhancedMessage) {
        guard message.needsVideoThumbnailForDisplay,
              let mediaUrl = message.mediaUrl,
              let url = URL(string: mediaUrl) else { return }
        let posterKey = "poster_\(message.id)"
        guard !hydratingMediaIds.contains(posterKey) else { return }
        hydratingMediaIds.insert(posterKey)
        Task { [weak self] in
            let poster = await ChatVideoPosterGenerator.poster(for: url, messageId: message.id)
            await MainActor.run {
                guard let self else { return }
                self.hydratingMediaIds.remove(posterKey)
                guard let poster,
                      let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
                    return
                }
                self.messages[index].thumbnailUrl = poster
                if let conversationId = self.conversation.id {
                    LocalPersistenceService.shared.saveMessages([self.messages[index]], conversationId: conversationId, sync: false)
                }
            }
        }
    }

    /// Precalienta la galería del cluster: caché en disco → URLs locales al instante,
    /// hidratación en paralelo para lo que falte, y prefetch de Kingfisher.
    func prefetchClusterGalleryMedia(_ clusterMessages: [EnhancedMessage]) {
        var didUpdate = false

        for clusterMessage in clusterMessages {
            guard let index = messages.firstIndex(where: { $0.id == clusterMessage.id }) else {
                refreshMediaMetadataIfNeeded(for: clusterMessage)
                hydrateMediaIfNeeded(for: clusterMessage)
                continue
            }

            if messages[index].mediaObjectPath == nil || messages[index].mediaEncryption == nil {
                refreshMediaMetadataIfNeeded(for: messages[index])
            }

            let warmed = chatService.warmMessageURLsFromDiskCache(messages[index])
            if let mediaUrl = warmed.mediaUrl,
               messages[index].mediaUrl != mediaUrl || messages[index].hasMissingLocalMedia {
                messages[index].mediaUrl = mediaUrl
                didUpdate = true
            }
            if let thumbnailUrl = warmed.thumbnailUrl,
               messages[index].thumbnailUrl != thumbnailUrl || messages[index].hasMissingLocalThumbnail {
                messages[index].thumbnailUrl = thumbnailUrl
                didUpdate = true
            }
            if messages[index].type == .video {
                if ChatMediaDownloadPolicy.shouldDownloadAutomatically() {
                    hydrateVideoThumbnailIfNeeded(for: messages[index])
                }
            } else if ChatMediaDownloadPolicy.shouldDownloadAutomatically() {
                hydrateMediaIfNeeded(for: messages[index])
            }
        }

        if didUpdate, let conversationId = conversation.id {
            LocalPersistenceService.shared.saveMessages(
                clusterMessages.compactMap { m in messages.first(where: { $0.id == m.id }) },
                conversationId: conversationId,
                sync: false
            )
        }

        ChatMediaGalleryPrefetcher.prefetch(messages: clusterMessages)
    }

    /// Re-enlaza URLs locales desde disco y persiste cambios en SwiftData.
    func warmAndApplyDiskURLs(to messages: inout [EnhancedMessage]) -> [EnhancedMessage] {
        var updated: [EnhancedMessage] = []

        for index in messages.indices {
            guard !messages[index].isDeleted else { continue }
            let warmed = chatService.warmMessageURLsFromDiskCache(messages[index])
            var changed = false

            if let mediaUrl = warmed.mediaUrl,
               messages[index].mediaUrl != mediaUrl || messages[index].hasMissingLocalMedia {
                messages[index].mediaUrl = mediaUrl
                changed = true
            }
            if let thumbnailUrl = warmed.thumbnailUrl,
               messages[index].thumbnailUrl != thumbnailUrl || messages[index].hasMissingLocalThumbnail {
                messages[index].thumbnailUrl = thumbnailUrl
                changed = true
            }

            if changed {
                updated.append(messages[index])
            }
        }

        return updated
    }

    private func applyWarmedMessagesFromDisk(_ warmed: [EnhancedMessage]) {
        guard !warmed.isEmpty else { return }
        let byId = Dictionary(uniqueKeysWithValues: warmed.map { ($0.id, $0) })
        var didChange = false

        func patch(_ message: inout EnhancedMessage) {
            guard let source = byId[message.id] else { return }
            if message.mediaUrl != source.mediaUrl {
                message.mediaUrl = source.mediaUrl
                didChange = true
            }
            if message.thumbnailUrl != source.thumbnailUrl {
                message.thumbnailUrl = source.thumbnailUrl
                didChange = true
            }
        }

        for index in historicalMessages.indices {
            patch(&historicalMessages[index])
        }
        for index in realTimeMessages.indices {
            patch(&realTimeMessages[index])
        }

        guard didChange else { return }
        rebuildMessagesList()
        prefetchUnresolvedMediaIfNeeded()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
    }

    private func scheduleAsyncDiskURLWarm() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        LocalPersistenceService.shared.scheduleWarmDiskMediaURLs(conversationId: conversationId) { [weak self] warmed in
            self?.applyWarmedMessagesFromDisk(warmed)
        }
    }

    /// Re-enlaza `file://` desde ChatCacheStore cuando el snapshot de Firestore no trae URLs locales.
    private func persistDiskCachedMediaURLs(into messages: inout [EnhancedMessage]) {
        let updated = warmAndApplyDiskURLs(to: &messages)
        guard !updated.isEmpty, let conversationId = conversation.id else { return }
        LocalPersistenceService.shared.saveMessages(updated, conversationId: conversationId, sync: false)
    }

    /// Hidrata media cifrada o pendiente de resolver (imagen, video, GIF/sticker legacy).
    func prefetchUnresolvedMediaIfNeeded() {
        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }
        for message in messages where messageNeedsMediaHydration(message) {
            hydrateMediaIfNeeded(for: message)
        }
        for message in messages where message.type == .gif || message.type == .sticker {
            guard let urlString = message.mediaUrl,
                  let url = URL(string: urlString),
                  !url.isFileURL else { continue }
            ChatGIFImageCache.shared.prefetch(url: url)
        }
    }

    /// Descarga manual (tap) o auto (policy) y abre el visor cuando la media ya está lista.
    func openMediaForViewing(_ message: EnhancedMessage, completion: @escaping (EnhancedMessage) -> Void) {
        guard message.needsDownloadForPlayback else {
            completion(message)
            return
        }

        guard !downloadingMediaIds.contains(message.id) else { return }
        downloadingMediaIds.insert(message.id)
        setDownloadProgress(0.03, for: message.id)
        prepareMediaForViewing(message, forceDownload: true) { [weak self] updated in
            self?.downloadingMediaIds.remove(message.id)
            self?.clearDownloadProgress(for: message.id)
            completion(updated)
        }
    }

    /// Tras reinstalar o sin caché local: descarga el `.enc`, descifra y actualiza el mensaje en la lista.
    func prepareMediaForViewing(
        _ message: EnhancedMessage,
        forceDownload: Bool = true,
        completion: @escaping (EnhancedMessage) -> Void
    ) {
        if message.hasLocalMediaReadyForViewer, !message.hasMissingLocalMedia {
            completion(message)
            return
        }

        if (message.type == .gif || message.type == .sticker),
           message.hasMissingLocalMedia,
           message.mediaObjectPath == nil {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].mediaUrl = nil
            }
            completion(messages.first(where: { $0.id == message.id }) ?? message)
            return
        }

        guard message.mediaObjectPath != nil, message.mediaEncryption != nil else {
            completion(message)
            return
        }

        Task {
            defer {
                Task { @MainActor in
                    clearDownloadProgress(for: message.id)
                }
            }

            guard let (mediaUrl, thumbnailUrl) = await chatService.resolveEncryptedMediaForMessage(message, forceDownload: forceDownload) else {
                await MainActor.run { completion(message) }
                return
            }
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].mediaUrl = mediaUrl
                    if let thumbnailUrl {
                        messages[index].thumbnailUrl = thumbnailUrl
                    }
                    if let conversationId = conversation.id {
                        LocalPersistenceService.shared.saveMessages([messages[index]], conversationId: conversationId, sync: false)
                    }
                }
                let updated = messages.first(where: { $0.id == message.id }) ?? message
                completion(updated)
            }
        }
    }

    private func rebuildMessagesList() {
        // 1. Unir real-time + históricos (PRIORIDAD AL REAL-TIME para cambios de estado)
        let allMessages = messagesRespectingDeletionCutoff(realTimeMessages + historicalMessages)
            .filter { !hiddenForMeMessageIds.contains($0.id) }
            .filter { !isVanishMessageHiddenFromCurrentUser($0) }

        // 2. Deduplicar por ID (se queda con el primero que encuentre, que ahora es el real-time)
        var seenIds = Set<String>()
        let uniqueMessages = allMessages.filter { seenIds.insert($0.id).inserted }

        // 3. Ordenar
        let sortedMessages = uniqueMessages.sorted { $0.timestamp < $1.timestamp }

        // 4. Preservar temporales y estados locales
        var finalMessages = preserveTemporaryMessages(sortedMessages)
        for message in finalMessages {
            preserveLocalReadState(into: message)
        }
        persistDiskCachedMediaURLs(into: &finalMessages)
        commitMessagesPresentation(finalMessages)
        syncLiveReactionOverlays(from: finalMessages)

        for id in Array(outgoingTempMessages.keys) {
            if let msg = finalMessages.first(where: { $0.id == id }), msg.status != .sending {
                outgoingTempMessages.removeValue(forKey: id)
            }
        }
    }

    /// Punto de corte tras borrar conversación: modelo local o mapa en memoria de ChatService.
    private func effectiveDeletedAtCutoff() -> Date? {
        if let cutoff = conversation.deletedAtCutoff(for: currentUserId) {
            return cutoff
        }
        guard let conversationId = conversation.id else { return nil }
        return chatService.deletedAtCutoff(for: conversationId)
    }

    private func messagesRespectingDeletionCutoff(_ messages: [EnhancedMessage]) -> [EnhancedMessage] {
        guard let cutoff = effectiveDeletedAtCutoff() else { return messages }
        return messages.filter { $0.timestamp > cutoff }
    }

    private func isVanishMessageHiddenFromCurrentUser(_ message: EnhancedMessage) -> Bool {
        guard message.isVanishModeMessage == true else { return false }
        if optimisticallyHiddenVanishIds.contains(message.id) { return true }
        if VanishMessageTimer.isExpired(message.vanishExpiresAt) { return true }
        return message.isVanished(forUserId: currentUserId)
    }

    private func commitReactionPresentation(conversationId: String? = nil) {
        messages = Array(messages)
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
        if let conversationId = conversationId ?? conversation.id, !conversationId.isEmpty {
            LocalPersistenceService.shared.saveMessages(messages, conversationId: conversationId)
        }
    }

    func displayReactions(for messageId: String) -> [String: [String]]? {
        if let overlay = liveReactionOverlays[messageId] {
            return overlay
        }
        return messages.first(where: { $0.id == messageId })?.reactions
    }

    private func syncLiveReactionOverlays(from messages: [EnhancedMessage]) {
        var overlays = liveReactionOverlays
        for message in messages {
            guard let reactions = message.reactions, !reactions.isEmpty else { continue }
            overlays[message.id] = chatService.mergeLegacyAndLiveReactions(
                legacy: overlays[message.id],
                live: reactions
            ) ?? reactions
        }
        liveReactionOverlays = overlays
    }

    private func setLiveReactions(_ reactions: [String: [String]]?, for messageId: String) {
        var overlays = liveReactionOverlays
        if let reactions, !reactions.isEmpty {
            overlays[messageId] = reactions
        } else {
            overlays.removeValue(forKey: messageId)
        }
        liveReactionOverlays = overlays

        mutateReactionState(for: messageId) { message in
            message.reactions = reactions
        }
        commitReactionPresentation()
    }

    private func mutateReactionState(
        for messageId: String,
        _ transform: (EnhancedMessage) -> Void
    ) {
        for message in realTimeMessages where message.id == messageId {
            transform(message)
        }
        for message in historicalMessages where message.id == messageId {
            transform(message)
        }
        if let outgoingMessage = outgoingTempMessages[messageId] {
            transform(outgoingMessage)
            outgoingTempMessages[messageId] = outgoingMessage
        }
        for message in messages where message.id == messageId {
            transform(message)
        }
    }

    private var hasReceivedInitialReactionSnapshot = false

    private func applyReactionUpdate(_ update: MessageReactionUpdate, conversationId: String) {
        let affectedIds = update.changedMessageIds.union(update.reactionsByMessage.keys)
        guard !affectedIds.isEmpty else { return }

        var overlays = liveReactionOverlays
        for messageId in affectedIds {
            let liveReactions = update.reactionsByMessage[messageId]
            mutateReactionState(for: messageId) { message in
                message.reactions = liveReactions
            }
            if let liveReactions, !liveReactions.isEmpty {
                overlays[messageId] = liveReactions
            } else {
                overlays.removeValue(forKey: messageId)
            }
        }

        if hasReceivedInitialReactionSnapshot {
            for messageId in update.changedMessageIds {
                guard
                    let message = messages.first(where: { $0.id == messageId }),
                    message.senderId == currentUserId,
                    let liveReactions = update.reactionsByMessage[messageId],
                    !liveReactions.isEmpty,
                    reactionIncludesOtherParticipant(liveReactions)
                else { continue }

                NotificationCenter.default.post(
                    name: .chatMessageReactionHighlight,
                    object: nil,
                    userInfo: [
                        "conversationId": conversationId,
                        "messageId": messageId
                    ]
                )
            }
        }
        hasReceivedInitialReactionSnapshot = true
        liveReactionOverlays = overlays

        commitReactionPresentation(conversationId: conversationId)
    }

    private func reactionIncludesOtherParticipant(_ reactions: [String: [String]]) -> Bool {
        reactions.values.contains { userIds in
            userIds.contains { $0 != currentUserId }
        }
    }

    // ✅ FUNCIÓN: Cargar más mensajes (SwiftData primero, luego Firestore)
    func loadMoreMessages() {
        guard !isLoadingMore, canLoadMore, let conversationId = conversation.id, let oldest = messages.first else {
            return
        }

        isLoadingMore = true
        isLoadingOlderHistory = true
        historyLoadNoticeTask?.cancel()
        historyLoadNotice = .hidden

        let cutoff = effectiveDeletedAtCutoff()
        let pageSize = Self.historyPageSize
        let cursor = MessageSyncCursor(timestamp: oldest.timestamp, messageId: oldest.id)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()

            let localPage = LocalPersistenceService.shared.loadMessagesBefore(
                conversationId: conversationId,
                cursor: cursor,
                cutoffDate: cutoff,
                limit: pageSize
            )

            if !localPage.isEmpty {

                self.prependHistoryPage(localPage)
                self.finishHistoryLoad(canLoadMore: true)
                return
            }

            guard NetworkMonitor.shared.isConnected else {
                self.historyLoadNotice = .offline
                self.finishHistoryLoad(canLoadMore: self.canLoadMore)
                self.endHistoryScrollRestoration()
                return
            }

            self.historyLoadNoticeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard let self, self.isLoadingOlderHistory else { return }
                self.historyLoadNotice = .loadingRemote
            }

            do {
                let olderMessages = try await self.fetchOlderMessagesFromFirestore(
                    conversationId: conversationId,
                    before: oldest.timestamp,
                    cutoffDate: cutoff,
                    limit: pageSize
                )

                let existingIds = Set((self.historicalMessages + self.realTimeMessages).map(\.id))
                let novel = olderMessages
                    .filter { !existingIds.contains($0.id) }
                    .sorted { $0.timestamp < $1.timestamp }

                if !novel.isEmpty {

                    self.prependHistoryPage(novel)
                    LocalPersistenceService.shared.appendMessages(novel, conversationId: conversationId)
                }

                let hasMore = olderMessages.count >= pageSize
                self.finishHistoryLoad(canLoadMore: hasMore)
                if novel.isEmpty {
                    self.endHistoryScrollRestoration()
                }
            } catch {
                self.historyLoadNotice = .error
                self.finishHistoryLoad(canLoadMore: self.canLoadMore)
                self.endHistoryScrollRestoration()
            }
        }
    }

    private func prependHistoryPage(_ page: [EnhancedMessage]) {
        guard !page.isEmpty else { return }
        let existingIds = Set((historicalMessages + realTimeMessages).map(\.id))
        let novel = page.filter { !existingIds.contains($0.id) }
        guard !novel.isEmpty else {
            return
        }
        historicalMessages.insert(contentsOf: novel, at: 0)
        rebuildMessagesList()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.prefetchUnresolvedMediaIfNeeded()
        }
    }

    private func finishHistoryLoad(canLoadMore: Bool) {
        self.canLoadMore = canLoadMore
        isLoadingMore = false
    }

    /// La vista llama esto cuando el scroll quedó re-anclado tras prepend.
    func endHistoryScrollRestoration() {
        historyLoadNoticeTask?.cancel()
        isLoadingOlderHistory = false
        if historyLoadNotice == .loadingRemote {
            historyLoadNotice = .hidden
        }
    }

    func clearHistoryLoadNotice() {
        historyLoadNoticeTask?.cancel()
        historyLoadNotice = .hidden
    }

    private func fetchOlderMessagesFromFirestore(
        conversationId: String,
        before timestamp: Date,
        cutoffDate: Date?,
        limit: Int
    ) async throws -> [EnhancedMessage] {
        try await withCheckedThrowingContinuation { continuation in
            chatService.fetchOlderMessages(
                conversationId: conversationId,
                before: timestamp,
                cutoffDate: cutoffDate,
                limit: limit
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func fetchMessagesAfterFromFirestore(
        conversationId: String,
        after cursor: MessageSyncCursor,
        cutoffDate: Date?,
        limit: Int
    ) async throws -> [EnhancedMessage] {
        try await withCheckedThrowingContinuation { continuation in
            chatService.fetchMessagesAfter(
                conversationId: conversationId,
                after: cursor,
                cutoffDate: cutoffDate,
                limit: limit
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func fetchMessageFromFirestore(
        conversationId: String,
        messageId: String
    ) async throws -> EnhancedMessage? {
        try await withCheckedThrowingContinuation { continuation in
            chatService.fetchMessage(conversationId: conversationId, messageId: messageId) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func initialWindowSize() -> Int {
        let days = Calendar.current.dateComponents([.day], from: conversation.timestamp, to: Date()).day ?? 0
        return days > Self.staleChatThresholdDays ? Self.staleChatWindowSize : Self.recentChatWindowSize
    }

    @discardableResult
    func navigateToMessage(messageId: String) async -> Bool {
        guard !messageId.isEmpty else { return false }
        if messages.contains(where: { $0.id == messageId }) {
            ChatScrollDebug.log("navigateToMessage: already in messages")
            return true
        }
        guard let conversationId = conversation.id else {
            ChatScrollDebug.log("navigateToMessage: no conversationId")
            return false
        }
        guard requestedHighlightMessageIds.insert(messageId).inserted else {
            ChatScrollDebug.log("navigateToMessage: deduped in-flight")
            return messages.contains(where: { $0.id == messageId })
        }
        defer { requestedHighlightMessageIds.remove(messageId) }

        ChatScrollDebug.log("navigateToMessage: loading window for \(messageId)")

        let cutoff = effectiveDeletedAtCutoff()
        let radius = Self.navigationWindowRadius

        let anchor: EnhancedMessage
        if let cached = (historicalMessages + realTimeMessages).first(where: { $0.id == messageId }) {
            anchor = cached
        } else if let local = LocalPersistenceService.shared.loadMessagesFast(conversationId: conversationId)
            .first(where: { $0.id == messageId }) {
            anchor = local
        } else {
            do {
                guard let fetched = try await fetchMessageFromFirestore(
                    conversationId: conversationId,
                    messageId: messageId
                ) else {
                    return false
                }
                anchor = fetched
                LocalPersistenceService.shared.appendMessages([fetched], conversationId: conversationId)
            } catch {
                print("Error loading navigation anchor message: \(error)")
                return false
            }
        }

        let cursor = MessageSyncCursor(timestamp: anchor.timestamp, messageId: anchor.id)
        var window = mergeNavigationWindow(
            before: LocalPersistenceService.shared.loadMessagesBefore(
                conversationId: conversationId,
                cursor: cursor,
                cutoffDate: cutoff,
                limit: radius
            ),
            anchor: anchor,
            after: LocalPersistenceService.shared.loadMessagesAfter(
                conversationId: conversationId,
                cursor: cursor,
                cutoffDate: cutoff,
                limit: radius + 1
            )
        )

        let expectedWindowCount = (radius * 2) + 1
        let needsRemoteWindow = window.count < expectedWindowCount
            || !window.contains(where: { $0.id == messageId })

        var reachedStartOfHistory: Bool?

        if needsRemoteWindow, NetworkMonitor.shared.isConnected {
            do {
                async let older = fetchOlderMessagesFromFirestore(
                    conversationId: conversationId,
                    before: anchor.timestamp,
                    cutoffDate: cutoff,
                    limit: radius
                )
                async let newer = fetchMessagesAfterFromFirestore(
                    conversationId: conversationId,
                    after: cursor,
                    cutoffDate: cutoff,
                    limit: radius
                )
                let remoteBefore = try await older
                let remoteAfter = try await newer
                reachedStartOfHistory = remoteBefore.count < radius
                window = mergeNavigationWindow(
                    before: remoteBefore,
                    anchor: anchor,
                    after: remoteAfter
                )
                if !window.isEmpty {
                    LocalPersistenceService.shared.appendMessages(window, conversationId: conversationId)
                }
            } catch {
                print("Error loading navigation window: \(error)")
            }
        }

        guard window.contains(where: { $0.id == messageId }) else {
            ChatScrollDebug.log("navigateToMessage: window missing target (window=\(window.count))")
            return false
        }
        applyMessageNavigationWindow(window, anchorMessageId: messageId, reachedStartOfHistory: reachedStartOfHistory)
        let success = messages.contains(where: { $0.id == messageId })
        ChatScrollDebug.log("navigateToMessage: applied window=\(window.count) success=\(success)")
        return success
    }

    private func mergeNavigationWindow(
        before: [EnhancedMessage],
        anchor: EnhancedMessage,
        after: [EnhancedMessage]
    ) -> [EnhancedMessage] {
        var seen = Set<String>()
        var merged: [EnhancedMessage] = []
        merged.reserveCapacity(before.count + after.count + 1)
        for message in (before + [anchor] + after) where seen.insert(message.id).inserted {
            merged.append(message)
        }
        return merged.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }

    private func applyMessageNavigationWindow(
        _ window: [EnhancedMessage],
        anchorMessageId: String,
        reachedStartOfHistory: Bool?
    ) {
        let sorted = window.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
        guard let lastInWindow = sorted.last else { return }

        let windowIds = Set(sorted.map(\.id))
        let windowEnd = MessageSyncCursor(timestamp: lastInWindow.timestamp, messageId: lastInWindow.id)

        historicalMessages = sorted
        realTimeMessages = realTimeMessages.filter { message in
            if windowIds.contains(message.id) { return false }
            return MessageSyncCursor(timestamp: message.timestamp, messageId: message.id).isAfter(windowEnd)
        }

        forcedNextTimelineMutation = ChatTimelineMutation(
            kind: .jump,
            reason: .highlight,
            anchorMessageId: anchorMessageId
        )
        canLoadMore = !(reachedStartOfHistory ?? false)
        rebuildMessagesList()
    }

    // MARK: - Lifecycle

    func loadCachedMessagesIfNeeded() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        guard !didLoadCacheFromSwiftData else { return }
        didLoadCacheFromSwiftData = true

        let cutoff = effectiveDeletedAtCutoff()
        let windowSize = initialWindowSize()
        let scanLimit = max(windowSize, 50)
        var recentMessages = LocalPersistenceService.shared.loadRecentMessagesFast(
            conversationId: conversationId,
            limit: scanLimit,
            cutoffDate: cutoff
        )

        if conversation.readStatus[currentUserId] == true {
            let hasUnreadIncoming = recentMessages.contains {
                $0.senderId != currentUserId && !$0.isRead
            }
            if !hasUnreadIncoming {
                LocalPersistenceService.shared.markConversationReadLocally(
                    conversationId: conversationId,
                    currentUserId: currentUserId
                )
                recentMessages = recentMessages.map { message in
                    guard message.senderId != currentUserId, !message.isRead else { return message }
                    var updated = message
                    updated.isRead = true
                    return updated
                }
            }
        }

        for message in recentMessages where message.senderId == currentUserId {
            switch message.status {
            case .sending, .pending, .failed:
                outgoingTempMessages[message.id] = message
            default:
                break
            }
        }

        guard !recentMessages.isEmpty else { return }

        historicalMessages = Array(recentMessages.suffix(windowSize))
        hydrateLocallyHiddenVanishMessages(from: recentMessages)
        rebuildMessagesList()
        syncLiveReactionOverlays(from: messages)
        prefetchUnresolvedMediaIfNeeded()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
        scheduleAsyncDiskURLWarm()
    }

    private func existingMessagesById() -> [String: EnhancedMessage] {
        var map: [String: EnhancedMessage] = [:]
        for message in historicalMessages { map[message.id] = message }
        for message in realTimeMessages { map[message.id] = message }
        return map
    }

    /// Aplica la ventana en vivo de Firestore preservando media local ya resuelta (local-first).
    private func applyFirestoreListenerMessages(_ messages: [EnhancedMessage], conversationId: String) {
        let newSet = Set(messages.map(\.id))
        let droppedMessages = realTimeMessages.filter { !newSet.contains($0.id) }

        if !droppedMessages.isEmpty {
            // Mensajes vanish que desaparecen del snapshot = borrados server-side (purga/expiración).
            // NO promoverlos a histórico (reaparecerían): se eliminan de verdad localmente.
            let droppedVanishIds = droppedMessages
                .filter { $0.isVanishModeMessage == true && $0.type != .chatNotice }
                .map(\.id)
            if !droppedVanishIds.isEmpty {
                optimisticallyHiddenVanishIds.formUnion(droppedVanishIds)
                for id in droppedVanishIds {
                    outgoingTempMessages.removeValue(forKey: id)
                }
                chatService.purgeVanishMessagesLocally(conversationId: conversationId, messageIds: droppedVanishIds)
            }

            let droppedVanishIdSet = Set(droppedVanishIds)
            let promotable = messagesRespectingDeletionCutoff(droppedMessages)
                .filter { !droppedVanishIdSet.contains($0.id) }
            let existingIds = Set(
                (historicalMessages + realTimeMessages).map(\.id)
            )
            historicalMessages.append(contentsOf: promotable.filter { !existingIds.contains($0.id) })
        }

        let existingById = existingMessagesById()

        if LocalFirstMessagingSettings.isEnabled {
            realTimeMessages = messages.map { incoming in
                preserveLocalMediaFields(from: existingById[incoming.id], into: incoming)
                return incoming
            }
        } else {
            realTimeMessages = messages
        }

        let realtimeIds = Set(realTimeMessages.map(\.id))
        historicalMessages.removeAll { realtimeIds.contains($0.id) }

        rebuildMessagesList()
        prefetchUnresolvedMediaIfNeeded()
        LocalPersistenceService.shared.reconcileMessages(realTimeMessages, conversationId: conversationId)
        stampVanishExpiryIfNeeded()
        isFirstFetch = false
    }

    // `readBy` incluye al lector aunque tenga los acuses de lectura desactivados (en ese caso
    // el servidor nunca escribe `isRead`), así que también cuenta como leído para este usuario.
    // `lastReadAt` sanea datos antiguos: mensajes anteriores al último "leído" de la conversación
    // cuentan como leídos aunque el doc individual quedara sin marcar.
    private func preserveLocalReadState(into incoming: EnhancedMessage) {
        guard !incoming.isRead, incoming.senderId != currentUserId else { return }
        if locallyReadMessageIds.contains(incoming.id) || incoming.readBy?.contains(currentUserId) == true {
            incoming.isRead = true
            return
        }
        if let lastRead = conversation.lastReadAt?[currentUserId], incoming.timestamp <= lastRead {
            incoming.isRead = true
        }
    }

    private func preserveLocalMediaFields(from existing: EnhancedMessage?, into incoming: EnhancedMessage) {
        guard let existing else { return }
        if incoming.mediaUrl == nil || incoming.hasMissingLocalMedia,
           let mediaUrl = existing.mediaUrl,
           !existing.hasMissingLocalMedia {
            incoming.mediaUrl = mediaUrl
        }
        if incoming.thumbnailUrl == nil || incoming.hasMissingLocalThumbnail,
           let thumbnailUrl = existing.thumbnailUrl,
           !existing.hasMissingLocalThumbnail {
            incoming.thumbnailUrl = thumbnailUrl
        }
        if let vanishedFor = existing.vanishedFor, !vanishedFor.isEmpty {
            incoming.vanishedFor = Array(Set((incoming.vanishedFor ?? []) + vanishedFor))
        }
        if optimisticallyHiddenVanishIds.contains(incoming.id) {
            var vanished = incoming.vanishedFor ?? []
            if !vanished.contains(currentUserId) {
                vanished.append(currentUserId)
            }
            incoming.vanishedFor = vanished
        }
    }

    func attachChatListenersIfNeeded() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            self.error = "ID de conversación no válido"
            return
        }
        guard !sessionListenersAttached else { return }
        sessionListenersAttached = true

        cancellables.removeAll()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil

        let cutoff = effectiveDeletedAtCutoff()
        chatService.listenToMessages(
            conversationId: conversationId,
            cutoffDate: cutoff,
            replaceExisting: false
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let messages):
                    self.applyFirestoreListenerMessages(messages, conversationId: conversationId)
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }

        chatService.listenToMessageReactions(conversationId: conversationId, replaceExisting: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let update):
                    self.applyReactionUpdate(update, conversationId: conversationId)
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }

        chatService.listenToConversationForwardingPreferences(conversationId: conversationId, replaceExisting: false) { [weak self] forwarding, buzz, vanishActive, timer in
            DispatchQueue.main.async {
                guard let self else { return }
                self.forwardingPreferences = forwarding
                self.buzzPreferences = buzz
                let wasVanishActive = self.vanishModeActive
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    self.vanishModeActive = vanishActive
                }
                self.conversation.vanishModeActive = vanishActive
                self.vanishMessageTimer = timer
                // Desactivación remota (el peer apagó vanish): purgar local para que ambos extremos
                // borren de verdad, sin depender solo del trigger de Cloud Functions.
                if wasVanishActive && !vanishActive {
                    self.purgeVanishMessagesLocally()
                }
                if let conversationId = self.conversation.id {
                    NotificationCenter.default.post(
                        name: .conversationVanishModeDidChange,
                        object: nil,
                        userInfo: [
                            "conversationId": conversationId,
                            "vanishModeActive": vanishActive
                        ]
                    )
                }
            }
        }

        chatService.listenToBuzzEvents(
            conversationId: conversationId,
            cutoffDate: effectiveDeletedAtCutoff(),
            replaceExisting: false
        ) { [weak self] event, isInitialSnapshot in
            Task { @MainActor in
                guard let self else { return }
                // Respetar preferencias del receptor también in-app (no solo en el push):
                // si el usuario actual desactivó zumbidos, no shake ni fila en timeline.
                let isIncoming = event.senderId != self.currentUserId
                if isIncoming, self.buzzPreferences[self.currentUserId] == false {
                    self.seenBuzzEventIds.insert(event.id)
                    return
                }
                guard self.seenBuzzEventIds.insert(event.id).inserted else { return }
                self.buzzEvents.append(event)
                self.buzzEvents.sort { $0.createdAt < $1.createdAt }
                if let momentsViewModel = self as? MomentsChatViewModel {
                    momentsViewModel.syncMessagePresentation()
                }
                if !isInitialSnapshot {
                    self.latestBuzzEvent = event
                }
            }
        }

        typingIndicatorEnabled = resolvedTypingIndicatorPreference(for: conversationId)
        applyTypingPreference(conversationId: conversationId)
    }

    /// La sesión se cachea en ChatSessionEngine: al reutilizarla hay que traer el `lastReadAt`
    /// fresco de la lista para que el saneado de leídos no trabaje con datos viejos.
    func mergeConversationReadMetadata(from fresh: Conversation) {
        guard let freshId = fresh.id, freshId == conversation.id else { return }
        if let lastReadAt = fresh.lastReadAt, lastReadAt != conversation.lastReadAt {
            conversation.lastReadAt = lastReadAt
        }
        conversation.lastMessageSenderId = fresh.lastMessageSenderId
        conversation.lastMessageSeenAt = fresh.lastMessageSeenAt
        conversation.lastMessageReaction = fresh.lastMessageReaction
    }

    func activateChatSession() {
        listenerPauseTask?.cancel()
        listenerPauseTask = nil
        chatSessionMode = .active
        isChatVisible = true
        loadCachedMessagesIfNeeded()
        attachChatListenersIfNeeded()

        if let conversationId = conversation.id {
            Task {
                await EncryptionService.shared.preloadConversationKeys(for: [conversationId])
            }
        }
    }

    func deactivateChatSession() {
        isChatVisible = false
        if LocalFirstMessagingSettings.isEnabled {
            pauseChatListenersImmediately()
            return
        }

        listenerPauseTask?.cancel()
        listenerPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenerPauseTTL)
            guard let self, !self.isChatVisible, self.chatSessionMode != .active else { return }
            self.pauseChatListenersImmediately()
        }
    }

    func pauseChatListenersImmediately() {
        listenerPauseTask?.cancel()
        listenerPauseTask = nil
        guard sessionListenersAttached else {
            chatSessionMode = .idle
            return
        }
        sessionListenersAttached = false
        chatSessionMode = .idle
        detachChatListeners()
    }

    private func detachChatListeners() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        chatService.removeListener(for: conversationId)
        chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        typingTimer?.invalidate()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil
        typingUsers = []
        cancellables.removeAll()
    }

    func stopListening() {
        pauseChatListenersImmediately()
        isChatVisible = false
    }

    /// Último buzz entrante aún no reproducido, dentro de la ventana MSN (~5 min).
    func pendingReplayBuzzEvent(within window: TimeInterval = ChatBuzzProcessedStore.replayWindow) -> ChatBuzzEvent? {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return nil }
        let cutoff = Date().addingTimeInterval(-window)
        return buzzEvents
            .filter { event in
                event.senderId != currentUserId
                    && event.createdAt >= cutoff
                    && !ChatBuzzProcessedStore.isProcessed(eventId: event.id, conversationId: conversationId)
            }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    func sendBuzz(completion: @escaping (Result<Void, Error>) -> Void) {
        guard canSendBuzz else {
            completion(.failure(NSError(
                domain: "ChatBuzz",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("chat.buzz.blocked", comment: "Buzz blocked by recipient")]
            )))
            return
        }

        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion(.failure(NSError(
                domain: "ChatBuzz",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ID de conversación no válido"]
            )))
            return
        }

        chatService.sendBuzz(
            conversationId: conversationId,
            senderId: currentUserId,
            completion: completion
        )
    }

    // ✅ NUEVA: Cleanup cuando se destruye el ViewModel
    deinit {
        if let messageStatusObserver {
            NotificationCenter.default.removeObserver(messageStatusObserver)
        }
        if let mediaUploadObserver {
            NotificationCenter.default.removeObserver(mediaUploadObserver)
        }
        typingUsersCancellable?.cancel()
    }

    // MARK: - Send Messages

    func sendTextMessage(_ text: String, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el mensaje: ID de conversación no válido"
            return
        }

        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .text,
            content: text,
            status: .sending,
            replyTo: replyTo,
            isVanishModeMessage: vanishModeActive ? true : nil,
            vanishExpiresAt: nil
        )

        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)

        chatService.sendTextMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            content: text,
            replyTo: replyTo,
            messageId: messageId,
            isVanishModeMessage: vanishModeActive,
            vanishExpiresAt: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func sendImageMessage(_ image: UIImage) {
        sendImageMessage(image, mediaBatchId: nil)
    }

    func sendImageMessage(_ image: UIImage, mediaBatchId: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la imagen: ID de conversación no válido"
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            error = "No se puede enviar la imagen"
            return
        }

        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(
            data: imageData,
            conversationId: conversationId,
            messageId: messageId,
            fileExtension: "jpg"
        )
        // Reservar dimensiones desde el origen: la burbuja calcula su altura sin esperar a descargar
        // la imagen, evitando el reflujo/padding al renderizar.
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaUrl: localPreview,
            mediaWidth: pixelWidth > 0 ? pixelWidth : nil,
            mediaHeight: pixelHeight > 0 ? pixelHeight : nil,
            status: .sending,
            mediaBatchId: mediaBatchId,
            isVanishModeMessage: vanishModeActive ? true : nil,
            vanishExpiresAt: nil
        )

        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)

        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId, // ✅ Pasar el mismo ID
            mediaBatchId: mediaBatchId,
            isVanishModeMessage: vanishModeActive,
            vanishExpiresAt: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.finalizeOutgoingMediaMessage(
                        messageId: messageId,
                        sentMessage: sentMessage,
                        fallbackMediaUrl: localPreview
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func handlePhotoPickerItem(_ item: PhotosPickerItem, mediaBatchId: String? = nil) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        sendImageMessage(image, mediaBatchId: mediaBatchId)
                    }
                } else {
                    await MainActor.run {
                        sendVideoMessage(data: data, mediaBatchId: mediaBatchId)
                    }
                }
            } else {
                await MainActor.run {
                    self.error = "Error al cargar la imagen o video"
                }
            }
        }
    }

    func handlePhotoPickerItems(_ items: [PhotosPickerItem]) {
        let mediaBatchId = items.count > 1 ? UUID().uuidString : nil
        for item in items {
            handlePhotoPickerItem(item, mediaBatchId: mediaBatchId)
        }
    }

    func sendSelectedPHAssets(_ assets: [PHAsset], completion: (() -> Void)? = nil) {
        let mediaBatchId = assets.count > 1 ? UUID().uuidString : nil
        Task {
            for asset in assets {
                await sendPHAsset(asset, mediaBatchId: mediaBatchId)
            }
            await MainActor.run {
                completion?()
            }
        }
    }

    private func sendPHAsset(_ asset: PHAsset, mediaBatchId: String?) async {
        switch asset.mediaType {
        case .image:
            if let image = await loadFullImage(from: asset) {
                sendImageMessage(image, mediaBatchId: mediaBatchId)
            }
        case .video:
            if let data = await loadVideoData(from: asset) {
                sendVideoMessage(data: data, mediaBatchId: mediaBatchId)
            }
        default:
            break
        }
    }

    private func loadFullImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func loadVideoData(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }

                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let data = try Data(contentsOf: urlAsset.url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func sendVideoMessage(data: Data) {
        sendVideoMessage(data: data, mediaBatchId: nil)
    }

    func sendVideoMessage(data: Data, mediaBatchId: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el video: ID de conversación no válido"
            return
        }


        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(
            data: data,
            conversationId: conversationId,
            messageId: messageId,
            fileExtension: "mp4"
        )
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            mediaUrl: localPreview,
            status: .sending,
            mediaBatchId: mediaBatchId,
            isVanishModeMessage: vanishModeActive ? true : nil,
            vanishExpiresAt: nil
        )

        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)

        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            mediaData: data,
            messageId: messageId, // ✅ Pasar el mismo ID
            mediaBatchId: mediaBatchId,
            isVanishModeMessage: vanishModeActive,
            vanishExpiresAt: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.finalizeOutgoingMediaMessage(
                        messageId: messageId,
                        sentMessage: sentMessage,
                        fallbackMediaUrl: localPreview
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func sendLocationMessage(latitude: Double, longitude: Double) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la ubicación: ID de conversación no válido"
            return
        }


        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: latitude,
            longitude: longitude,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )

        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)

        chatService.sendLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: latitude,
            longitude: longitude,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // MARK: - Audio Messages

    func sendAudioMessage(audioData: Data, duration: Double) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el audio: ID de conversación no válido"
            return
        }


        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(
            data: audioData,
            conversationId: conversationId,
            messageId: messageId,
            fileExtension: "m4a"
        )
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            mediaUrl: localPreview,
            duration: duration,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )

        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)

        chatService.sendAudioMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            audioData: audioData,
            duration: duration,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.finalizeOutgoingMediaMessage(
                        messageId: messageId,
                        sentMessage: sentMessage,
                        fallbackMediaUrl: localPreview
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    private func trackSuccessfulDirectMessage() {
        let targetUserId = conversation.otherParticipantId
        guard !targetUserId.isEmpty else { return }
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .directMessage, with: targetUserId)
        }
    }

    // MARK: - Message Actions

    private func removeMessageFromLocalStores(_ messageId: String) {
        realTimeMessages.removeAll { $0.id == messageId }
        historicalMessages.removeAll { $0.id == messageId }
        messages.removeAll { $0.id == messageId }
        outgoingTempMessages.removeValue(forKey: messageId)
        localMessageStates.removeValue(forKey: messageId)
        uploadProgress.removeValue(forKey: messageId)
        clearDownloadProgress(for: messageId)
        liveReactionOverlays.removeValue(forKey: messageId)
    }

    func applyDeletedForEveryoneLocally(_ message: EnhancedMessage) {
        message.isDeleted = true
        message.deletedAt = Date()
        message.mediaUrl = nil
        message.thumbnailUrl = nil

        removeMessageFromLocalStores(message.id)
        realTimeMessages.append(message)

        ChatCacheStore.deleteMessageFiles(
            conversationId: message.conversationId,
            messageId: message.id
        )
        LocalPersistenceService.shared.markMessageDeletedForEveryone(
            conversationId: message.conversationId,
            messageId: message.id
        )

        rebuildMessagesList()
    }

    func applyDeletedForMeLocally(_ message: EnhancedMessage) {
        hiddenForMeMessageIds.insert(message.id)
        removeMessageFromLocalStores(message.id)
        LocalPersistenceService.shared.removeCachedMessage(
            conversationId: message.conversationId,
            messageId: message.id
        )
        rebuildMessagesList()
    }

    func deleteMessageForEveryone(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        guard message.senderId == currentUserId else { return }

        applyDeletedForEveryoneLocally(message)

        chatService.deleteMessageWithCleanup(
            conversationId: conversationId,
            messageId: message.id
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }


    func deleteMessageForMe(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        applyDeletedForMeLocally(message)

        chatService.deleteMessageForMe(
            conversationId: conversationId,
            messageId: message.id,
            userId: currentUserId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    func editMessage(_ message: EnhancedMessage, newContent: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        guard ChatMessagePolicy.canEdit(message, userId: currentUserId) else {
            error = NSLocalizedString("chat.error.editWindowExpired", comment: "")
            return
        }

        chatService.editMessage(
            conversationId: conversationId,
            messageId: message.id,
            newContent: newContent
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    func addReaction(to message: EnhancedMessage, emoji: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        EmojiUsageStore.increment(emoji, userId: currentUserId)

        let wasToggleOff = message.reactions?[emoji]?.contains(currentUserId) ?? false
        let updated = MessageReactionMutation.apply(
            to: message.reactions,
            emoji: emoji,
            userId: currentUserId
        )
        setLiveReactions(updated, for: message.id)

        chatService.addReaction(
            conversationId: conversationId,
            messageId: message.id,
            emoji: emoji,
            userId: currentUserId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }

        guard message.id == messages.last?.id, message.senderId != currentUserId else { return }
        if wasToggleOff {
            chatService.clearLastMessageReaction(conversationId: conversationId) { _ in }
        } else {
            chatService.setLastMessageReaction(
                conversationId: conversationId,
                messageId: message.id,
                emoji: emoji,
                byUserId: currentUserId
            ) { _ in }
        }
    }

    func forwardTextMessage(_ message: EnhancedMessage, toUserIds: Set<String>) {
        guard let sourceConversationId = conversation.id, !sourceConversationId.isEmpty else { return }
        guard ChatMessagePolicy.canForward(
            message,
            currentUserId: currentUserId,
            forwardingPreferences: forwardingPreferences
        ), let rawContent = message.content else { return }

        Task {
            let plaintext = await chatService.decryptMessageContent(rawContent, for: sourceConversationId)
            chatService.forwardTextMessage(
                plaintext: plaintext,
                toUserIds: toUserIds,
                senderId: currentUserId
            ) { [weak self] result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        self?.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func toggleStar(for message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        let isStarred = message.isStarred(by: currentUserId)
        let newStarred = !isStarred

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var starredBy = messages[index].starredBy ?? []
            if newStarred {
                if !starredBy.contains(currentUserId) { starredBy.append(currentUserId) }
            } else {
                starredBy.removeAll { $0 == currentUserId }
            }
            messages[index].starredBy = starredBy.isEmpty ? nil : starredBy
        }

        chatService.toggleMessageStar(
            conversationId: conversationId,
            messageId: message.id,
            userId: currentUserId,
            isStarred: newStarred
        ) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Read Status

    /// - Parameter sealsVanish: si `true`, los mensajes recién marcados se consideran vistos de verdad
    ///   y sellan expiración vanish. El mark-read en bloque al salir debe pasar `false`: marca «visto»
    ///   sin expirar vanish de mensajes que el usuario no llegó a ver.
    func markVisibleConversationAsRead(sealsVanish: Bool = true) {
        guard isChatVisible else { return }
        // Capturar los ids antes del optimistic-read local: EnhancedMessage es clase y el
        // marcado local muta las mismas instancias, dejando sin nada que escribir al servidor.
        let markedIds = applyOptimisticReadLocally(sealsVanish: sealsVanish)
        markUnreadMessagesAsRead(messageIds: markedIds)
        clearLastMessageReactionIfViewedBySender()
    }

    private func clearLastMessageReactionIfViewedBySender() {
        guard let conversationId = conversation.id,
              let reaction = conversation.lastMessageReaction,
              reaction.byUserId != currentUserId else { return }
        conversation.lastMessageReaction = nil
        chatService.clearLastMessageReaction(conversationId: conversationId) { _ in }
    }

    @discardableResult
    private func applyOptimisticReadLocally(sealsVanish: Bool = true) -> [String] {
        var didChange = false
        var markedIds: [String] = []

        func markIncomingIfNeeded(_ message: inout EnhancedMessage) {
            guard message.senderId != currentUserId, !message.isRead else { return }
            message.isRead = true
            markedIds.append(message.id)
            didChange = true
        }

        for index in realTimeMessages.indices {
            markIncomingIfNeeded(&realTimeMessages[index])
        }
        for index in historicalMessages.indices {
            markIncomingIfNeeded(&historicalMessages[index])
        }

        if let conversationId = conversation.id {
            if !markedIds.isEmpty {
                LocalPersistenceService.shared.markMessagesAsRead(conversationId: conversationId, messageIds: markedIds)
            }
            LocalPersistenceService.shared.markConversationReadLocally(conversationId: conversationId, currentUserId: currentUserId)
            NotificationCenter.default.post(
                name: .conversationMarkedReadLocally,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }

        locallyReadMessageIds.formUnion(markedIds)

        guard didChange else { return markedIds }
        if sealsVanish {
            sessionSeenIncomingMessageIds.formUnion(markedIds)
            stampVanishExpiryIfNeeded(messageIds: Set(markedIds))
        }
        rebuildMessagesList()
        return markedIds
    }

    private func hydrateLocallyHiddenVanishMessages(from loaded: [EnhancedMessage]) {
        let hiddenIds = loaded
            .filter { $0.isVanishModeMessage == true && $0.isVanished(forUserId: currentUserId) }
            .map(\.id)
        guard !hiddenIds.isEmpty else { return }
        optimisticallyHiddenVanishIds.formUnion(hiddenIds)
    }

    private func markUnreadMessagesAsRead(messageIds: [String]) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        if messageIds.isEmpty {
            // Si no hay mensajes individuales sin leer, de todos modos marcamos el documento de la conversación como leído (útil si se marcó como no leído manualmente).
            chatService.markConversationAsRead(conversationId: conversationId, userId: currentUserId)
        } else {
            let marksLastMessageSeen = messages.last.map {
                messageIds.contains($0.id) && $0.senderId != currentUserId
            } ?? false
            chatService.markMessagesAsRead(
                conversationId: conversationId,
                messageIds: messageIds,
                readerId: currentUserId,
                marksLastMessageSeen: marksLastMessageSeen
            ) { error in
                if error != nil {
                    // Error marking messages as read
                }
            }
        }
    }

    // MARK: - Typing Indicator

    private func handleTypingIndicator() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        guard typingIndicatorEnabled else {
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
            return
        }

        typingTimer?.invalidate()

        if isTyping {
            chatService.startTyping(conversationId: conversationId, userId: currentUserId)

            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isTyping = false
                }
            }
        } else {
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        }
    }

    // MARK: - Vanish mode

    /// Marca mensajes salientes para purge al desactivar vanish.
    var outgoingVanishMessageFlag: Bool? {
        vanishModeActive ? true : nil
    }

    var marksOutgoingAsVanish: Bool {
        vanishModeActive
    }

    func toggleVanishMode(completion: ((Error?) -> Void)? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion?(NSError(domain: "ChatViewModel", code: -1))
            return
        }

        let targetActive = !vanishModeActive
        chatService.setVanishMode(
            conversationId: conversationId,
            active: targetActive,
            userId: currentUserId,
            timer: targetActive ? vanishMessageTimer : nil
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    completion?(error)
                    return
                }

                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    self.vanishModeActive = targetActive
                }
                self.conversation.vanishModeActive = targetActive
                if !targetActive {
                    self.purgeVanishMessagesLocally()
                }
                NotificationCenter.default.post(
                    name: .conversationVanishModeDidChange,
                    object: nil,
                    userInfo: [
                        "conversationId": conversationId,
                        "vanishModeActive": targetActive
                    ]
                )
                if targetActive {
                    self.publishVanishEnabledNotice(completion: completion)
                } else {
                    self.publishVanishDisabledNotice(completion: completion)
                }
            }
        }
    }

    func setVanishMessageTimer(_ timer: VanishMessageTimer?, completion: ((Error?) -> Void)? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion?(NSError(domain: "ChatViewModel", code: -1))
            return
        }

        if timer == nil {
            guard vanishModeActive else {
                completion?(nil)
                return
            }
            toggleVanishMode(completion: completion)
            return
        }

        chatService.setVanishMessageTimer(conversationId: conversationId, timer: timer!) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    completion?(error)
                    return
                }
                let selectedTimer = timer!
                self.vanishMessageTimer = selectedTimer
                self.conversation.vanishMessageTimer = selectedTimer.rawValue
                if self.vanishModeActive {
                    self.updateVanishEnabledNotice(
                        noticeKey: selectedTimer.enabledNoticeToken,
                        completion: completion
                    )
                } else {
                    completion?(nil)
                }
            }
        }
    }

    func handleChatDismissedForVanishMode() {
        guard let conversationId = conversation.id else { return }

        // Calcular elegibilidad ANTES del mark-read en bloque del cierre: así no ocultamos
        // mensajes entrantes que el usuario nunca llegó a ver (solo «pasó por encima»).
        let eligibleIds = messages
            .filter { message in
                guard message.shouldHideVanishOnChatDismiss(for: currentUserId, timer: vanishMessageTimer) else {
                    return false
                }
                if message.senderId == currentUserId { return true }
                // Entrante: solo expira si se vio de verdad esta sesión o ya estaba expirado por timer.
                return sessionSeenIncomingMessageIds.contains(message.id)
                    || VanishMessageTimer.isExpired(message.vanishExpiresAt)
            }
            .map(\.id)

        applyOptimisticReadLocally(sealsVanish: false)

        guard !eligibleIds.isEmpty else { return }

        optimisticallyHiddenVanishIds.formUnion(eligibleIds)
        LocalPersistenceService.shared.markVanishMessagesDismissed(
            conversationId: conversationId,
            messageIds: eligibleIds,
            userId: currentUserId
        )
        chatService.markVanishMessagesVanishedForMe(
            conversationId: conversationId,
            messageIds: eligibleIds,
            userId: currentUserId
        )
        rebuildMessagesList()
    }

    func refreshVanishExpiryPresentation() {
        guard vanishMessageTimer != .onceSeen else { return }
        rebuildMessagesList()
    }

    private func resolveVanishEnabledNoticeMessageId() -> String? {
        if let stored = conversation.vanishSettingsNoticeMessageId, !stored.isEmpty,
           messages.contains(where: { $0.id == stored && !$0.isDeleted }) {
            return stored
        }
        return messages.last(where: { message in
            guard message.type == .chatNotice, let content = message.content, !message.isDeleted else { return false }
            return content.hasPrefix("disappearing:enabled:")
        })?.id
    }

    private func resolveVanishDisabledNoticeMessageId() -> String? {
        if let stored = conversation.vanishDisabledNoticeMessageId, !stored.isEmpty,
           messages.contains(where: { $0.id == stored && !$0.isDeleted }) {
            return stored
        }
        return messages.last(where: { message in
            guard message.type == .chatNotice, let content = message.content, !message.isDeleted else { return false }
            return content == VanishMessageTimer.disabledNoticeToken
        })?.id
    }

    /// Activar vanish: borra el último notice "turned off" y publica uno nuevo "turned on".
    private func publishVanishEnabledNotice(completion: ((Error?) -> Void)? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion?(NSError(domain: "ChatViewModel", code: -1))
            return
        }

        removeVanishDisabledNoticeIfNeeded(conversationId: conversationId) { [weak self] in
            guard let self else { return }
            let noticeKey = self.vanishMessageTimer.enabledNoticeToken
            self.chatService.sendChatNotice(
                conversationId: conversationId,
                senderId: self.currentUserId,
                noticeKey: noticeKey
            ) { [weak self] messageId, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let messageId {
                        self.conversation.vanishSettingsNoticeMessageId = messageId
                        self.chatService.setVanishSettingsNoticeMessageId(
                            conversationId: conversationId,
                            messageId: messageId
                        )
                    }
                    completion?(error)
                }
            }
        }
    }

    /// Desactivar vanish: añade notice "turned off" (coexiste con el enabled). Anti-spam si ya hay uno activo.
    private func publishVanishDisabledNotice(completion: ((Error?) -> Void)? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion?(NSError(domain: "ChatViewModel", code: -1))
            return
        }

        let noticeKey = VanishMessageTimer.disabledNoticeToken

        if let noticeId = resolveVanishDisabledNoticeMessageId() {
            updateLocalNoticeContent(messageId: noticeId, noticeKey: noticeKey)
            chatService.updateChatNotice(
                conversationId: conversationId,
                messageId: noticeId,
                noticeKey: noticeKey
            ) { error in
                DispatchQueue.main.async {
                    completion?(error)
                }
            }
            return
        }

        chatService.sendChatNotice(
            conversationId: conversationId,
            senderId: currentUserId,
            noticeKey: noticeKey
        ) { [weak self] messageId, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let messageId {
                    self.conversation.vanishDisabledNoticeMessageId = messageId
                    self.chatService.setVanishDisabledNoticeMessageId(
                        conversationId: conversationId,
                        messageId: messageId
                    )
                }
                completion?(error)
            }
        }
    }

    /// Cambiar timer: actualiza solo el notice enabled existente (no duplica).
    private func updateVanishEnabledNotice(noticeKey: String, completion: ((Error?) -> Void)? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion?(NSError(domain: "ChatViewModel", code: -1))
            return
        }

        if let noticeId = resolveVanishEnabledNoticeMessageId() {
            updateLocalNoticeContent(messageId: noticeId, noticeKey: noticeKey)
            chatService.updateChatNotice(
                conversationId: conversationId,
                messageId: noticeId,
                noticeKey: noticeKey
            ) { error in
                DispatchQueue.main.async {
                    completion?(error)
                }
            }
            return
        }

        chatService.sendChatNotice(
            conversationId: conversationId,
            senderId: currentUserId,
            noticeKey: noticeKey
        ) { [weak self] messageId, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let messageId {
                    self.conversation.vanishSettingsNoticeMessageId = messageId
                    self.chatService.setVanishSettingsNoticeMessageId(
                        conversationId: conversationId,
                        messageId: messageId
                    )
                }
                completion?(error)
            }
        }
    }

    private func removeVanishDisabledNoticeIfNeeded(
        conversationId: String,
        completion: @escaping () -> Void
    ) {
        guard let noticeId = resolveVanishDisabledNoticeMessageId() else {
            completion()
            return
        }

        removeMessageFromLocalStores(noticeId)
        LocalPersistenceService.shared.removeCachedMessage(
            conversationId: conversationId,
            messageId: noticeId
        )
        conversation.vanishDisabledNoticeMessageId = nil
        chatService.clearVanishDisabledNoticeMessageId(conversationId: conversationId)
        chatService.deleteMessage(conversationId: conversationId, messageId: noticeId) { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func updateLocalNoticeContent(messageId: String, noticeKey: String) {
        func patch(in messages: inout [EnhancedMessage]) {
            guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
            messages[index] = messages[index].replacingContent(noticeKey)
        }

        patch(in: &realTimeMessages)
        patch(in: &historicalMessages)
        rebuildMessagesList()

        if let conversationId = conversation.id {
            LocalPersistenceService.shared.updateMessageNoticeContent(
                conversationId: conversationId,
                messageId: messageId,
                content: noticeKey
            )
        }
    }

    /// Ancla `vanishExpiresAt` cuando todos han visto (24h/7d), no al enviar.
    private func stampVanishExpiryIfNeeded(messageIds: Set<String>? = nil) {
        guard vanishModeActive,
              vanishMessageTimer != .onceSeen,
              let conversationId = conversation.id,
              let expiresAt = vanishMessageTimer.expiresAt(from: Date()) else { return }

        var stampedAny = false

        func tryStamp(_ message: inout EnhancedMessage) {
            guard message.isVanishModeMessage == true,
                  message.type != .chatNotice,
                  message.vanishExpiresAt == nil,
                  message.everyoneHasSeen(for: currentUserId) else { return }
            if let messageIds, !messageIds.contains(message.id) { return }
            message.vanishExpiresAt = expiresAt
            stampedAny = true
            chatService.stampVanishExpiry(
                conversationId: conversationId,
                messageId: message.id,
                expiresAt: expiresAt
            )
        }

        for index in realTimeMessages.indices {
            tryStamp(&realTimeMessages[index])
        }
        for index in historicalMessages.indices {
            tryStamp(&historicalMessages[index])
        }

        if stampedAny {
            rebuildMessagesList()
        }
    }

    private func purgeVanishMessagesLocally() {
        guard let conversationId = conversation.id else { return }
        let vanishIds = messages
            .filter { $0.isVanishModeMessage == true && $0.type != .chatNotice }
            .map(\.id)
        guard !vanishIds.isEmpty else { return }

        optimisticallyHiddenVanishIds.formUnion(vanishIds)
        historicalMessages.removeAll { vanishIds.contains($0.id) }
        realTimeMessages.removeAll { vanishIds.contains($0.id) }
        for id in vanishIds {
            outgoingTempMessages.removeValue(forKey: id)
        }
        chatService.purgeVanishMessagesLocally(conversationId: conversationId, messageIds: vanishIds)
        rebuildMessagesList()
    }

    func reportVanishScreenshotIfNeeded() {
        guard vanishModeActive, let conversationId = conversation.id else { return }
        chatService.reportVanishScreenshot(
            conversationId: conversationId,
            reporterId: currentUserId
        )
    }

    func reportVanishScreenRecordingIfNeeded() {
        guard vanishModeActive, let conversationId = conversation.id else { return }
        chatService.reportVanishScreenRecording(
            conversationId: conversationId,
            reporterId: currentUserId
        )
    }

    // MARK: - Search

    func performSearch(query: String) {
        searchDebounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversationId = conversation.id, !conversationId.isEmpty else {
            searchResults = []
            isSearchingHistory = false
            return
        }

        let token = UUID()
        activeSearchToken = token

        searchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, self.activeSearchToken == token else { return }

            let normalizedQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let inMemoryMatches = self.messages.filter { message in
                let searchable = [message.content, message.preview]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return searchable.contains(normalizedQuery)
            }.map(\.id)

            let localIds = LocalPersistenceService.shared.searchMessageIds(
                conversationId: conversationId,
                query: trimmed,
                limit: 100
            )

            var merged = Self.mergeSearchResultIds(localIds + inMemoryMatches)
            self.searchResults = merged

            guard merged.count < 100 else {
                self.isSearchingHistory = false
                return
            }

            self.isSearchingHistory = true
            let excluding = Set(merged)

            self.chatService.searchMessages(
                conversationId: conversationId,
                query: trimmed,
                excludingIds: excluding,
                limit: 100 - merged.count
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.activeSearchToken == token else { return }
                    self.isSearchingHistory = false
                    if case .success(let remoteMatches) = result {
                        let remoteIds = remoteMatches.map(\.id)
                        merged = Self.mergeSearchResultIds(merged + remoteIds)
                        self.searchResults = merged
                        LocalPersistenceService.shared.appendMessages(remoteMatches, conversationId: conversationId)
                    } else if case .failure(let error) = result {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func clearSearch() {
        searchDebounceTask?.cancel()
        activeSearchToken = UUID()
        searchResults = []
        isSearchingHistory = false
    }

    private static func mergeSearchResultIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for id in ids where seen.insert(id).inserted {
            merged.append(id)
        }
        return merged
    }

    func searchMessages(query: String) {
        performSearch(query: query)
    }

    // MARK: - Ephemeral Messages

    func sendEphemeralMessage(content: String?, mediaUrl: String?, duration: Int = 24) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar mensaje efímero: ID de conversación no válido"
            return
        }

        chatService.sendEphemeralMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            content: content,
            mediaUrl: mediaUrl,
            expirationHours: duration
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Ephemeral message sent successfully
                    break
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    func markEphemeralAsViewed(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        chatService.markEphemeralAsViewed(
            conversationId: conversationId,
            messageId: message.id
        ) { error in
            if error != nil {
                // Error marking ephemeral as viewed
            }
        }
    }
}
