import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class QuantityClarificationTests: XCTestCase {
  func testUnresolvedQuantityPresentsStructuredQuestionWithSuggestions() async {
    let model = LogViewModel(
      parser: QuantityFoodParser(),
      provider: GramsOnlyFoodProvider()
    )
    model.input = "mystery food"
    model.submit()
    await waitUntil { model.stage == .choosing }

    guard let result = model.results.first else {
      XCTFail("Expected search results")
      return
    }
    model.select(result)
    await waitUntil { model.stage == .clarifying }

    XCTAssertEqual(model.stage, .clarifying)
    XCTAssertEqual(model.activeQuestion?.code, .missingQuantity)
    XCTAssertEqual(model.activeQuestion?.prompt, model.message)
    XCTAssertTrue(model.activeQuestion?.suggestedAnswers.contains("1 serving") == true)
    XCTAssertTrue(model.activeQuestion?.suggestedAnswers.contains("100 g") == true)
  }

  func testQuantitySuggestionResolvesToReview() async {
    let model = LogViewModel(
      parser: QuantityFoodParser(),
      provider: GramsOnlyFoodProvider()
    )
    model.input = "mystery food"
    model.submit()
    await waitUntil { model.stage == .choosing }
    guard let first = model.results.first else {
      XCTFail("Expected results")
      return
    }
    model.select(first)
    await waitUntil { model.stage == .clarifying }

    model.chooseClarificationSuggestion("100 g")
    await waitUntil { model.stage == .reviewing }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.resolution?.consumedGrams, 100)
    XCTAssertNil(model.activeQuestion)
  }

  func testOneServingSuggestionUsesUSDAServing() async {
    let model = LogViewModel(
      parser: QuantityFoodParser(),
      provider: GramsOnlyFoodProvider()
    )
    model.input = "mystery food"
    model.submit()
    await waitUntil { model.stage == .choosing }
    guard let first = model.results.first else {
      XCTFail("Expected results")
      return
    }
    model.select(first)
    await waitUntil { model.stage == .clarifying }

    model.chooseClarificationSuggestion("1 serving")
    await waitUntil { model.stage == .reviewing }

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.resolution?.basis, .servings)
    XCTAssertEqual(model.resolution?.servingMultiplier, 1)
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
