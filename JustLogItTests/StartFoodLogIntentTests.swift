import AppIntents
import Foundation
import SwiftData
import XCTest

@testable import JustLogIt

/// Unit tests for Start Food Log handoff via `SiriFoodLogCoordinator` and `StartFoodLogIntent`.
@MainActor
final class StartFoodLogIntentTests: XCTestCase {
  func testStartFoodLogUsesConversationalDynamicForegroundMode() {
    XCTAssertTrue(StartFoodLogIntent.supportedModes.contains(.background))
    XCTAssertTrue(StartFoodLogIntent.supportedModes.contains(.foreground(.dynamic)))
  }

  // MARK: - Coordinator (isolated navigation)

  func testCoordinatorBeginLogPreservesConsumedAtAndSiriSource() throws {
    let navigation = AppNavigation()
    navigation.tab = .entries
    let coordinator = SiriFoodLogCoordinator(navigation: navigation)
    let eatenAt = Date(timeIntervalSince1970: 1_740_000_000)

    let accepted = coordinator.beginLog(
      description: "  two scrambled eggs  ",
      consumedAt: eatenAt,
      source: .siri
    )

    XCTAssertTrue(accepted)
    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "two scrambled eggs")
    XCTAssertEqual(pending.consumedAt, eatenAt)
    XCTAssertEqual(pending.source, .siri)
    XCTAssertEqual(navigation.tab, .log)
  }

  func testCoordinatorBeginLogRejectsEmptyDescription() {
    let navigation = AppNavigation()
    navigation.tab = .settings
    navigation.pendingFoodLog = PendingFoodLog(
      description: "existing",
      consumedAt: nil,
      source: .inApp
    )
    let coordinator = SiriFoodLogCoordinator(navigation: navigation)

    XCTAssertFalse(
      coordinator.beginLog(
        description: "   ",
        consumedAt: Date(),
        source: .siri
      )
    )

    XCTAssertEqual(navigation.pendingFoodLog?.description, "existing")
    XCTAssertEqual(navigation.tab, .settings)
  }

  func testCoordinatorWithoutNavigationRejectsBeginLog() {
    let coordinator = SiriFoodLogCoordinator(navigation: nil)
    XCTAssertFalse(coordinator.beginLog(description: "apple", consumedAt: nil))
  }

  func testCoordinatorAttachWiresNavigation() {
    let coordinator = SiriFoodLogCoordinator(navigation: nil)
    let navigation = AppNavigation()
    coordinator.attach(navigation)

    XCTAssertTrue(coordinator.beginLog(description: "banana", consumedAt: nil, source: .siri))
    XCTAssertEqual(navigation.pendingFoodLog?.description, "banana")
    XCTAssertEqual(navigation.pendingFoodLog?.source, .siri)
  }

  func testCoordinatorTakePendingClearsNavigation() throws {
    let navigation = AppNavigation()
    let coordinator = SiriFoodLogCoordinator(navigation: navigation)
    coordinator.beginLog(
      description: "apple",
      consumedAt: nil,
      source: .shortcut
    )

    let taken = try XCTUnwrap(coordinator.takePending())
    XCTAssertEqual(taken.description, "apple")
    XCTAssertEqual(taken.source, .shortcut)
    XCTAssertNil(navigation.pendingFoodLog)
  }

  // MARK: - StartFoodLogIntent.perform (injected dependency)

  func testPerformInstallsPendingFoodLogFromSiriSource() async throws {
    let eatenAt = Date(timeIntervalSince1970: 1_750_000_000)
    let navigation = AppNavigation()
    navigation.tab = .entries

    let intent = StartFoodLogIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    intent.foodDescription = "greek yogurt"
    intent.consumedAt = eatenAt

    _ = try await intent.perform()

    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "greek yogurt")
    XCTAssertEqual(pending.consumedAt, eatenAt)
    XCTAssertEqual(pending.source, .siri)
    XCTAssertEqual(navigation.tab, .log)
  }

  func testPerformWithEmptyDescriptionThrowsAndDoesNotInstallPending() async {
    let navigation = AppNavigation()
    navigation.tab = .settings
    let intent = StartFoodLogIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    intent.foodDescription = "   "

    do {
      _ = try await intent.perform()
      XCTFail("Expected empty description to throw needsValueError")
    } catch {
      // IntentParameter.needsValueError is the expected path.
    }

    XCTAssertNil(navigation.pendingFoodLog)
    XCTAssertEqual(navigation.tab, .settings)
  }

  func testPerformTrimsFoodDescriptionBeforeHandoff() async throws {
    let navigation = AppNavigation()
    let intent = StartFoodLogIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    intent.foodDescription = "  banana  "

    _ = try await intent.perform()

    XCTAssertEqual(navigation.pendingFoodLog?.description, "banana")
    XCTAssertEqual(navigation.pendingFoodLog?.source, .siri)
  }

  // MARK: - GetTodayNutritionSummaryIntent

  func testTodayNutritionUsesBackgroundFirstDynamicForegroundMode() {
    XCTAssertTrue(GetTodayNutritionSummaryIntent.supportedModes.contains(.background))
    XCTAssertTrue(
      GetTodayNutritionSummaryIntent.supportedModes.contains(.foreground(.dynamic))
    )
  }

  func testGetTodayNutritionSummaryOpensEntriesWithoutBoundStore() async throws {
    let navigation = AppNavigation()
    navigation.tab = .log
    TodayNutritionSnapshotSource.unbind()

    let intent = GetTodayNutritionSummaryIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    _ = try await intent.perform()

    XCTAssertEqual(navigation.tab, .entries)
  }

  func testGetTodayNutritionSummaryStaysInSiriWithBoundEmptyStore() async throws {
    let navigation = AppNavigation()
    navigation.tab = .settings
    let container = try ModelContainer(
      for: FoodLogEntryRecord.self,
      HealthDeletionTombstone.self,
      RecognizedFoodRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    TodayNutritionSnapshotSource.bind(to: container)
    defer { TodayNutritionSnapshotSource.unbind() }

    let intent = GetTodayNutritionSummaryIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    _ = try await intent.perform()

    XCTAssertEqual(
      navigation.tab,
      .settings,
      "A ready snapshot should be spoken without unnecessarily opening JustLogIt"
    )
  }

  // MARK: - SearchFoodLogsIntent

  func testCoordinatorBeginSearchInstallsPendingQueryAndEntriesTab() {
    let navigation = AppNavigation()
    navigation.tab = .log
    let coordinator = SiriFoodLogCoordinator(navigation: navigation)

    XCTAssertTrue(coordinator.beginSearch(query: "  yogurt  "))
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.pendingSearchQuery, "yogurt")
  }

  func testCoordinatorBeginSearchWithoutNavigationReturnsFalse() {
    let coordinator = SiriFoodLogCoordinator(navigation: nil)
    XCTAssertFalse(coordinator.beginSearch(query: "eggs"))
  }

  func testSearchFoodLogsIntentPerformInstallsPendingSearch() async throws {
    let navigation = AppNavigation()
    navigation.tab = .settings

    let intent = SearchFoodLogsIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    intent.criteria = StringSearchCriteria(term: "  oatmeal  ")

    _ = try await intent.perform()

    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.pendingSearchQuery, "oatmeal")
  }

  func testSearchFoodLogsIntentEmptyTermStillOpensEntriesWithoutQuery() async throws {
    let navigation = AppNavigation()
    navigation.tab = .log
    navigation.pendingSearchQuery = "stale"

    let intent = SearchFoodLogsIntent(
      coordinator: SiriFoodLogCoordinator(navigation: navigation)
    )
    intent.criteria = StringSearchCriteria(term: "   ")

    _ = try await intent.perform()

    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertNil(navigation.pendingSearchQuery)
  }
}
