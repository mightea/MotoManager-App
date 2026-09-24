//
//  MotoManagerUITests.swift
//  MotoManagerUITests
//
//  Created by Tobias Herrmann on 15.04.2026.
//

import XCTest

final class MotoManagerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoginFormValidation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-logged-out"]
        app.launch()

        let server = app.textFields["login.server"]
        let identifier = app.textFields["login.identifier"]
        let password = app.secureTextFields["login.password"]
        let submit = app.buttons["login.submit"]

        XCTAssertTrue(server.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)

        server.tap()
        server.typeText("https://moto.example.com")
        identifier.tap()
        identifier.typeText("fahrerin")
        password.tap()
        password.typeText("sicheres-passwort")

        XCTAssertTrue(submit.isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Optional, read-only smoke coverage against a seeded server. Credentials
    /// are supplied by the test runner; ordinary local runs need no server.
    @MainActor
    func testAdaptiveWorkspaceAndFuelEditing() throws {
        let app = try launchSeededWorkspace()
        let switchBike = app.buttons["workspace.switchMotorcycle"]
        capture(app, "workspace-portrait")

        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(switchBike.waitForExistence(timeout: 5))
            capture(app, "workspace-tablet-landscape")
        }

        let firstRecord = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fuel.record.'")).firstMatch
        if UIDevice.current.userInterfaceIdiom == .phone {
            for _ in 0..<8 where !firstRecord.exists { app.collectionViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(firstRecord.waitForExistence(timeout: 15), "Use a server with fuel history.")
        let recordID = firstRecord.identifier
        firstRecord.tap()
        XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 5))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(switchBike.isHittable, "Motorcycle context remains available beside a detail.")
        } else {
            XCTAssertFalse(switchBike.isHittable, "Phones open records full screen, covering the header.")
        }
        capture(app, "workspace-fuel-detail")
        app.buttons["Bearbeiten"].tap()

        let odo = app.textFields["fuel.odo"]
        let price = app.textFields["fuel.price"]
        XCTAssertTrue(odo.waitForExistence(timeout: 5))
        let originalOdo = odo.value as? String
        let originalPrice = price.value as? String
        XCTAssertFalse(originalOdo?.isEmpty ?? true)
        odo.tap()
        XCTAssertEqual(odo.value as? String, originalOdo, "Focusing the odometer must preserve all digits.")
        price.tap()
        XCTAssertEqual(price.value as? String, originalPrice, "Focusing the price must preserve its value.")
        odo.tap()
        XCTAssertEqual(odo.value as? String, originalOdo)
        capture(app, "workspace-fuel-form")
        app.buttons["Abbrechen"].tap()

        if UIDevice.current.userInterfaceIdiom == .phone {
            // Expanded Duo details return to their overview; compact phones
            // use native back navigation to return to the list.
            let overview = app.buttons["workspace.overview"]
            let back = app.buttons["BackButton"]
            if overview.isHittable { overview.tap() }
            else if back.exists { back.tap() }
            else { app.navigationBars.buttons.element(boundBy: 0).tap() }
            XCTAssertTrue(app.buttons[recordID].waitForExistence(timeout: 5))
            app.buttons[recordID].tap()
            XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 5), "The same row must reopen after going back.")
        }
        app.buttons["Neue Tankung"].tap()
        XCTAssertTrue(odo.waitForExistence(timeout: 5))
        let seededOdo = odo.value as? String
        let seededPrice = price.value as? String
        odo.tap()
        XCTAssertEqual(odo.value as? String, seededOdo, "New entries must not strip odometer digits on focus.")
        price.tap()
        XCTAssertEqual(price.value as? String, seededPrice, "New entries must not strip price decimals on focus.")
        app.buttons["Abbrechen"].tap()

        for title in ["Technik", "Wartung", "Teile"] {
            let sidebarItem = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
            if sidebarItem.exists { sidebarItem.tap() }
            else { app.buttons[title].firstMatch.tap() }
            XCTAssertTrue(switchBike.waitForExistence(timeout: 5))
            capture(app, "workspace-\(title)")
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            for _ in 0..<8 where !app.staticTexts["parts.scopeSummary"].exists {
                app.collectionViews.firstMatch.swipeUp()
            }
        }
        XCTAssertTrue(app.staticTexts["parts.scopeSummary"].exists)
        let fuelTab = app.cells.matching(NSPredicate(format: "label == 'Tanken'")).firstMatch
        if fuelTab.exists { fuelTab.tap() } else { app.buttons["Tanken"].firstMatch.tap() }
        let identity = app.staticTexts["workspace.motorcycleIdentity"]
        let previousIdentity = identity.label
        switchBike.tap()
        let bikes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'garage.motorcycle.'"))
        XCTAssertTrue(bikes.firstMatch.waitForExistence(timeout: 5))
        if bikes.count > 1 {
            bikes.element(boundBy: 1).tap()
            XCTAssertTrue(switchBike.waitForExistence(timeout: 10))
            XCTAssertNotEqual(identity.label, previousIdentity)
            XCTAssertFalse(app.buttons[recordID].exists, "Switching motorcycles must discard the previous detail and records.")
            XCTAssertFalse(app.buttons["Bearbeiten"].exists)
            capture(app, "workspace-switched-motorcycle")
        } else { app.buttons["Fertig"].tap() }
        XCUIDevice.shared.orientation = .portrait
    }

    /// A split-view sidebar can have compact width inside a regular workspace.
    /// It must never show both the native search drawer and the inline field.
    @MainActor
    func testPartsSearchAcrossLayouts() throws {
        let app = try launchSeededWorkspace()
        defer { XCUIDevice.shared.orientation = .portrait }
        let sidebarItem = app.cells.matching(NSPredicate(format: "label == 'Teile'")).firstMatch
        if sidebarItem.isHittable { sidebarItem.tap() }
        else {
            let partsTab = app.buttons.matching(identifier: "Teile").allElementsBoundByIndex.first { $0.isHittable }
            try XCTUnwrap(partsTab, "The Parts tab must be available.").tap()
        }

        let prompt = "Name oder Teilenummer …"
        let query = "zz-no-matching-part"
        let inventory = app.collectionViews["parts.inventory"]
        let searchField = app.textFields[prompt]
        // The tall iPad portrait view can fit the entire demo list. Check
        // scrolling in landscape with the full inventory, then exercise query
        // persistence in both orientations. The filter is local display state.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        let bikeFilter = inventory.switches.firstMatch
        if bikeFilter.waitForExistence(timeout: 5) && bikeFilter.value as? String == "1" {
            // SwiftUI exposes the whole labeled row as the switch. Tap the
            // trailing control, since the label does not toggle it on iPad.
            bikeFilter.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(bikeFilter.value as? String, "0")
        }
        for _ in 0..<3 where searchField.isHittable { inventory.swipeUp() }
        XCTAssertFalse(searchField.isHittable, "Search must scroll away to free space for parts.")
        XCTAssertFalse(inventory.staticTexts["workspace.listTitle"].isHittable)
        capture(app, "parts-scrolled")
        for (index, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait].enumerated() {
            XCUIDevice.shared.orientation = orientation
            for _ in 0..<6 where !searchField.isHittable { inventory.swipeDown() }
            capture(app, "parts-search-layout-\(index)")
            let fields = (app.searchFields.allElementsBoundByIndex
                + app.textFields.matching(identifier: prompt).allElementsBoundByIndex)
                .filter { $0.isHittable }
            XCTAssertEqual(fields.count, 1, "Each workspace layout must expose exactly one search field.")
            let search = try XCTUnwrap(fields.first)
            if index == 0 {
                search.tap()
                search.typeText(query + "\n")
            } else {
                XCTAssertEqual(search.value as? String, query, "Search must survive layout changes.")
            }
            let summary = app.staticTexts["parts.scopeSummary"]
            for _ in 0..<6 where !summary.exists { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertTrue(summary.label.hasPrefix("0 angezeigt"), "The query must filter the parts list.")
            if index == 2 {
                search.tap()
                if search.elementType == .searchField {
                    search.buttons.firstMatch.tap()
                } else {
                    app.buttons["Suche löschen"].tap()
                }
                XCTAssertEqual(search.value as? String, prompt, "Clearing search removes the entire query.")
                let restored = NSPredicate(format: "NOT label BEGINSWITH '0 angezeigt'")
                expectation(for: restored, evaluatedWith: summary)
                waitForExpectations(timeout: 5)
                capture(app, "parts-search-restored")
            }
        }
    }

    @MainActor
    func testWorkspaceInformationIsNotDuplicated() throws {
        let app = try launchSeededWorkspace()
        defer { XCUIDevice.shared.orientation = .portrait }
        let expanded = ProcessInfo.processInfo.environment["MM_UI_TEST_EXPANDED"] == "1"
            || UIDevice.current.userInterfaceIdiom == .pad
        let fuelHistory = app.collectionViews["fuel.history"]
        let fuelOverview = app.collectionViews["fuel.overview"]
        let consumption = NSPredicate(format: "label BEGINSWITH 'Ø Verbrauch:'")
        let trend = NSPredicate(format: "label BEGINSWITH 'Verbrauchstrend der letzten'")

        for (index, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait].enumerated() {
            XCUIDevice.shared.orientation = orientation
            capture(app, "deduplicated-fuel-\(index)")
            XCTAssertTrue(fuelHistory.waitForExistence(timeout: 5))
            XCTAssertTrue(app.otherElements.matching(consumption).firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.otherElements.matching(consumption).count, 1)
            XCTAssertEqual(fuelHistory.otherElements.matching(consumption).count, expanded ? 0 : 1)
            XCTAssertEqual(fuelHistory.otherElements.matching(trend).count, expanded ? 0 : 1)
            if expanded { XCTAssertTrue(fuelOverview.isHittable) }
            let window = app.windows.firstMatch.frame
            if window.width > window.height && window.height < 750 {
                XCTAssertLessThan(app.otherElements["workspace.header"].frame.height, 150,
                                  "Short landscape windows should have a smaller motorcycle header.")
            }
        }
        if expanded {
            let record = fuelHistory.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fuel.record.'")).firstMatch
            XCTAssertTrue(record.isHittable, "Expanded fuel history starts directly with entries.")
            record.tap()
            XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 5))
            XCTAssertFalse(fuelOverview.exists)
            XCTAssertEqual(fuelHistory.otherElements.matching(consumption).count, 0)
            let backToOverview = app.buttons["workspace.overview"]
            XCTAssertTrue(backToOverview.isHittable, "The return to the overview must be visible in expanded details.")
            XCTAssertTrue(backToOverview.label.contains("Zur Übersicht"))
            capture(app, "fuel-return-to-overview")
            backToOverview.tap()
            XCTAssertTrue(fuelOverview.waitForExistence(timeout: 5))
            XCTAssertEqual(app.otherElements.matching(consumption).count, 1)
        }

        try tapWorkspaceTab("Wartung", in: app)
        let serviceHistory = app.collectionViews["service.history"]
        let serviceOverview = app.collectionViews["service.overview"]
        let serviceStats = NSPredicate(format: "label BEGINSWITH 'Letzte Wartung:'")
        let intervals = NSPredicate(format: "label BEGINSWITH 'Service-Intervalle:'")
        XCTAssertTrue(serviceHistory.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(serviceStats).count, 1)
        XCTAssertEqual(serviceHistory.otherElements.matching(serviceStats).count, expanded ? 0 : 1)
        XCTAssertEqual(app.buttons.matching(intervals).count, 1)
        XCTAssertEqual(serviceHistory.buttons.matching(intervals).count, expanded ? 0 : 1)
        capture(app, "deduplicated-maintenance")
        serviceHistory.buttons["Mängel"].tap()
        let issuePredicate = NSPredicate(format: "identifier BEGINSWITH 'service.issue.'")
        XCTAssertTrue(serviceHistory.buttons.matching(issuePredicate).firstMatch.waitForExistence(timeout: 5))
        if expanded {
            serviceOverview.swipeUp()
            XCTAssertEqual(serviceOverview.buttons.matching(issuePredicate).count, 0)
        }
        capture(app, "deduplicated-issues")

        try tapWorkspaceTab("Technik", in: app)
        let references = app.collectionViews["workshop.references"]
        let referenceOverview = app.collectionViews["workshop.overview"]
        references.buttons["workshop.category.pressure"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Reifendruck bearbeiten").count, 1)
        if expanded {
            XCTAssertFalse(referenceOverview.buttons["Reifendruck bearbeiten"].exists)
        }
        capture(app, "deduplicated-pressure")
        references.buttons["workshop.category.details"].tap()
        let detailPredicate = NSPredicate(format: "identifier BEGINSWITH 'workshop.detail.'")
        let detail = references.buttons.matching(detailPredicate).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        if expanded {
            referenceOverview.swipeUp()
            XCTAssertEqual(referenceOverview.buttons.matching(detailPredicate).count, 0)
        }
        XCTAssertEqual(app.buttons.matching(identifier: detail.identifier).count, 1)
        capture(app, "deduplicated-technical-details")
    }

    @MainActor
    private func tapWorkspaceTab(_ title: String, in app: XCUIApplication) throws {
        let sidebarItem = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if sidebarItem.isHittable { sidebarItem.tap() }
        else {
            let tab = app.buttons.matching(identifier: title).allElementsBoundByIndex.first { $0.isHittable }
            try XCTUnwrap(tab, "The \(title) tab must be available.").tap()
        }
    }

    @MainActor
    private func launchSeededWorkspace() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let serverURL = env["MM_UI_TEST_SERVER"],
              let username = env["MM_UI_TEST_USER"],
              let password = env["MM_UI_TEST_PASSWORD"] else {
            throw XCTSkip("Set MM_UI_TEST_SERVER, MM_UI_TEST_USER and MM_UI_TEST_PASSWORD for workspace smoke coverage.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-logged-out"]
        if env["MM_UI_TEST_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let server = app.textFields["login.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        let existing = server.value as? String ?? ""
        if existing != serverURL {
            server.tap()
            server.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            server.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            server.typeText(serverURL)
        }
        XCTAssertEqual(server.value as? String, serverURL)
        app.textFields["login.identifier"].tap()
        app.textFields["login.identifier"].typeText(username)
        app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText(password)
        // Submitting from the focused field avoids an iPad keyboard transition
        // moving the button while the test synthesizes its tap.
        app.secureTextFields["login.password"].typeText("\n")

        let switchBike = app.buttons["workspace.switchMotorcycle"]
        if app.buttons["Not Now"].waitForExistence(timeout: 5) { app.buttons["Not Now"].tap() }
        if app.buttons["Nicht jetzt"].exists { app.buttons["Nicht jetzt"].tap() }
        XCTAssertTrue(switchBike.waitForExistence(timeout: 30))
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        _ = app.alerts.firstMatch.waitForNonExistence(timeout: 5)
        // Let the system's alert-dismissal and rotation animations settle before
        // taking a visual artifact (element existence alone precedes them).
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        // Duo's inner display is a separate screen; the main screen can be
        // its inactive cover display while the expanded app is visible.
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = index == 0 ? name : "\(name)-screen-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
