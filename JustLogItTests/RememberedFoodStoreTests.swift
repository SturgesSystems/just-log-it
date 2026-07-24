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

  func testCatalogForgetAndRankedDisplay() {
    var catalog = RememberedFoodCatalog()
    catalog.remember(
      query: "cookie", fdcID: 1, displayName: "Cookie A", at: .now.addingTimeInterval(-10))
    catalog.remember(query: "milk", fdcID: 2, displayName: "Milk B", at: .now)
    XCTAssertEqual(catalog.rankedForDisplay().map(\.fdcID), [2, 1])
    catalog.remove(signature: "cookie", fdcID: 1)
    XCTAssertEqual(catalog.preferredFdcIDs(forQuery: "cookie"), [])
    XCTAssertEqual(catalog.preferredFdcIDs(forQuery: "milk"), [2])
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
    // The remembered pick is now high-confidence, so it auto-selects past the
    // picker; assert on the ranked results, which carry the memory boost.
    await waitUntil { !model2.results.isEmpty }

    XCTAssertEqual(model2.results.first?.fdcID, 99)
    XCTAssertEqual(model2.results.map(\.fdcID).sorted(), [1, 99])
  }

  func testManualSearchBypassesRememberedAutoSelection() async {
    let suite = "justlogit.tests.remembered.choose-different.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsRememberedFoodStore(defaults: defaults)

    var catalog = RememberedFoodCatalog()
    catalog.remember(query: "cookie", fdcID: 99, displayName: "REMEMBERED COOKIE")
    store.save(catalog)

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
    let model = LogViewModel(
      parser: FixedRememberedFoodParser(),
      provider: OrderedSearchProvider(results: [other, remembered]),
      rememberedFoods: store
    )

    model.input = "cookie"
    model.submit()
    await waitUntil { model.stage == .choosing }

    // Memory may rank a prior choice first, but it must never silently select
    // nutrition data on the person's behalf.
    XCTAssertNil(model.selectedResult)
    XCTAssertEqual(model.results.first?.fdcID, 99)

    model.select(remembered)
    await waitUntil { model.stage == .clarifying || model.stage == .reviewing }

    // An explicit request to choose another food must stay on the picker. The
    // remembered result remains ranked first, but must not immediately select
    // itself again and return the person to review.
    model.searchManually()
    await waitUntil { model.stage == .choosing }

    XCTAssertNil(model.selectedResult)
    XCTAssertEqual(model.results.first?.fdcID, 99)
    XCTAssertEqual(model.results.map(\.fdcID).sorted(), [1, 99])
  }

  func testCompositeSaveRemembersComponentQueryAndRelogBoostsWithoutAutoSelection() async throws {
    let suite = "justlogit.tests.remembered.composite.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsRememberedFoodStore(defaults: defaults)
    let provider = CompositeRememberedFoodProvider()

    let first = LogViewModel(
      parser: FixedCompositeFoodParser(),
      provider: provider,
      rememberedFoods: store
    )
    first.input = "eggs and toast"
    first.submit()
    await waitUntil { first.stage == .choosing && first.activeCompositeComponent == "eggs" }

    let chosenEgg = try XCTUnwrap(first.results.first(where: { $0.fdcID == 99 }))
    first.select(chosenEgg)
    await waitUntil { first.stage == .choosing && first.activeCompositeComponent == "toast" }
    let toast = try XCTUnwrap(first.results.first(where: { $0.fdcID == 3 }))
    first.select(toast)
    await waitUntil { first.stage == .reviewing }
    first.markSaved()

    let catalog = store.load()
    XCTAssertEqual(catalog.preferredFdcIDs(forQuery: "eggs"), [99])
    XCTAssertEqual(
      catalog.preferredFdcIDs(forQuery: "Egg, whole, cooked, scrambled"),
      [],
      "USDA's display description must not replace the component lookup signature"
    )

    let relog = LogViewModel(
      parser: FixedCompositeFoodParser(),
      provider: provider,
      rememberedFoods: store
    )
    relog.input = "eggs and toast"
    relog.submit()
    await waitUntil { relog.stage == .choosing && relog.activeCompositeComponent == "eggs" }

    XCTAssertEqual(relog.results.first?.fdcID, 99, "The confirmed egg should be rank-boosted")
    XCTAssertNil(
      relog.selectedResult,
      "Remembered component matches must keep the picker visible rather than applying nutrition"
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(2))
    }
    XCTAssertTrue(condition(), "Timed out waiting for expected state")
  }
}

private struct FixedRememberedFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: "cookie", searchTerms: "cookie")
  }
}

private struct FixedCompositeFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(
      productName: "eggs and toast",
      searchTerms: "eggs and toast",
      containsMultipleFoods: true,
      componentNames: ["eggs", "toast"]
    )
  }
}

private actor CompositeRememberedFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    let foods: [FoodSearchResult]
    if FoodLookupSignature.normalize(request.query) == "toast" {
      foods = [
        FoodSearchResult(fdcID: 3, description: "Toast", dataType: "Survey (FNDDS)")
      ]
    } else {
      foods = [
        FoodSearchResult(
          fdcID: 1,
          description: "Egg substitute, cooked",
          dataType: "Survey (FNDDS)"
        ),
        FoodSearchResult(
          fdcID: 99,
          description: "Egg, whole, cooked, scrambled",
          dataType: "SR Legacy"
        ),
      ]
    }
    return FoodSearchResponse(
      foods: foods,
      totalHits: foods.count,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    let description =
      fdcID == 99
      ? "Egg, whole, cooked, scrambled"
      : "Toast"
    return FoodDetails(
      fdcID: fdcID,
      description: description,
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
    )
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
