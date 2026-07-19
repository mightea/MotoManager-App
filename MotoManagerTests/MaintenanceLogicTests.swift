import Foundation
import Testing
@testable import MotoManager

/// Pure-logic tests for the service/maintenance display layer: category
/// normalization, summarizer, DOT parsing, grouping and the intervals engine.
@MainActor
struct MaintenanceLogicTests {

    /// Standalone record (no container needed for pure property logic).
    private func record(
        type: String,
        date: String = "2025-06-01",
        odo: Int = 100_000,
        serverId: Int? = nil,
        parentId: Int? = nil,
        cost: Double? = nil,
        currency: String? = nil,
        configure: (SDMaintenanceRecord) -> Void = { _ in }
    ) -> SDMaintenanceRecord {
        let r = SDMaintenanceRecord(serverId: serverId, motorcycleId: 1, date: date, odo: odo, recordType: type)
        r.parentId = parentId
        r.cost = cost
        r.currency = currency
        configure(r)
        return r
    }

    private func isoDate(_ day: String) -> Date {
        MaintenanceIntervalsEngine.parseISODate(day)!
    }

    // MARK: - Category normalization

    @Test func canonicalTypesMapToThemselves() {
        for category in MaintenanceCategory.allCases {
            let (mapped, fluid) = MaintenanceCategory.normalize(type: category.rawValue)
            #expect(mapped == category)
            #expect(fluid == nil)
        }
    }

    @Test func legacyTypesNormalize() {
        let expectations: [(String, MaintenanceCategory, String?)] = [
            ("oil", .fluid, "engineoil"),
            ("engineoil", .fluid, "engineoil"),
            ("gearboxoil", .fluid, "gearboxoil"),
            ("finaldriveoil", .fluid, "finaldriveoil"),
            ("forkoil", .fluid, "forkoil"),
            ("brakefluid", .fluid, "brakefluid"),
            ("coolant", .fluid, "coolant"),
            ("tires", .tire, nil),
            ("brakes", .brakepad, nil),
            ("electric", .battery, nil),
            ("somethingelse", .general, nil),
        ]
        for (raw, category, fluid) in expectations {
            let normalized = MaintenanceCategory.normalize(type: raw)
            #expect(normalized.category == category, "\(raw)")
            #expect(normalized.fluidType == fluid, "\(raw)")
        }
    }

    @Test func explicitFluidTypeWinsOverInference() {
        let normalized = MaintenanceCategory.normalize(type: "oil", fluidType: "gearboxoil")
        #expect(normalized.fluidType == "gearboxoil")
    }

    @Test func legacyOilRecordGetsFluidLabel() {
        let r = record(type: "oil")
        #expect(r.category == .fluid)
        #expect(r.fluidTypeLabel == "Motoröl")
    }

    // MARK: - Summarizer

    @Test func summarizesTireWithAllFields() {
        let r = record(type: "tire") {
            $0.brand = "Michelin"; $0.model = "Road 6"
            $0.tirePosition = "rear"; $0.tireSize = "180/55ZR17"; $0.dotCode = "2423"
        }
        #expect(MaintenanceSummarizer.summarize(r) == "Michelin Road 6 (Hinten) 180/55ZR17 DOT 24/23")
    }

    @Test func summarizesTireFallback() {
        #expect(MaintenanceSummarizer.summarize(record(type: "tire")) == "Reifenwechsel")
    }

    @Test func summarizesFluidWithViscosity() {
        let r = record(type: "fluid") {
            $0.fluidType = "engineoil"; $0.brand = "Motul"; $0.viscosity = "10W-40"
        }
        #expect(MaintenanceSummarizer.summarize(r) == "Motoröl Motul 10W-40")
    }

    @Test func summarizesLegacyOilAsFluid() {
        let r = record(type: "oil")
        #expect(MaintenanceSummarizer.summarize(r) == "Motoröl")
    }

    @Test func summarizesInspectionWithLocation() {
        let r = record(type: "inspection") { $0.locationId = 7 }
        let locations = [Location(id: 7, name: "MFK Bern", type: "garage", latitude: nil, longitude: nil)]
        #expect(MaintenanceSummarizer.summarize(r, locations: locations) == "MFK bei MFK Bern")
        #expect(MaintenanceSummarizer.summarize(r) == "MFK")
    }

