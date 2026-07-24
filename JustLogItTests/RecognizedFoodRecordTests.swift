import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

@MainActor
final class RecognizedFoodRecordTests: XCTestCase {
  func testFailedSaveRollsBackEntryAndExistingRecognizedFoodMutationBeforeRetry() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = RecognizedFoodRecord(
      displayName: "Oatmeal",
      lastUsedAt: originalDate,
      useCount: 1,
      servingHint: "1 bowl",
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )
    context.insert(existing)
    try context.save()

    let failedEntry = try makeManualOatmealEntry(
      originalText: "oatmeal again",
      quantityDisplay: "2 bowls",
      calories: 400
    )
    XCTAssertThrowsError(
      try FoodLogSaveTransaction.save(failedEntry, in: context) { _ in
        throw InjectedPersistenceError()
      }
    )

    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 0)
    let foodsAfterFailure = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
    let unchanged = try XCTUnwrap(foodsAfterFailure.first)
    XCTAssertEqual(foodsAfterFailure.count, 1)
    XCTAssertEqual(unchanged.id, existing.id)
    XCTAssertEqual(unchanged.useCount, 1)
    XCTAssertEqual(unchanged.lastUsedAt, originalDate)
    XCTAssertEqual(unchanged.servingHint, "1 bowl")
    XCTAssertEqual(unchanged.nutrients?.first?.amount, 200)

    let retryEntry = try makeManualOatmealEntry(
      originalText: "oatmeal retry",
      quantityDisplay: "2 bowls",
      calories: 400
    )
    let recognized = try FoodLogSaveTransaction.save(retryEntry, in: context)

    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
    XCTAssertEqual(recognized.id, existing.id)
    XCTAssertEqual(recognized.useCount, 2)
    XCTAssertEqual(recognized.servingHint, "2 bowls")
    XCTAssertEqual(recognized.nutrients?.first?.amount, 400)
    XCTAssertEqual(retryEntry.recognizedFoodID, existing.id)
  }

  func testUpsertCreatesAndLinksByFdcID() throws {
    let container = try makeContainer()
    let context = container.mainContext

    let entry = try FoodLogEntryRecord(
      originalText: "eggs",
      displayName: "Eggs, scrambled",
      brand: nil,
      quantityDisplay: "1 serving",
      isApproximate: false,
      source: .usda,
      fdcID: 42,
      usdaDataType: "Survey (FNDDS)",
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: 148)]
    )
    context.insert(entry)

    let recognized = try RecognizedFoodRecord.upsert(from: entry, in: context)
    entry.recognizedFoodID = recognized.id
    try context.save()

    XCTAssertEqual(recognized.fdcID, 42)
    XCTAssertEqual(recognized.useCount, 1)
    XCTAssertEqual(recognized.displayName, "Eggs, scrambled")
    XCTAssertEqual(entry.recognizedFoodID, recognized.id)

    let second = try FoodLogEntryRecord(
      originalText: "more eggs",
      displayName: "Eggs, scrambled, large",
      quantityDisplay: "2 servings",
      isApproximate: false,
      source: .usda,
      fdcID: 42,
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: 296)]
    )
    context.insert(second)
    let again = try RecognizedFoodRecord.upsert(from: second, in: context)
    try context.save()

    XCTAssertEqual(again.id, recognized.id)
    XCTAssertEqual(again.useCount, 2)
    XCTAssertEqual(again.displayName, "Eggs, scrambled, large")
    XCTAssertEqual(again.servingHint, "2 servings")

    let all = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
    XCTAssertEqual(all.count, 1)
  }

  func testUpsertMatchesNormalizedNameWithoutFdcID() throws {
    let container = try makeContainer()
    let context = container.mainContext

    let first = try FoodLogEntryRecord(
      originalText: "Homemade oatmeal",
      displayName: "Oatmeal",
      quantityDisplay: "1 bowl",
      isApproximate: true,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )
    context.insert(first)
    let a = try RecognizedFoodRecord.upsert(from: first, in: context)

    let second = try FoodLogEntryRecord(
      originalText: "oatmeal again",
      displayName: "oatmeal",
      quantityDisplay: "1 cup",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 150)]
    )
    context.insert(second)
    let b = try RecognizedFoodRecord.upsert(from: second, in: context)

    XCTAssertEqual(a.id, b.id)
    XCTAssertEqual(b.useCount, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
  }

  func testCompositeEntryRoundTripsComponentPayload() throws {
    let components = [
      CompositeComponentSnapshot(
        displayName: "Eggs",
        fdcID: 1,
        quantityDisplay: "2 large",
        nutrients: [
          NutrientAmount(key: .energy, amount: 180),
          NutrientAmount(key: .protein, amount: 12),
        ]
      ),
      CompositeComponentSnapshot(
        displayName: "Butter",
        brand: "Land O Lakes",
        fdcID: 2,
        quantityDisplay: "1 tsp",
        nutrients: [NutrientAmount(key: .energy, amount: 34)],
        isApproximate: true
      ),
    ]
    let draft = CompositeDraftBuilder.make(name: "Fried eggs", components: components)

    let record = try FoodLogEntryRecord(
      originalText: "fried eggs with butter",
      displayName: draft.name,
      quantityDisplay: "2 foods",
      isApproximate: true,
      source: .usda,
      calculationBasis: .manual,
      nutrients: draft.totalNutrients,
      isComposite: true,
      components: draft.components
    )

    XCTAssertTrue(record.isCompositeEntry)
    XCTAssertEqual(record.components.count, 2)
    XCTAssertEqual(record.components[0].displayName, "Eggs")
    XCTAssertEqual(record.components[1].isApproximate, true)
    XCTAssertEqual(record.calories, 214)
    XCTAssertEqual(record.protein, 12)
  }

  func testMalformedComponentPayloadFailsClosed() throws {
    let record = try FoodLogEntryRecord(
      originalText: "meal",
      displayName: "Meal",
      quantityDisplay: "1",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 100)],
      isComposite: true,
      components: [
        CompositeComponentSnapshot(
          displayName: "A",
          quantityDisplay: "1",
          nutrients: [NutrientAmount(key: .energy, amount: 100)]
        )
      ]
    )
    record.componentPayload = Data("not-json".utf8)
    XCTAssertEqual(record.components, [])
  }

  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: FoodLogEntryRecord.self, HealthDeletionTombstone.self, RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }

  private func makeManualOatmealEntry(
    originalText: String,
    quantityDisplay: String,
    calories: Double
  ) throws -> FoodLogEntryRecord {
    try FoodLogEntryRecord(
      originalText: originalText,
      displayName: "Oatmeal",
      quantityDisplay: quantityDisplay,
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: calories)]
    )
  }
}

private struct InjectedPersistenceError: Error {}
