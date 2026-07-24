import Foundation
import XCTest

@testable import JustLogIt

/// Unit tests for the typed Siri / in-app food-log handoff seam on `AppNavigation`.
@MainActor
final class AppNavigationFoodLogTests: XCTestCase {
  private var navigation: AppNavigation!
  /// Snapshot of process-wide singleton state so shared-touching tests cannot leak.
  private var sharedSnapshot: SharedNavigationSnapshot?

  override func setUp() async throws {
    try await super.setUp()
    navigation = AppNavigation()
  }

  override func tearDown() async throws {
    if let sharedSnapshot {
      // Restore tab/selection from before the shared-touching test; pending handoffs
      // are always cleared below so suites never leak across cases.
      let shared = AppNavigation.shared
      shared.tab = sharedSnapshot.tab
      shared.selectedEntryID = sharedSnapshot.selectedEntryID
      shared.selectedFoodID = sharedSnapshot.selectedFoodID
      self.sharedSnapshot = nil
    }
    resetSharedNavigationPendingState()
    navigation = nil
    try await super.tearDown()
  }

  // MARK: - logAgain (in-app)

  func testLogAgainSetsPendingFoodLogWithInAppSourceAndSwitchesToLogTab() throws {
    navigation.tab = .entries
    navigation.selectedEntryID = UUID()

    navigation.logAgain("Eggs, scrambled")

    XCTAssertEqual(navigation.tab, .log)
    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "Eggs, scrambled")
    XCTAssertNil(pending.consumedAt)
    XCTAssertEqual(pending.source, .inApp)
  }

  func testLogAgainTrimsDescriptionWhitespace() {
    navigation.logAgain("  turkey sandwich  ")

    XCTAssertEqual(navigation.pendingFoodLog?.description, "turkey sandwich")
    XCTAssertEqual(navigation.pendingFoodLog?.source, .inApp)
  }

  // MARK: - beginPendingFoodLog (Siri / shortcut)

  func testBeginPendingFoodLogWithSiriSourcePreservesConsumedAt() throws {
    navigation.tab = .settings
    let eatenAt = Date(timeIntervalSince1970: 1_700_000_000)

    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: "two scrambled eggs",
        consumedAt: eatenAt,
        source: .siri
      )
    )

    XCTAssertEqual(navigation.tab, .log)
    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "two scrambled eggs")
    XCTAssertEqual(pending.consumedAt, eatenAt)
    XCTAssertEqual(pending.source, .siri)
  }

  func testBeginPendingFoodLogWithShortcutSource() throws {
    let eatenAt = Date(timeIntervalSince1970: 1_710_000_000)

    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: "oatmeal with blueberries",
        consumedAt: eatenAt,
        source: .shortcut
      )
    )

    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "oatmeal with blueberries")
    XCTAssertEqual(pending.consumedAt, eatenAt)
    XCTAssertEqual(pending.source, .shortcut)
    XCTAssertEqual(navigation.tab, .log)
  }

  // MARK: - take / consume

  func testTakePendingFoodLogReturnsAndClearsPending() throws {
    let eatenAt = Date(timeIntervalSince1970: 1_720_000_000)
    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: "greek yogurt",
        consumedAt: eatenAt,
        source: .siri
      )
    )

    let taken = try XCTUnwrap(navigation.takePendingFoodLog())
    XCTAssertEqual(taken.description, "greek yogurt")
    XCTAssertEqual(taken.consumedAt, eatenAt)
    XCTAssertEqual(taken.source, .siri)
    XCTAssertNil(navigation.pendingFoodLog)
    XCTAssertNil(navigation.takePendingFoodLog())
  }

  // MARK: - empty / whitespace rejection

  func testEmptyAndWhitespaceDescriptionsAreRejected() {
    navigation.tab = .entries
    let existing = PendingFoodLog(
      description: "keep me",
      consumedAt: nil,
      source: .inApp
    )
    navigation.pendingFoodLog = existing
    navigation.tab = .entries

    navigation.logAgain("")
    navigation.logAgain("   \n\t  ")
    navigation.beginPendingFoodLog(
      PendingFoodLog(description: "", consumedAt: Date(), source: .siri)
    )
    navigation.beginPendingFoodLog(
      PendingFoodLog(description: " \t", consumedAt: Date(), source: .shortcut)
    )

    XCTAssertEqual(navigation.pendingFoodLog, existing)
    XCTAssertEqual(navigation.tab, .entries)
  }

  // MARK: - openEntry / openFood

  func testOpenEntryAndOpenFoodStillWorkAndClearTheOtherSelection() {
    let foodID = UUID()
    let entryID = UUID()

    navigation.openFood(foodID)
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.selectedFoodID, foodID)
    XCTAssertNil(navigation.selectedEntryID)

    navigation.openEntry(entryID)
    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.selectedEntryID, entryID)
    XCTAssertNil(navigation.selectedFoodID)

    navigation.openFood(foodID)
    XCTAssertEqual(navigation.selectedFoodID, foodID)
    XCTAssertNil(navigation.selectedEntryID)
  }

  func testPendingFoodLogDoesNotClearEntryOrFoodSelectionOnItsOwn() {
    let foodID = UUID()
    navigation.openFood(foodID)

    navigation.logAgain("banana")

    XCTAssertEqual(navigation.tab, .log)
    XCTAssertEqual(navigation.selectedFoodID, foodID)
    XCTAssertNotNil(navigation.pendingFoodLog)
  }

  func testBeginPendingFoodLogReplacesExistingPending() throws {
    navigation.logAgain("first")
    let later = Date(timeIntervalSince1970: 1_730_000_000)

    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: "second",
        consumedAt: later,
        source: .shortcut
      )
    )

    let pending = try XCTUnwrap(navigation.pendingFoodLog)
    XCTAssertEqual(pending.description, "second")
    XCTAssertEqual(pending.consumedAt, later)
    XCTAssertEqual(pending.source, .shortcut)
  }

  func testPendingFoodLogEquality() {
    let date = Date(timeIntervalSince1970: 42)
    let a = PendingFoodLog(description: "eggs", consumedAt: date, source: .siri)
    let b = PendingFoodLog(description: "eggs", consumedAt: date, source: .siri)
    let c = PendingFoodLog(description: "eggs", consumedAt: date, source: .inApp)

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  func testShowEntriesSelectsEntriesTab() {
    navigation.tab = .log
    navigation.showEntries()
    XCTAssertEqual(navigation.tab, .entries)
  }

  // MARK: - pending search (Siri / system.searchInApp)

  func testBeginPendingSearchTrimsAndSelectsEntriesTab() {
    navigation.tab = .log

    navigation.beginPendingSearch("  breakfast  ")

    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertEqual(navigation.pendingSearchQuery, "breakfast")
  }

  func testBeginPendingSearchWithWhitespaceOnlyStillSelectsEntriesWithoutQuery() {
    navigation.tab = .settings
    navigation.pendingSearchQuery = "keep?"

    navigation.beginPendingSearch("  \n\t  ")

    XCTAssertEqual(navigation.tab, .entries)
    XCTAssertNil(navigation.pendingSearchQuery)
  }

  func testTakePendingSearchQueryReturnsAndClears() {
    navigation.beginPendingSearch("eggs")

    XCTAssertEqual(navigation.takePendingSearchQuery(), "eggs")
    XCTAssertNil(navigation.pendingSearchQuery)
    XCTAssertNil(navigation.takePendingSearchQuery())
  }

  func testBeginPendingSearchReplacesExistingQuery() {
    navigation.beginPendingSearch("first")
    navigation.beginPendingSearch("second")

    XCTAssertEqual(navigation.pendingSearchQuery, "second")
    XCTAssertEqual(navigation.tab, .entries)
  }

  func testPendingFoodLogAndSearchAreIndependent() throws {
    navigation.beginPendingFoodLog(
      PendingFoodLog(description: "eggs", consumedAt: nil, source: .siri)
    )
    navigation.beginPendingSearch("yogurt")

    XCTAssertEqual(navigation.pendingFoodLog?.description, "eggs")
    XCTAssertEqual(navigation.pendingSearchQuery, "yogurt")
    // Search wins the tab selection (entries).
    XCTAssertEqual(navigation.tab, .entries)

    navigation.logAgain("toast")
    XCTAssertEqual(navigation.tab, .log)
    XCTAssertEqual(navigation.pendingFoodLog?.description, "toast")
    XCTAssertEqual(navigation.pendingSearchQuery, "yogurt")
  }

  // MARK: - shared singleton isolation

  func testSharedSingletonPendingStateCanBeTakenAndClearedWithoutLeaking() throws {
    sharedSnapshot = SharedNavigationSnapshot.capture()
    let shared = AppNavigation.shared

    shared.beginPendingFoodLog(
      PendingFoodLog(description: "shared eggs", consumedAt: nil, source: .shortcut)
    )
    shared.beginPendingSearch("shared search")

    XCTAssertEqual(shared.pendingFoodLog?.description, "shared eggs")
    XCTAssertEqual(shared.pendingSearchQuery, "shared search")

    XCTAssertEqual(shared.takePendingFoodLog()?.description, "shared eggs")
    XCTAssertEqual(shared.takePendingSearchQuery(), "shared search")
    XCTAssertNil(shared.pendingFoodLog)
    XCTAssertNil(shared.pendingSearchQuery)
  }
}

// MARK: - Shared singleton helpers

@MainActor
private struct SharedNavigationSnapshot {
  let tab: AppNavigation.Tab
  let selectedEntryID: UUID?
  let selectedFoodID: UUID?
  let pendingFoodLog: PendingFoodLog?
  let pendingSearchQuery: String?

  static func capture() -> SharedNavigationSnapshot {
    let shared = AppNavigation.shared
    return SharedNavigationSnapshot(
      tab: shared.tab,
      selectedEntryID: shared.selectedEntryID,
      selectedFoodID: shared.selectedFoodID,
      pendingFoodLog: shared.pendingFoodLog,
      pendingSearchQuery: shared.pendingSearchQuery
    )
  }

  func restore() {
    let shared = AppNavigation.shared
    shared.tab = tab
    shared.selectedEntryID = selectedEntryID
    shared.selectedFoodID = selectedFoodID
    shared.pendingFoodLog = pendingFoodLog
    shared.pendingSearchQuery = pendingSearchQuery
  }
}

@MainActor
private func resetSharedNavigationPendingState() {
  let shared = AppNavigation.shared
  _ = shared.takePendingFoodLog()
  _ = shared.takePendingSearchQuery()
}
