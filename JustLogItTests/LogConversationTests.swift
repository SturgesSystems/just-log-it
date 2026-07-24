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

  /// Siri/Shortcuts handoff: external `consumedAt` + clear inference must survive
  /// parse → review → continue (when-eaten skipped, timestamp preserved).
  func testExternalConsumedAtHandoffSurvivesParseAndSkipsWhenEaten() async {
    let eatenAt = Date(timeIntervalSince1970: 1_700_000_000)
    let model = LogViewModel(
      parser: StaticFoodParser(productName: "Greek Yogurt", searchTerms: "Greek Yogurt"),
      provider: SingleBigMacProvider()
    )
    // Mirror LogView.applyPendingFoodLog for a Siri pending with consumedAt.
    model.reset()
    model.input = "greek yogurt"
    model.consumedAt = eatenAt
    model.consumedAtInference = MealTimeInference(
      date: eatenAt,
      displayLabel: "From Siri",
      isClear: true
    )
    model.submit()

    await waitUntil { model.stage == .reviewing || model.stage == .choosing || model.stage == .failed }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .reviewing }
    }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.consumedAt, eatenAt)
    XCTAssertEqual(model.consumedAtInference?.isClear, true)
    XCTAssertEqual(model.consumedAtInference?.displayLabel, "From Siri")

    model.continueFromReview()
    XCTAssertEqual(model.stage, .confirming)
    XCTAssertNotEqual(model.stage, .whenEaten)
    XCTAssertEqual(model.consumedAt, eatenAt)
    XCTAssertEqual(model.consumedAtInference?.displayLabel, "From Siri")
  }

  /// A completed log must not leak its clear meal time into the next typed log.
  func testNewLogAfterCompletedClearsPriorMealTimeInference() async {
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
    model.continueFromReview()
    XCTAssertEqual(model.stage, .confirming)
    model.markSaved(entryID: UUID())
    XCTAssertEqual(model.stage, .completed)
    XCTAssertEqual(model.consumedAtInference?.isClear, true)

    model.input = "apple"
    model.submit()
    await waitUntil {
      model.stage == .reviewing || model.stage == .choosing || model.stage == .failed
    }
    // Prior "Just now" must not stick; re-infer from "apple" (not clear).
    XCTAssertNotEqual(model.consumedAtInference?.displayLabel, "Just now")
    XCTAssertNotEqual(model.consumedAtInference?.isClear, true)
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

  func testSubmitCustomTwoHoursAgoPreservesAnswerAndSetsConsumedAt() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    guard model.stage == .whenEaten else {
      XCTFail("Expected when-eaten for logs without a clear meal-time cue")
      return
    }

    model.whenEatenAnswer = "2 hours ago"
    let before = Date.now
    model.submitWhenEaten()

    XCTAssertEqual(model.stage, .confirming)
    XCTAssertEqual(model.transcript.last?.text, "2 hours ago")
    XCTAssertEqual(model.consumedAtInference?.displayLabel, "2 hours ago")
    XCTAssertEqual(model.consumedAtInference?.isClear, true)
    let elapsed = before.timeIntervalSince(model.consumedAt)
    XCTAssertGreaterThan(elapsed, 110 * 60)
    XCTAssertLessThan(elapsed, 130 * 60)
  }

  func testUnparsedWhenEatenStaysEditableAndDoesNotSilentlyUseNow() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    guard model.stage == .whenEaten else {
      XCTFail("Expected when-eaten for logs without a clear meal-time cue")
      return
    }
    model.whenEatenAnswer = "sometime after the meeting"
    let before = model.consumedAt
    model.submitWhenEaten()

    XCTAssertEqual(model.stage, .whenEaten)
    XCTAssertEqual(
      model.message,
      "I couldn’t understand that time. Try “8:30 pm,” “yesterday at 7,” or choose an exact date and time."
    )
    XCTAssertEqual(model.consumedAt, before)
  }

  func testExactWhenEatenPickerRemediatesFreeformFailure() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    guard model.stage == .whenEaten else {
      XCTFail("Expected when-eaten for logs without a clear meal-time cue")
      return
    }
    model.whenEatenAnswer = "after the meeting"
    model.submitWhenEaten()
    XCTAssertEqual(model.stage, .whenEaten)

    let selected = Date(timeIntervalSince1970: 1_700_000_000)
    model.consumedAt = selected
    model.useSelectedWhenEatenDate()

    XCTAssertEqual(model.stage, .confirming)
    XCTAssertEqual(model.consumedAt, selected)
    XCTAssertTrue(model.consumedAtInference?.isClear == true)
    XCTAssertNil(model.message)
  }

  func testSubmitAppendsUserTurnToTranscript() async {
    let model = LogViewModel(
      parser: ConversationFoodParser(),
      provider: ConversationFoodProvider()
    )
    model.input = "scrambled eggs"
    model.submit()
    await advancePickerIfNeeded(model)

    let users = model.transcript.filter(\.isUser)
    XCTAssertEqual(users.count, 1)
    XCTAssertEqual(users.first?.text, "scrambled eggs")
    // Selecting a USDA match echoes a "Using …" assistant turn.
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

  func testEditAmountFromReviewKeepsFoodAndSeedsCurrentServings() async {
    let model = await advanceToReviewing()
    let food = model.details
    let resolution = model.resolution
    XCTAssertNotNil(food)
    XCTAssertNotNil(resolution)

    model.editAmountFromReview()

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.details?.fdcID, food?.fdcID)
    XCTAssertEqual(model.selectedResult?.fdcID, food?.fdcID)
    XCTAssertNotNil(model.resolution)
    if resolution?.basis == .servings,
      let multiplier = resolution?.servingMultiplier, multiplier > 0
    {
      XCTAssertFalse(model.clarificationServings.isEmpty)
    } else if resolution?.basis == .grams,
      let grams = resolution?.consumedGrams, grams > 0
    {
      XCTAssertFalse(model.clarificationGrams.isEmpty)
      XCTAssertTrue(model.clarificationServings.isEmpty)
    }
  }

  func testEditAmountFromConfirmAlsoReentersQuantity() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    if model.stage == .whenEaten {
      model.applyWhenEatenSuggestion("Just now")
    }
    XCTAssertEqual(model.stage, .confirming)
    let fdcID = model.details?.fdcID

    model.editAmountFromReview()

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.details?.fdcID, fdcID)
  }

  func testEditAmountFromReviewNoopsForComposite() async {
    let model = await advanceToReviewing()
    // Simulate a composite meal already on review.
    model.setCompositeComponents([
      CompositeComponentSnapshot(
        displayName: "Eggs",
        brand: nil,
        fdcID: 1,
        quantityDisplay: "1 serving",
        nutrients: [NutrientAmount(key: .energy, amount: 100)],
        isApproximate: false
      )
    ])
    XCTAssertEqual(model.stage, .reviewing)

    model.editAmountFromReview()

    XCTAssertEqual(model.stage, .reviewing)
  }

  func testEditTimeFromReviewPrefillsLabelAndKeepsFood() async {
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
    XCTAssertEqual(model.consumedAtInference?.displayLabel, "Just now")
    let fdcID = model.details?.fdcID
    let nutrients = model.nutrients

    model.editTimeFromReview()

    XCTAssertEqual(model.stage, .whenEaten)
    XCTAssertEqual(model.whenEatenAnswer, "Just now")
    XCTAssertEqual(model.details?.fdcID, fdcID)
    XCTAssertEqual(model.nutrients.map(\.key), nutrients.map(\.key))
    XCTAssertNotNil(model.resolution)
  }

  func testEditTimeFromConfirmReturnsToWhenEaten() async {
    let model = await advanceToReviewing()
    model.continueFromReview()
    if model.stage == .whenEaten {
      model.applyWhenEatenSuggestion("An hour ago")
    }
    XCTAssertEqual(model.stage, .confirming)
    let fdcID = model.details?.fdcID

    model.editTimeFromReview()

    XCTAssertEqual(model.stage, .whenEaten)
    XCTAssertEqual(model.whenEatenAnswer, "An hour ago")
    XCTAssertEqual(model.details?.fdcID, fdcID)
  }

  func testExplicitEggCountSurvivesModelOmissionAndUsesMatchingUSDAPortion() async {
    let model = LogViewModel(
      parser: QuantityOmittingEggParser(),
      provider: MultipleEggPortionsProvider()
    )
    model.input = "Two large scrambled eggs"
    model.submit()

    await waitUntil {
      model.stage == .choosing || model.stage == .reviewing || model.stage == .failed
    }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .reviewing || model.stage == .failed }
    }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.parsed?.quantity, 2)
    XCTAssertEqual(UnitConversion.family(model.parsed?.unit ?? ""), "egg")
    XCTAssertEqual(model.resolution?.consumedGrams, 122)
    XCTAssertEqual(model.resolution?.displayText, "two large scrambled eggs")
    XCTAssertEqual(
      model.nutrients.first(where: { $0.key == .energy })?.amount ?? .nan,
      180.56,
      accuracy: 0.000_1
    )
    XCTAssertEqual(
      model.nutrients.first(where: { $0.key == .protein })?.amount ?? .nan,
      12.2,
      accuracy: 0.000_1
    )
  }

  func testUnsizedEggCountClarifiesBetweenUSDASizesWithoutDefaultingToServing() async {
    let model = LogViewModel(
      parser: QuantityOmittingUnsizedEggParser(),
      provider: MultipleEggPortionsProvider()
    )
    model.input = "Two scrambled eggs"
    model.submit()

    await waitUntil {
      model.stage == .choosing || model.stage == .clarifying || model.stage == .failed
    }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .clarifying || model.stage == .failed }
    }

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.parsed?.quantity, 2)
    XCTAssertEqual(UnitConversion.family(model.parsed?.unit ?? ""), "egg")
    XCTAssertNotEqual(model.parsed?.unit, "serving")
    XCTAssertNil(model.resolution)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    XCTAssertTrue(model.message?.contains("more than one matching size") == true)
  }

  // MARK: - Helpers

  private func advanceToReviewing() async -> LogViewModel {
    let model = LogViewModel(
      parser: ConversationFoodParser(),
      provider: ConversationFoodProvider()
    )
    model.input = "scrambled eggs"
    model.submit()
    await advancePickerIfNeeded(model)
    return model
  }

  private func advancePickerIfNeeded(_ model: LogViewModel) async {
    await waitUntil {
      model.stage == .choosing || model.stage == .reviewing || model.stage == .failed
    }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .reviewing || model.stage == .failed }
    }
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

