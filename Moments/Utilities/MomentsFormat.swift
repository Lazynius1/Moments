import Foundation

/// Centralized locale-aware formatting for dates, times, counts, and distances.
/// Fechas y unidades salen de los formateadores del sistema con `Locale.current` / `Calendar.current`
/// (plurales y 12/24 h incluidos); solo «ahora» usa una clave propia (`time.now`).
/// No user-visible `DateFormatter.dateFormat = ...` should live outside this file.
enum MomentsFormat {

    // MARK: - Relative time

    enum RelativeTimeStyle {
        /// Corto sin «hace»: «ahora», «5 min», «3 h», «2 d», «4 sem.», «1 a» (en: «5m», «3h», «2d», «4w»).
        /// Comentarios, lista de chats, historias, notificaciones, Echoes y mapas.
        case compact
        /// Largo del sistema con una sola unidad: «hace 3 horas», «3 hours ago», «vor 3 Stunden».
        /// Sesiones iniciadas, Nova y pantalla de actividad.
        case long
        /// Locale-native relative wording, limited to a single unit for brevity.
        case conversational(unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .abbreviated)
    }

    enum DateContext {
        /// Posts: «ahora», «hace 5 minutos» hasta 7 días y luego «12 de septiembre» (con año si no es el actual).
        case feedTimestamp
        /// Separador del chat: «14:32», «Ayer, 14:32», «lun 14:32», «12 sept 14:32», «12 sept 2025 14:32».
        case chatSeparator
        case storyArchive
        case detailHeader
        case messageAbsolute
        case monthYearLabel
        case monthAbbreviated
        case dayMonthLabel
        case weekdayNarrow
        case timeOnly
        case inboxTimestamp
        case mediumDate
        case mediumDateTime
        case longDate
        case fullDateTime
        case numericDate
        case numericDayMonth
    }

    enum CountStyle {
        /// Profile stats: exact below 10K with grouping; abbreviated from 10K.
        case profileStat
        /// Likes, reactions, reels: abbreviated from 1K.
        case socialMetric
        /// Always exact with thousands separator, never abbreviated.
        case exact
    }

    static func relativeTime(
        from date: Date,
        style: RelativeTimeStyle = .compact,
        relativeTo reference: Date = Date()
    ) -> String {
        switch style {
        case .compact:
            return shortElapsedTime(from: date, relativeTo: reference)
        case .long:
            return longElapsedTime(from: date, relativeTo: reference)
        case .conversational(let unitsStyle):
            return singleUnitRelativeTime(from: date, relativeTo: reference, unitsStyle: unitsStyle)
        }
    }

    static func smartDate(
        from date: Date,
        context: DateContext,
        relativeTo reference: Date = Date()
    ) -> String {
        let calendar = Calendar.current

        switch context {
        case .feedTimestamp:
            // Tiempo transcurrido, no días de calendario.
            let elapsed = reference.timeIntervalSince(date)
            if elapsed < secondsPerMinute {
                return NSLocalizedString("time.now", comment: "Just now")
            }
            if elapsed < 7 * secondsPerDay {
                let components: DateComponents
                if elapsed < secondsPerHour {
                    components = DateComponents(minute: -Int(elapsed / secondsPerMinute))
                } else if elapsed < secondsPerDay {
                    components = DateComponents(hour: -Int(elapsed / secondsPerHour))
                } else {
                    components = DateComponents(day: -Int(elapsed / secondsPerDay))
                }
                return feedRelativeFormatter().localizedString(from: components)
            }
            let sameYear = calendar.isDate(date, equalTo: reference, toGranularity: .year)
            return localizedDateString(from: date, template: sameYear ? "dMMMM" : "yMMMMd")

        case .chatSeparator:
            // Agrupa por día de calendario; la hora sigue la preferencia 12/24 h del sistema.
            let dayOffset = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: reference)
            ).day ?? 0
            switch dayOffset {
            case 0:
                return localizedDateString(from: date, template: "jmm")
            case 1:
                return relativeDayTimeFormatter().string(from: date)
            case 2...6:
                return localizedDateString(from: date, template: "EEEjmm")
            default:
                let sameYear = calendar.isDate(date, equalTo: reference, toGranularity: .year)
                return localizedDateString(from: date, template: sameYear ? "dMMMjmm" : "yMMMdjmm")
            }

