import AppIntents

/// Shortcuts/Siri entry point for today’s nutrition overview.
///
/// Background-first, main-app only:
/// 1. Speaks today’s totals in Siri when the **already-bootstrapped** store is bound
///    (`TodayNutritionSnapshotSource`) — never opens a second `ModelContainer`.
/// 2. Otherwise asks JustLogIt to open Entries so the person still gets a useful result.
struct GetTodayNutritionSummaryIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Today's Nutrition Summary"
  static let description = IntentDescription(
    "Reports today's calories and macros in Siri when available, otherwise opens today's entries in JustLogIt."
  )
  static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  static var parameterSummary: some ParameterSummary {
    Summary("Get today's nutrition summary")
  }

  @Dependency
  private var coordinator: SiriFoodLogCoordinator

  init() {}

  /// Test seam for invoking `perform()` outside the App Intents runtime.
  @MainActor
  init(coordinator: SiriFoodLogCoordinator) {
    self.coordinator = coordinator
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    // Read only the process-local container bound after bootstrap — no second store.
    if let snapshot = try? TodayNutritionSnapshotSource.loadTodayIfAvailable() {
      // Complete in Siri/Shortcuts without opening the app when totals are ready.
      return .result(dialog: IntentDialog("\(snapshot.spokenSummary)"))
    }

    // Cold/background execution can arrive before lazy SwiftData bootstrap. In that
    // case, open Entries rather than claiming zero totals or creating another store.
    _ = coordinator.showEntries()
    if systemContext.currentMode.canContinueInForeground {
      try await continueInForeground(
        IntentDialog("Opening today's food entries in JustLogIt."),
        alwaysConfirm: false
      )
    }

    return .result(dialog: IntentDialog("Open JustLogIt to see today's food entries."))
  }
}
