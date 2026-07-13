import XCTest

@MainActor
final class LoggingFlowUITests: XCTestCase {
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
}
