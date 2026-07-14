import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class LogConversationTests: XCTestCase {
  func testConfirmIsRequiredBeforeMarkSavedProducesCompletedStage() async throws {
    let model = await advanceToReviewing()
    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertNil(model.lastSavedEntryID)

    // Review alone must not complete a save.
    XCTAssertNotEqual(model.stage, .completed)

    model.continueFromReview()
    // Default test input has no meal-time cue → ask when eaten.
    if model.stage == .whenEaten {
      model.applyWhenEatenSuggestion("Just now")
    }
    XCTAssertEqual(model.stage, .confirming)

    let record = try model.makeRecord()
    XCTAssertEqual(record.displayName, "Eggs, scrambled")
    // Still not completed until markSaved (view inserts then marks).
    XCTAssertEqual(model.stage, .confirming)

    let entryID = UUID()
    let foodID = UUID()
    model.markSaved(entryID: entryID, recognizedFoodID: foodID)

    XCTAssertEqual(model.stage, .completed)
    XCTAssertEqual(model.lastSavedEntryID, entryID)
    XCTAssertEqual(model.lastSavedRecognizedFoodID, foodID)
  }

  func testNeverCompletesWithoutConfirmAfterFullPipeline() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    if model.stage == .whenEaten {
      model.submitWhenEaten()
    }
    XCTAssertEqual(model.stage, .confirming)
    XCTAssertNil(model.lastSavedEntryID)
    XCTAssertNotEqual(model.stage, .completed)
  }

  func testClearJustAteSkipsWhenEatenAndShowsOnReview() async {
    let model = LogViewModel(
      parser: StaticFoodParser(productName: "Big Mac", searchTerms: "Big Mac"),
      provider: SingleBigMacProvider()
    )
    model.input = "I just ate a Big Mac"
    model.submit()
    await waitUntil { model.stage == .reviewing || model.stage == .choosing || model.stage == .failed }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .reviewing }
    }
    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.consumedAtInference?.isClear, true)
    XCTAssertEqual(model.consumedAtInference?.displayLabel, "Just now")

    model.continueFromReview()
    XCTAssertEqual(model.stage, .confirming)
    XCTAssertNotEqual(model.stage, .whenEaten)
  }

  func testEditUserMessageRewindsTranscriptAndClearsResults() async {
    let model = await advanceToReviewing()
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertNotNil(model.selectedResult)
    XCTAssertGreaterThanOrEqual(model.transcript.filter(\.isUser).count, 1)

    guard case .user(let id, _, _) = model.transcript.first(where: \.isUser) else {
      XCTFail("Expected a user turn in the transcript")
      return
    }

    model.editUserMessage(id: id, newText: "one apple")
    // Rewind + clear happen synchronously; assert before the async re-run repopulates.
    let userTurns = model.transcript.filter(\.isUser)
    XCTAssertEqual(userTurns.count, 1)
    XCTAssertEqual(userTurns.first?.text, "one apple")
    // editUserMessage keeps the composer empty — the edited bubble is the source of truth.
    XCTAssertEqual(model.input, "")
    // Downstream selection/review state is cleared before the pipeline re-runs.
    XCTAssertNil(model.selectedResult)
    XCTAssertNil(model.details)
    XCTAssertNil(model.resolution)

    // The rewound text drives a fresh interpretation (stage stayed .reviewing
    // synchronously, so wait on the re-parsed identity instead).
    await waitUntil { model.parsed?.productName.contains("apple") == true }
    XCTAssertEqual(model.parsed?.productName.contains("apple"), true)
  }

  func testApplyWhenEatenSuggestionAnHourAgoSetsConsumedAt() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    guard model.stage == .whenEaten else {
      XCTFail("Expected when-eaten for logs without a clear meal-time cue")
      return
    }

    let before = Date.now
    model.applyWhenEatenSuggestion("An hour ago")
    XCTAssertEqual(model.stage, .confirming)

    let elapsed = before.timeIntervalSince(model.consumedAt)
    XCTAssertGreaterThan(elapsed, 50 * 60)
    XCTAssertLessThan(elapsed, 70 * 60)

    let record = try? model.makeRecord()
    XCTAssertEqual(record?.consumedAt, model.consumedAt)
  }

  func testUnparsedWhenEatenFallsBackToNowWithSoftMessage() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    guard model.stage == .whenEaten else {
      XCTFail("Expected when-eaten for logs without a clear meal-time cue")
      return
    }
    model.whenEatenAnswer = "sometime after the meeting"
    let before = Date.now
    model.submitWhenEaten()

    XCTAssertEqual(model.stage, .confirming)
    XCTAssertEqual(model.message, "Couldn’t parse that time — using now.")
    XCTAssertLessThan(abs(model.consumedAt.timeIntervalSince(before)), 2)
  }

  func testSubmitAppendsUserTurnToTranscript() async {
    let model = LogViewModel(
      parser: ConversationFoodParser(),
      provider: ConversationFoodProvider()
    )
    model.input = "scrambled eggs"
    model.submit()
    await waitUntil { model.stage == .reviewing }

    let users = model.transcript.filter(\.isUser)
    XCTAssertEqual(users.count, 1)
    XCTAssertEqual(users.first?.text, "scrambled eggs")
    // Auto-select echoes a "Using …" assistant turn into the transcript.
    XCTAssertTrue(model.transcript.contains(where: { !$0.isUser }))
  }

  func testAdjustQuantityFromReviewReentersAmountWithoutResearching() async {
    let model = await advanceToReviewing()
    XCTAssertEqual(model.stage, .reviewing)
    let food = model.details

    model.adjustQuantity()

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    // Same food is kept — this re-enters the amount, it does not re-search.
    XCTAssertEqual(model.details?.fdcID, food?.fdcID)
  }

  // MARK: - Helpers

  private func advanceToReviewing() async -> LogViewModel {
    let model = LogViewModel(
      parser: ConversationFoodParser(),
      provider: ConversationFoodProvider()
    )
    model.input = "scrambled eggs"
    model.submit()
    // A single high-confidence hit auto-selects and resolves straight to review.
    await waitUntil { model.stage == .reviewing }
    return model
  }

  private func waitUntil(
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    // Poll with a real sleep rather than busy-spinning on Task.yield(): the
    // pipeline runs off the main actor, and a tight yield loop can starve it.
    while !condition(), clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(2))
    }
    XCTAssertTrue(condition(), "Timed out waiting for expected state")
  }
}

