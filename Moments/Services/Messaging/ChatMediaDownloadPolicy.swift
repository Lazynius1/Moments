import Foundation

enum ChatMediaAutoDownload: String, CaseIterable, Identifiable {
    case wifiOnly
    case always
    case never

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .wifiOnly: return "settings.chatStorage.autoDownload.wifi"
        case .always: return "settings.chatStorage.autoDownload.always"
        case .never: return "settings.chatStorage.autoDownload.never"
        }
    }
}

enum ChatMediaRetention: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case forever = 0

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .days7: return "settings.chatStorage.retention.7days"
        case .days30: return "settings.chatStorage.retention.30days"
        case .days90: return "settings.chatStorage.retention.90days"
        case .forever: return "settings.chatStorage.retention.forever"
        }
    }
}

enum ChatMediaDownloadPolicy {
    private static let appGroupID = MessageIngestQueue.appGroupID
    private static let autoDownloadKey = "chat_media_auto_download"
    private static let retentionDaysKey = "chat_media_retention_days"
    private static let maxBytesKey = "chat_media_max_bytes"

    static let defaultMaxBytes: Int64 = 1_610_612_736 // 1.5 GB

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var autoDownload: ChatMediaAutoDownload {
        get {
            guard let raw = defaults?.string(forKey: autoDownloadKey),
                  let value = ChatMediaAutoDownload(rawValue: raw) else {
                return .wifiOnly
            }
            return value
        }
        set {
            defaults?.set(newValue.rawValue, forKey: autoDownloadKey)
        }
    }

    static var retention: ChatMediaRetention {
        get {
            guard let defaults else { return .days30 }
            let days = defaults.integer(forKey: retentionDaysKey)
            if days == 0, defaults.object(forKey: retentionDaysKey) == nil {
                return .days30
            }
            return ChatMediaRetention(rawValue: days) ?? .days30
        }
        set {
            defaults?.set(newValue.rawValue, forKey: retentionDaysKey)
        }
    }

    static var retentionDays: Int {
        retention.rawValue
    }

    static var maxMediaBytes: Int64 {
        get {
            let stored = defaults?.object(forKey: maxBytesKey) as? Int64
                ?? (defaults?.object(forKey: maxBytesKey) as? Int).map(Int64.init)
            return stored ?? defaultMaxBytes
        }
        set {
            defaults?.set(newValue, forKey: maxBytesKey)
        }
    }

    /// Returns whether a network download of encrypted chat media should proceed.
    /// Cache hits are handled separately (always served when the file exists).
    static func shouldDownloadAutomatically(force: Bool = false) -> Bool {
        if force { return true }

        switch autoDownload {
        case .never:
            return false
        case .always:
            return NetworkMonitor.shared.isConnected
        case .wifiOnly:
            guard NetworkMonitor.shared.isConnected else { return false }
            switch NetworkMonitor.shared.connectionType {
            case .wifi, .ethernet:
                return true
            case .cellular, .unknown:
                return false
            }
        }
    }

    /// Miniaturas de preview (~KB): se permiten con cualquier policy de auto-descarga
    /// del fichero completo (blur real antes del tap).
    static func shouldDownloadThumbnailPreview(force: Bool = false) -> Bool {
        if force { return true }
        return NetworkMonitor.shared.isConnected
    }
}