    @Test func summarizesServiceFromDescription() {
        let r = record(type: "service") { $0.recordDescription = "Grosser Service" }
        #expect(MaintenanceSummarizer.summarize(r) == "Grosser Service")
        #expect(MaintenanceSummarizer.summarize(record(type: "service")) == "Service")
    }

    @Test func summarizesBatteryWithType() {
        let r = record(type: "battery") { $0.brand = "Varta"; $0.batteryType = "agm" }
        #expect(MaintenanceSummarizer.summarize(r) == "Varta (AGM)")
    }

    // MARK: - DOT parsing

    @Test func parsesValidDotCode() {
        let date = MaintenanceSummarizer.parseDotCode("2423")
        #expect(date != nil)
        let components = Calendar.current.dateComponents([.year], from: date!)
        #expect(components.year == 2023)
    }

    @Test func parsesDotCodeWithPrefixAndWhitespace() {
        #expect(MaintenanceSummarizer.parseDotCode("DOT 1H2X 2423") != nil)
        #expect(MaintenanceSummarizer.parseDotCode(" 24 23 ") != nil)
    }

    @Test func rejectsInvalidDotCodes() {
        #expect(MaintenanceSummarizer.parseDotCode(nil) == nil)
        #expect(MaintenanceSummarizer.parseDotCode("") == nil)
        #expect(MaintenanceSummarizer.parseDotCode("123") == nil)
        #expect(MaintenanceSummarizer.parseDotCode("5923") == nil)  // week 59
        #expect(MaintenanceSummarizer.parseDotCode("ABCD") == nil)
    }

    @Test func formatsDotCode() {
        #expect(MaintenanceSummarizer.formattedDot("2423") == "24/23")
        #expect(MaintenanceSummarizer.formattedDot("XYZ") == "XYZ")
    }

    // MARK: - Grouping

