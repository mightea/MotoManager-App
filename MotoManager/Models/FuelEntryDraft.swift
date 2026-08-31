import Foundation

/// Crash-safe persistence for an in-progress fuel entry.
///
/// SwiftUI `@State` survives ordinary backgrounding, but not the process being
/// terminated while suspended (memory pressure, a long lock). The draft mirrors
/// every user-editable field of `AddFuelView`: it is written on each change
/// while the sheet is open and cleared when the sheet closes normally (save,
/// cancel, swipe-dismiss). A draft still present at launch therefore means the
/// app died mid-entry — `FuelListView` reopens the sheet seeded from it.
struct FuelEntryDraft: Codable, Equatable {
    let motorcycleId: Int
    /// `nil` for a new entry; the edited record's `clientId` otherwise.
    let editingClientId: UUID?
    var odo: String
    var liters: String
    var price: String
    var total: String
    /// Raw value of `AddFuelView.PriceCouple`.
    var coupleSource: String
    var fullTank: Bool
    var fuelAdditiveAdded: Bool
    var leadSubstituteAdded: Bool
    var currency: String
    var date: Date
    /// Stamped by `persist()`; `.distantPast` in the live snapshot so that
    /// `onChange(of:)` comparisons ignore it.
    var savedAt: Date

    private static let key = "com.motomanager.fuelEntryDraft"
    /// Resurrecting a half-typed entry days later would confuse more than help.
    private static let maxAge: TimeInterval = 24 * 60 * 60

    /// The stored draft, if one exists and hasn't expired.
    static func load(from defaults: UserDefaults = .standard) -> FuelEntryDraft? {
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(FuelEntryDraft.self, from: data),
              Date().timeIntervalSince(draft.savedAt) < maxAge
        else { return nil }
        return draft
    }

    /// The stored draft only if it belongs to the given motorcycle and edit
    /// target (`nil` = new entry).
    static func load(
        motorcycleId: Int,
        editingClientId: UUID?,
        from defaults: UserDefaults = .standard
    ) -> FuelEntryDraft? {
        guard let draft = load(from: defaults),
              draft.motorcycleId == motorcycleId,
              draft.editingClientId == editingClientId
        else { return nil }
        return draft
    }

    func persist(to defaults: UserDefaults = .standard) {
        var stamped = self
        stamped.savedAt = Date()
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Self.key)
    }
}
