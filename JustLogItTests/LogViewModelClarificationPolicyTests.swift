import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class LogViewModelClarificationPolicyTests: XCTestCase {
  func testTerminalResolvingParserSuppliesTheAppOutcomeWithoutASecondParseOrPolicyPass() async {
    let provider = SearchCountingFoodProvider()
    let resolution = FoodInterpretationTerminalResolver().resolve(
      ParsedFoodRequest(productName: "", searchTerms: ""),
      sourceText: "hello",
      searchRoute: .onDeviceSemantic
    )
    let parser = FixedTerminalResolutionParser(resolution: resolution)
    let model = LogViewModel(parser: parser, provider: provider)
    model.input = "hello"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(resolution.route, .manualSearch)
    XCTAssertEqual(model.stage, .failed)
    XCTAssertEqual(model.failureKind, .interpretation)
    let resolveCalls = await parser.resolveCalls
    let parseCalls = await parser.parseCalls
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(resolveCalls, 1)
    XCTAssertEqual(parseCalls, 0)
    XCTAssertEqual(searchCalls, 0)
  }

  func testEmptyProductWithModelPromptDoesNotSearch() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "",
          searchTerms: "",
          clarificationPrompt: "What did you eat?"
        )
      ),
      provider: provider
    )
    model.input = "???"

    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    XCTAssertEqual(model.stage, .awaitingClarification)
    XCTAssertNil(model.failureKind)
    XCTAssertEqual(model.activeQuestion?.code, .emptyIdentity)
    XCTAssertEqual(model.activeQuestion?.prompt, "What did you eat?")
    let emptySearchCalls = await provider.searchCalls
    XCTAssertEqual(emptySearchCalls, 0)
  }

  func testSomethingYummyUsesModelPromptWithoutSearching() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "",
          searchTerms: "",
          clarificationPrompt: "I’m sure it was! What did you eat?"
        )
      ),
      provider: provider
    )
    model.input = "I ate something yummy"

    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    XCTAssertEqual(model.stage, .awaitingClarification)
    XCTAssertNil(model.failureKind)
    XCTAssertEqual(model.activeQuestion?.prompt, "I’m sure it was! What did you eat?")
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 0)
  }

  func testWhitespaceOnlyInputDoesNotSearch() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(productName: "banana", searchTerms: "banana")
      ),
      provider: provider
    )
    model.input = "   "

    model.submit()
    await waitUntil {
      model.stage == .failed || model.stage == .idle || model.stage == .choosing
    }

    // Empty / whitespace-only input should not search USDA.
    let whitespaceSearchCalls = await provider.searchCalls
    XCTAssertEqual(whitespaceSearchCalls, 0)
  }

  func testMultipleFoodsBeginsCompositeEvenWithModelWhichOnePrompt() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
        foods: [
          FoodSearchResult(
            fdcID: 5,
            description: "Eggs, scrambled",
            dataType: "Survey (FNDDS)",
            servingSize: 100,
            servingSizeUnit: "g",
            householdServing: "1 large"
          )
        ],
        totalHits: 1,
        currentPage: 1,
        totalPages: 1
      )
    )
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "eggs and bacon",
          searchTerms: "eggs and bacon",
          containsMultipleFoods: true,
          clarificationPrompt: "It looks like more than one food. Which one do you want to log?",
          clarificationSuggestions: ["eggs", "bacon"]
        )
      ),
      provider: provider
    )
    model.input = "eggs and bacon"

    model.submit()
    // Product prefers composite for eggs-and-bacon style multi-food meals.
    await waitUntil { model.isBuildingComposite || model.stage == .failed }

    XCTAssertTrue(model.isBuildingComposite)
    XCTAssertNil(model.failureKind)
    XCTAssertNil(model.activeQuestion)
    XCTAssertEqual(model.activeCompositeComponent?.lowercased(), "eggs")
    XCTAssertEqual(model.pendingCompositeNames.map { $0.lowercased() }, ["bacon"])
    XCTAssertEqual((model.activeCompositeComponent == nil ? 0 : 1) + model.pendingCompositeNames.count, 2)
  }

  func testAnsweringUnsplittableMultipleFoodsClarificationProceedsToSearch() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
        foods: [
          FoodSearchResult(
            fdcID: 7,
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
    )
    let model = LogViewModel(
      parser: ScriptedFoodParser(results: [
        ParsedFoodRequest(
          productName: "mixed plate",
          searchTerms: "mixed plate",
          containsMultipleFoods: true,
          clarificationPrompt: "Which one?",
          clarificationSuggestions: ["eggs", "bacon"]
        ),
        ParsedFoodRequest(
          productName: "scrambled eggs",
          searchTerms: "scrambled eggs",
          quantity: 2,
          unit: "egg",
          preparation: "scrambled"
        ),
      ]),
      provider: provider
    )
    model.input = "mixed plate"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    model.clarificationAnswer = "scrambled eggs"
    model.submitClarificationAnswer()
    // Single high-confidence hit auto-selects, then asks for a resolvable amount.
    await waitUntil { model.stage == .clarifying }

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.parsed?.productName, "scrambled eggs")
    XCTAssertFalse(model.parsed?.containsMultipleFoods ?? true)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    XCTAssertNil(model.failureKind)
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 1)
  }

  func testModelFlaggedVagueAmountClarifiesWithoutSearching() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
        foods: [
          FoodSearchResult(
            fdcID: 1123,
            description: "Egg, whole, cooked, scrambled",
            dataType: "Survey (FNDDS)",
            servingSize: 100,
            servingSizeUnit: "g",
            householdServing: "1 large"
          )
        ],
        totalHits: 1,
        currentPage: 1,
        totalPages: 1
      )
    )
    let model = LogViewModel(
      parser: ScriptedFoodParser(results: [
        ParsedFoodRequest(
          productName: "eggs",
          searchTerms: "eggs",
          isApproximate: true,
          quantityNeedsClarification: true,
          preparationNeedsClarification: true,
          clarificationPrompt: "Sounds great — how many were they, and how were they cooked?"
        ),
        ParsedFoodRequest(
          productName: "eggs",
          searchTerms: "scrambled eggs",
          quantity: 3,
          unit: "egg",
          preparation: "scrambled"
        ),
      ]),
      provider: provider
    )
    model.input = "I had a few eggs"

    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    XCTAssertEqual(model.stage, .awaitingClarification)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    XCTAssertEqual(
      model.activeQuestion?.prompt,
      "Sounds great — how many were they, and how were they cooked?"
    )
    XCTAssertNil(model.failureKind)
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 0)

    model.clarificationAnswer = "3 scrambled"
    model.submitClarificationAnswer()
    // The broader USDA description is not an exact identity, so the tightened
    // policy keeps it in the picker before quantity resolution.
    await waitUntil { model.stage == .choosing || model.stage == .failed }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .clarifying || model.stage == .failed }
    }

    let afterAnswerCalls = await provider.searchCalls
    XCTAssertEqual(afterAnswerCalls, 1)
    XCTAssertEqual(model.parsed?.quantity, 3)
    XCTAssertEqual(model.parsed?.preparation, "scrambled")
    XCTAssertEqual(model.stage, .clarifying)
  }

  func testDismissiveClarificationReplyDoesNotSearchUSDA() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: ScriptedFoodParser(results: [
        ParsedFoodRequest(
          productName: "",
          searchTerms: "",
          clarificationPrompt: "I’m sure it was! What did you eat?"
        ),
        // Model re-read of "who cares?" — still no food, ask again.
        ParsedFoodRequest(
          productName: "",
          searchTerms: "",
          clarificationPrompt: "No worries — what food should I log?"
        ),
      ]),
      provider: provider
    )
    model.input = "Something yummy"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    model.clarificationAnswer = "who cares?"
    model.submitClarificationAnswer()
    // Re-parse is async; wait for the *second* model prompt, not the pre-reparse stage.
    await waitUntil {
      model.activeQuestion?.prompt == "No worries — what food should I log?"
        || model.stage == .choosing
        || model.stage == .failed
    }

    XCTAssertNotEqual(model.stage, .choosing)
    XCTAssertEqual(model.stage, .awaitingClarification)
    XCTAssertEqual(model.activeQuestion?.prompt, "No worries — what food should I log?")
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 0, "Dismissive replies must not trigger USDA search")
  }

  func testChoosingSuggestionAnswersUnsplittableMultipleFoodsClarification() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
        foods: [
          FoodSearchResult(fdcID: 11, description: "Bacon", dataType: "Branded")
        ],
        totalHits: 1,
        currentPage: 1,
        totalPages: 1
      )
    )
    let model = LogViewModel(
      parser: ScriptedFoodParser(results: [
        ParsedFoodRequest(
          productName: "mixed plate",
          searchTerms: "mixed plate",
          containsMultipleFoods: true,
          clarificationPrompt: "Which one?",
          clarificationSuggestions: ["eggs", "bacon"]
        ),
        ParsedFoodRequest(
          productName: "bacon",
          searchTerms: "bacon"
        ),
      ]),
      provider: provider
    )
    model.input = "mixed plate"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    XCTAssertEqual(model.activeQuestion?.suggestedAnswers, ["eggs", "bacon"])

    model.chooseClarificationSuggestion("bacon")
    // A lone generic result is not permission to select nutrition silently.
    await waitUntil { model.stage == .choosing || model.stage == .failed }
    if model.stage == .choosing, let first = model.results.first {
      model.select(first)
      await waitUntil { model.stage == .clarifying || model.stage == .failed }
    }

    XCTAssertEqual(model.parsed?.productName.lowercased(), "bacon")
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 1)
  }

  func testEmptyClarificationAnswerIsIgnored() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "mixed plate",
          searchTerms: "mixed plate",
          containsMultipleFoods: true,
          clarificationPrompt: "Which one?"
        )
      ),
      provider: provider
    )
    model.input = "mixed plate"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    model.clarificationAnswer = "   "
    model.submitClarificationAnswer()
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .awaitingClarification)
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 0)
  }

  func testValidSingleFoodAutoSelectsAndAsksForQuantity() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
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
    )
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "scrambled eggs",
          searchTerms: "scrambled eggs",
          quantity: 2,
          unit: "eggs"
        )
      ),
      provider: provider,
      rememberedFoods: EmptyRememberedFoodStore()
    )
    model.input = "2 scrambled eggs"

    model.submit()
    // A single high-confidence hit auto-selects and skips the picker; the stub
    // food lacks resolvable serving data, so it asks for a quantity.
    await waitUntil { model.stage == .clarifying }

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.parsed?.productName, "scrambled eggs")
    XCTAssertFalse(model.manualSearchTerms.isEmpty)
    XCTAssertNil(model.failureKind)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    let validSearchCalls = await provider.searchCalls
    XCTAssertEqual(validSearchCalls, 1)
  }

  func testCancelDuringCompositeAssemblyClearsTheSession() async {
    let provider = SearchCountingFoodProvider(
      searchResponse: FoodSearchResponse(
        foods: [
          FoodSearchResult(fdcID: 5, description: "Eggs, scrambled", dataType: "Survey (FNDDS)")
        ],
        totalHits: 1, currentPage: 1, totalPages: 1))
    let model = LogViewModel(
      parser: ScriptedFoodParser(results: [
        ParsedFoodRequest(
          productName: "eggs and bacon", searchTerms: "eggs and bacon",
          containsMultipleFoods: true, componentNames: ["eggs", "bacon"])
      ]),
      provider: provider)
    model.input = "eggs and bacon"
    model.submit()
    await waitUntil { model.isBuildingComposite }

    model.cancel()

    // Cancelling must abandon the composite so a later log doesn't merge into it.
    XCTAssertFalse(model.isBuildingComposite)
    XCTAssertTrue(model.compositeComponents.isEmpty)
    XCTAssertTrue(model.pendingCompositeNames.isEmpty)
    XCTAssertEqual(model.stage, .idle)
  }

  func testCompositeMatchingStatusLabelUsesOrdinalProgress() {
    let model = LogViewModel(provider: SearchCountingFoodProvider())
    model.compositeSessionActive = true
    model.compositeComponents = [
      CompositeComponentSnapshot(
        displayName: "Big Mac",
        quantityDisplay: "1 item",
        nutrients: [NutrientAmount(key: .energy, amount: 540)]
      )
    ]
    model.pendingCompositeNames = []
    model.activeCompositeComponent = "fries"

    XCTAssertEqual(model.compositeMatchingStatusLabel, "Matching fries (2 of 2)…")
    XCTAssertEqual(model.compositePickerCaption, "fries · 2 of 2")
  }

  func testSkipFailedCompositeComponentPreservesConfirmedItems() {
    let model = LogViewModel(provider: SearchCountingFoodProvider())
    model.compositeSessionActive = true
    model.compositeSessionSource = "Big Mac and fries"
    model.compositeComponents = [
      CompositeComponentSnapshot(
        displayName: "Big Mac",
        quantityDisplay: "1 item",
        nutrients: [
          NutrientAmount(key: .energy, amount: 540),
          NutrientAmount(key: .protein, amount: 25),
        ]
      )
    ]
    model.pendingCompositeNames = []
    model.activeCompositeComponent = "fries"
    model.stage = .failed
    model.failureKind = .noResults
    model.message = "Couldn’t match fries."

    XCTAssertTrue(model.canSkipActiveCompositeComponent)
    model.skipActiveCompositeComponent()

    XCTAssertEqual(model.compositeComponents.count, 1)
    XCTAssertEqual(model.compositeComponents.first?.displayName, "Big Mac")
    XCTAssertFalse(model.isBuildingComposite)
    XCTAssertNil(model.activeCompositeComponent)
    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(
      model.nutrients.first(where: { $0.key == .energy })?.amount,
      540
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition(), "Timed out waiting for expected state")
  }

  private func settleAsyncWork() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}

