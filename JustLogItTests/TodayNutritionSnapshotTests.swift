import Foundation
import JustLogItCore
import SwiftData
import XCTest

@testable import JustLogIt

@MainActor
final class TodayNutritionSnapshotTests: XCTestCase {
  private var retainedContainers: [ModelContainer] = []

  override func tearDown() {
    TodayNutritionSnapshotSource.unbind()
    retainedContainers.removeAll()
    super.tearDown()
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  /// 2023-11-14 12:00:00 UTC — mid-day so boundary tests have room on both sides.
  private var referenceNow: Date {
    Date(timeIntervalSince1970: 1_700_000_000)
  }

  private var dayStart: Date {
    utcCalendar.startOfDay(for: referenceNow)
  }

  private var dayEnd: Date {
    utcCalendar.date(byAdding: .day, value: 1, to: dayStart)!
  }

  func testEmptyContextReturnsZeroTotalsForToday() throws {
    let context = try makeContext()

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.dayStart, dayStart)
    XCTAssertEqual(snapshot.entryCount, 0)
    XCTAssertEqual(snapshot.calories, 0)
    XCTAssertEqual(snapshot.proteinGrams, 0)
    XCTAssertEqual(snapshot.carbohydrateGrams, 0)
    XCTAssertEqual(snapshot.fatGrams, 0)
    XCTAssertTrue(snapshot.isEmpty)
  }

