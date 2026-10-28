//
//  macflareUITests.swift
//  macflareUITests
//
//  Created by Peter C. Allport on 6/24/25.
//

import XCTest

final class MacflareUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenAndSignInButton() throws {
        #if DEBUG
        let app = XCUIApplication()
        app.launchEnvironment["MACFLARE_UI_TESTING"] = "1"
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }

        let title = app.staticTexts["welcomeTitle"]
        let subtitle = app.staticTexts["welcomeSubtitle"]
        let signInButton = app.buttons["cloudflareSignInButton"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Macflare")
        XCTAssertEqual(subtitle.value as? String, "Cloudflare for power users on macOS.")
        XCTAssertTrue(signInButton.isEnabled)
        XCTAssertTrue(signInButton.isHittable)
        XCTAssertEqual(signInButton.label, "Sign in with Cloudflare")

        // Inspect the real action without opening a browser or changing a saved session.
        XCTAssertEqual(app.state, .runningForeground)
        #else
        throw XCTSkip("This smoke test requires the Debug-only isolated launch mode.")
        #endif
    }
}
