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
}
