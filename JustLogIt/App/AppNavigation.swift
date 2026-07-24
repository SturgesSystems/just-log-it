import Foundation
import SwiftUI

/// Cross-tab navigation for opening a saved entry or recognized food from the log completion card,
/// and for Siri / Shortcut / in-app pending log and search handoffs.
@MainActor
final class AppNavigation: ObservableObject {
  static let shared = AppNavigation()

  enum Tab: Hashable {
    case log
    case entries
    case settings
  }

  @Published var tab: Tab = .log
  @Published var selectedEntryID: UUID?
  @Published var selectedFoodID: UUID?
  /// Single source of truth for a pending reviewed food-log handoff.
  @Published var pendingFoodLog: PendingFoodLog?
  /// Pending Entries search query from Siri / in-app search intents.
  @Published var pendingSearchQuery: String?

  func openEntry(_ id: UUID) {
    selectedEntryID = id
    selectedFoodID = nil
    tab = .entries
  }

  func openFood(_ id: UUID) {
    selectedFoodID = id
    selectedEntryID = nil
    tab = .entries
  }

  /// Queues a pending food log and selects the Log tab. Ignores empty descriptions.
  func beginPendingFoodLog(_ pending: PendingFoodLog) {
    let trimmed = pending.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    pendingFoodLog = PendingFoodLog(
      description: trimmed,
      consumedAt: pending.consumedAt,
      source: pending.source
    )
    tab = .log
  }

  /// Takes and clears the pending food log, if any.
  func takePendingFoodLog() -> PendingFoodLog? {
    let pending = pendingFoodLog
    pendingFoodLog = nil
    return pending
  }

  func logAgain(_ text: String) {
    beginPendingFoodLog(
      PendingFoodLog(description: text, consumedAt: nil, source: .inApp)
    )
  }

  /// Selects Entries and optionally seeds the search field.
  func beginPendingSearch(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      pendingSearchQuery = nil
    } else {
      pendingSearchQuery = trimmed
    }
    tab = .entries
  }

  /// Takes and clears the pending search query, if any.
  func takePendingSearchQuery() -> String? {
    let query = pendingSearchQuery
    pendingSearchQuery = nil
    return query
  }

  /// Selects the Entries tab without a search query.
  func showEntries() {
    tab = .entries
  }
}
