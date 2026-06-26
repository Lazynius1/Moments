import Foundation

/// Centralized locale-aware formatting for dates, times, counts, and distances.
/// Feed timestamps use compact Instagram-style units (`time.*` keys).
/// Absolute dates and measurements use native `FormatStyle` / Foundation formatters with `Locale.current`.
/// No user-visible `DateFormatter.dateFormat = ...` should live outside this file.
enum MomentsFormat {

    // MARK: - Relative time

    enum RelativeTimeStyle {
        /// Compact feed style: `5 min ago` / `hace 5 min` via `time.*` localization keys.
        case compact
        /// Locale-native relative wording, limited to a single unit for Instagram-like brevity.
        case conversational(unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .abbreviated)
    }

    enum DateContext {
        case feedTimestamp
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
            return compactRelativeTime(from: date, relativeTo: reference)
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
            let components = calendar.dateComponents(
                [.day, .hour, .minute, .second],
                from: date,
                to: reference
            )
            if let day = components.day, day >= 7 || (components.year ?? 0) > 0 {
                if calendar.isDate(date, equalTo: reference, toGranularity: .year) {
                    return date.formatted(.dateTime.month(.abbreviated).day())
                }
                return date.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return compactRelativeTime(from: date, relativeTo: reference)

        case .chatSeparator:
            if calendar.isDateInToday(date) {
                return NSLocalizedString("chat.date.today", comment: "Today")
            }
            if calendar.isDateInYesterday(date) {
                return NSLocalizedString("chat.date.yesterday", comment: "Yesterday")
            }
            if calendar.isDate(date, equalTo: reference, toGranularity: .year) {
                return date.formatted(.dateTime.month(.abbreviated).day())
            }
            return date.formatted(date: .abbreviated, time: .omitted)

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

    private static func compactRelativeTime(from date: Date, relativeTo reference: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .weekOfYear, .day, .hour, .minute, .second],
            from: date,
            to: reference
        )

        var timeString = ""

        if let year = components.year, year > 0 {
            let unit = NSLocalizedString(year == 1 ? "time.unit.yr" : "time.unit.yrs", comment: "Year unit")
            timeString = compactValueAndUnit(year, unit: unit)
        } else if let month = components.month, month > 0 {
            let unit = NSLocalizedString(month == 1 ? "time.unit.mo" : "time.unit.mos", comment: "Month unit")
            timeString = compactValueAndUnit(month, unit: unit)
        } else if let week = components.weekOfYear, week > 0 {
            let unit = NSLocalizedString("time.unit.wk", comment: "Week unit")
            timeString = compactValueAndUnit(week, unit: unit)
        } else if let day = components.day, day > 0 {
            let unit = NSLocalizedString("time.unit.d", comment: "Day unit")
            timeString = compactValueAndUnit(day, unit: unit)
        } else if let hour = components.hour, hour > 0 {
            let unit = NSLocalizedString("time.unit.h", comment: "Hour unit")
            timeString = compactValueAndUnit(hour, unit: unit)
        } else if let minute = components.minute, minute > 0 {
            let unit = NSLocalizedString("time.unit.min", comment: "Minute unit")
            timeString = compactValueAndUnit(minute, unit: unit)
        } else {
            return NSLocalizedString("time.now", comment: "Just now")
        }

        let format = NSLocalizedString("time.ago", comment: "Time ago")
        return String(format: format, timeString)
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func narrowWeekdaySymbol(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.count == 7
            ? calendar.veryShortStandaloneWeekdaySymbols
            : calendar.veryShortWeekdaySymbols
        let index = max(0, min(symbols.count - 1, calendar.component(.weekday, from: date) - 1))
        return symbols[index]
    }

    private static func compactValueAndUnit(_ value: Int, unit: String) -> String {
        let separator = unit.count == 1 ? "" : " "
        return "\(value)\(separator)\(unit)"
    }

    private static func firstNonZero(_ value: Int?) -> Int? {
        guard let value, value != 0 else { return nil }
        return value
    }
}
