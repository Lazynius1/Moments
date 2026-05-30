import Foundation

// MARK: - Storage path conventions (users/{uid}/…)
enum StorageUploadDomain: Equatable {
    case profileAvatar(uploadId: String = UUID().uuidString)
    case momentMedia(momentId: String, mediaId: String = UUID().uuidString)
    case momentThumbnail(momentId: String, mediaId: String = UUID().uuidString)
    case momentHiddenLayerImage(momentId: String, layerId: String)
    case momentHiddenLayerAudio(momentId: String, layerId: String)
    case storyMedia(storyId: String, mediaId: String = UUID().uuidString)
    case storyThumbnail(storyId: String, mediaId: String = UUID().uuidString)
    case storyFrame(storyId: String, uploadId: String = UUID().uuidString, blurred: Bool = false)
    case storyStickerAudio(storyId: String, uploadId: String = UUID().uuidString)
    case chatMedia(conversationId: String, messageId: String, fileExtension: String)
    case chatThumbnail(conversationId: String, messageId: String)
    case dataExport(exportId: String = UUID().uuidString)
}

struct StorageUploadTarget {
    let objectPath: String
    let contentType: String
    let customMetadata: [String: String]
}

enum StoragePathBuilder {
    static func build(userId: String, domain: StorageUploadDomain) -> StorageUploadTarget {
        let safeUserId = sanitized(userId)
        let path: String
        let contentType: String
        var metadata: [String: String] = ["ownerId": safeUserId]

        switch domain {
        case .profileAvatar(let uploadId):
            path = "users/\(safeUserId)/profile/avatar/\(sanitized(uploadId)).jpg"
            contentType = "image/jpeg"
            metadata["type"] = "profile_picture"

        case .momentMedia(let momentId, let mediaId):
            path = "users/\(safeUserId)/moments/\(sanitized(momentId))/media/\(sanitized(mediaId)).mp4"
            contentType = "video/mp4"
            metadata["type"] = "moment_video"
            metadata["momentId"] = sanitized(momentId)

        case .momentThumbnail(let momentId, let mediaId):
            path = "users/\(safeUserId)/moments/\(sanitized(momentId))/thumbnails/\(sanitized(mediaId)).jpg"
            contentType = "image/jpeg"
            metadata["type"] = "moment_thumbnail"
            metadata["momentId"] = sanitized(momentId)

        case .momentHiddenLayerImage(let momentId, let layerId):
            path = "users/\(safeUserId)/moments/\(sanitized(momentId))/hidden_layers/\(sanitized(layerId))/media.jpg"
            contentType = "image/jpeg"
            metadata["type"] = "moment_hidden_layer_image"
            metadata["momentId"] = sanitized(momentId)
            metadata["layerId"] = sanitized(layerId)

        case .momentHiddenLayerAudio(let momentId, let layerId):
            path = "users/\(safeUserId)/moments/\(sanitized(momentId))/hidden_layers/\(sanitized(layerId))/audio.m4a"
            contentType = "audio/mp4"
            metadata["type"] = "moment_hidden_layer_audio"
            metadata["momentId"] = sanitized(momentId)
            metadata["layerId"] = sanitized(layerId)

        case .storyMedia(let storyId, let mediaId):
            path = "users/\(safeUserId)/stories/\(sanitized(storyId))/media/\(sanitized(mediaId)).mp4"
            contentType = "video/mp4"
            metadata["type"] = "story_video"
            metadata["storyId"] = sanitized(storyId)

        case .storyThumbnail(let storyId, let mediaId):
            path = "users/\(safeUserId)/stories/\(sanitized(storyId))/thumbnails/\(sanitized(mediaId)).jpg"
            contentType = "image/jpeg"
            metadata["type"] = "story_thumbnail"
            metadata["storyId"] = sanitized(storyId)

        case .storyFrame(let storyId, let uploadId, let blurred):
            let prefix = blurred ? "blurred_" : ""
            path = "users/\(safeUserId)/stories/\(sanitized(storyId))/frames/\(prefix)\(sanitized(uploadId)).jpg"
            contentType = "image/jpeg"
            metadata["type"] = blurred ? "story_frame_blurred" : "story_frame"
            metadata["storyId"] = sanitized(storyId)

        case .storyStickerAudio(let storyId, let uploadId):
            path = "users/\(safeUserId)/stories/\(sanitized(storyId))/audio/\(sanitized(uploadId)).m4a"
            contentType = "audio/mp4"
            metadata["type"] = "story_sticker_audio"
            metadata["storyId"] = sanitized(storyId)

        case .chatMedia(let conversationId, let messageId, let ext):
            let safeExt = sanitizedExtension(ext)
            path = "users/\(safeUserId)/chat/\(sanitized(conversationId))/\(sanitized(messageId))/media.\(safeExt)"
            contentType = contentTypeForChatExtension(safeExt)
            metadata["type"] = "chat_media"
            metadata["conversationId"] = sanitized(conversationId)
            metadata["messageId"] = sanitized(messageId)

        case .chatThumbnail(let conversationId, let messageId):
            path = "users/\(safeUserId)/chat/\(sanitized(conversationId))/\(sanitized(messageId))/thumb.jpg"
            contentType = "image/jpeg"
            metadata["type"] = "chat_thumbnail"
            metadata["conversationId"] = sanitized(conversationId)
            metadata["messageId"] = sanitized(messageId)

        case .dataExport(let exportId):
            path = "users/\(safeUserId)/exports/\(sanitized(exportId)).zip"
            contentType = "application/zip"
            metadata["type"] = "data_export"
        }

        return StorageUploadTarget(objectPath: path, contentType: contentType, customMetadata: metadata)
    }

