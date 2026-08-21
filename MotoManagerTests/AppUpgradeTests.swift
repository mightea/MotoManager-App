import Foundation
import Testing
@testable import MotoManager

/// Pure-logic tests for the upgrade decision: soft bound is inclusive
/// (build <= soft → reminder), hard bound is exclusive (build < hard →
/// blocked), and the seeded 0/0 disables both checks.
@MainActor
struct AppUpgradeTests {

    @Test func zeroBoundsDisableBothChecks() {
        #expect(AppUpgradeManager.evaluate(build: 1, softUpgradeBuild: 0, hardUpgradeBuild: 0) == .supported)
        #expect(AppUpgradeManager.evaluate(build: 901, softUpgradeBuild: 0, hardUpgradeBuild: 0) == .supported)
    }

    @Test func softBoundIsInclusive() {
        // At the bound → reminder.
        #expect(AppUpgradeManager.evaluate(build: 1001, softUpgradeBuild: 1001, hardUpgradeBuild: 0) == .updateRecommended)
        // Below the bound → reminder.
        #expect(AppUpgradeManager.evaluate(build: 901, softUpgradeBuild: 1001, hardUpgradeBuild: 0) == .updateRecommended)
        // Above the bound → fine.
        #expect(AppUpgradeManager.evaluate(build: 1002, softUpgradeBuild: 1001, hardUpgradeBuild: 0) == .supported)
    }

    @Test func hardBoundIsExclusive() {
        // Below the bound → blocked.
        #expect(AppUpgradeManager.evaluate(build: 900, softUpgradeBuild: 0, hardUpgradeBuild: 901) == .unsupported)
        // At the bound → the first supported build.
        #expect(AppUpgradeManager.evaluate(build: 901, softUpgradeBuild: 0, hardUpgradeBuild: 901) == .supported)
    }

    @Test func hardBoundWinsOverSoftBound() {
        #expect(AppUpgradeManager.evaluate(build: 900, softUpgradeBuild: 1001, hardUpgradeBuild: 901) == .unsupported)
        // At hard but below soft → reminder only.
        #expect(AppUpgradeManager.evaluate(build: 901, softUpgradeBuild: 1001, hardUpgradeBuild: 901) == .updateRecommended)
    }

    @Test func upgradeInfoDecodesBackendPayload() throws {
        let json = Data(#"{"softUpgradeBuild":1001,"hardUpgradeBuild":901}"#.utf8)
        let info = try JSONDecoder().decode(AppUpgradeInfo.self, from: json)
        #expect(info.softUpgradeBuild == 1001)
        #expect(info.hardUpgradeBuild == 901)
    }
}
