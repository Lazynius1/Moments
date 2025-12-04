import Foundation

// MARK: - Idiomas soportados por Nova
enum NovaLanguage: String, CaseIterable {
    case es
    case en
    case ca
    
    var displayName: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        case .ca: return "Català"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .es: return "Nova responderá en Español"
        case .en: return "Nova will reply in English"
        case .ca: return "Nova respondrà en Català"
        }
    }
}

// MARK: - Servicio de preferencia de idioma para Nova
final class NovaLanguageService {
    private static let preferenceKey = "nova.preferredLanguage"
    
    /// Devuelve el idioma preferido guardado, si existe
    static func getPreferredLanguage() -> NovaLanguage? {
        guard let raw = UserDefaults.standard.string(forKey: preferenceKey) else { return nil }
        return NovaLanguage(rawValue: raw)
    }
    
    /// Guarda el idioma preferido
    static func setPreferredLanguage(_ language: NovaLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
    }
    
    /// Devuelve el código de idioma a usar por Nova (preferido o sistema)
    static func preferredLanguageCode() -> String {
        if let saved = getPreferredLanguage() {
            return saved.rawValue
        }
        // Fallback a idioma del sistema si no hay preferencia
        if #available(iOS 16.0, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }
}