    @Test func mergesSameDayOdoTypeRecords() {
        let a = record(type: "fluid", date: "2025-06-01", odo: 100, cost: 50, currency: "CHF") { $0.fluidType = "engineoil" }
        let b = record(type: "fluid", date: "2025-06-01", odo: 100, cost: 30) { $0.fluidType = "gearboxoil" }
        let groups = MaintenanceGrouper.group([a, b])
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].cost == 80)
        #expect(groups[0].summaries == ["Motoröl", "Getriebeöl"])
    }

    @Test func childRecordsFoldIntoParentGroup() {
        let parent = record(type: "service", date: "2025-06-01", odo: 100, serverId: 10, cost: 200)
        let child = record(type: "fluid", date: "2025-06-01", odo: 100, serverId: 11, parentId: 10, cost: nil) {
            $0.fluidType = "engineoil"
        }
        let groups = MaintenanceGrouper.group([child, parent])
        #expect(groups.count == 1)
        #expect(groups[0].category == .service)
        #expect(groups[0].count == 1)       // child doesn't count
        #expect(groups[0].cost == 200)
        #expect(groups[0].primary?.serverId == 10)
        #expect(groups[0].records.first?.serverId == 10)  // parent sorted first
        #expect(groups[0].summaries.contains("Motoröl"))
    }

    @Test func orphanChildGroupsStandalone() {
        let orphan = record(type: "fluid", date: "2025-06-01", odo: 100, serverId: 11, parentId: 99) {
            $0.fluidType = "engineoil"
        }
        let groups = MaintenanceGrouper.group([orphan])
        #expect(groups.count == 1)
        #expect(groups[0].primary?.serverId == 11)
    }

    @Test func legacyAndCanonicalTypesShareGroup() {
        let legacy = record(type: "oil", date: "2025-06-01", odo: 100)
        let canonical = record(type: "fluid", date: "2025-06-01", odo: 100) { $0.fluidType = "brakefluid" }
        #expect(MaintenanceGrouper.group([legacy, canonical]).count == 1)
    }

    @Test func groupsBucketByYearNewestFirst() {
        let groups = MaintenanceGrouper.group([
            record(type: "service", date: "2023-03-01", odo: 50),
            record(type: "service", date: "2025-06-01", odo: 100),
            record(type: "chain", date: "2025-01-15", odo: 90),
        ])
        let years = MaintenanceGrouper.byYear(groups)
        #expect(years.map(\.year) == ["2025", "2023"])
        #expect(years[0].groups.count == 2)
    }

    @Test func tireMetricShowsPositions() {
        let front = record(type: "tire", date: "2025-06-01", odo: 100) { $0.tirePosition = "front" }
        let rear = record(type: "tire", date: "2025-06-01", odo: 100) { $0.tirePosition = "rear" }
        let groups = MaintenanceGrouper.group([front, rear])
        #expect(MaintenanceGrouper.collapsedMetric(groups[0], fallbackCurrency: "CHF") == "Vorne & Hinten")
    }

    // MARK: - Intervals engine

    @Test func overdueFluidInsight() {
        let r = record(type: "fluid", date: "2020-01-01", odo: 90_000) { $0.fluidType = "engineoil" }
        let insights = MaintenanceIntervalsEngine.insights(
            records: [r], currentOdo: 100_000, now: isoDate("2025-06-01"))
        let engineOil = insights.first { $0.key == "fluid-engineoil" }
        #expect(engineOil?.status == .overdue)
        #expect(engineOil?.kmsSinceLast == 10_000)
    }

    @Test func dueTireInsightUsesDotDate() {
        // DOT week 30/2017 → due 2025-07-xx; "now" within 90 days → due.
        let r = record(type: "tire", date: "2018-05-01", odo: 95_000) {
            $0.tirePosition = "front"; $0.dotCode = "3017"
        }
        let insights = MaintenanceIntervalsEngine.insights(
            records: [r], currentOdo: 100_000, now: isoDate("2025-06-01"))
        let front = insights.first { $0.key == "tire-front" }
        #expect(front?.status == .due)
    }

    @Test func okAndAbsentInsights() {
        let recent = record(type: "fluid", date: "2025-01-01", odo: 99_000) { $0.fluidType = "brakefluid" }
        let insights = MaintenanceIntervalsEngine.insights(
            records: [recent], currentOdo: 100_000, now: isoDate("2025-06-01"))
        #expect(insights.first { $0.key == "fluid-brakefluid" }?.status == .ok)
        // No engine-oil record at all → item absent.
        #expect(insights.first { $0.key == "fluid-engineoil" } == nil)
    }

    @Test func lithiumBatteryUsesLongerInterval() {
        let r = record(type: "battery", date: "2018-01-01", odo: 80_000) { $0.batteryType = "lithium-ion" }
        let insights = MaintenanceIntervalsEngine.insights(
            records: [r], currentOdo: 100_000, now: isoDate("2025-06-01"))
        // 2018 + 10y = 2028 → ok. (Default 6y would already be overdue.)
        #expect(insights.first { $0.key == "battery" }?.status == .ok)
    }

    @Test func legacyCoolantFeedsCoolantInsight() {
        let r = record(type: "coolant", date: "2024-06-01", odo: 98_000)
        let insights = MaintenanceIntervalsEngine.insights(
            records: [r], currentOdo: 100_000, now: isoDate("2025-06-01"))
        #expect(insights.first { $0.key == "fluid-coolant" }?.status == .ok)
    }

    @Test func relativeAgeFormatting() {
        let now = isoDate("2025-06-01")
        #expect(MaintenanceIntervalsEngine.relativeAge(from: isoDate("2023-05-01"), to: now) == "vor 2 Jahren")
        #expect(MaintenanceIntervalsEngine.relativeAge(from: isoDate("2025-03-01"), to: now) == "vor 3 Monaten")
        #expect(MaintenanceIntervalsEngine.relativeAge(from: isoDate("2025-05-27"), to: now) == "vor 5 Tagen")
        #expect(MaintenanceIntervalsEngine.relativeAge(from: isoDate("2024-06-01"), to: now) == "vor 1 Jahr")
    }
}
