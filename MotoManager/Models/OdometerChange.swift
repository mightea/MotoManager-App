import Foundation

/// The odometer was replaced, or a five-digit counter rolled over (backend
/// migration 065). Readings are raw instrument values.
///
/// Every stored `odo` — on the server and in SwiftData — is the TOTAL distance
/// the bike has run: the instrument reading plus the offsets of all changes
/// dated on or before the record. Forms take what the instrument shows; the
/// view model converts on write and remembers the offset it applied so the
/// server can correct it if this device's list of changes was stale.
struct OdometerChange: Codable, Identifiable, Hashable {
    let id: Int
    let motorcycleId: Int
    /// "YYYY-MM-DD"
    let date: String
    /// What the old instrument showed when it came off.
    let readingBefore: Int
    /// What the new instrument showed when it went on.
    let readingAfter: Int
    /// "replacement" | "rollover"
    let kind: String

    /// Distance this change adds to every later instrument reading.
    var offset: Int { readingBefore - readingAfter }

    var isRollover: Bool { kind == "rollover" }
}

enum Odometer {
    /// The day part of a stored date ("2018-11-22" or an ISO timestamp).
    static func day(_ date: String) -> Substring { date.prefix(10) }

    /// Offset in force on `date`: every change on or before that day counts,
    /// so a record on the day of the swap was read off the new instrument.
    static func offset(_ changes: [OdometerChange], on date: String) -> Int {
        let target = day(date)
        return changes
            .filter { day($0.date) <= target }
            .reduce(0) { $0 + $1.offset }
    }

    /// What the instrument showed for a stored total on `date`.
    static func reading(total: Int, changes: [OdometerChange], on date: String) -> Int {
        max(0, total - offset(changes, on: date))
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        // Calendar day as the user sees it, matching the forms' date pickers.
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

struct OdometerChangeListResponse: Codable {
    let odometerChanges: [OdometerChange]
}
