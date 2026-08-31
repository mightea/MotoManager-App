import Foundation

/// Detects when the user re-typed a complete value over a fast-entry
/// placeholder in the fuel sheet (see `AddFuelView`'s `prepare*IfNeeded`).
///
/// The prep strips the part of a pre-filled field that usually changes (the
/// odometer's last three digits, the price's decimals) so only the delta needs
/// typing. Users who don't notice the placeholder type the full value again —
/// producing nonsense like 26'594 → "26" + "26500" = "2'626'500". These
/// helpers spot the re-entry and discard the placeholder.
enum FuelEntryRetype {
    /// The user typed a complete odometer reading after the prep prefix.
    ///
    /// Trigger: the digits typed after `prefix` are at least as many as the
    /// pre-strip reading had — a genuine delta is at most the three stripped
    /// digits, while a re-typed reading can't be shorter than the old one
    /// (odometers only grow). Returns the typed digits, which replace the
    /// whole field.
    ///
    /// - Parameters:
    ///   - value: current field text (digits only).
    ///   - prefix: what the prep left in the field (e.g. "26").
    ///   - originalCount: digit count of the reading before stripping (5 for "26594").
    static func fullOdoRetype(value: String, prefix: String, originalCount: Int) -> String? {
        guard !prefix.isEmpty, value.hasPrefix(prefix) else { return nil }
        let typed = value.dropFirst(prefix.count)
        guard typed.count >= originalCount, typed.first != "0" else { return nil }
        return String(typed)
    }

    /// The user re-entered the integer part over a prepped "<integer>." price.
    ///
    /// Trigger: the text typed after `prefix` is one or more digits followed
    /// by a second decimal separator (prep left "1.", the user typed "1." →
    /// the field holds "1.1."). Returns the typed part, which replaces the
    /// whole field. Must run on the raw text — `sanitizeDecimal` would drop
    /// the second separator and hide the signal.
    static func retypedPrice(value: String, prefix: String) -> String? {
        guard !prefix.isEmpty, value.hasPrefix(prefix) else { return nil }
        let typed = value.dropFirst(prefix.count)
        guard typed.count >= 2,
              let last = typed.last, last == "." || last == ",",
              typed.dropLast().allSatisfy(\.isNumber)
        else { return nil }
        return String(typed)
    }
}