  func testSumsMacrosForEntriesConsumedToday() throws {
    let context = try makeContext()
    try insert(
      in: context,
      consumedAt: referenceNow,
      nutrients: [
        NutrientAmount(key: .energy, amount: 200),
        NutrientAmount(key: .protein, amount: 10),
        NutrientAmount(key: .carbohydrate, amount: 20),
        NutrientAmount(key: .totalFat, amount: 8),
      ]
    )
    try insert(
      in: context,
      consumedAt: referenceNow.addingTimeInterval(3_600),
      nutrients: [
        NutrientAmount(key: .energy, amount: 150),
        NutrientAmount(key: .protein, amount: 5),
        NutrientAmount(key: .carbohydrate, amount: 30),
        NutrientAmount(key: .totalFat, amount: 2),
      ]
    )

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.entryCount, 2)
    XCTAssertEqual(snapshot.calories, 350)
    XCTAssertEqual(snapshot.proteinGrams, 15)
    XCTAssertEqual(snapshot.carbohydrateGrams, 50)
    XCTAssertEqual(snapshot.fatGrams, 10)
    XCTAssertFalse(snapshot.isEmpty)
  }

  func testExcludesEntriesFromOtherDays() throws {
    let context = try makeContext()
    try insert(
      in: context,
      consumedAt: referenceNow,
      nutrients: [NutrientAmount(key: .energy, amount: 100)]
    )
    try insert(
      in: context,
      consumedAt: dayStart.addingTimeInterval(-60),
      nutrients: [
        NutrientAmount(key: .energy, amount: 999),
        NutrientAmount(key: .protein, amount: 99),
      ]
    )
    try insert(
      in: context,
      consumedAt: dayEnd,
      nutrients: [
        NutrientAmount(key: .energy, amount: 888),
        NutrientAmount(key: .protein, amount: 88),
      ]
    )
    try insert(
      in: context,
      consumedAt: dayEnd.addingTimeInterval(3_600),
      nutrients: [NutrientAmount(key: .energy, amount: 777)]
    )

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.entryCount, 1)
    XCTAssertEqual(snapshot.calories, 100)
    XCTAssertEqual(snapshot.proteinGrams, 0)
  }

  func testIncludesEntryExactlyAtDayStartAndExcludesDayEnd() throws {
    let context = try makeContext()
    try insert(
      in: context,
      consumedAt: dayStart,
      nutrients: [NutrientAmount(key: .energy, amount: 50)]
    )
    try insert(
      in: context,
      consumedAt: dayEnd.addingTimeInterval(-1),
      nutrients: [NutrientAmount(key: .energy, amount: 25)]
    )
    try insert(
      in: context,
      consumedAt: dayEnd,
      nutrients: [NutrientAmount(key: .energy, amount: 400)]
    )

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.entryCount, 2)
    XCTAssertEqual(snapshot.calories, 75)
  }

  func testMissingMacrosCountAsZeroButStillCountEntry() throws {
    let context = try makeContext()
    try insert(
      in: context,
      consumedAt: referenceNow,
      nutrients: [NutrientAmount(key: .energy, amount: 120)]
    )
    try insert(
      in: context,
      consumedAt: referenceNow.addingTimeInterval(120),
      nutrients: []
    )

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.entryCount, 2)
    XCTAssertEqual(snapshot.calories, 120)
    XCTAssertEqual(snapshot.proteinGrams, 0)
    XCTAssertEqual(snapshot.carbohydrateGrams, 0)
    XCTAssertEqual(snapshot.fatGrams, 0)
  }

  func testNegativeNutrientsAreIgnored() throws {
    let context = try makeContext()
    try insert(
      in: context,
      consumedAt: referenceNow,
      nutrients: [
        NutrientAmount(key: .energy, amount: 100),
        NutrientAmount(key: .totalFat, amount: -5),
      ]
    )

    let snapshot = try TodayNutritionSnapshot.load(
      from: context,
      now: referenceNow,
      calendar: utcCalendar
    )

    XCTAssertEqual(snapshot.entryCount, 1)
    XCTAssertEqual(snapshot.calories, 100)
    XCTAssertEqual(snapshot.proteinGrams, 0)
    XCTAssertEqual(snapshot.carbohydrateGrams, 0)
    XCTAssertEqual(snapshot.fatGrams, 0)
  }

  func testNonFiniteNutrientsAreRejectedAtPersistenceBoundary() {
    for amount in [Double.nan, .infinity] {
      XCTAssertThrowsError(
        try FoodLogEntryRecord(
          originalText: "test",
          displayName: "Test food",
          quantityDisplay: "1 portion",
          isApproximate: false,
          source: .manual,
          calculationBasis: .manual,
          nutrients: [NutrientAmount(key: .protein, amount: amount)]
        )
      )
    }
  }

  // MARK: - Pure math (`make` / `zero` / `spokenSummary` — no store I/O)

  func testMakeEmptyEntriesReturnsZeroTotals() {
    let snapshot = TodayNutritionSnapshot.make(
      dayStart: dayStart,
      dayEnd: dayEnd,
      entries: []
    )

    XCTAssertEqual(snapshot.dayStart, dayStart)
    XCTAssertEqual(snapshot.entryCount, 0)
    XCTAssertEqual(snapshot.calories, 0)
    XCTAssertEqual(snapshot.proteinGrams, 0)
    XCTAssertEqual(snapshot.carbohydrateGrams, 0)
    XCTAssertEqual(snapshot.fatGrams, 0)
    XCTAssertTrue(snapshot.isEmpty)
  }

  func testMakeSumsMacrosAcrossMultipleEntries() throws {
    let first = try FoodLogEntryRecord(
      consumedAt: referenceNow,
      originalText: "breakfast",
      displayName: "Oats",
      quantityDisplay: "1 bowl",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [
        NutrientAmount(key: .energy, amount: 200),
        NutrientAmount(key: .protein, amount: 10),
        NutrientAmount(key: .carbohydrate, amount: 20),
        NutrientAmount(key: .totalFat, amount: 8),
      ]
    )
    let second = try FoodLogEntryRecord(
      consumedAt: referenceNow.addingTimeInterval(3_600),
      originalText: "lunch",
      displayName: "Salad",
      quantityDisplay: "1 plate",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [
        NutrientAmount(key: .energy, amount: 150),
        NutrientAmount(key: .protein, amount: 5),
        NutrientAmount(key: .carbohydrate, amount: 30),
        NutrientAmount(key: .totalFat, amount: 2),
      ]
    )

    let snapshot = TodayNutritionSnapshot.make(
      dayStart: dayStart,
      dayEnd: dayEnd,
      entries: [first, second]
    )

    XCTAssertEqual(snapshot.entryCount, 2)
    XCTAssertEqual(snapshot.calories, 350)
    XCTAssertEqual(snapshot.proteinGrams, 15)
    XCTAssertEqual(snapshot.carbohydrateGrams, 50)
    XCTAssertEqual(snapshot.fatGrams, 10)
    XCTAssertFalse(snapshot.isEmpty)
  }

  func testMakeIgnoresEntriesOutsideProvidedDayBounds() throws {
    let inRange = try FoodLogEntryRecord(
      consumedAt: referenceNow,
      originalText: "in",
      displayName: "In range",
      quantityDisplay: "1",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 40)]
    )
    let outOfRange = try FoodLogEntryRecord(
      consumedAt: dayStart.addingTimeInterval(-1),
      originalText: "out",
      displayName: "Out of range",
      quantityDisplay: "1",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: [NutrientAmount(key: .energy, amount: 900)]
    )

    let snapshot = TodayNutritionSnapshot.make(
      dayStart: dayStart,
      dayEnd: dayEnd,
      entries: [inRange, outOfRange]
    )

    XCTAssertEqual(snapshot.entryCount, 1)
    XCTAssertEqual(snapshot.calories, 40)
  }

  func testZeroFactory() {
    let snapshot = TodayNutritionSnapshot.zero(dayStart: dayStart)
    XCTAssertEqual(snapshot.dayStart, dayStart)
    XCTAssertTrue(snapshot.isEmpty)
    XCTAssertEqual(snapshot.calories, 0)
  }

  func testSpokenSummaryForEmptyDay() {
    let snapshot = TodayNutritionSnapshot.zero(dayStart: dayStart)
    XCTAssertEqual(snapshot.spokenSummary, "You haven't logged any meals today.")
  }

  func testSpokenSummaryFormatForMultipleEntries() {
    let snapshot = TodayNutritionSnapshot(
      dayStart: dayStart,
      entryCount: 2,
      calories: 350,
      proteinGrams: 15,
      carbohydrateGrams: 50,
      fatGrams: 10
    )
    XCTAssertEqual(
      snapshot.spokenSummary,
      "Today you've logged 2 entries: 350 calories, 15 grams protein, 50 grams carbs, 10 grams fat."
    )
  }

  func testSpokenSummaryUsesSingularEntryWord() {
    let snapshot = TodayNutritionSnapshot(
      dayStart: dayStart,
      entryCount: 1,
      calories: 100,
      proteinGrams: 8.5,
      carbohydrateGrams: 12,
      fatGrams: 3
    )
    let spoken = snapshot.spokenSummary
    XCTAssertTrue(spoken.hasPrefix("Today you've logged 1 entry:"), spoken)
    XCTAssertFalse(spoken.contains("entries"), spoken)
    XCTAssertTrue(spoken.contains("calories"), spoken)
    XCTAssertTrue(spoken.contains("grams protein"), spoken)
    XCTAssertTrue(spoken.contains("grams carbs"), spoken)
    XCTAssertTrue(spoken.contains("grams fat"), spoken)
  }

  func testSnapshotSourceLoadsFromBoundContainerOnly() throws {
    TodayNutritionSnapshotSource.unbind()
    XCTAssertNil(try TodayNutritionSnapshotSource.loadTodayIfAvailable(
      now: referenceNow,
      calendar: utcCalendar
    ))

    let container = try ModelContainer(
      for: FoodLogEntryRecord.self,
      HealthDeletionTombstone.self,
      RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    try insert(
      in: context,
      consumedAt: referenceNow,
      nutrients: [NutrientAmount(key: .energy, amount: 220)]
    )

    TodayNutritionSnapshotSource.bind(to: container)
    defer { TodayNutritionSnapshotSource.unbind() }

    let snapshot = try XCTUnwrap(
      try TodayNutritionSnapshotSource.loadTodayIfAvailable(
        now: referenceNow,
        calendar: utcCalendar
      )
    )
    XCTAssertEqual(snapshot.entryCount, 1)
    XCTAssertEqual(snapshot.calories, 220)
  }

  // MARK: - Helpers

  private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
      for: FoodLogEntryRecord.self,
      HealthDeletionTombstone.self,
      RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    retainedContainers.append(container)
    return container.mainContext
  }

  private func insert(
    in context: ModelContext,
    consumedAt: Date,
    nutrients: [NutrientAmount]
  ) throws {
    let entry = try FoodLogEntryRecord(
      consumedAt: consumedAt,
      originalText: "test",
      displayName: "Test food",
      quantityDisplay: "1 portion",
      isApproximate: false,
      source: .manual,
      calculationBasis: .manual,
      nutrients: nutrients
    )
    context.insert(entry)
    try context.save()
  }
}
