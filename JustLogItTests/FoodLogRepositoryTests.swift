import Foundation
import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

@MainActor
final class FoodLogRepositoryTests: XCTestCase {
  // MARK: - Happy path

  func testSaveInsertsEntryUpsertsRecognizedFoodAndReturnsIDs() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let entry = try makeUSDAEntry(
      originalText: "two scrambled eggs",
      displayName: "Eggs, scrambled",
      fdcID: 42,
      quantityDisplay: "2 servings",
      calories: 296
    )
    let result = try repository.save(entry)

    XCTAssertEqual(result.entryID, entry.id)
    XCTAssertEqual(result.recognizedFoodID, entry.recognizedFoodID)
    XCTAssertFalse(context.hasChanges)

    let entries = try context.fetch(FetchDescriptor<FoodLogEntryRecord>())
    let foods = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(foods.count, 1)

    let saved = try XCTUnwrap(entries.first)
    let recognized = try XCTUnwrap(foods.first)
    XCTAssertEqual(saved.id, result.entryID)
    XCTAssertEqual(recognized.id, result.recognizedFoodID)
    XCTAssertEqual(saved.recognizedFoodID, recognized.id)
    XCTAssertEqual(recognized.fdcID, 42)
    XCTAssertEqual(recognized.useCount, 1)
    XCTAssertEqual(recognized.servingHint, "2 servings")
    XCTAssertEqual(recognized.nutrients?.first?.amount, 296)
  }

  func testSaveResultMatchesPersistedIDsAndIsEquatable() throws {
    let container = try makeContainer()
    let repository = FoodLogRepository(context: container.mainContext)
    let entry = try makeManualEntry(
      originalText: "toast",
      displayName: "Toast",
      quantityDisplay: "1 slice",
      calories: 80
    )

    let result = try repository.save(entry)
    let again = FoodLogRepository.SaveResult(
      entryID: entry.id,
      recognizedFoodID: try XCTUnwrap(entry.recognizedFoodID)
    )

    XCTAssertEqual(result, again)
    XCTAssertEqual(result.entryID, entry.id)
    XCTAssertEqual(result.recognizedFoodID, entry.recognizedFoodID)
  }

  // MARK: - Upsert semantics through the repository transaction

  func testSecondSaveWithSameFdcIDUpsertsRecognizedFoodWithoutDuplicatingIt() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let first = try makeUSDAEntry(
      originalText: "eggs",
      displayName: "Eggs, scrambled",
      fdcID: 42,
      quantityDisplay: "1 serving",
      calories: 148
    )
    let firstResult = try repository.save(first)

    let second = try makeUSDAEntry(
      originalText: "more eggs",
      displayName: "Eggs, scrambled, large",
      fdcID: 42,
      quantityDisplay: "2 servings",
      calories: 296
    )
    let secondResult = try repository.save(second)

    XCTAssertNotEqual(firstResult.entryID, secondResult.entryID)
    XCTAssertEqual(firstResult.recognizedFoodID, secondResult.recognizedFoodID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)

    let recognized = try XCTUnwrap(
      context.fetch(FetchDescriptor<RecognizedFoodRecord>()).first
    )
    XCTAssertEqual(recognized.useCount, 2)
    XCTAssertEqual(recognized.displayName, "Eggs, scrambled, large")
    XCTAssertEqual(recognized.servingHint, "2 servings")
  }

  func testSecondSaveWithNormalizedNameUpsertsWithoutFdcID() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let first = try makeManualEntry(
      originalText: "Homemade oatmeal",
      displayName: "Oatmeal",
      quantityDisplay: "1 bowl",
      calories: 200
    )
    let firstResult = try repository.save(first)

    let second = try makeManualEntry(
      originalText: "oatmeal again",
      displayName: "oatmeal",
      quantityDisplay: "1 cup",
      calories: 150
    )
    let secondResult = try repository.save(second)

    XCTAssertNotEqual(firstResult.entryID, secondResult.entryID)
    XCTAssertEqual(firstResult.recognizedFoodID, secondResult.recognizedFoodID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)

    let recognized = try XCTUnwrap(
      context.fetch(FetchDescriptor<RecognizedFoodRecord>()).first
    )
    XCTAssertEqual(recognized.useCount, 2)
    XCTAssertEqual(recognized.servingHint, "1 cup")
    XCTAssertEqual(recognized.nutrients?.first?.amount, 150)
  }

  func testDistinctFoodsProduceDistinctRecognizedRecords() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let eggs = try makeUSDAEntry(
      originalText: "eggs",
      displayName: "Eggs",
      fdcID: 1,
      quantityDisplay: "2",
      calories: 140
    )
    let toast = try makeManualEntry(
      originalText: "toast",
      displayName: "Toast",
      quantityDisplay: "1 slice",
      calories: 80
    )

    let eggsResult = try repository.save(eggs)
    let toastResult = try repository.save(toast)

    XCTAssertNotEqual(eggsResult.entryID, toastResult.entryID)
    XCTAssertNotEqual(eggsResult.recognizedFoodID, toastResult.recognizedFoodID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 2)
  }

  /// Callers (especially intents that may retry) own idempotency; each save inserts a new entry.
  func testRepeatedSaveOfLogicalConfirmationCreatesSeparateEntries() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let first = try makeUSDAEntry(
      originalText: "two eggs",
      displayName: "Eggs",
      fdcID: 99,
      quantityDisplay: "2",
      calories: 140
    )
    let second = try makeUSDAEntry(
      originalText: "two eggs",
      displayName: "Eggs",
      fdcID: 99,
      quantityDisplay: "2",
      calories: 140
    )

    let firstResult = try repository.save(first)
    let secondResult = try repository.save(second)

    XCTAssertNotEqual(firstResult.entryID, secondResult.entryID)
    XCTAssertEqual(firstResult.recognizedFoodID, secondResult.recognizedFoodID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
  }

  func testCompositeEntrySavesAndLinksRecognizedFood() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

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
        fdcID: 2,
        quantityDisplay: "1 tsp",
        nutrients: [NutrientAmount(key: .energy, amount: 34)]
      ),
    ]
    let draft = CompositeDraftBuilder.make(name: "Fried eggs", components: components)
    let entry = try FoodLogEntryRecord(
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

    let result = try repository.save(entry)

    XCTAssertEqual(result.entryID, entry.id)
    XCTAssertEqual(entry.recognizedFoodID, result.recognizedFoodID)
    XCTAssertTrue(entry.isCompositeEntry)
    XCTAssertEqual(entry.components.count, 2)

    let saved = try XCTUnwrap(context.fetch(FetchDescriptor<FoodLogEntryRecord>()).first)
    XCTAssertTrue(saved.isCompositeEntry)
    XCTAssertEqual(saved.components.count, 2)
    XCTAssertEqual(saved.recognizedFoodID, result.recognizedFoodID)
  }

  // MARK: - Failure / rollback

  func testFailedPersistRollsBackEntryAndRecognizedFoodMutation() throws {
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

    let repository = FoodLogRepository(context: context) { _ in
      throw InjectedPersistenceError()
    }
    let failedEntry = try makeManualEntry(
      originalText: "oatmeal again",
      displayName: "Oatmeal",
      quantityDisplay: "2 bowls",
      calories: 400
    )

    XCTAssertThrowsError(try repository.save(failedEntry))

    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 0)
    let foods = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
    let unchanged = try XCTUnwrap(foods.first)
    XCTAssertEqual(foods.count, 1)
    XCTAssertEqual(unchanged.id, existing.id)
    XCTAssertEqual(unchanged.useCount, 1)
    XCTAssertEqual(unchanged.lastUsedAt, originalDate)
    XCTAssertEqual(unchanged.servingHint, "1 bowl")
    XCTAssertEqual(unchanged.nutrients?.first?.amount, 200)
  }

  func testFailedPersistRollsBackBrandNewRecognizedFoodInsert() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context) { _ in
      throw InjectedPersistenceError()
    }

    XCTAssertThrowsError(
      try repository.save(
        try makeManualEntry(
          originalText: "brand new food",
          displayName: "Quinoa Bowl",
          quantityDisplay: "1 bowl",
          calories: 350
        )
      )
    )

    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 0)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 0)
  }

  func testEmptyDisplayNameFailsAndRollsBackInsertedEntry() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let repository = FoodLogRepository(context: context)

    let entry = try FoodLogEntryRecord(
      originalText: "   ",
      displayName: "   ",
      quantityDisplay: "1",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 10)]
    )

    XCTAssertThrowsError(try repository.save(entry)) { error in
      guard case RecognizedFoodStoreError.emptyDisplayName = error else {
        XCTFail("Expected emptyDisplayName, got \(error)")
        return
      }
    }

    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 0)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 0)
  }

  func testRetryAfterFailureSucceedsThroughSameRepository() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let existing = RecognizedFoodRecord(
      displayName: "Oatmeal",
      lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000),
      useCount: 1,
      servingHint: "1 bowl",
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )
    context.insert(existing)
    try context.save()

    var shouldFail = true
    let repository = FoodLogRepository(context: context) { ctx in
      if shouldFail {
        throw InjectedPersistenceError()
      }
      try ctx.save()
    }

    XCTAssertThrowsError(
      try repository.save(
        try makeManualEntry(
          originalText: "oatmeal fail",
          displayName: "Oatmeal",
          quantityDisplay: "2 bowls",
          calories: 400
        )
      )
    )

    shouldFail = false
    let retryEntry = try makeManualEntry(
      originalText: "oatmeal retry",
      displayName: "Oatmeal",
      quantityDisplay: "2 bowls",
      calories: 400
    )
    let result = try repository.save(retryEntry)

    XCTAssertEqual(result.entryID, retryEntry.id)
    XCTAssertEqual(result.recognizedFoodID, existing.id)
    XCTAssertEqual(retryEntry.recognizedFoodID, existing.id)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
    XCTAssertEqual(existing.useCount, 2)
    XCTAssertEqual(existing.servingHint, "2 bowls")
  }

  // MARK: - Compatibility + container factory paths

  func testLegacySaveTransactionDelegatesToRepositoryCommit() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let entry = try makeManualEntry(
      originalText: "toast",
      displayName: "Toast",
      quantityDisplay: "1 slice",
      calories: 80
    )
    let recognized = try FoodLogSaveTransaction.save(entry, in: context)

    XCTAssertEqual(entry.recognizedFoodID, recognized.id)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
  }

  func testSaveWorksOnUITestingInMemoryContainer() throws {
    let built = try ModelContainerFactory.make(isUITesting: true)
    XCTAssertFalse(
      built.usesVolatileStore,
      "isUITesting path is intentional in-memory testing, not a volatile fallback"
    )

    let context = built.container.mainContext
    let repository = FoodLogRepository(context: context)
    let entry = try makeUSDAEntry(
      originalText: "apple",
      displayName: "Apple, raw",
      fdcID: 1_689,
      quantityDisplay: "1 medium",
      calories: 95
    )
    let result = try repository.save(entry)

    XCTAssertEqual(result.entryID, entry.id)
    XCTAssertEqual(entry.recognizedFoodID, result.recognizedFoodID)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
  }

  func testSaveWorksOnForcedVolatileInMemoryContainer() throws {
    let built = try ModelContainerFactory.make(
      isUITesting: false,
      forceVolatileStore: true
    )
    XCTAssertTrue(built.usesVolatileStore)

    let context = built.container.mainContext
    let repository = FoodLogRepository(context: context)
    let entry = try makeManualEntry(
      originalText: "banana",
      displayName: "Banana",
      quantityDisplay: "1",
      calories: 105
    )
    let result = try repository.save(entry)

    XCTAssertEqual(result.entryID, entry.id)
    XCTAssertEqual(entry.recognizedFoodID, result.recognizedFoodID)
    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<RecognizedFoodRecord>()).count, 1)
  }

  // MARK: - Helpers

  /// Default fixture uses the same schema and in-memory store policy as UI testing.
  private func makeContainer() throws -> ModelContainer {
    let built = try ModelContainerFactory.make(isUITesting: true)
    return built.container
  }

  private func makeUSDAEntry(
    originalText: String,
    displayName: String,
    fdcID: Int,
    quantityDisplay: String,
    calories: Double
  ) throws -> FoodLogEntryRecord {
    try FoodLogEntryRecord(
      originalText: originalText,
      displayName: displayName,
      quantityDisplay: quantityDisplay,
      isApproximate: false,
      source: .usda,
      fdcID: fdcID,
      usdaDataType: "Survey (FNDDS)",
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: calories)]
    )
  }

  private func makeManualEntry(
    originalText: String,
    displayName: String,
    quantityDisplay: String,
    calories: Double
  ) throws -> FoodLogEntryRecord {
    try FoodLogEntryRecord(
      originalText: originalText,
      displayName: displayName,
      quantityDisplay: quantityDisplay,
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: calories)]
    )
  }
}

private struct InjectedPersistenceError: Error {}
