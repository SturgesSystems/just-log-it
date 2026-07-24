import AppIntents
import Foundation

/// Registers App Intent dependencies. Safe to call more than once.
///
/// Does not open SwiftData or touch the model container — only navigation handoff
/// types used by foreground Siri intents.
@MainActor
func registerJustLogItAppDependencies() {
  // Capture on the main actor, then hand the Sendable instance to the factory.
  // Reading `.shared` inside AppDependencyManager's Sendable closure is illegal.
  let coordinator = SiriFoodLogCoordinator.shared
  AppDependencyManager.shared.add {
    coordinator
  }
}
