import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class QuantityClarificationTests: XCTestCase {
  func testMissingQuantityDefaultsToOneServingAndSkipsPickerWhenMatchIsClear() async {
    // "mystery food" is multi-token + single USDA hit → auto-select + 1 serving default.
    let model = LogViewModel(
      parser: QuantityFoodParser(),
      provider: GramsOnlyFoodProvider()
    )
    model.input = "mystery food"
    model.submit()
    await waitUntil { model.stage == .reviewing }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.parsed?.quantity, 1)
    XCTAssertEqual(model.resolution?.servingMultiplier, 1)
    XCTAssertEqual(model.resolution?.consumedGrams, 50)
    XCTAssertNil(model.activeQuestion)
  }

  func testExplicitGramsOverrideStillResolvesWhenUserPicksFromPicker() async {
    // Two weak rice hits → picker; user selects then amount is still defaulted to 1 serving
    // unless they use a parse with quantity. Here parse has no qty → 1 USDA serving.
    let model = LogViewModel(
      parser: RiceFoodParser(),
      provider: AmbiguousRiceProvider()
    )
    model.input = "rice"
    model.submit()
    await waitUntil { model.stage == .choosing }
    XCTAssertEqual(model.stage, .choosing)
    XCTAssertGreaterThanOrEqual(model.results.count, 2)

    model.select(model.results[0])
    await waitUntil { model.stage == .reviewing || model.stage == .clarifying }

    // Serving present on stub → default 1 serving reaches review.
    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.resolution?.servingMultiplier, 1)
  }

  func testResolveQuantityEntryStillWorksForManualAmount() async {
    let model = LogViewModel(
      parser: QuantityFoodParser(),
      provider: GramsOnlyFoodProvider()
    )
    model.input = "mystery food"
    model.submit()
    await waitUntil { model.stage == .reviewing }

    // From review, user can still force a gram amount via the quantity path if clarifying.
    // Simulate re-resolve after details are loaded.
    guard let details = model.details else {
      XCTFail("Expected details after auto path")
      return
    }
    model.resolveQuantityEntry(amountText: "100", unit: "g")
    await waitUntil { model.stage == .reviewing }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.resolution?.consumedGrams, 100)
    _ = details
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

private struct QuantityFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    // No quantity/unit → post-USDA clarification.
    ParsedFoodRequest(productName: "mystery food", searchTerms: "mystery food")
  }
}

private actor GramsOnlyFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 501,
          description: "MYSTERY FOOD",
          dataType: "Branded",
          servingSize: 50,
          servingSizeUnit: "g",
          householdServing: "1 bar"
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
      description: "MYSTERY FOOD",
      dataType: "Branded",
      servingSize: 50,
      servingSizeUnit: "g",
      householdServing: "1 bar",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 200)],
      nutrientsPerServing: [NutrientAmount(key: .energy, amount: 100)]
    )
  }
}

private struct RiceFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: "rice", searchTerms: "rice")
  }
}

private actor AmbiguousRiceProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 1, description: "Rice, white, cooked", dataType: "Foundation",
          servingSize: 158, servingSizeUnit: "g", householdServing: "1 cup"),
        FoodSearchResult(
          fdcID: 2, description: "Brown rice, cooked", dataType: "Foundation",
          servingSize: 195, servingSizeUnit: "g", householdServing: "1 cup"),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: fdcID == 1 ? "Rice, white, cooked" : "Brown rice, cooked",
      dataType: "Foundation",
      servingSize: fdcID == 1 ? 158 : 195,
      servingSizeUnit: "g",
      householdServing: "1 cup",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 130)],
      nutrientsPerServing: [NutrientAmount(key: .energy, amount: 200)]
    )
  }
}
