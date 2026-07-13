import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class LogViewModelConcurrencyTests: XCTestCase {
  func testCancelRemainsIdleWhenObsoleteParserLaterFails() async {
    let parser = ControlledFoodParser()
    let model = LogViewModel(parser: parser, provider: StubFoodProvider())
    model.input = "one apple"

    model.submit()
    await parser.waitUntilStarted()
    XCTAssertEqual(model.stage, .parsing)

    model.cancel()
    await parser.fail(ProbeError.expected)
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .idle)
    XCTAssertNil(model.message)
  }

  func testOlderSelectionFailureCannotOverwriteNewerSelection() async {
    let provider = ControlledFoodProvider()
    let model = LogViewModel(parser: StubFoodParser(), provider: provider)
    model.input = "one egg"
    model.submit()
    await waitUntil { model.stage == .choosing }

    let older = Self.result(id: 1, description: "Older result")
    let newer = Self.result(id: 2, description: "Newer result")
    model.select(older)
    await provider.waitUntilDetailsRequested(for: older.fdcID)

    model.select(newer)
    await provider.waitUntilDetailsRequested(for: newer.fdcID)
    await provider.succeedDetails(for: newer.fdcID, description: newer.description)
    await waitUntil { model.stage == .reviewing }

    await provider.failDetails(for: older.fdcID, error: ProbeError.expected)
    await settleAsyncWork()

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.selectedResult?.fdcID, newer.fdcID)
    XCTAssertEqual(model.details?.fdcID, newer.fdcID)
    XCTAssertNil(model.message)
  }

  func testParserFailureHasInterpretationContext() async {
    let model = LogViewModel(parser: FailingFoodParser(), provider: StubFoodProvider())
    model.input = "two large scrambled eggs"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .interpretation)
    XCTAssertEqual(
      model.message,
      "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
    )
  }

  func testSearchFailureHasSearchContext() async {
    let model = LogViewModel(parser: StubFoodParser(), provider: SearchFailingFoodProvider())
    model.input = "one egg"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .search)
    XCTAssertEqual(model.message, "Food search failed.")
  }

  func testEmptySearchResultsHaveNoResultsContext() async {
    let model = LogViewModel(parser: StubFoodParser(), provider: StubFoodProvider())
    model.input = "an impossible food"

    model.submit()
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .noResults)
    XCTAssertEqual(
      model.message, "No USDA foods matched. Edit the search or enter nutrition manually."
    )
  }

  func testDetailsFailureHasDetailsContext() async {
    let provider = DetailsFailingFoodProvider()
    let model = LogViewModel(parser: StubFoodParser(), provider: provider)
    model.input = "one egg"

    model.submit()
    await waitUntil { model.stage == .choosing }
    let result = try? XCTUnwrap(model.results.first)
    XCTAssertNotNil(result)
    guard let result else { return }

    model.select(result)
    await waitUntil { model.stage == .failed }

    XCTAssertEqual(model.failureKind, .details)
    XCTAssertEqual(model.message, "The selected food details could not be loaded.")
  }

  func testSearchWorkflowRanksRequestedCookieAboveCompositeDessert() async {
    let model = LogViewModel(parser: OreoFoodParser(), provider: OreoSearchProvider())
    model.input = "An Oreo cookie"

    model.submit()
    // Ranking is applied before any auto-select; assert on the ranked results
    // rather than the picker stage (a high-confidence hit may auto-advance).
    await waitUntil { model.results.count == 2 }

    XCTAssertEqual(model.results.map(\.fdcID), [101, 102])
  }

  private static func result(id: Int, description: String) -> FoodSearchResult {
    FoodSearchResult(
      fdcID: id,
      description: description,
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving"
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
    for _ in 0..<10 { await Task.yield() }
  }
}

private enum ProbeError: Error {
  case expected
}

private struct FailingFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    throw ProbeError.expected
  }
}

private actor ControlledFoodParser: FoodDescriptionParsing {
  private var continuation: CheckedContinuation<ParsedFoodRequest, any Error>?
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var started = false

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    started = true
    startedContinuation?.resume()
    startedContinuation = nil
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func fail(_ error: any Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

private struct StubFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: input,
      searchTerms: input,
      quantity: 1,
      unit: "serving"
    )
  }
}

private struct OreoFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      brand: "Oreo",
      productName: "cookie",
      searchTerms: "Oreo cookie",
      quantity: 1,
      unit: "cookie"
    )
  }
}

private struct OreoSearchProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 102,
          description: "McDONALD'S, McFLURRY WITH OREO COOKIES",
          brandOwner: "McDonald's Corporation",
          dataType: "Branded"
        ),
        FoodSearchResult(
          fdcID: 101,
          description: "OREO CHOCOLATE SANDWICH COOKIES",
          brandOwner: "MONDELEZ GLOBAL LLC",
          dataType: "Branded"
        ),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct StubFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(foods: [], totalHits: 0, currentPage: 1, totalPages: 1)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct SearchFailingFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    throw ProbeError.expected
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw ProbeError.expected
  }
}

private struct DetailsFailingFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 42,
          description: "Eggs",
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
    throw ProbeError.expected
  }
}

private actor ControlledFoodProvider: FoodDataProviding {
  private var continuations: [Int: CheckedContinuation<FoodDetails, any Error>] = [:]
  private var requestWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
  private var requestedIDs = Set<Int>()

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(fdcID: 1, description: "Older result", dataType: "Survey (FNDDS)"),
        FoodSearchResult(fdcID: 2, description: "Newer result", dataType: "Survey (FNDDS)"),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    requestedIDs.insert(fdcID)
    requestWaiters.removeValue(forKey: fdcID)?.resume()
    return try await withCheckedThrowingContinuation { continuations[fdcID] = $0 }
  }

  func waitUntilDetailsRequested(for fdcID: Int) async {
    guard !requestedIDs.contains(fdcID) else { return }
    await withCheckedContinuation { requestWaiters[fdcID] = $0 }
  }

  func succeedDetails(for fdcID: Int, description: String) {
    resume(
      for: fdcID,
      with: .success(
        FoodDetails(
          fdcID: fdcID,
          description: description,
          dataType: "Survey (FNDDS)",
          servingSize: 100,
          servingSizeUnit: "g",
          householdServing: "1 serving",
          nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
        )))
  }

  func failDetails(for fdcID: Int, error: any Error) {
    resume(for: fdcID, with: .failure(error))
  }

  private func resume(for fdcID: Int, with result: Result<FoodDetails, any Error>) {
    guard let continuation = continuations.removeValue(forKey: fdcID) else { return }
    continuation.resume(with: result)
  }
}
