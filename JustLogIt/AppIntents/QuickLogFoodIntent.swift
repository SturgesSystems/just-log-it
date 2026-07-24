import AppIntents
import Foundation

// MARK: - Spike C stub (design only)
//
// Full in-Siri confirm-and-save requires a shared `FoodLoggingWorkflow`
// (Spike B) and confirmation UI (Spike C). Until those land, this intent
// deliberately does **not** resolve USDA identity, compute nutrition, or
// persist anything. It always continues on the same foreground path as
// `StartFoodLogIntent` / `SiriFoodLogCoordinator.beginLog`.
//
// `isDiscoverable` is false so Siri / Spotlight do not surface a second
// "log food" action that looks ready for silent completion. Do **not**
// register this intent in `JustLogItShortcuts` until Spike C is real.

/// Stub for a future hands-free quick log that would confirm nutrition in Siri.
///
/// Current behavior: open JustLogIt with the spoken food text for the ordinary
/// reviewed Log flow. Never saves from this intent.
struct QuickLogFoodIntent: AppIntent {
  static let title: LocalizedStringResource = "Quick Log Food"
  static let description = IntentDescription(
    "Opens JustLogIt to review a food log. Full in-Siri confirmation is not available yet."
  )
  /// Hidden until FoodLoggingWorkflow + confirmation UI ship; avoids competing with Start Food Log.
  static let isDiscoverable = false
  static let supportedModes: IntentModes = [.foreground(.deferred)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @Parameter(title: "Food", requestValueDialog: IntentDialog("What food would you like to log?"))
  var foodDescription: String

  @Parameter(title: "When Eaten")
  var consumedAt: Date?

  @Dependency
  private var coordinator: SiriFoodLogCoordinator

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    // STUB: silent / in-Siri save path not implemented.
    // Future Spike C: call FoodLoggingWorkflow → readyForConfirmation → requestConfirmation
    // → save once; any other outcome continues in-app with captured input preserved.
    let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw $foodDescription.needsValueError(
        IntentDialog("What food would you like to log?")
      )
    }

    coordinator.beginLog(
      description: trimmed,
      consumedAt: consumedAt,
      source: .siri
    )
    return .result(
      dialog: IntentDialog(
        "I'll open JustLogIt so you can review nutrition before saving."
      )
    )
  }
}
