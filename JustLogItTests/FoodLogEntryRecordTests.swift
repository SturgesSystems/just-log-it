import JustLogItCore
import XCTest

@testable import JustLogIt

@MainActor
final class FoodLogEntryRecordTests: XCTestCase {
  func testNutrientSnapshotRoundTripsThroughPersistenceEncoding() throws {
    let nutrients = [
      NutrientAmount(key: .energy, amount: 148),
      NutrientAmount(key: .protein, amount: 10),
      NutrientAmount(key: .carbohydrate, amount: 1.6),
      NutrientAmount(key: .totalFat, amount: 11),
    ]

    let record = try FoodLogEntryRecord(
      originalText: "One serving of scrambled eggs",
      displayName: "Eggs, scrambled",
      quantityDisplay: "1 USDA serving",
      isApproximate: false,
      source: .usda,
      fdcID: 999_001,
      usdaDescription: "Eggs, scrambled",
      usdaDataType: "Survey (FNDDS)",
      calculationBasis: .servings,
      servingMultiplier: 1,
      consumedGrams: 100,
      nutrients: nutrients
    )

    XCTAssertEqual(record.source, .usda)
    XCTAssertEqual(record.calculationBasis, .servings)
    XCTAssertEqual(record.nutrients, nutrients)
    XCTAssertEqual(record.calories, 148)
    XCTAssertEqual(record.protein, 10)
  }

  func testUnknownStoredEnumValuesFallBackSafely() throws {
    let record = try FoodLogEntryRecord(
      originalText: "Custom food",
      displayName: "Custom food",
      quantityDisplay: "1 portion",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )

    record.sourceRawValue = "future-source"
    record.calculationBasisRawValue = "future-basis"

    XCTAssertEqual(record.source, .manual)
    XCTAssertEqual(record.calculationBasis, .manual)
  }

  func testMalformedNutrientSnapshotFailsClosed() throws {
    let record = try FoodLogEntryRecord(
      originalText: "Custom food",
      displayName: "Custom food",
      quantityDisplay: "1 portion",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )

    record.nutrientsData = Data("not-json".utf8)

    XCTAssertEqual(record.nutrients, [])
    XCTAssertNil(record.calories)
    XCTAssertNil(record.protein)
  }
}
