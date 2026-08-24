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

    /// Display year from the backend's model-year field, which may hold a bare
    /// year ("1990") or a month-qualified first registration ("07/1990").
    /// Callers used to take `prefix(4)`, which turned "07/1990" into "07/1".
    nonisolated static func modelYear(_ raw: String) -> String? {
        let numericRuns = raw.split(whereSeparator: { !$0.isNumber })
        if let year = numericRuns.first(where: { $0.count == 4 }) {
            return String(year)
        }
        return numericRuns.first.map(String.init)
    }

    // MARK: - Numbers

    /// Swiss-style grouping (`134'373`), matching how SwiftUI's localized
    /// `Text` interpolation renders Ints elsewhere in the UI. Use this
    /// wherever a number is built into a plain `String` (which bypasses
    /// SwiftUI's localization) so odometer readings format consistently.
    private static let groupedIntFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.numberStyle = .decimal
        return f
    }()

    /// e.g. `kilometers(134373) -> "134'373 km"`.
    static func kilometers(_ value: Int) -> String {
        let number = groupedIntFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) km"
    }

    // MARK: - Currency

    /// e.g. `currency(12.5, code: "CHF") -> "CHF 12.50"`.
    static func currency(_ value: Double, code: String, fractionDigits: Int = 2) -> String {
        "\(code) \(String(format: "%.\(fractionDigits)f", value))"
    }

    /// SF Symbols base name for a currency's sign (compose with ".circle" /
    /// ".circle.fill"). A dollar glyph next to CHF amounts read as wrong.
    nonisolated static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "CHF": return "francsign"
        case "EUR": return "eurosign"
        case "GBP": return "sterlingsign"
        case "JPY": return "yensign"
        default: return "dollarsign"
        }
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
