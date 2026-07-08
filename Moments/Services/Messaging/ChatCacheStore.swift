import Foundation

struct ChatStorageBreakdown {
    let messageCount: Int
    let decryptedMediaBytes: Int64
    let posterBytes: Int64

    var totalMediaBytes: Int64 { decryptedMediaBytes + posterBytes }
}

enum ChatCacheStore {
    private static let appGroupID = MessageIngestQueue.appGroupID
    private static let didMigrateKey = "didMigrateChatMediaToAppGroup"
    private static let legacyDecryptedFolder = "chat_media_decrypted"
    private static let legacyPostersFolder = "chat_video_posters"

    static func decryptedMediaURL(
        conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose,
        fileExtension: String
    ) -> URL {
        let filename = decryptedFilename(
            conversationId: conversationId,
            messageId: messageId,
            purpose: purpose,
            fileExtension: fileExtension
        )
        return decryptedDirectory().appendingPathComponent(filename)
    }

    static func posterURL(for messageId: String) -> URL {
        let safeId = messageId.replacingOccurrences(of: "/", with: "_")
        return postersDirectory().appendingPathComponent("\(safeId).jpg")
    }

    static func ensureDirectories() throws {
        migrateFromLegacyCachesIfNeeded()
        try FileManager.default.createDirectory(at: chatMediaRoot(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decryptedDirectory(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: postersDirectory(), withIntermediateDirectories: true)
        excludeFromBackup(chatMediaRoot())
    }

    /// Escribe media descifrada en App Group (misma ruta que usa el resolver al descargar).
    @discardableResult
    static func writeDecryptedMedia(
        _ data: Data,
        conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose,
        fileExtension: String
    ) throws -> URL {
        try ensureDirectories()
        let url = decryptedMediaURL(
            conversationId: conversationId,
            messageId: messageId,
            purpose: purpose,
            fileExtension: fileExtension
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Re-enlaza rutas `file://` si el fichero sigue en App Group (p. ej. tras reiniciar la app).
    /// Firestore no persiste URLs locales; la ruta local se deriva del disco.
    static func localURLsIfPresent(for message: EnhancedMessage) -> (mediaUrl: String?, thumbnailUrl: String?) {
        guard !message.isDeleted else { return (nil, nil) }

        var mediaUrl = message.mediaUrl
        var thumbnailUrl = message.thumbnailUrl

        if mediaUrl == nil || localFileMissing(mediaUrl),
           let mediaEncryption = message.mediaEncryption {
            let cacheURL = decryptedMediaURL(
                conversationId: message.conversationId,
                messageId: message.id,
                purpose: mediaEncryption.purpose,
                fileExtension: mediaEncryption.fileExtension
            )
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                mediaUrl = cacheURL.absoluteString
                touchAccessDate(at: cacheURL)
            }
        }

        if thumbnailUrl == nil || localFileMissing(thumbnailUrl),
           let thumbEncryption = message.thumbnailEncryption {
            let cacheURL = decryptedMediaURL(
                conversationId: message.conversationId,
                messageId: message.id,
                purpose: thumbEncryption.purpose,
                fileExtension: thumbEncryption.fileExtension
            )
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                thumbnailUrl = cacheURL.absoluteString
                touchAccessDate(at: cacheURL)
            }
        }

        if thumbnailUrl == nil || localFileMissing(thumbnailUrl),
           message.type == .video,
           let posterURL = ChatVideoPosterGenerator.cachedPosterURL(messageId: message.id) {
            thumbnailUrl = posterURL.absoluteString
        }

        return (mediaUrl, thumbnailUrl)
    }

    private static func localFileMissing(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    static func totalMediaBytes() -> Int64 {
        directoryBytes(decryptedDirectory()) + directoryBytes(postersDirectory())
    }

    static func bytes(for conversationId: String) -> Int64 {
        let prefix = safeComponent(conversationId) + "_"
        return files(in: decryptedDirectory())
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .reduce(Int64(0)) { partial, url in
                partial + fileSize(at: url)
            }
    }

    /// Bytes de media descifrada agrupados por conversación, en un solo escaneo de disco.
    /// Solo devuelve conversaciones con media cacheada (> 0 bytes).
    static func bytesByConversation(for conversationIds: [String]) -> [String: Int64] {
        guard !conversationIds.isEmpty else { return [:] }
        let scanned = files(in: decryptedDirectory()).map { ($0.lastPathComponent, fileSize(at: $0)) }
        guard !scanned.isEmpty else { return [:] }

        var result: [String: Int64] = [:]
        for conversationId in conversationIds {
            let prefix = safeComponent(conversationId) + "_"
            let total = scanned.reduce(Int64(0)) { partial, entry in
                entry.0.hasPrefix(prefix) ? partial + entry.1 : partial
            }
            if total > 0 {
                result[conversationId] = total
            }
        }
        return result
    }

    @MainActor
    static func storageBreakdown() -> ChatStorageBreakdown {
        let messageCount = LocalPersistenceService.shared.cachedMessageCount()
        let breakdown = ChatStorageBreakdown(
            messageCount: messageCount,
            decryptedMediaBytes: directoryBytes(decryptedDirectory()),
            posterBytes: directoryBytes(postersDirectory())
        )
        return breakdown
    }

    static func deleteMessageFiles(conversationId: String, messageId: String) {
        let convPrefix = safeComponent(conversationId) + "_"
        let msgPrefix = convPrefix + safeComponent(messageId) + "_"

        for url in files(in: decryptedDirectory()) where url.lastPathComponent.hasPrefix(msgPrefix) {
            try? FileManager.default.removeItem(at: url)
        }

        let poster = posterURL(for: messageId)
        if FileManager.default.fileExists(atPath: poster.path) {
            try? FileManager.default.removeItem(at: poster)
        }
    }

    static func deleteConversation(_ conversationId: String, messageIds: [String]) {
        let prefix = safeComponent(conversationId) + "_"
        for url in files(in: decryptedDirectory()) where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
        for messageId in messageIds {
            let poster = posterURL(for: messageId)
            if FileManager.default.fileExists(atPath: poster.path) {
                try? FileManager.default.removeItem(at: poster)
            }
        }
    }

    static func clearAllMedia() {
        removeContents(of: decryptedDirectory())
        removeContents(of: postersDirectory())
    }

    @MainActor
    static func enforceQuota() {
        let maxBytes = ChatMediaDownloadPolicy.maxMediaBytes
        var total = totalMediaBytes()
        guard total > maxBytes else { return }

        let protectedKeys = LocalPersistenceService.shared.cachedMessageKeysWithMedia()

        var candidates = trackedFiles()
            .sorted { $0.modificationDate < $1.modificationDate }

        while total > maxBytes {
            guard let index = candidates.firstIndex(where: { tracked in
                guard let key = tracked.messageKey else { return true }
                return !protectedKeys.contains(key)
            }) else { break }

            let oldest = candidates.remove(at: index)
            let size = fileSize(at: oldest.url)
            try? FileManager.default.removeItem(at: oldest.url)
            total -= size
        }
    }

    /// Actualiza mtime para LRU justo al servir media desde caché.
    static func touchAccessDate(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    @MainActor
    static func enforceRetention() {
        let retentionDays = ChatMediaDownloadPolicy.retentionDays
        guard retentionDays > 0 else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let protectedKeys = LocalPersistenceService.shared.cachedMessageKeys(since: cutoff)

        for tracked in trackedFiles() {
            if tracked.modificationDate >= cutoff { continue }
            if let key = tracked.messageKey, protectedKeys.contains(key) { continue }
            try? FileManager.default.removeItem(at: tracked.url)
        }
    }

    @MainActor
    static func runMaintenance() {
        migrateFromLegacyCachesIfNeeded()
        enforceRetention()
        enforceQuota()
    }

    // MARK: - Private

    private struct TrackedFile {
        let url: URL
        let modificationDate: Date
        let messageKey: String?
    }

    private static func chatMediaRoot() -> URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("ChatMedia", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ChatMedia", isDirectory: true)
    }

    private static func decryptedDirectory() -> URL {
        chatMediaRoot().appendingPathComponent("decrypted", isDirectory: true)
    }

    private static func postersDirectory() -> URL {
        chatMediaRoot().appendingPathComponent("posters", isDirectory: true)
    }

    private static func decryptedFilename(
        conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose,
        fileExtension: String
    ) -> String {
        let safeConversation = safeComponent(conversationId)
        let safeMessage = safeComponent(messageId)
        return "\(safeConversation)_\(safeMessage)_\(purpose.rawValue).\(fileExtension)"
    }

    private static func safeComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
    }

    private static func migrateFromLegacyCachesIfNeeded() {
        let sharedDefaults = UserDefaults(suiteName: appGroupID)
        guard sharedDefaults?.bool(forKey: didMigrateKey) != true else { return }

        do {
            try ensureDirectoriesWithoutMigrationFlag()
        } catch {
            sharedDefaults?.set(true, forKey: didMigrateKey)
            return
        }

        let legacyCaches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        migrateDirectory(from: legacyCaches.appendingPathComponent(legacyDecryptedFolder), to: decryptedDirectory())
        migrateDirectory(from: legacyCaches.appendingPathComponent(legacyPostersFolder), to: postersDirectory())
        sharedDefaults?.set(true, forKey: didMigrateKey)
    }

    private static func ensureDirectoriesWithoutMigrationFlag() throws {
        try FileManager.default.createDirectory(at: chatMediaRoot(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decryptedDirectory(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: postersDirectory(), withIntermediateDirectories: true)
        excludeFromBackup(chatMediaRoot())
    }

    private static func migrateDirectory(from source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        for url in files(in: source) {
            let target = destination.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try? FileManager.default.copyItem(at: url, to: target)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private static func files(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func removeContents(of directory: URL) {
        for url in files(in: directory) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func directoryBytes(_ directory: URL) -> Int64 {
        files(in: directory).reduce(Int64(0)) { partial, url in
            partial + fileSize(at: url)
        }
    }

    private static func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func modificationDate(at url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func trackedFiles() -> [TrackedFile] {
        var results: [TrackedFile] = []

        for url in files(in: decryptedDirectory()) {
            results.append(
                TrackedFile(
                    url: url,
                    modificationDate: modificationDate(at: url),
                    messageKey: messageKey(fromDecryptedFilename: url.lastPathComponent)
                )
            )
        }

        for url in files(in: postersDirectory()) {
            let messageId = url.deletingPathExtension().lastPathComponent
            results.append(
                TrackedFile(
                    url: url,
                    modificationDate: modificationDate(at: url),
                    messageKey: nil
                )
            )
            _ = messageId
        }

        return results
    }

    private static func messageKey(fromDecryptedFilename filename: String) -> String? {
        let name = (filename as NSString).deletingPathExtension
        let parts = name.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let purposeRaw = String(parts[parts.count - 1])
        guard ChatMediaPurpose(rawValue: purposeRaw) != nil else { return nil }
        let messageId = String(parts[parts.count - 2])
        let conversationId = parts.dropLast(2).joined(separator: "_")
        guard !conversationId.isEmpty, !messageId.isEmpty else { return nil }
        return "\(conversationId):\(messageId)"
    }
}
