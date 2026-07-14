import Foundation
import JustLogItCore

// Deterministic doubles used only when the app launches with `-ui-testing`.
// They live in shipping source (not the test target) because the running app
// process selects them at launch.

struct MockFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-parser-failure") {
      throw FoodParserError.invalidResponse
    }
    return ParsedFoodRequest(productName: input, searchTerms: input, quantity: 1, unit: "serving")
  }
}

struct MockFoodDataProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 999_001, description: "EGGS, SCRAMBLED", dataType: "Survey (FNDDS)",
          servingSize: 100, servingSizeUnit: "g", householdServing: "1 serving")
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
