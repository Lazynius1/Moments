import Foundation

/// Privacidad de vistas previas en chat (inbox, push, in-app).
/// Los mensajes vanish se tratan como si el usuario tuviera previews desactivadas.
enum ChatPreviewPrivacy {
    private static let appGroup = "group.com.glowsyapp"

    static func isUserPreviewEnabled(for conversationId: String) -> Bool {
        UserDefaults(suiteName: appGroup)?
            .object(forKey: "chat_show_message_preview_\(conversationId)") as? Bool ?? true
    }

    static func shouldRevealPreview(for conversationId: String, isVanishModeMessage: Bool) -> Bool {
        isUserPreviewEnabled(for: conversationId) && !isVanishModeMessage
    }

    static func isVanishModeMessage(in userInfo: [AnyHashable: Any]) -> Bool {
        if let flag = userInfo["isVanishModeMessage"] as? Bool { return flag }
        if let flag = userInfo["isVanishModeMessage"] as? String {
            return ["1", "true"].contains(flag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return false
    }

    static func isVanishModeMessage(in data: [String: Any]) -> Bool {
        isVanishModeMessage(in: Dictionary(uniqueKeysWithValues: data.map { (AnyHashable($0.key), $0.value) }))
    }
}
