import XCTest

@MainActor
final class LoggingFlowUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  func testLogsMockedUSDAFoodAndShowsItInEntries() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("One serving of scrambled eggs")

    let continueButton = app.buttons["continue-button"]
    XCTAssertTrue(continueButton.isEnabled)
    continueButton.tap()

    let result = app.buttons["usda-result-999001"]
    // First parse + search after a cold launch can be slow in the simulator.
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    result.tap()

    let continueReview = app.buttons["continue-from-review"]
    XCTAssertTrue(continueReview.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Here’s what I’ll log"].exists)
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].exists)
    continueReview.tap()

    let justNow = app.buttons["when-eaten-suggestion"].firstMatch
    XCTAssertTrue(justNow.waitForExistence(timeout: 5))
    justNow.tap()

    let saveButton = app.buttons["save-entry"]
    XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Confirm this log?"].exists)
    saveButton.tap()

    let savedStatus = app.descendants(matching: .any)["status-message"]
    XCTAssertTrue(savedStatus.waitForExistence(timeout: 5))
    XCTAssertTrue(savedStatus.label.contains("Entry saved on this device."))

    app.tabBars.buttons["Entries"].tap()

    XCTAssertTrue(app.navigationBars["Entries"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].waitForExistence(timeout: 5))
  }

  func testFreshLogScreenHasOnePromptAndVisibleManualEntry() {
    let app = launchApp()

    XCTAssertTrue(app.navigationBars["JustLogIt"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["What did you eat?"].exists)
    XCTAssertFalse(app.staticTexts["Log Food"].exists)
    XCTAssertTrue(
      app.staticTexts["Your food log stays on this iPhone"].exists
        || app.staticTexts["On-device chat · log stays on this iPhone"].exists
    )

    let plusMenu = app.buttons["composer-plus-menu"]
    XCTAssertTrue(plusMenu.exists)
    plusMenu.tap()
    let manualEntry = app.buttons["Enter nutrition manually"]
    XCTAssertTrue(manualEntry.waitForExistence(timeout: 2))
  }

  func testParserFailureShowsSingleRecoveryPath() {
    let app = launchApp(additionalArguments: ["-ui-testing-parser-failure"])
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("Something unusual")
    app.buttons["continue-button"].tap()

    // A parser failure surfaces one recovery card with the failure title and
    // the two recovery actions — not a duplicated error message.
    XCTAssertTrue(app.staticTexts["Couldn’t read that"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Edit message"].exists)
    XCTAssertTrue(app.buttons["Enter manually"].exists)
  }

  func testManualEntryValidation() {
    let app = launchApp()
    let plusMenu = app.buttons["composer-plus-menu"]
    XCTAssertTrue(plusMenu.waitForExistence(timeout: 5))
    plusMenu.tap()
    let manualEntry = app.buttons["Enter nutrition manually"]
    XCTAssertTrue(manualEntry.waitForExistence(timeout: 2))
    manualEntry.tap()

    let name = app.textFields["manual-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Homemade soup")

    let calories = app.textFields["manual-calories"]
    calories.tap()
    calories.typeText("240")
    XCTAssertTrue(app.buttons["manual-save"].isEnabled)

    let protein = app.textFields["manual-protein"]
    protein.tap()
    protein.typeText("1..2")
    XCTAssertFalse(app.buttons["manual-save"].isEnabled)
    XCTAssertTrue(app.staticTexts["Protein must be a nonnegative number."].exists)
  }

  private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"] + additionalArguments
    app.launch()
    return app
  }
}
