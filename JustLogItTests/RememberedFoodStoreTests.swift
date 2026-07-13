import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class RememberedFoodStoreTests: XCTestCase {
  func testUserDefaultsStoreRoundTripsCatalog() {
    let suite = "justlogit.tests.remembered.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = UserDefaultsRememberedFoodStore(defaults: defaults)
    var catalog = RememberedFoodCatalog()
    catalog.remember(query: "Oreo cookie", fdcID: 55, displayName: "OREO COOKIE", brand: "Mondelēz")
    store.save(catalog)

    let loaded = store.load()
    XCTAssertEqual(loaded.preferredFdcIDs(forQuery: "oreo cookie"), [55])
    XCTAssertEqual(loaded.selections.first?.displayName, "OREO COOKIE")
  }

  func testCorruptStoreDataFailsOpenToEmptyCatalog() {
    let suite = "justlogit.tests.remembered.corrupt.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("not-json".utf8), forKey: UserDefaultsRememberedFoodStore.storageKey)

    let store = UserDefaultsRememberedFoodStore(defaults: defaults)
    XCTAssertTrue(store.load().selections.isEmpty)
  }

  func testMarkSavedRemembersSelectionAndBoostsLaterSearch() async {
    let suite = "justlogit.tests.remembered.vm.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsRememberedFoodStore(defaults: defaults)

    let remembered = FoodSearchResult(
      fdcID: 99,
      description: "REMEMBERED COOKIE",
      dataType: "Branded"
    )
    let other = FoodSearchResult(
      fdcID: 1,
      description: "OTHER COOKIE SNACK",
      dataType: "Branded"
    )
    let provider = OrderedSearchProvider(results: [other, remembered])
    let model = LogViewModel(
      parser: FixedRememberedFoodParser(),
      provider: provider,
      rememberedFoods: store
    )
    model.input = "cookie"
    model.manualSearchTerms = "cookie"
    model.submit()
    await waitUntil { model.stage == .choosing }

    // Without memory, order follows USDA response ranking (still both present).
    XCTAssertEqual(Set(model.results.map(\.fdcID)), [1, 99])

    model.select(remembered)
    await waitUntil { model.stage == .clarifying || model.stage == .reviewing }
    // Force a reviewing path via grams if needed.
    if model.stage == .clarifying {
      model.clarificationGrams = "10"
      model.resolveWithGrams()
    }
    await waitUntil { model.stage == .reviewing }
    model.markSaved()

    let preferred = store.load().preferredFdcIDs(forQuery: "cookie")
    XCTAssertEqual(preferred, [99])

    let model2 = LogViewModel(
      parser: FixedRememberedFoodParser(),
      provider: OrderedSearchProvider(results: [other, remembered]),
      rememberedFoods: store
    )
    model2.input = "cookie"
    model2.manualSearchTerms = "cookie"
    model2.submit()
    await waitUntil { model2.stage == .choosing }

    XCTAssertEqual(model2.results.first?.fdcID, 99)
    XCTAssertEqual(model2.results.map(\.fdcID).sorted(), [1, 99])
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
}

private struct FixedRememberedFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: "cookie", searchTerms: "cookie")
  }
}

private actor OrderedSearchProvider: FoodDataProviding {
  let results: [FoodSearchResult]

  init(results: [FoodSearchResult]) {
    self.results = results
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: results, totalHits: results.count, currentPage: 1, totalPages: 1)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: results.first(where: { $0.fdcID == fdcID })?.description ?? "food",
      dataType: "Branded",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
    )
  }
}
