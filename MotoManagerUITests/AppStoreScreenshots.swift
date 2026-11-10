import XCTest

/// Shoots the App Store listing screenshots. Driven by
/// `scripts/make-screenshots.sh`; skips unless the runner supplies the demo
/// server credentials and an output directory (`MM_UI_TEST_SHOTS`).
///
/// One PNG per listing slot, written at the simulator's native pixel size
/// (iPhone Air 1260x2736, iPad Pro 13" 2064x2752 — the App Store sizes).
final class AppStoreScreenshots: XCTestCase {
    @MainActor
    func testShootListing() throws {
        let env = ProcessInfo.processInfo.environment
        guard let serverURL = env["MM_UI_TEST_SERVER"],
              let username = env["MM_UI_TEST_USER"],
              let password = env["MM_UI_TEST_PASSWORD"],
              let outDir = env["MM_UI_TEST_SHOTS"] else {
            throw XCTSkip("Set MM_UI_TEST_SERVER/USER/PASSWORD and MM_UI_TEST_SHOTS to shoot screenshots.")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        // The argument domain prefills the server field; editing it by
        // keystrokes is unreliable across keyboard layouts.
        app.launchArguments = ["--ui-testing-logged-out", "-com.motomanager.baseURL", serverURL]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.textFields["login.server"].waitForExistence(timeout: 15))
        let identifier = app.textFields["login.identifier"]
        identifier.tap()
        identifier.typeText(username + "\n")   // Return moves focus to the password
        app.typeText(password)
        app.typeText("\n")                      // submits

        if app.buttons["Not Now"].waitForExistence(timeout: 6) { app.buttons["Not Now"].tap() }
        if app.buttons["Nicht jetzt"].exists { app.buttons["Nicht jetzt"].tap() }
        XCTAssertTrue(app.buttons["workspace.switchMotorcycle"].waitForExistence(timeout: 40),
                      "Login against \(serverURL) did not reach the workspace.")
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }

        func shot(_ name: String, settle: TimeInterval = 2.5) {
            RunLoop.current.run(until: Date().addingTimeInterval(settle))
            let png = XCUIScreen.main.screenshot().pngRepresentation
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
            XCTAssertNoThrow(try png.write(to: url))
        }
        func tab(_ title: String) {
            let cell = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
            if cell.exists && cell.isHittable { cell.tap(); return }
            app.buttons.matching(identifier: title).allElementsBoundByIndex.first { $0.isHittable }?.tap()
        }

        // The Dynamic Island stays rendered for ~10 s after launch.
        tab("Tanken");  shot("01-tanken", settle: 12)
        tab("Technik"); shot("02-technik")
        tab("Wartung"); shot("03-wartung")
        tab("Teile");   shot("05-teile")
        if UIDevice.current.userInterfaceIdiom == .pad {
            tab("Statistik"); shot("04-statistik")
        } else {
            tab("Tanken")
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            let stats = app.buttons["statistics.link"]
            if stats.waitForExistence(timeout: 3) {
                stats.tap(); shot("04-statistik")
                if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
                else { app.navigationBars.buttons.element(boundBy: 0).tap() }
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
            let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fuel.record.'")).firstMatch
            if record.waitForExistence(timeout: 5) { record.tap(); shot("06-tankung") }
        }
    }
}
