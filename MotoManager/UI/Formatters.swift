import Foundation

/// Centralized, cached formatters.
///
/// Replaces six per-view `DateFormatter()` instances (each rebuilt on every
/// render and hardcoding `de_DE`) and the scattered currency string-building.
/// `DateFormatter` allocation is expensive, so the instances here are created
/// once and reused.
enum Formatters {
    /// Display locale for the German-only UI. Kept as a single source of truth
    /// so a future localization pass has one place to change.
    static let displayLocale = Locale(identifier: "de_DE")

    // MARK: - Dates

    /// Parses the backend's `yyyy-MM-dd` day strings (locale-independent).
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = displayLocale
        f.dateFormat = "d. MMM yyyy"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = displayLocale
        f.dateFormat = "dd.MM."
        return f
    }()

    private static let dayMonthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = displayLocale
        f.dateFormat = "d. MMM"
        return f
    }()

    private static func parseDay(_ iso: String) -> Date? {
        dayParser.date(from: String(iso.prefix(10)))
    }

    /// e.g. `"15. Okt 2023"`. Returns the raw input if it can't be parsed.
    static func mediumDate(_ iso: String) -> String {
        guard let date = parseDay(iso) else { return iso }
        return mediumDateFormatter.string(from: date)
    }

    /// e.g. `"15.10."`. Returns the raw input if it can't be parsed.
    static func dayMonth(_ iso: String) -> String {
        guard let date = parseDay(iso) else { return iso }
        return dayMonthFormatter.string(from: date)
    }

    /// e.g. `"15. Okt"` — day + month name without the year, for rows that sit
    /// under a year section header. Returns the raw input if it can't be parsed.
    static func dayMonthName(_ iso: String) -> String {
        guard let date = parseDay(iso) else { return iso }
        return dayMonthNameFormatter.string(from: date)
    }

    // MARK: - Currency

    /// e.g. `currency(12.5, code: "CHF") -> "CHF 12.50"`.
    static func currency(_ value: Double, code: String, fractionDigits: Int = 2) -> String {
        "\(code) \(String(format: "%.\(fractionDigits)f", value))"
    }

    /// The minor-unit label for a currency, when it has a conventional one.
    static func minorUnitLabel(for currency: String) -> String? {
        switch currency.uppercased() {
        case "CHF": return "Rp."
        case "EUR": return "ct"
        case "USD": return "¢"
        case "GBP": return "p"
        default: return nil
        }
    }

    /// Cost-per-kilometer display. For currencies with a minor unit this shows
    /// e.g. `"12.3 Rp."` (CHF); otherwise it falls back to `"USD 0.12/km"`
    /// rather than mislabeling every currency as Swiss Rappen.
    static func costPerKilometer(_ value: Double, currency: String) -> String {
        if let minor = minorUnitLabel(for: currency) {
            return String(format: "%.1f %@", value * 100, minor)
        }
        return String(format: "%@ %.2f/km", currency, value)
    }
}
