import HealthKit
import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

final class HealthKitNutritionWriterTests: XCTestCase {
  func testEveryModeledNutrientExceptAddedSugarHasUniqueHealthKitMapping() {
    let mapped = NutrientKey.allCases.compactMap(HealthKitNutrientMapping.init)

    XCTAssertEqual(mapped.count, NutrientKey.allCases.count - 1)
    XCTAssertNil(HealthKitNutrientMapping(.addedSugar))
    XCTAssertEqual(Set(mapped.map(\.quantityType.identifier)).count, mapped.count)
  }

  func testCanonicalUnitsMatchHealthKitDimensions() {
    XCTAssertEqual(HealthKitNutrientMapping(.energy)?.unit, .kilocalorie())
    XCTAssertEqual(HealthKitNutrientMapping(.protein)?.unit, .gram())
    XCTAssertEqual(HealthKitNutrientMapping(.sodium)?.unit, .gramUnit(with: .milli))
    XCTAssertEqual(HealthKitNutrientMapping(.vitaminD)?.unit, .gramUnit(with: .micro))
    XCTAssertEqual(HealthKitNutrientMapping(.water)?.unit, .literUnit(with: .milli))
  }

  @MainActor
  func testCoordinatorKeepsLocalEntryAndMarksSuccessfulWrite() async throws {
    let container = try ModelContainer(
      for: FoodLogEntryRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let entry = try FoodLogEntryRecord(
      originalText: "One egg",
      displayName: "Egg",
      quantityDisplay: "1 egg",
      isApproximate: false,
      source: .usda,
      fdcID: 123,
      calculationBasis: .servings,
      nutrients: [NutrientAmount(key: .energy, amount: 72)]
    )
    context.insert(entry)
    try context.save()
    UserDefaults.standard.set(true, forKey: HealthSyncCoordinator.preferenceKey)
    defer { UserDefaults.standard.removeObject(forKey: HealthSyncCoordinator.preferenceKey) }

    await HealthSyncCoordinator.syncIfEnabled(
      entry, modelContext: context, writer: SuccessfulHealthWriter())

    XCTAssertEqual(entry.healthSyncStatus, .synced)
    XCTAssertNotNil(entry.healthSyncedAt)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntryRecord>()).count, 1)
  }
}

private actor SuccessfulHealthWriter: HealthNutritionWriting {
  nonisolated let isAvailable = true

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    HealthAuthorizationSummary(
      authorizedNutrientCount: 1, requestedNutrientCount: 1, canWriteFood: true)
  }

  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws {}
}
