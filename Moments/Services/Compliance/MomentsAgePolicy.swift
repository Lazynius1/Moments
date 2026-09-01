import Foundation

/// Edad mínima global de cuenta (16+) para rollout internacional excepto China.
enum MomentsAgePolicy {
    static let defaultMinimumAccountAge = 16
    static let indiaMinimumAccountAge = 18
    static let privacyPolicyVersion = "2026-09-01-regional-age-policy"

    /// Region is a policy input only; it is not treated as verified residence.
    static var currentCountryCode: String {
        (Locale.current.region?.identifier ?? Locale.current.regionCode ?? "ZZ").uppercased()
    }

    static func minimumAccountAge(for countryCode: String = currentCountryCode) -> Int {
        countryCode.uppercased() == "IN" ? indiaMinimumAccountAge : defaultMinimumAccountAge
    }

    static func isEligibleForAccount(
        birthDate: Date,
        countryCode: String = currentCountryCode,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let years = calendar.dateComponents(
            [.year],
            from: startOfDay(birthDate, calendar: calendar),
            to: startOfDay(referenceDate, calendar: calendar)
        ).year ?? 0
        return years >= minimumAccountAge(for: countryCode)
    }

    static func defaultPickerBirthDate(countryCode: String = currentCountryCode, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .year,
            value: -minimumAccountAge(for: countryCode),
            to: startOfDay(Date(), calendar: calendar),
            wrappingComponents: false
        ) ?? Date()
    }

    static func maximumSelectableBirthDate(countryCode: String = currentCountryCode, calendar: Calendar = .current) -> Date {
        defaultPickerBirthDate(countryCode: countryCode, calendar: calendar)
    }

    static func minimumSelectableBirthDate(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -120, to: Date(), wrappingComponents: false)
            ?? Date(timeIntervalSince1970: 0)
    }

    static func normalizedBirthDate(_ date: Date, calendar: Calendar = .current) -> Date {
        startOfDay(date, calendar: calendar)
    }

    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
}
