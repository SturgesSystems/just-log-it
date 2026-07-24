import Foundation
import JustLogItCore
import SwiftData
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

  func testDefaultCompositeFieldsRemainInactiveForSingleFood() throws {
    let record = try FoodLogEntryRecord(
      originalText: "Custom food",
      displayName: "Custom food",
      quantityDisplay: "1 portion",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )

    XCTAssertFalse(record.isCompositeEntry)
    XCTAssertNil(record.componentPayload)
    XCTAssertEqual(record.components, [])
    XCTAssertNil(record.recognizedFoodID)
  }

  func testSharePlainTextIncludesNameQuantityTimeMacrosAndOriginal() throws {
    let consumedAt = Date(timeIntervalSince1970: 1_700_000_002)
    let record = try FoodLogEntryRecord(
      consumedAt: consumedAt,
      originalText: "One serving of scrambled eggs",
      displayName: "Eggs, scrambled",
      brand: "Test Kitchen",
      quantityDisplay: "1 USDA serving",
      isApproximate: false,
      source: .usda,
      fdcID: 999_001,
      calculationBasis: .servings,
      nutrients: [
        NutrientAmount(key: .energy, amount: 148),
        NutrientAmount(key: .protein, amount: 10),
        NutrientAmount(key: .carbohydrate, amount: 1.6),
        NutrientAmount(key: .totalFat, amount: 11),
        NutrientAmount(key: .sodium, amount: 250),
      ]
    )
    record.healthSyncStatus = .failed
    record.healthSyncError = "secret diagnostic"

    let text = FoodLogEntryShareText.plainText(for: record)
    let logged = consumedAt.formatted(date: .abbreviated, time: .shortened)

    XCTAssertEqual(
      text,
      """
      Eggs, scrambled
      Test Kitchen
      Amount: 1 USDA serving
      Logged: \(logged)

      Calories: 148 kcal
      Protein: 10 g
      Carbohydrates: 1.6 g
      Total Fat: 11 g

      Original: One serving of scrambled eggs
      """
    )
    XCTAssertFalse(text.contains("secret diagnostic"))
    XCTAssertFalse(text.contains("999001"))
    XCTAssertFalse(text.contains("Sodium"))
  }

  func testSharePlainTextOmitsEmptyBrandAndMissingMacros() throws {
    let consumedAt = Date(timeIntervalSince1970: 1_710_000_000)
    let record = try FoodLogEntryRecord(
      consumedAt: consumedAt,
      originalText: "  homemade soup  ",
      displayName: "Soup",
      brand: "   ",
      quantityDisplay: "1 bowl",
      isApproximate: true,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 200)]
    )

    let text = FoodLogEntryShareText.plainText(for: record)
    let logged = consumedAt.formatted(date: .abbreviated, time: .shortened)

    XCTAssertEqual(
      text,
      """
      Soup
      Amount: 1 bowl
      Logged: \(logged)

      Calories: 200 kcal

      Original: homemade soup
      """
    )
    XCTAssertFalse(text.contains("Protein"))
    XCTAssertFalse(text.contains("Brand"))
  }

  func testConfirmedUSDAEntrySurvivesDiskCloseAndReopen() throws {
    let fixture = makeDiskFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let entryID = UUID(uuidString: "9E6F42E1-FA51-4A69-82A1-99E290DC3201")!
    let recognizedID: UUID = try withDiskContainer(at: fixture.storeURL) { context in
      let entry = try FoodLogEntryRecord(
        id: entryID,
        createdAt: Date(timeIntervalSince1970: 1_700_000_001),
        consumedAt: Date(timeIntervalSince1970: 1_700_000_002),
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_003),
        originalText: "two scrambled eggs",
        displayName: "Eggs, scrambled",
        brand: "Test Kitchen",
        quantityDisplay: "2 large eggs (100 g)",
        isApproximate: true,
        source: .usda,
        fdcID: 1_234_567,
        usdaDescription: "Egg, whole, cooked, scrambled",
        usdaDataType: "Survey (FNDDS)",
        calculationBasis: .grams,
        servingMultiplier: 2,
        consumedGrams: 100,
        nutrients: [
          NutrientAmount(key: .energy, amount: 212),
          NutrientAmount(key: .protein, amount: 13.6),
          NutrientAmount(key: .totalFat, amount: 15.8),
        ]
      )
      entry.healthSyncStatus = .failed
      entry.healthSyncVersion = 3
      entry.healthSyncedAt = Date(timeIntervalSince1970: 1_700_000_004)
      entry.healthSyncError = "Test failure"
      entry.healthSyncRetryCount = 2
      entry.healthSyncNextRetryAt = Date(timeIntervalSince1970: 1_700_000_005)
      context.insert(entry)
      let recognized = try RecognizedFoodRecord.upsert(
        from: entry,
        in: context,
        at: Date(timeIntervalSince1970: 1_700_000_006)
      )
      entry.recognizedFoodID = recognized.id
      try context.save()
      return recognized.id
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.storeURL.path))

    try withDiskContainer(at: fixture.storeURL) { context in
      let entries = try context.fetch(FetchDescriptor<FoodLogEntryRecord>())
      let recognizedFoods = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
      let entry = try XCTUnwrap(entries.first(where: { $0.id == entryID }))
      let recognized = try XCTUnwrap(recognizedFoods.first(where: { $0.id == recognizedID }))

      XCTAssertEqual(entries.count, 1)
      XCTAssertEqual(recognizedFoods.count, 1)
      XCTAssertEqual(entry.createdAt, Date(timeIntervalSince1970: 1_700_000_001))
      XCTAssertEqual(entry.consumedAt, Date(timeIntervalSince1970: 1_700_000_002))
      XCTAssertEqual(entry.modifiedAt, Date(timeIntervalSince1970: 1_700_000_003))
      XCTAssertEqual(entry.originalText, "two scrambled eggs")
      XCTAssertEqual(entry.displayName, "Eggs, scrambled")
      XCTAssertEqual(entry.brand, "Test Kitchen")
      XCTAssertEqual(entry.quantityDisplay, "2 large eggs (100 g)")
      XCTAssertTrue(entry.isApproximate)
      XCTAssertEqual(entry.source, .usda)
      XCTAssertEqual(entry.fdcID, 1_234_567)
      XCTAssertEqual(entry.usdaDescription, "Egg, whole, cooked, scrambled")
      XCTAssertEqual(entry.usdaDataType, "Survey (FNDDS)")
      XCTAssertEqual(entry.calculationBasis, .grams)
      XCTAssertEqual(entry.servingMultiplier, 2)
      XCTAssertEqual(entry.consumedGrams, 100)
      XCTAssertEqual(entry.calories, 212)
      XCTAssertEqual(entry.protein, 13.6)
      XCTAssertEqual(entry.healthSyncStatus, .failed)
      XCTAssertEqual(entry.healthSyncVersion, 3)
      XCTAssertEqual(entry.healthSyncedAt, Date(timeIntervalSince1970: 1_700_000_004))
      XCTAssertEqual(entry.healthSyncError, "Test failure")
      XCTAssertEqual(entry.healthSyncRetryCount, 2)
      XCTAssertEqual(entry.healthSyncNextRetryAt, Date(timeIntervalSince1970: 1_700_000_005))
      XCTAssertEqual(entry.recognizedFoodID, recognized.id)
      XCTAssertEqual(recognized.fdcID, entry.fdcID)
      XCTAssertEqual(recognized.servingHint, entry.quantityDisplay)
      XCTAssertEqual(recognized.nutrients, entry.nutrients)
    }
  }

  func testManualEntryEquivalentTransactionSurvivesDiskCloseAndReopen() throws {
    let fixture = makeDiskFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let entryID = UUID(uuidString: "75D5CB17-A481-4B23-8B08-5A89DD530118")!
    let consumedAt = Date(timeIntervalSince1970: 1_710_000_000)
    let recognizedID: UUID = try withDiskContainer(at: fixture.storeURL) { context in
      // Mirrors ManualEntryView's save boundary after its localized-number validation.
      let entry = try FoodLogEntryRecord(
        id: entryID,
        consumedAt: consumedAt,
        originalText: "Grandma's oatmeal",
        displayName: "Grandma's oatmeal",
        quantityDisplay: "Amount not specified",
        isApproximate: true,
        source: .manual,
        calculationBasis: .manual,
        nutrients: [
          NutrientAmount(key: .energy, amount: 285),
          NutrientAmount(key: .protein, amount: 9.5),
          NutrientAmount(key: .carbohydrate, amount: 44),
          NutrientAmount(key: .totalFat, amount: 8.25),
        ]
      )
      context.insert(entry)
      let recognized = try RecognizedFoodRecord.upsert(from: entry, in: context)
      entry.recognizedFoodID = recognized.id
      try context.save()
      return recognized.id
    }

    try withDiskContainer(at: fixture.storeURL) { context in
      let entries = try context.fetch(FetchDescriptor<FoodLogEntryRecord>())
      let foods = try context.fetch(FetchDescriptor<RecognizedFoodRecord>())
      let entry = try XCTUnwrap(entries.first(where: { $0.id == entryID }))
      let food = try XCTUnwrap(foods.first(where: { $0.id == recognizedID }))

      XCTAssertEqual(entries.count, 1)
      XCTAssertEqual(foods.count, 1)
      XCTAssertEqual(entry.consumedAt, consumedAt)
      XCTAssertEqual(entry.originalText, "Grandma's oatmeal")
      XCTAssertEqual(entry.displayName, "Grandma's oatmeal")
      XCTAssertEqual(entry.quantityDisplay, "Amount not specified")
      XCTAssertTrue(entry.isApproximate)
      XCTAssertEqual(entry.source, .manual)
      XCTAssertEqual(entry.calculationBasis, .manual)
      XCTAssertNil(entry.fdcID)
      XCTAssertEqual(entry.nutrients.count, 4)
      XCTAssertEqual(entry.calories, 285)
      XCTAssertEqual(entry.protein, 9.5)
      XCTAssertEqual(entry.recognizedFoodID, food.id)
      XCTAssertEqual(food.displayName, entry.displayName)
      XCTAssertEqual(food.normalizedName, "grandma s oatmeal")
      XCTAssertEqual(food.useCount, 1)
      XCTAssertEqual(food.servingHint, "Amount not specified")
      XCTAssertEqual(food.nutrients, entry.nutrients)
    }
  }

  func testCompositeEntryAndComponentsSurviveDiskCloseAndReopen() throws {
    let fixture = makeDiskFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let components = [
      CompositeComponentSnapshot(
        displayName: "Eggs, fried",
        fdcID: 101,
        quantityDisplay: "3 large eggs",
        nutrients: [
          NutrientAmount(key: .energy, amount: 270),
          NutrientAmount(key: .protein, amount: 18),
          NutrientAmount(key: .totalFat, amount: 21),
        ]
      ),
      CompositeComponentSnapshot(
        displayName: "Olive oil",
        brand: "Pantry",
        fdcID: 202,
        quantityDisplay: "2 tsp",
        nutrients: [
          NutrientAmount(key: .energy, amount: 80),
          NutrientAmount(key: .totalFat, amount: 9),
        ],
        isApproximate: true
      ),
    ]
    let draft = CompositeDraftBuilder.make(name: "Three fried eggs", components: components)
    let entryID = UUID(uuidString: "EB476837-01BA-418C-86A5-6B781678D87C")!
    let recognizedID: UUID = try withDiskContainer(at: fixture.storeURL) { context in
      let entry = try FoodLogEntryRecord(
        id: entryID,
        originalText: "three fried eggs in two teaspoons olive oil",
        displayName: draft.name,
        quantityDisplay: "2 foods",
        isApproximate: true,
        source: .usda,
        calculationBasis: .manual,
        nutrients: draft.totalNutrients,
        isComposite: true,
        components: draft.components
      )
      context.insert(entry)
      let recognized = try RecognizedFoodRecord.upsert(from: entry, in: context)
      entry.recognizedFoodID = recognized.id
      try context.save()
      return recognized.id
    }

    try withDiskContainer(at: fixture.storeURL) { context in
      let entry = try XCTUnwrap(
        context.fetch(FetchDescriptor<FoodLogEntryRecord>()).first(where: { $0.id == entryID })
      )
      let food = try XCTUnwrap(
        context.fetch(FetchDescriptor<RecognizedFoodRecord>()).first(where: {
          $0.id == recognizedID
        })
      )

      XCTAssertTrue(entry.isCompositeEntry)
      XCTAssertNotNil(entry.componentPayload)
      XCTAssertEqual(entry.components, components)
      XCTAssertEqual(entry.nutrients, draft.totalNutrients)
      XCTAssertEqual(entry.calories, 350)
      XCTAssertEqual(entry.protein, 18)
      XCTAssertEqual(entry.recognizedFoodID, food.id)
      XCTAssertEqual(food.displayName, "Three fried eggs")
      XCTAssertEqual(food.nutrients, draft.totalNutrients)
      XCTAssertEqual(food.servingHint, "2 foods")
    }
  }

  private func makeDiskFixture() -> (directory: URL, storeURL: URL) {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "justlogit-persistence-boundary-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    return (directory, directory.appending(path: "test.store"))
  }

  /// Keeps each container inside an autorelease pool so the next invocation is a
  /// genuine store reopen rather than another context on the same container.
  private func withDiskContainer<Value>(
    at storeURL: URL,
    _ body: (ModelContext) throws -> Value
  ) throws -> Value {
    var outcome: Result<Value, Error>!
    autoreleasepool {
      do {
        try FileManager.default.createDirectory(
          at: storeURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        let result = try ModelContainerFactory.make(
          isUITesting: false,
          persistentStoreURL: storeURL
        )
        XCTAssertFalse(result.usesVolatileStore, "Disk fixture unexpectedly fell back to memory")
        outcome = .success(try body(result.container.mainContext))
      } catch {
        outcome = .failure(error)
      }
    }
    return try outcome.get()
  }
}
