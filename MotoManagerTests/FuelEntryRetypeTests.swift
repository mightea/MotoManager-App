import Testing
@testable import MotoManager

/// Retype detection over the fuel sheet's fast-entry placeholders: a re-typed
/// complete odometer reading or price integer part discards the stripped
/// placeholder instead of concatenating into nonsense.
@MainActor
struct FuelEntryRetypeTests {

    // MARK: - Odometer ("26594" prepped to prefix "26", originalCount 5)

    @Test func deltaTypingKeepsPrefix() {
        // The intended fast path: a 3-digit delta completes the reading.
        #expect(FuelEntryRetype.fullOdoRetype(value: "26612", prefix: "26", originalCount: 5) == nil)
        // Even a sloppy 4-digit entry is not treated as a full retype.
        #expect(FuelEntryRetype.fullOdoRetype(value: "266120", prefix: "26", originalCount: 5) == nil)
    }

    @Test func fullRetypeDropsPlaceholder() {
        #expect(FuelEntryRetype.fullOdoRetype(value: "2626650", prefix: "26", originalCount: 5) == "26650")
    }

    @Test func retypeAcrossDigitGrowth() {
        // 99'950 → prefix "99"; the new reading 100'020 has one digit more.
        #expect(FuelEntryRetype.fullOdoRetype(value: "99100020", prefix: "99", originalCount: 5) == "100020")
    }

    @Test func fourDigitReading() {
        // "2650" strips to prefix "2"; retyping "2700" over it.
        #expect(FuelEntryRetype.fullOdoRetype(value: "22700", prefix: "2", originalCount: 4) == "2700")
    }

    @Test func leadingZeroIsNotAReading() {
        #expect(FuelEntryRetype.fullOdoRetype(value: "2600123", prefix: "26", originalCount: 5) == nil)
    }

    @Test func editedPrefixNeverTriggers() {
        // The user deleted/changed the placeholder themselves — hands off.
        #expect(FuelEntryRetype.fullOdoRetype(value: "3126650", prefix: "26", originalCount: 5) == nil)
        #expect(FuelEntryRetype.fullOdoRetype(value: "", prefix: "26", originalCount: 5) == nil)
    }

    @Test func emptyPrefixNeverTriggers() {
        #expect(FuelEntryRetype.fullOdoRetype(value: "26650", prefix: "", originalCount: 5) == nil)
    }

    // MARK: - Price ("1.68" prepped to prefix "1.")

    @Test func secondSeparatorDropsPlaceholder() {
        #expect(FuelEntryRetype.retypedPrice(value: "1.1.", prefix: "1.") == "1.")
        // Comma keyboards produce the same shape.
        #expect(FuelEntryRetype.retypedPrice(value: "1.2,", prefix: "1.") == "2,")
    }

    @Test func multiDigitIntegerRetype() {
        #expect(FuelEntryRetype.retypedPrice(value: "1.12.", prefix: "1.") == "12.")
    }

    @Test func decimalTypingDoesNotTrigger() {
        // The intended fast path: the user just types the decimals.
        #expect(FuelEntryRetype.retypedPrice(value: "1.7", prefix: "1.") == nil)
        #expect(FuelEntryRetype.retypedPrice(value: "1.72", prefix: "1.") == nil)
    }

    @Test func bareSeparatorDoesNotTrigger() {
        // A lone extra separator has no re-entered integer to promote.
        #expect(FuelEntryRetype.retypedPrice(value: "1..", prefix: "1.") == nil)
    }

    @Test func editedPrefixDoesNotTrigger() {
        #expect(FuelEntryRetype.retypedPrice(value: "2.1.", prefix: "1.") == nil)
        #expect(FuelEntryRetype.retypedPrice(value: "1,1.", prefix: "1.") == nil)
    }
}
