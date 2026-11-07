import Foundation
import Testing
@testable import MotoManager

/// VIN recognition, settings-driven interval rules and the reminder plan —
/// the pure logic behind the motorcycle edit sheet and the Wartung reminders.
@MainActor
struct VehicleAndRemindersTests {

    // MARK: - VIN recognition

    @Test func recognisesVinInNoisyText() {
        #expect(VinRecognizer.vin(in: "Fahrgestell-Nr. WB10A1234LZ123456 Typ") == "WB10A1234LZ123456")
    }

    @Test func normalisesOcrConfusions() {
        // O→0, I→1, Q→0, spaces dropped, lowercase accepted.
        #expect(VinRecognizer.vin(in: "wb1oa1234 lz12345i") == "WB10A1234LZ123451")
    }

    @Test func rejectsShortOrInvalidVins() {
        #expect(VinRecognizer.vin(in: "WB10A1234LZ12345") == nil)
        #expect(VinRecognizer.vin(in: "123456") == nil)
    }

    @Test func frameNumberTakesLongestDigitRun() {
        #expect(VinRecognizer.frameNumber(in: "R51/3 0103596 1951") == "0103596")
        #expect(VinRecognizer.frameNumber(in: "12345") == nil)
    }

    // MARK: - Interval rules from settings

    private func record(type: String, date: String, odo: Int, configure: (SDMaintenanceRecord) -> Void = { _ in }) -> SDMaintenanceRecord {
        let r = SDMaintenanceRecord(serverId: nil, motorcycleId: 1, date: date, odo: odo, recordType: type)
        configure(r)
        return r
    }

    private func isoDate(_ day: String) -> Date { MaintenanceIntervalsEngine.parseISODate(day)! }

    @Test func userYearsOverrideDefaults() {
        var settings = UserSettings.defaults
        settings.engineOilInterval = 1
        let oil = record(type: "fluid", date: "2024-01-01", odo: 90_000) { $0.fluidType = "engineoil" }
        let withDefaults = MaintenanceIntervalsEngine.insights(
            records: [oil], currentOdo: 91_000, now: isoDate("2025-06-01"))
        let withUser = MaintenanceIntervalsEngine.insights(
            records: [oil], currentOdo: 91_000, settings: settings, now: isoDate("2025-06-01"))
        #expect(withDefaults.first { $0.key == "fluid-engineoil" }?.status == .ok)
        #expect(withUser.first { $0.key == "fluid-engineoil" }?.status == .overdue)
        #expect(withUser.first { $0.key == "fluid-engineoil" }?.intervalYears == 1)
    }

    @Test func kmRuleMakesItemDueAndOverdue() {
        var settings = UserSettings.defaults
        settings.engineOilKmInterval = 10_000
        let oil = record(type: "fluid", date: "2025-01-01", odo: 90_000) { $0.fluidType = "engineoil" }
        let now = isoDate("2025-06-01")
        let due = MaintenanceIntervalsEngine.insights(records: [oil], currentOdo: 99_200, settings: settings, now: now)
        let overdue = MaintenanceIntervalsEngine.insights(records: [oil], currentOdo: 100_500, settings: settings, now: now)
        #expect(due.first { $0.key == "fluid-engineoil" }?.status == .due)
        #expect(due.first { $0.key == "fluid-engineoil" }?.kmsRemaining == 800)
        #expect(overdue.first { $0.key == "fluid-engineoil" }?.status == .overdue)
        #expect(overdue.first { $0.key == "fluid-engineoil" }?.kmsRemaining == -500)
    }

    @Test func zeroYearRuleDisablesItem() {
        var settings = UserSettings.defaults
        settings.chainInterval = 0
        let chain = record(type: "chain", date: "2020-01-01", odo: 1_000)
        let insights = MaintenanceIntervalsEngine.insights(
            records: [chain], currentOdo: 2_000, settings: settings, now: isoDate("2025-06-01"))
        #expect(insights.first { $0.key == "chain" } == nil)
    }

    @Test func settingsRoundTripThroughJson() throws {
        var settings = UserSettings.defaults
        settings.tireKmInterval = 15_000
        let data = try JSONSerialization.data(withJSONObject: settings.updatePayload)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded == settings)
        // Cleared km limits are sent as explicit nulls, not omitted.
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["chainKmInterval"] is NSNull)
    }

    // MARK: - Reminder plan

    private func insight(key: String, nextDate: String, years: Int = 2) -> MaintenanceInsight {
        MaintenanceInsight(
            key: key, category: .fluessigkeiten, label: "Motoröl", status: .ok,
            lastDate: isoDate("2024-01-01"), nextDate: isoDate(nextDate),
            intervalYears: years, intervalKms: nil, lastOdo: nil, kmsSinceLast: nil)
    }

    @Test func plansWindowAndDueReminders() {
        let plan = MaintenanceReminderScheduler.plan(
            for: insight(key: "fluid-engineoil", nextDate: "2026-01-01"),
            bikeId: 7, bikeName: "BMW R 51/3", now: isoDate("2025-06-01"))
        #expect(plan.count == 2)
        #expect(plan[0].identifier == "interval.7.fluid-engineoil.due")
        #expect(plan[1].identifier == "interval.7.fluid-engineoil.overdue")
        // The window reminder sits 90 days ahead of the due date, at 09:00.
        let calendar = Calendar.current
        let windowDay = calendar.date(byAdding: .day, value: -90, to: isoDate("2026-01-01"))!
        #expect(calendar.isDate(plan[0].fireDate, inSameDayAs: windowDay))
        #expect(calendar.component(.hour, from: plan[0].fireDate) == 9)
        #expect(plan[1].body.contains("alle 2 Jahre"))
        #expect(plan[0].title.contains("BMW R 51/3"))
    }

    @Test func skipsRemindersAlreadyInThePast() {
        // Due within the window: only the due-date reminder remains.
        let soon = MaintenanceReminderScheduler.plan(
            for: insight(key: "a", nextDate: "2025-07-01"),
            bikeId: 1, bikeName: "X", now: isoDate("2025-06-01"))
        #expect(soon.map(\.identifier) == ["interval.1.a.overdue"])
        // Already overdue: nothing to schedule.
        let overdue = MaintenanceReminderScheduler.plan(
            for: insight(key: "b", nextDate: "2025-01-01"),
            bikeId: 1, bikeName: "X", now: isoDate("2025-06-01"))
        #expect(overdue.isEmpty)
    }
}
