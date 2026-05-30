import Foundation

/// App locale metadata for Nova session context — not used for LLM prompts.
enum NovaLocaleContext {
    static var appLocaleIdentifier: String {
        Locale.current.identifier
    }

    static var appLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
