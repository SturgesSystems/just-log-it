import XCTest

@MainActor
final class LoggingFlowUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  /// Simulates a Siri pending-log handoff without real Siri: launches with
  /// `-ui-pending-log` + `UI_PENDING_LOG_TEXT`. Source is `.siri`, so the app
  /// auto-submits into the reviewed flow; the description must surface as the
  /// user chat bubble (or still be in the composer if submit is in flight).
  func testPendingFoodLogHandoffShowsFoodDescription() {
    let pendingText = "two scrambled eggs"
    let app = launchApp(
      additionalArguments: ["-ui-pending-log"],
      environment: ["UI_PENDING_LOG_TEXT": pendingText]
    )

    XCTAssertTrue(app.navigationBars["JustLogIt"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Log"].isSelected)

    // ChatUserBubble exposes a combined accessibility label ("You said, …").
    let userBubble = element(containing: "You said, \(pendingText)", in: app)
    if userBubble.waitForExistence(timeout: 5) {
      return
    }

    // Fallback if submit has not run yet: composer still holds the handoff text.
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 2))
    XCTAssertEqual(description.value as? String, pendingText)
  }

  func testLogsMockedUSDAFoodAndShowsItInEntries() {
    continueAfterFailure = false
    let app = launchApp()
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
        || app.staticTexts["Food interpretation stays on this iPhone"].exists
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
    XCTAssertTrue(app.buttons["recovery-edit-message"].exists)
    XCTAssertTrue(app.buttons["recovery-search-usda"].exists)
    XCTAssertTrue(app.buttons["recovery-manual-entry"].exists)

    // The preserved text can go straight to USDA without invoking the failed
    // parser again.
    app.buttons["recovery-search-usda"].tap()
    XCTAssertTrue(app.buttons["usda-result-999001"].waitForExistence(timeout: 10))

    // The other recovery route opens a usable Manual Entry form.
    app.buttons["new-conversation"].tap()
    let freshDescription = app.textFields["food-description"]
    XCTAssertTrue(freshDescription.waitForExistence(timeout: 5))
    freshDescription.tap()
    freshDescription.typeText("Still unusual")
    app.buttons["continue-button"].tap()
    XCTAssertTrue(app.buttons["recovery-manual-entry"].waitForExistence(timeout: 5))
    app.buttons["recovery-manual-entry"].tap()
    XCTAssertTrue(app.textFields["manual-name"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Manual Entry"].exists)
  }

  func testExplicitEggCountUsesLargeEggPortionAndShowsScaledNutrition() {
    let app = launchApp(additionalArguments: ["-ui-testing-egg-portions"])
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("Two large scrambled eggs")
    app.buttons["continue-button"].tap()

    let result = app.buttons["usda-result-999002"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()
    XCTAssertTrue(app.buttons["continue-from-review"].waitForExistence(timeout: 10))
    XCTAssertTrue(element(containing: "two large scrambled eggs", in: app).exists)
    XCTAssertTrue(element(containing: "180.6 kcal", in: app).exists)
    XCTAssertFalse(app.staticTexts["1 serving"].exists)
  }

  func testHybridDeterministicEggPathWorksWithoutFoundationModels() {
    let app = launchApp(
      additionalArguments: ["-hybrid-parser", "-ui-testing-egg-portions"])
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("Two large scrambled eggs")
    app.buttons["continue-button"].tap()

    // The simulator cannot run the on-device model. Reaching review proves this
    // family took the deterministic route and still used the normal USDA flow.
    let result = app.buttons["usda-result-999002"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()
    XCTAssertTrue(app.buttons["continue-from-review"].waitForExistence(timeout: 10))
    XCTAssertTrue(element(containing: "two large scrambled eggs", in: app).exists)
    XCTAssertTrue(element(containing: "180.6 kcal", in: app).exists)
    XCTAssertFalse(app.staticTexts["1 serving"].exists)
  }

  func testProductionDeterministicFirstEggPathWorksWithoutFoundationModels() {
    let app = launchApp(
      additionalArguments: ["-deterministic-parser", "-ui-testing-egg-portions"])
    submit("Two large scrambled eggs", in: app)

    // The production architecture's baseline model is unavailable on Simulator. Reaching the
    // picker proves this allowlisted family neither waited for nor fell through to that model.
    let result = app.buttons["usda-result-999002"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()
    XCTAssertTrue(app.buttons["continue-from-review"].waitForExistence(timeout: 10))
    XCTAssertTrue(element(containing: "two large scrambled eggs", in: app).exists)
    XCTAssertTrue(element(containing: "180.6 kcal", in: app).exists)
  }

  func testHybridSemanticNamedDishStaysOneFood() {
    let app = launchApp(
      additionalArguments: ["-hybrid-parser", "-ui-testing-hybrid-named-dish"])
    submit("Mac and cheese", in: app)

    // The semantic proposal explicitly classifies this named dish as one food.
    // It must reach one USDA picker instead of splitting on “and”.
    let result = app.buttons["usda-result-999003"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()

    let continueReview = app.buttons["continue-from-review"]
    if !continueReview.waitForExistence(timeout: 2) {
      let oneServing = app.buttons["quantity-suggestion"].firstMatch
      XCTAssertTrue(oneServing.waitForExistence(timeout: 5))
      oneServing.tap()
    }
    XCTAssertTrue(continueReview.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Macaroni and cheese"].exists)
    XCTAssertFalse(app.staticTexts["Here’s the meal"].exists)
  }

  func testHybridSemanticCompositeWalksEachFoodThenShowsOneMeal() {
    let app = launchApp(
      additionalArguments: ["-hybrid-parser", "-ui-testing-hybrid-composite"])
    submit("Eggs and toast", in: app)

    let eggs = app.buttons["usda-result-999004"]
    XCTAssertTrue(eggs.waitForExistence(timeout: 10))
    eggs.tap()

    // Confirming the first match advances the same composite session to toast.
    let toast = app.buttons["usda-result-999005"]
    XCTAssertTrue(toast.waitForExistence(timeout: 10))
    toast.tap()

    XCTAssertTrue(app.buttons["continue-from-review"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Here’s the meal"].exists)
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].exists)
    XCTAssertTrue(app.staticTexts["Toast, white"].exists)
  }

  func testHybridUnsafeAmountBindingOffersEditableManualUSDARecovery() {
    let app = launchApp(
      additionalArguments: ["-hybrid-parser", "-ui-testing-hybrid-unsafe-amount"])
    submit("2 scoops protein powder", in: app)

    XCTAssertTrue(app.staticTexts["Couldn’t read that"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["recovery-edit-message"].exists)
    XCTAssertTrue(app.buttons["recovery-search-usda"].exists)
    XCTAssertFalse(element(containing: "unsafeAmountBinding", in: app).exists)
    XCTAssertFalse(element(containing: "deterministic", in: app).exists)

    // Manual USDA recovery retains the user's words and remains editable after results arrive.
    app.buttons["recovery-search-usda"].tap()
    XCTAssertTrue(app.buttons["usda-result-999006"].waitForExistence(timeout: 10))
    let manualSearch = app.textFields["manual-search"]
    XCTAssertTrue(manualSearch.exists)
    XCTAssertTrue(element(containing: "You said, 2 scoops protein powder", in: app).exists)
    manualSearch.tap()
    manualSearch.typeText("chocolate protein powder")
    XCTAssertEqual(manualSearch.value as? String, "chocolate protein powder")
    let searchAgain = app.buttons["search-usda-button"]
    XCTAssertTrue(searchAgain.exists)
    searchAgain.tap()
    XCTAssertTrue(app.buttons["usda-result-999006"].waitForExistence(timeout: 10))
  }

  func testHybridGroundedApproximationPreservesAmountThroughUSDAReview() {
    let app = launchApp(
      additionalArguments: ["-hybrid-parser", "-ui-testing-hybrid-grounded-approximation"])
    submit("nearly two tablespoons olive oil", in: app)

    let review = app.buttons["continue-from-review"]
    if !review.waitForExistence(timeout: 5) {
      // The app may require a user pick when more than one plausible USDA match exists.
      let result = app.buttons["usda-result-999007"]
      XCTAssertTrue(result.waitForExistence(timeout: 5))
      result.tap()
    }

    XCTAssertTrue(review.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Olive oil"].exists)
    XCTAssertTrue(element(containing: "nearly two tablespoons", in: app).exists)
    XCTAssertTrue(element(containing: "Approximate quantity", in: app).exists)
    XCTAssertFalse(app.staticTexts["1 serving"].exists)
  }

  func testHybridSemanticUnavailableOffersWorkingRecovery() {
    assertHybridSemanticRecovery(
      argument: "-ui-testing-hybrid-semantic-unavailable")
  }

  func testHybridSemanticRefusalOffersWorkingRecovery() {
    assertHybridSemanticRecovery(
      argument: "-ui-testing-hybrid-semantic-refused")
  }

  func testHybridSemanticInvalidResponseOffersWorkingRecovery() {
    assertHybridSemanticRecovery(
      argument: "-ui-testing-hybrid-semantic-invalid")
  }

  func testUnsizedEggCountAsksForSizeInsteadOfDefaultingToServing() {
    let app = launchApp(additionalArguments: ["-ui-testing-ambiguous-egg-portions"])
    submit("Two scrambled eggs", in: app)

    // USDA search results do not include food portions. Choose the match so the app can fetch
    // details and discover that both large and small egg portions are available.
    let result = app.buttons["usda-result-999002"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()

    let explanation = element(containing: "more than one matching size", in: app)
    XCTAssertTrue(explanation.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["continue-from-review"].exists)
    XCTAssertFalse(app.staticTexts["1 serving"].exists)
  }

  func testCustomWhenEatenAnswerIsSubmittedInsteadOfJustNow() {
    let app = launchApp()
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("One serving of scrambled eggs")
    app.buttons["continue-button"].tap()

    let result = app.buttons["usda-result-999001"]
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    result.tap()

    let continueReview = app.buttons["continue-from-review"]
    XCTAssertTrue(continueReview.waitForExistence(timeout: 5))
    continueReview.tap()

    let whenEaten = app.textFields["when-eaten-answer"]
    XCTAssertTrue(whenEaten.waitForExistence(timeout: 5))
    whenEaten.tap()
    // Match the food-composer safeguard: Simulator keyboard synthesis can drop
    // the final character when Send is tapped immediately after typing.
    whenEaten.typeText("2 hours ago ")
    app.buttons["when-eaten-continue"].tap()

    // ChatUserBubble intentionally combines its child Text into one accessible
    // element, so assert the bubble's public accessibility label rather than a
    // StaticText child that is not exposed to XCUI.
    XCTAssertTrue(
      element(containing: "You said, 2 hours ago", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element(containing: "You said, Just now", in: app).exists)
    let save = app.buttons["save-entry"]
    XCTAssertTrue(save.exists)
    XCTAssertTrue(app.descendants(matching: .any)["confirm-consumed-at"].exists)
    save.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["status-message"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Entries"].tap()
    XCTAssertTrue(app.staticTexts["Eggs, scrambled"].waitForExistence(timeout: 5))
  }

  func testRecognizedFoodLogAgainReturnsToLogWithPrefilledComposer() {
    let app = launchApp()
    saveMockEggs(in: app)

    let openFood = app.buttons["open-food"]
    XCTAssertTrue(openFood.waitForExistence(timeout: 5))
    openFood.tap()

    let logAgain = app.buttons["log-food-again"]
    XCTAssertTrue(logAgain.waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Eggs, scrambled"].exists)
    logAgain.tap()

    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    XCTAssertEqual(description.value as? String, "Eggs, scrambled")
    XCTAssertTrue(app.tabBars.buttons["Log"].isSelected)
  }

  func testRememberedFoodIsVisibleAndRepeatSearchStillRequiresUserSelection() {
    let app = launchApp()
    saveMockEggs(in: app)

    app.tabBars.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.descendants(matching: .any)["remembered-food-999001"].waitForExistence(timeout: 5))

    app.tabBars.buttons["Log"].tap()
    let logAnother = app.buttons["log-another"]
    XCTAssertTrue(logAnother.waitForExistence(timeout: 5))
    logAnother.tap()

    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("One serving of scrambled eggs")
    app.buttons["continue-button"].tap()

    // Memory may rank a previously confirmed match first, but it is never
    // permission to choose nutrition without another explicit tap.
    XCTAssertTrue(app.buttons["usda-result-999001"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["continue-from-review"].exists)
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
    typeTextVerifyingDelivery("Homemade soup", into: name)

    let calories = app.textFields["manual-calories"]
    typeTextVerifyingDelivery("240", into: calories)
    XCTAssertTrue(app.buttons["manual-save"].isEnabled)

    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 3))
    done.tap()
    XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
    XCTAssertEqual(name.value as? String, "Homemade soup")
    XCTAssertEqual(calories.value as? String, "240")

    let protein = app.textFields["manual-protein"]
    protein.tap()
    protein.typeText("1..2")
    XCTAssertFalse(app.buttons["manual-save"].isEnabled)
    XCTAssertTrue(app.staticTexts["Protein must be a nonnegative number."].exists)
  }

  func testVolatileStoreBlocksConversationalAndManualSaves() {
    let app = launchApp(additionalArguments: ["-ui-testing-volatile-store"])
    XCTAssertTrue(
      app.descendants(matching: .any)["volatile-store-warning"].waitForExistence(timeout: 5))

    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("One serving of scrambled eggs")
    app.buttons["continue-button"].tap()
    let result = app.buttons["usda-result-999001"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()
    let continueReview = app.buttons["continue-from-review"]
    XCTAssertTrue(continueReview.waitForExistence(timeout: 5))
    continueReview.tap()
    let justNow = app.buttons["when-eaten-suggestion"].firstMatch
    XCTAssertTrue(justNow.waitForExistence(timeout: 5))
    justNow.tap()

    let save = app.buttons["save-entry"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    XCTAssertFalse(save.isEnabled)
    XCTAssertTrue(
      app.descendants(matching: .any)["volatile-confirmation-warning"].exists)

    app.terminate()
    app.launch()
    XCTAssertTrue(
      app.descendants(matching: .any)["volatile-store-warning"].waitForExistence(timeout: 5))
    app.buttons["composer-plus-menu"].tap()
    app.buttons["Enter nutrition manually"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["volatile-manual-warning"].waitForExistence(timeout: 5))
    let name = app.textFields["manual-name"]
    name.tap()
    name.typeText("Homemade soup")
    let calories = app.textFields["manual-calories"]
    calories.tap()
    calories.typeText("240")
    XCTAssertFalse(app.buttons["manual-save"].isEnabled)
  }

  private func launchApp(
    additionalArguments: [String] = [],
    environment: [String: String] = [:]
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-ui-testing",
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US",
      ] + additionalArguments
    if !environment.isEmpty {
      app.launchEnvironment = environment
    }
    app.launch()
    return app
  }

  private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
      .firstMatch
  }

  /// XCUI keyboard synthesis on the iOS 27 beta can occasionally return before the final
  /// character is delivered. Complete a missing suffix once, but fail on any other mutation so
  /// this safeguard cannot hide an app-side replacement or formatting defect.
  private func typeTextVerifyingDelivery(_ text: String, into field: XCUIElement) {
    field.tap()
    field.typeText(text)

    guard let delivered = field.value as? String, delivered != text else { return }
    guard text.hasPrefix(delivered) else {
      XCTFail("Expected \(text.debugDescription), received \(delivered.debugDescription)")
      return
    }

    field.typeText(String(text.dropFirst(delivered.count)))
    XCTAssertEqual(field.value as? String, text)
  }

  private func submit(_ text: String, in app: XCUIApplication) {
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    // A trailing disposable character prevents Simulator keyboard synthesis from occasionally
    // dropping the final food-name character when Continue is tapped immediately afterward.
    description.typeText(text + " ")
    app.buttons["continue-button"].tap()
  }

  private func assertHybridSemanticRecovery(argument: String) {
    let app = launchApp(additionalArguments: ["-hybrid-parser", argument])
    submit("Mac and cheese", in: app)

    let editMessage = app.buttons["recovery-edit-message"]
    XCTAssertTrue(editMessage.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["recovery-manual-entry"].exists)

    // The original user evidence is preserved as an editable/manual USDA query.
    let searchUSDA = app.buttons["recovery-search-usda"]
    XCTAssertTrue(searchUSDA.exists)
    searchUSDA.tap()
    XCTAssertTrue(app.buttons["usda-result-999001"].waitForExistence(timeout: 10))
  }

  private func saveMockEggs(in app: XCUIApplication) {
    let description = app.textFields["food-description"]
    XCTAssertTrue(description.waitForExistence(timeout: 5))
    description.tap()
    description.typeText("One serving of scrambled eggs")
    app.buttons["continue-button"].tap()

    let result = app.buttons["usda-result-999001"]
    XCTAssertTrue(result.waitForExistence(timeout: 10))
    result.tap()

    let continueReview = app.buttons["continue-from-review"]
    XCTAssertTrue(continueReview.waitForExistence(timeout: 5))
    continueReview.tap()

    let justNow = app.buttons["when-eaten-suggestion"].firstMatch
    XCTAssertTrue(justNow.waitForExistence(timeout: 5))
    justNow.tap()

    let save = app.buttons["save-entry"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    save.tap()
    XCTAssertTrue(app.buttons["open-food"].waitForExistence(timeout: 5))
  }
}
