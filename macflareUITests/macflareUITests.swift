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
    func testWelcomeScreenAndLoginPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let title = app.staticTexts["welcomeTitle"]
        let subtitle = app.staticTexts["welcomeSubtitle"]
        let loginButton = app.buttons["cloudflareLoginButton"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Macflare")
        XCTAssertEqual(subtitle.value as? String, "Cloudflare for power users on macOS.")
        XCTAssertTrue(loginButton.isHittable)
        XCTAssertEqual(loginButton.label, "Login with Cloudflare")

        loginButton.click()

        // Authentication is a placeholder; clicking it must leave the welcome screen usable.
        XCTAssertTrue(title.exists)
        XCTAssertTrue(loginButton.isHittable)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