private struct QuantityOmittingEggParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: "scrambled eggs",
      searchTerms: "scrambled eggs",
      preparation: "scrambled",
      descriptors: ["large"]
    )
  }
}

private struct QuantityOmittingUnsizedEggParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: "scrambled eggs",
      searchTerms: "scrambled eggs",
      preparation: "scrambled"
    )
  }
}

private struct MultipleEggPortionsProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 99,
          description: "Egg, whole, cooked, scrambled",
          dataType: "SR Legacy"
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
      description: "Egg, whole, cooked, scrambled",
      dataType: "SR Legacy",
      servingSize: 220,
      servingSizeUnit: "g",
      householdServing: "1 cup",
      foodPortions: [
        USDAFoodPortion(gramWeight: 220, amount: 1, portionDescription: "1 cup"),
        USDAFoodPortion(gramWeight: 61, amount: 1, portionDescription: "1 large egg"),
        USDAFoodPortion(gramWeight: 44, amount: 1, portionDescription: "1 small egg"),
      ],
      nutrientsPer100Grams: [
        NutrientAmount(key: .energy, amount: 148),
        NutrientAmount(key: .protein, amount: 10),
      ]
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
      foodPortions: [
        USDAFoodPortion(
          gramWeight: 205,
          amount: 1,
          portionDescription: "1 McDonald's Big Mac"
        )
      ],
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 257)],
      nutrientsPerServing: [NutrientAmount(key: .energy, amount: 535)]
    )
  }
}
