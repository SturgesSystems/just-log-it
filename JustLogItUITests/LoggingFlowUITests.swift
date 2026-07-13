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
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    result.tap()

    let saveButton = app.buttons["save-entry"]
    XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Review entry"].exists)
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].exists)
    saveButton.tap()

    let savedStatus = app.descendants(matching: .any)["status-message"]
    XCTAssertTrue(savedStatus.waitForExistence(timeout: 5))
    XCTAssertTrue(savedStatus.label.contains("Entry saved on this device."))

    app.tabBars.buttons["Entries"].tap()

    XCTAssertTrue(app.navigationBars["Entries"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].waitForExistence(timeout: 5))
  }

  func testComposerKeyboardHasNativeDoneAction() {
    let app = launchApp()
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("Greek yogurt")

    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 2))
    done.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
    XCTAssertTrue(app.buttons["continue-button"].isEnabled)
  }

  func testParserFailureShowsSingleRecoveryPath() {
    let app = launchApp(additionalArguments: ["-ui-testing-parser-failure"])
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("Something unusual")
    app.buttons["continue-button"].tap()

    let recovery = app.textFields["manual-search"]
    XCTAssertTrue(recovery.waitForExistence(timeout: 5))
    XCTAssertFalse(app.textFields["food-description"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["recovery-title"].exists)
    XCTAssertTrue(app.buttons["Search USDA"].isEnabled)
  }

  func testManualEntryValidationAndKeyboardDismissal() {
    let app = launchApp()
    let manualEntry = app.buttons["manual-entry-button"]
    XCTAssertTrue(manualEntry.waitForExistence(timeout: 5))
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

    app.buttons["Done"].tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
  }

  private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"] + additionalArguments
    app.launch()
    return app
  }
}