private struct ConversationFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: input,
      searchTerms: input,
      quantity: 1,
      unit: "serving"
    )
  }
}

private struct ConversationFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 42,
          description: "Eggs, scrambled",
          dataType: "Survey (FNDDS)",
          servingSize: 100,
          servingSizeUnit: "g",
          householdServing: "1 serving"
        )
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Eggs, scrambled",
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving",
      nutrientsPer100Grams: [
        NutrientAmount(key: .energy, amount: 148),
        NutrientAmount(key: .protein, amount: 10),
        NutrientAmount(key: .carbohydrate, amount: 1.6),
        NutrientAmount(key: .totalFat, amount: 11),
      ]
    )
  }
}

private struct StaticFoodParser: FoodDescriptionParsing {
  let productName: String
  let searchTerms: String
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: productName, searchTerms: searchTerms, quantity: 1, unit: "item")
  }
}

private actor SingleBigMacProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 2706916,
          description: "Big Mac (McDonalds)",
          dataType: "Survey (FNDDS)",
          servingSize: 205,
          servingSizeUnit: "g",
          householdServing: "1 McDonald's Big Mac"
        )
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Big Mac (McDonalds)",
      dataType: "Survey (FNDDS)",
      servingSize: 205,
      servingSizeUnit: "g",
      householdServing: "1 McDonald's Big Mac",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 257)],
      nutrientsPerServing: [NutrientAmount(key: .energy, amount: 535)]
    )
  }
}
