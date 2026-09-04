import Foundation

/// Local daily cache for the Nova welcome spark. Keyed by user and calendar day.
enum NovaWelcomeSparkStore {
    struct Cached {
        let day: String
        let text: String
    }

    static func todayKey(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    static func load(userId: String) -> Cached? {
        let defaults = UserDefaults.standard
        guard let day = defaults.string(forKey: dayKey(userId)),
              let text = defaults.string(forKey: textKey(userId))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return Cached(day: day, text: text)
    }

    static func previousText(userId: String) -> String? {
        guard let text = UserDefaults.standard.string(forKey: previousKey(userId))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    static func save(userId: String, day: String, text: String) {
        let defaults = UserDefaults.standard
        if let oldDay = defaults.string(forKey: dayKey(userId)),
           oldDay != day,
           let oldText = defaults.string(forKey: textKey(userId))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !oldText.isEmpty {
            defaults.set(oldText, forKey: previousKey(userId))
        }
        defaults.set(day, forKey: dayKey(userId))
        defaults.set(text, forKey: textKey(userId))
    }

    private static func dayKey(_ userId: String) -> String {
        "novaWelcomeSpark.day-\(userId)"
    }

    private static func textKey(_ userId: String) -> String {
        "novaWelcomeSpark.text-\(userId)"
    }

    private static func previousKey(_ userId: String) -> String {
        "novaWelcomeSpark.previous-\(userId)"
    }
}