private final class EmptyRememberedFoodStore: RememberedFoodStoring, @unchecked Sendable {
  func load() -> RememberedFoodCatalog {
    RememberedFoodCatalog()
  }

  func save(_: RememberedFoodCatalog) {}
}

private struct FixedFoodParser: FoodDescriptionParsing {
  let result: ParsedFoodRequest

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    result
  }
}

private actor FixedTerminalResolutionParser: FoodDescriptionTerminalResolving {
  let resolution: FoodInterpretationTerminalResolution
  private(set) var resolveCalls = 0
  private(set) var parseCalls = 0

  init(resolution: FoodInterpretationTerminalResolution) {
    self.resolution = resolution
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    parseCalls += 1
    return ParsedFoodRequest(productName: input, searchTerms: input)
  }

  func resolveForApplication(
    semanticContext: String,
    groundingText: String,
    turnCount: Int
  ) async throws -> FoodInterpretationTerminalResolution {
    resolveCalls += 1
    return resolution
  }
}

/// Returns successive parse results so clarification re-parses can advance the pipeline.
private actor ScriptedFoodParser: FoodDescriptionParsing {
  private var results: [ParsedFoodRequest]

  init(results: [ParsedFoodRequest]) {
    self.results = results
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    if results.isEmpty {
      return ParsedFoodRequest(productName: input, searchTerms: input)
    }
    return results.removeFirst()
  }
}

private actor SearchCountingFoodProvider: FoodDataProviding {
  private(set) var searchCalls = 0
  private let searchResponse: FoodSearchResponse

  init(
    searchResponse: FoodSearchResponse = FoodSearchResponse(
      foods: [], totalHits: 0, currentPage: 1, totalPages: 1
    )
  ) {
    self.searchResponse = searchResponse
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    searchCalls += 1
    return searchResponse
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "stub",
      dataType: "Survey (FNDDS)"
    )
  }
}
