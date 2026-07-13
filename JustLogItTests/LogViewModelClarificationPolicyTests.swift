import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class LogViewModelClarificationPolicyTests: XCTestCase {
  func testEmptyProductDoesNotSearchAndFailsInterpretation() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(productName: "", searchTerms: "")
      ),
      provider: provider
    )
    model.input = "???"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .interpretation)
    XCTAssertEqual(
      model.message,
      "Enter a food name to search. Empty identity cannot proceed to USDA."
    )
    XCTAssertEqual(model.manualSearchTerms, "???")
    XCTAssertNil(model.activeQuestion)
    let emptySearchCalls = await provider.searchCalls
    XCTAssertEqual(emptySearchCalls, 0)
  }

  func testWhitespaceOnlyProductDoesNotSearch() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(productName: "   ", searchTerms: "   ")
      ),
      provider: provider
    )
    model.input = "   banana"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .interpretation)
    let whitespaceSearchCalls = await provider.searchCalls
    XCTAssertEqual(whitespaceSearchCalls, 0)
  }

  func testMultipleFoodsPresentsClarificationWithoutSearching() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "eggs and bacon",
          searchTerms: "eggs and bacon",
          containsMultipleFoods: true
        )
      ),
      provider: provider
    )
    model.input = "eggs and bacon"

    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    XCTAssertEqual(model.stage, .awaitingClarification)
    XCTAssertNil(model.failureKind)
    XCTAssertEqual(
      model.activeQuestion?.prompt,
      "It looks like more than one food. Which one do you want to log?"
    )
    XCTAssertEqual(model.activeQuestion?.code, .multipleFoods)
    XCTAssertEqual(model.message, model.activeQuestion?.prompt)
    XCTAssertEqual(model.manualSearchTerms, "eggs and bacon")
    XCTAssertNil(model.parsed)
    let multiFoodSearchCalls = await provider.searchCalls
    XCTAssertEqual(multiFoodSearchCalls, 0)
  }

  func testAnsweringMultipleFoodsClarificationProceedsToSearch() async {
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
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "eggs and bacon",
          searchTerms: "eggs and bacon",
          containsMultipleFoods: true
        )
      ),
      provider: provider
    )
    model.input = "eggs and bacon"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    model.clarificationAnswer = "scrambled eggs"
    model.submitClarificationAnswer()
    await waitUntil { model.stage == .choosing }

    XCTAssertEqual(model.stage, .choosing)
    XCTAssertEqual(model.parsed?.productName, "scrambled eggs")
    XCTAssertFalse(model.parsed?.containsMultipleFoods ?? true)
    XCTAssertNil(model.activeQuestion)
    XCTAssertNil(model.failureKind)
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 1)
  }

  func testChoosingSuggestionAnswersClarification() async {
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
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "eggs and bacon",
          searchTerms: "eggs and bacon",
          containsMultipleFoods: true
        )
      ),
      provider: provider
    )
    model.input = "eggs and bacon"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    // Source-grounded suggestions come from the policy when the source splits cleanly.
    XCTAssertTrue((model.activeQuestion?.suggestedAnswers.count ?? 0) >= 2)

    model.chooseClarificationSuggestion("bacon")
    await waitUntil { model.stage == .choosing }

    XCTAssertEqual(model.parsed?.productName.lowercased(), "bacon")
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 1)
  }

  func testEmptyClarificationAnswerIsIgnored() async {
    let provider = SearchCountingFoodProvider()
    let model = LogViewModel(
      parser: FixedFoodParser(
        result: ParsedFoodRequest(
          productName: "eggs and bacon",
          searchTerms: "eggs and bacon",
          containsMultipleFoods: true
        )
      ),
      provider: provider
    )
    model.input = "eggs and bacon"
    model.submit()
    await waitUntil { model.stage == .awaitingClarification }

    model.clarificationAnswer = "   "
    model.submitClarificationAnswer()
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .awaitingClarification)
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(searchCalls, 0)
  }

  func testValidSingleFoodSearchesAndReachesChoosing() async {
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
      provider: provider
    )
    model.input = "2 scrambled eggs"

    model.submit()
    await waitUntil { model.stage == .choosing }

    XCTAssertEqual(model.stage, .choosing)
    XCTAssertEqual(model.parsed?.productName, "scrambled eggs")
    XCTAssertFalse(model.manualSearchTerms.isEmpty)
    XCTAssertNil(model.failureKind)
    XCTAssertNil(model.activeQuestion)
    let validSearchCalls = await provider.searchCalls
    XCTAssertEqual(validSearchCalls, 1)
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

private struct FixedFoodParser: FoodDescriptionParsing {
  let result: ParsedFoodRequest

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    result
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
