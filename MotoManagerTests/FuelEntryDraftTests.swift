import Foundation
import Testing
@testable import MotoManager

/// The crash-safe fuel-entry draft: round-trip, scoping to motorcycle/edit
/// target, expiry, and clearing. Uses a suite-named UserDefaults so the tests
/// never touch the app's real draft.
@MainActor
struct FuelEntryDraftTests {

    private func makeDefaults() -> UserDefaults {
        let name = "FuelEntryDraftTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeDraft(motorcycleId: Int = 7, editingClientId: UUID? = nil) -> FuelEntryDraft {
        FuelEntryDraft(
            motorcycleId: motorcycleId,
            editingClientId: editingClientId,
            odo: "26712", liters: "14.5", price: "1.68", total: "24.36",
            coupleSource: "perLiter",
            fullTank: true, fuelAdditiveAdded: false, leadSubstituteAdded: true,
            currency: "CHF", date: Date(timeIntervalSince1970: 1_756_000_000),
            savedAt: .distantPast
        )
    }

    @Test func roundTripsAllFields() {
        let defaults = makeDefaults()
        let draft = makeDraft()
        draft.persist(to: defaults)

        let loaded = FuelEntryDraft.load(motorcycleId: 7, editingClientId: nil, from: defaults)
        #expect(loaded != nil)
        #expect(loaded?.odo == "26712")
        #expect(loaded?.liters == "14.5")
        #expect(loaded?.price == "1.68")
        #expect(loaded?.total == "24.36")
        #expect(loaded?.coupleSource == "perLiter")
        #expect(loaded?.fullTank == true)
        #expect(loaded?.leadSubstituteAdded == true)
        #expect(loaded?.currency == "CHF")
        #expect(loaded?.date == Date(timeIntervalSince1970: 1_756_000_000))
    }

    @Test func persistStampsSavedAt() {
        let defaults = makeDefaults()
        makeDraft().persist(to: defaults)
        // A .distantPast stamp would fail the age gate — load succeeding proves
        // persist() re-stamped it.
        #expect(FuelEntryDraft.load(from: defaults) != nil)
    }

    @Test func scopedToMotorcycleAndEditTarget() {
        let defaults = makeDefaults()
        makeDraft(motorcycleId: 7).persist(to: defaults)

        // Другой bike → no draft; same bike but an edit sheet → no draft.
        #expect(FuelEntryDraft.load(motorcycleId: 8, editingClientId: nil, from: defaults) == nil)
        #expect(FuelEntryDraft.load(motorcycleId: 7, editingClientId: UUID(), from: defaults) == nil)
        #expect(FuelEntryDraft.load(motorcycleId: 7, editingClientId: nil, from: defaults) != nil)

        // Edit drafts only surface for the record they belong to.
        let clientId = UUID()
        makeDraft(motorcycleId: 7, editingClientId: clientId).persist(to: defaults)
        #expect(FuelEntryDraft.load(motorcycleId: 7, editingClientId: nil, from: defaults) == nil)
        #expect(FuelEntryDraft.load(motorcycleId: 7, editingClientId: clientId, from: defaults) != nil)
    }

    @Test func expiredDraftIsDropped() {
        let defaults = makeDefaults()
        var stale = makeDraft()
        stale.savedAt = Date(timeIntervalSinceNow: -25 * 60 * 60)
        // Bypass persist() (which would re-stamp) to plant an old draft.
        let data = try! JSONEncoder().encode(stale)
        defaults.set(data, forKey: "com.motomanager.fuelEntryDraft")

        #expect(FuelEntryDraft.load(from: defaults) == nil)
    }

    @Test func clearRemovesDraft() {
        let defaults = makeDefaults()
        makeDraft().persist(to: defaults)
        FuelEntryDraft.clear(from: defaults)
        #expect(FuelEntryDraft.load(from: defaults) == nil)
    }
}
