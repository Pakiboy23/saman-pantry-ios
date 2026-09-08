import XCTest

/// Optional Mac helper for App Store shots. The canonical PNG writer is
/// `scripts/capture-app-store-screenshots.sh` (simctl). These tests launch the
/// same `-UITesting` scenes, assert the seeded kitchen is on screen, and keep
/// screenshot attachments on the test report.
///
/// Demo account (instead of `-UITesting`):
///   SAMAN_DEMO_EMAIL / SAMAN_DEMO_PASSWORD
///   TEST_RUNNER_CAPTURE_USE_DEMO_ACCOUNT=1
final class AppStoreScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .dark
    }

    @MainActor
    func testPantryShowsDesiStaplesAndLowStock() throws {
        let app = launch(scene: "pantry")
        XCTAssertTrue(app.descendants(matching: .any)["screenshot.pantry"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Haldi"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Atta"].exists)
        attach(app, name: "01-pantry")
    }

    @MainActor
    func testRecipeReviewPreservesAndazaSe() throws {
        let app = launch(scene: "recipeReview")
        XCTAssertTrue(app.descendants(matching: .any)["screenshot.recipeReview"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["turmeric"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["haldi — andaza se"].exists)
        attach(app, name: "02-recipe-review")
    }

    @MainActor
    func testShoppingListIsMidCheckout() throws {
        let app = launch(scene: "shoppingList")
        XCTAssertTrue(app.descendants(matching: .any)["screenshot.shoppingList"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Atta"].waitForExistence(timeout: 8) || app.staticTexts["Paneer"].exists)
        attach(app, name: "03-shopping-list")
    }

    @MainActor
    func testHomeDashboardShowsLowStockAndList() throws {
        let app = launch(scene: "home")
        XCTAssertTrue(app.descendants(matching: .any)["screenshot.home"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Running low"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["Patel Brothers"].exists ||
            app.staticTexts["Chicken Karahi"].exists
        )
        attach(app, name: "04-home")
    }

    @MainActor
    func testPaywallSceneLaunches() throws {
        let app = launch(scene: "paywall")
        // RevenueCat's offering UI is network/StoreKit-dependent. Capture
        // whatever actually renders — never substitute a fake marketing image.
        _ = app.descendants(matching: .any)["screenshot.paywall"].waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "05-paywall")
    }

    // MARK: - Launch

    @MainActor
    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        let useDemo = env["CAPTURE_USE_DEMO_ACCOUNT"] == "1"
        let email = env["SAMAN_DEMO_EMAIL"] ?? ""
        let password = env["SAMAN_DEMO_PASSWORD"] ?? ""

        var args = ["-ScreenshotSeed", "-ScreenshotScene", scene, "-ScreenshotAppearance", "dark"]
        if useDemo && !email.isEmpty && !password.isEmpty {
            app.launchArguments = args
            app.launch()
            signIn(app: app, email: email, password: password)
        } else {
            args.insert("-UITesting", at: 0)
            app.launchArguments = args
            app.launch()
        }
        return app
    }

    @MainActor
    private func signIn(app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 12), "Auth screen did not appear for demo sign-in")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["auth.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(
            app.tabBars.buttons["Home"].waitForExistence(timeout: 20) ||
            app.tabBars.buttons["Pantry"].waitForExistence(timeout: 2),
            "Demo account sign-in did not reach the tab shell. Confirm the account is pre-confirmed, or drop CAPTURE_USE_DEMO_ACCOUNT and use -UITesting."
        )
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