    /// Image moment media (non-video).
    static func momentImageTarget(userId: String, momentId: String, mediaId: String = UUID().uuidString) -> StorageUploadTarget {
        let safeUserId = sanitized(userId)
        let path = "users/\(safeUserId)/moments/\(sanitized(momentId))/media/\(sanitized(mediaId)).jpg"
        return StorageUploadTarget(
            objectPath: path,
            contentType: "image/jpeg",
            customMetadata: [
                "ownerId": safeUserId,
                "type": "moment_image",
                "momentId": sanitized(momentId)
            ]
        )
    }

    /// Image story media (non-video).
    static func storyImageTarget(userId: String, storyId: String, mediaId: String = UUID().uuidString) -> StorageUploadTarget {
        let safeUserId = sanitized(userId)
        let path = "users/\(safeUserId)/stories/\(sanitized(storyId))/media/\(sanitized(mediaId)).jpg"
        return StorageUploadTarget(
            objectPath: path,
            contentType: "image/jpeg",
            customMetadata: [
                "ownerId": safeUserId,
                "type": "story_image",
                "storyId": sanitized(storyId)
            ]
        )
    }

    static func extractObjectPath(from urlOrPath: String) -> String {
        let trimmed = urlOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.hasPrefix("https://firebasestorage.googleapis.com") {
            guard let urlComponents = URLComponents(string: trimmed),
                  let pathComponent = urlComponents.path.components(separatedBy: "/o/").last else {
                return trimmed
            }
            let pathWithoutQuery = pathComponent.components(separatedBy: "?").first ?? pathComponent
            return pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        }

        if trimmed.contains("://") { return trimmed }
        return trimmed
    }

    static func isUserOwnedStoragePath(_ objectPath: String, userId: String) -> Bool {
        let path = extractObjectPath(from: objectPath)
        let prefix = "users/\(sanitized(userId))/"
        if path.hasPrefix(prefix) { return true }

        // Legacy
        if path.hasPrefix("images/") || path.hasPrefix("videos/") {
            return path.contains("_\(sanitized(userId)).")
        }
        if path.hasPrefix("hidden_layers/\(sanitized(userId))/") { return true }
        if path.hasPrefix("background_frames/\(sanitized(userId))/") { return true }
        if path.hasPrefix("exports/\(sanitized(userId))/") { return true }
        return false
    }

    private static func sanitized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.map(String.init).joined()
    }

    private static func sanitizedExtension(_ ext: String) -> String {
        let lowered = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowered {
        case "jpg", "jpeg", "png", "gif", "mp4", "m4a", "pdf", "txt": return lowered == "jpeg" ? "jpg" : lowered
        default: return "bin"
        }
    }

    private static func contentTypeForChatExtension(_ ext: String) -> String {
        switch ext {
        case "jpg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "m4a": return "audio/mp4"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
