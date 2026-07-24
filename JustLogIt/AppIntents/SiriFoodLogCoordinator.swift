import Foundation

/// App Intents–facing facade over `AppNavigation` pending handoff state.
///
/// Navigation remains the single source of truth for pending logs and search;
/// this type exists so intents can resolve a Sendable dependency without opening
/// SwiftData or racing bootstrap.
@MainActor
final class SiriFoodLogCoordinator: ObservableObject, @unchecked Sendable {
  static let shared = SiriFoodLogCoordinator()

  private weak var navigation: AppNavigation?

  /// Production `shared` defaults to `AppNavigation.shared`.
  /// Tests inject a private navigation, or pass `nil` to simulate no attachment.
  init(navigation: AppNavigation? = AppNavigation.shared) {
    self.navigation = navigation
  }

  /// Wires (or re-wires) the live navigation seam after the UI hierarchy exists.
  func attach(_ navigation: AppNavigation) {
    self.navigation = navigation
  }

  /// Queues a reviewed log on the Log tab.
  /// - Returns: `false` when no navigation is attached or the description is empty.
  @discardableResult
  func beginLog(
    description: String,
    consumedAt: Date?,
    source: PendingFoodLog.Source = .siri
  ) -> Bool {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let navigation else { return false }
    navigation.beginPendingFoodLog(
      PendingFoodLog(
        description: trimmed,
        consumedAt: consumedAt,
        source: source
      )
    )
    return true
  }

  /// Takes and clears the pending food log, if any.
  func takePending() -> PendingFoodLog? {
    navigation?.takePendingFoodLog()
  }

  /// Opens Entries with an optional search query.
  /// - Returns: `false` when no navigation is attached.
  @discardableResult
  func beginSearch(query: String) -> Bool {
    guard let navigation else { return false }
    navigation.beginPendingSearch(query)
    return true
  }

  /// Opens the Entries tab (e.g. today’s nutrition summary handoff).
  /// Does not open SwiftData or compute nutrition in the intent process.
  /// - Returns: `false` when no navigation is attached.
  @discardableResult
  func showEntries() -> Bool {
    guard let navigation else { return false }
    navigation.showEntries()
    return true
  }
}