        case .storyArchive:
            if calendar.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            }
            if calendar.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            }
            if calendar.isDate(date, equalTo: reference, toGranularity: .year) {
                return date.formatted(.dateTime.day().month(.wide))
            }
            return date.formatted(.dateTime.day().month(.wide).year())

        case .detailHeader:
            if calendar.isDateInToday(date) {
                return date.formatted(date: .omitted, time: .shortened)
            }
            if calendar.isDate(date, equalTo: reference, toGranularity: .year) {
                return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())

        case .messageAbsolute:
            if calendar.isDateInToday(date) {
                return date.formatted(date: .omitted, time: .shortened)
            }
            if calendar.isDate(date, equalTo: reference, toGranularity: .weekOfYear) {
                return date.formatted(.dateTime.weekday(.wide).hour().minute())
            }
            if calendar.isDate(date, equalTo: reference, toGranularity: .year) {
                return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            }
            return date.formatted(date: .numeric, time: .shortened)

        case .monthYearLabel:
            return localizedDateString(from: date, template: "yMMM")

        case .monthAbbreviated:
            return localizedDateString(from: date, template: "MMM")

        case .dayMonthLabel:
            return localizedDateString(from: date, template: "dMMM")

        case .weekdayNarrow:
            return narrowWeekdaySymbol(for: date)

        case .timeOnly:
            return date.formatted(date: .omitted, time: .shortened)

        case .inboxTimestamp:
            if calendar.isDateInToday(date) {
                return date.formatted(date: .omitted, time: .shortened)
            }
            if calendar.isDateInYesterday(date) {
                return NSLocalizedString("notifications.date.yesterday", comment: "Yesterday")
            }
            return date.formatted(date: .numeric, time: .omitted)

        case .mediumDate:
            return date.formatted(date: .abbreviated, time: .omitted)

        case .mediumDateTime:
            return date.formatted(date: .abbreviated, time: .shortened)

        case .longDate:
            return date.formatted(date: .long, time: .omitted)

        case .fullDateTime:
            return date.formatted(date: .complete, time: .shortened)

        case .numericDate:
            return date.formatted(date: .numeric, time: .omitted)

        case .numericDayMonth:
            return localizedDateString(from: date, template: "Md")
        }
    }

    /// `true` si el formato corto mostraría «ahora» (menos de un minuto).
    static func isJustNow(_ date: Date, relativeTo reference: Date = Date()) -> Bool {
        reference.timeIntervalSince(date) < secondsPerMinute
    }

    // MARK: - Read receipts

    /// Recibo de lectura con momento exacto: «Visto hoy, 14:32», «Visto ayer, 23:00»,
    /// «Visto el lun, 14:32», «Visto el 24 sept, 14:32» (con año si no es el actual).
    /// Fecha y hora salen de plantillas del sistema; la frase, de claves con `%@`.
    static func seenReceipt(at date: Date, relativeTo reference: Date = Date()) -> String {
        let calendar = Calendar.current
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: reference)
        ).day ?? 0
        let time = smartDate(from: date, context: .timeOnly, relativeTo: reference)
        switch dayOffset {
        case ...0:
            return String(format: NSLocalizedString("chat.seen.at.today", comment: "Seen today, %@ = time"), time)
        case 1:
            return String(format: NSLocalizedString("chat.seen.at.yesterday", comment: "Seen yesterday, %@ = time"), time)
        case 2...6:
            return String(
                format: NSLocalizedString("chat.seen.at.date", comment: "Seen on %@ = weekday or date with time"),
                localizedDateString(from: date, template: "EEEjmm")
            )
        default:
            let sameYear = calendar.isDate(date, equalTo: reference, toGranularity: .year)
            return String(
                format: NSLocalizedString("chat.seen.at.date", comment: "Seen on %@ = weekday or date with time"),
                localizedDateString(from: date, template: sameYear ? "dMMMjmm" : "ydMMMjmm")
            )
        }
    }

    // MARK: - Durations

    /// Duración para VoiceOver con palabras del sistema: «dos minutos y treinta segundos».
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let formatter: DateComponentsFormatter = FormatterCache.shared.formatter(for: "spokenDuration") {
            let formatter = DateComponentsFormatter()
            formatter.calendar = Calendar.current
            formatter.unitsStyle = .spellOut
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.zeroFormattingBehavior = .dropAll
            return formatter
        }
        return formatter.string(from: max(0, seconds.rounded(.down))) ?? ""
    }

    // MARK: - Counts

    static func count(_ value: Int, style: CountStyle) -> String {
        switch style {
        case .exact:
            return formattedInteger(value)
        case .profileStat:
            if value < 10_000 {
                return formattedInteger(value)
            }
            return abbreviatedCount(value, wholeThousandsThreshold: 10_000)
        case .socialMetric:
            if value < 1_000 {
                return "\(value)"
            }
            return abbreviatedCount(value, wholeThousandsThreshold: 10_000)
        }
    }

    // MARK: - Distance

    static func distance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }

    // MARK: - Private

    private static let secondsPerMinute: TimeInterval = 60
    private static let secondsPerHour: TimeInterval = 3_600
    private static let secondsPerDay: TimeInterval = 86_400

    /// Unidad única abreviada del sistema por tiempo transcurrido; años = días / 365.
    private static func shortElapsedTime(from date: Date, relativeTo reference: Date) -> String {
        let elapsed = reference.timeIntervalSince(date)
        guard elapsed >= secondsPerMinute else {
            return NSLocalizedString("time.now", comment: "Just now")
        }
        let days = Int(elapsed / secondsPerDay)
        let components: DateComponents
        if elapsed < secondsPerHour {
            components = DateComponents(minute: Int(elapsed / secondsPerMinute))
        } else if elapsed < secondsPerDay {
            components = DateComponents(hour: Int(elapsed / secondsPerHour))
        } else if days < 7 {
            components = DateComponents(day: days)
        } else if days < 365 {
            components = DateComponents(weekOfMonth: days / 7)
        } else {
            components = DateComponents(year: days / 365)
        }
        return shortUnitsFormatter().string(for: components)
            ?? NSLocalizedString("time.now", comment: "Just now")
    }

    /// «hace 3 horas»: una unidad por tiempo transcurrido (como `.compact`), palabras completas del sistema.
    private static func longElapsedTime(from date: Date, relativeTo reference: Date) -> String {
        let elapsed = reference.timeIntervalSince(date)
        guard elapsed >= secondsPerMinute else {
            return NSLocalizedString("time.now", comment: "Just now")
        }
        let days = Int(elapsed / secondsPerDay)
        let components: DateComponents
        if elapsed < secondsPerHour {
            components = DateComponents(minute: -Int(elapsed / secondsPerMinute))
        } else if elapsed < secondsPerDay {
            components = DateComponents(hour: -Int(elapsed / secondsPerHour))
        } else if days < 7 {
            components = DateComponents(day: -days)
        } else if days < 365 {
            components = DateComponents(weekOfMonth: -(days / 7))
        } else {
            components = DateComponents(year: -(days / 365))
        }
        return feedRelativeFormatter().localizedString(from: components)
    }

    private static func singleUnitRelativeTime(
        from date: Date,
        relativeTo reference: Date,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle
    ) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .weekOfYear, .day, .hour, .minute, .second],
            from: reference,
            to: date
        )

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = unitsStyle
        formatter.locale = Locale.current

        if let year = firstNonZero(components.year) {
            return formatter.localizedString(from: DateComponents(year: year))
        }
        if let month = firstNonZero(components.month) {
            return formatter.localizedString(from: DateComponents(month: month))
        }
        if let week = firstNonZero(components.weekOfYear) {
            return formatter.localizedString(from: DateComponents(weekOfYear: week))
        }
        if let day = firstNonZero(components.day) {
            return formatter.localizedString(from: DateComponents(day: day))
        }
        if let hour = firstNonZero(components.hour) {
            return formatter.localizedString(from: DateComponents(hour: hour))
        }
        if let minute = firstNonZero(components.minute) {
            return formatter.localizedString(from: DateComponents(minute: minute))
        }
        if let second = firstNonZero(components.second) {
            return formatter.localizedString(from: DateComponents(second: second))
        }

        return formatter.localizedString(from: DateComponents(second: 0))
    }

    private static func formattedInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func abbreviatedCount(_ count: Int, wholeThousandsThreshold: Int) -> String {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let numericValue = Double(count)

        if count >= 1_000_000 {
            let millions = numericValue / 1_000_000
            if count >= 10_000_000 {
                return String(format: "%.0fM", millions)
            }
            return trimTrailingZero(
                String(format: "%.1fM", millions),
                decimalSeparator: decimalSeparator,
                suffix: "M"
            )
        }

        let thousands = numericValue / 1_000
        if count >= wholeThousandsThreshold {
            return String(format: "%.0fK", thousands)
        }
        return trimTrailingZero(
            String(format: "%.1fK", thousands),
            decimalSeparator: decimalSeparator,
            suffix: "K"
        )
    }

    private static func trimTrailingZero(_ value: String, decimalSeparator: String, suffix: String) -> String {
        var result = value
        if decimalSeparator != "." {
            result = result.replacingOccurrences(of: ".", with: decimalSeparator)
        }
        let zeroSuffix = "\(decimalSeparator)0\(suffix)"
        return result.replacingOccurrences(of: zeroSuffix, with: suffix)
    }

    private static func localizedDateString(from date: Date, template: String) -> String {
        let formatter: DateFormatter = FormatterCache.shared.formatter(for: "template.\(template)") {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.calendar = Calendar.current
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        return formatter.string(from: date)
    }

    /// «Ayer, 14:32» / «Yesterday at 2:32 PM» con la palabra relativa del sistema.
    private static func relativeDayTimeFormatter() -> DateFormatter {
        FormatterCache.shared.formatter(for: "relativeDayTime") {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.calendar = Calendar.current
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            formatter.formattingContext = .beginningOfSentence
            return formatter
        }
    }

    private static func feedRelativeFormatter() -> RelativeDateTimeFormatter {
        FormatterCache.shared.formatter(for: "feedRelative") {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale.current
            formatter.calendar = Calendar.current
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .numeric
            return formatter
        }
    }

    /// Estilo por idioma (comprobado en macOS con es, en, de, ja, fr y el resto de idiomas de la app):
    /// - `.abbreviated` solo en inglés: «5m», «3h», «2d», «4w», «1y» (`.short` alarga a «2 days», «4 wks»).
    /// - `.short` en el resto: ja «4週間», «1年» (con `.abbreviated` salía «4w», «1y»); de «3 Std.», «2 Tg.»
    ///   (en vez de «3h», «2d»); tr «5 dk.», «4 hf.» (en vez de «5d», «4h», ambiguos); fr «2 j», «1 an»;
    ///   es «3 h», «2 d», «4 sem.» (igual que antes salvo el punto de «sem.»).
    private static func shortUnitsFormatter() -> DateComponentsFormatter {
        FormatterCache.shared.formatter(for: "shortUnits") {
            let formatter = DateComponentsFormatter()
            formatter.calendar = Calendar.current
            let languageCode = Locale.current.language.languageCode?.identifier
            formatter.unitsStyle = languageCode == "en" ? .abbreviated : .short
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .year]
            return formatter
        }
    }

    private static func narrowWeekdaySymbol(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.count == 7
            ? calendar.veryShortStandaloneWeekdaySymbols
            : calendar.veryShortWeekdaySymbols
        let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return symbols[index]
    }

    private static func firstNonZero(_ value: Int?) -> Int? {
        guard let value, value != 0 else { return nil }
        return value
    }
}

/// Caché de formateadores; se vacía al cambiar idioma, región o zona horaria.
private final class FormatterCache: @unchecked Sendable {
    static let shared = FormatterCache()

    private let lock = NSLock()
    private var storage: [String: AnyObject] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let names: [Foundation.Notification.Name] = [
            NSLocale.currentLocaleDidChangeNotification,
            .NSSystemTimeZoneDidChange
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.removeAll()
            }
        }
    }

    func formatter<T: AnyObject>(for key: String, make: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] as? T {
            return cached
        }
        let formatter = make()
        storage[key] = formatter
        return formatter
    }

    private func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
