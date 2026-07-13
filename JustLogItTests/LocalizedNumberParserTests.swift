import Foundation
import JustLogItCore
import XCTest

@testable import JustLogIt

final class LocalizedNumberParserTests: XCTestCase {
  func testParsesCommaDecimalAndGroupingForFrenchLocale() {
    let locale = Locale(identifier: "fr_FR")
    let parser = LocalizedNumberParser(locale: locale)
    let grouping = locale.groupingSeparator ?? "\u{202f}"

    XCTAssertEqual(parser.parse("1,5", minimum: .greaterThanZero), 1.5)
    XCTAssertEqual(parser.parse("1\(grouping)234,5", minimum: .greaterThanZero), 1_234.5)
  }

  func testParsesDotDecimalAndGroupingForUSLocale() {
    let parser = LocalizedNumberParser(locale: Locale(identifier: "en_US"))

    XCTAssertEqual(parser.parse("1.5", minimum: .greaterThanZero), 1.5)
    XCTAssertEqual(parser.parse("1,234.5", minimum: .greaterThanZero), 1_234.5)
    XCTAssertEqual(parser.parse(".5", minimum: .greaterThanZero), 0.5)
    XCTAssertEqual(parser.parse("1.", minimum: .greaterThanZero), 1)
  }

  func testPositivePolicyRejectsZeroNegativeAndNonfiniteInput() {
    let parser = LocalizedNumberParser(locale: Locale(identifier: "en_US"))

    for input in ["0", "-1", "nan", "NaN", "inf", "infinity", "1e309"] {
      XCTAssertNil(parser.parse(input, minimum: .greaterThanZero), input)
    }
  }

  func testNonnegativePolicyAllowsZeroButRejectsNegativeAndNonfiniteInput() {
    let parser = LocalizedNumberParser(locale: Locale(identifier: "en_US"))

    XCTAssertEqual(parser.parse("0", minimum: .zero), 0)
    XCTAssertEqual(parser.parse("+0.5", minimum: .zero), 0.5)
    for input in ["-0.1", "nan", "inf", "1e309"] {
      XCTAssertNil(parser.parse(input, minimum: .zero), input)
    }
  }

  func testRejectsMalformedOrMixedLocaleNumbers() {
    let parser = LocalizedNumberParser(locale: Locale(identifier: "en_US"))

    for input in ["1,5", "12,34.5", "1.2.3", ".", "1 food", "--1", ""] {
      XCTAssertNil(parser.parse(input, minimum: .greaterThanZero), input)
    }
  }

  @MainActor
  func testLogClarificationUsesInjectedCommaLocale() async {
    let model = LogViewModel(
      parser: ClarificationFoodParser(),
      provider: ClarificationFoodProvider(),
      numberParser: LocalizedNumberParser(locale: Locale(identifier: "fr_FR"))
    )
    model.input = "chocolate milk"
    model.submit()

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while model.stage != .clarifying, clock.now < deadline {
      await Task.yield()
    }
    XCTAssertEqual(model.stage, .clarifying)

    model.clarificationGrams = "1,5"
    model.resolveWithGrams()

    XCTAssertEqual(model.stage, .reviewing)
    XCTAssertEqual(model.resolution?.consumedGrams, 1.5)
  }
}

private struct ClarificationFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    ParsedFoodRequest(productName: input, searchTerms: input)
  }
}

private struct ClarificationFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [FoodSearchResult(fdcID: 1, description: "Chocolate milk", dataType: "Branded")],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Chocolate milk",
      dataType: "Branded",
      nutrientsPer100Grams: [NutrientAmount(key: .energy, amount: 100)]
    )
  }
}
