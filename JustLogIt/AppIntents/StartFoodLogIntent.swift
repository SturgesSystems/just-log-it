import AppIntents
import Foundation

/// Conversational handoff: Siri resolves food text (+ optional time) before JustLogIt
/// comes forward, then the app opens the ordinary reviewed Log flow.
/// Does not persist nutrition or open SwiftData.
struct StartFoodLogIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Food Log"
  static let description = IntentDescription(
    "Starts a reviewed food log in JustLogIt. You confirm the food and nutrition before anything is saved."
  )
  // Dynamic foreground keeps required-parameter collection in Siri/Shortcuts. Only
  // after the system has resolved the food description does perform() ask to bring
  // JustLogIt forward for nutrition review.
  static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  static var parameterSummary: some ParameterSummary {
    When(\.$consumedAt, .hasAnyValue) {
      Summary("Log \(\.$foodDescription) eaten \(\.$consumedAt)")
    } otherwise: {
      Summary("Log \(\.$foodDescription)")
    }
  }

  @Parameter(
    title: "Food",
    description: "What you ate, including amount if you know it (for example, two scrambled eggs).",
    inputOptions: String.IntentInputOptions(
      keyboardType: .default,
      capitalizationType: .sentences,
      multiline: false,
      autocorrect: true
    ),
    requestValueDialog: IntentDialog("What did you eat?")
  )
  var foodDescription: String

  @Parameter(
    title: "When Eaten",
    description: "Optional time you ate this food. Leave blank to use now.",
    kind: .dateTime,
    requestValueDialog: IntentDialog("When did you eat that?")
  )
  var consumedAt: Date?

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
    let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw $foodDescription.needsValueError(
        IntentDialog("What did you eat?")
      )
    }

    coordinator.beginLog(
      description: trimmed,
      consumedAt: consumedAt,
      source: .siri
    )
    if systemContext.currentMode.canContinueInForeground {
      try await continueInForeground(
        IntentDialog("I got \(trimmed). Opening JustLogIt to review nutrition before saving."),
        alwaysConfirm: false
      )
    }
    return .result(
      dialog: IntentDialog("I got \(trimmed). Review the nutrition in JustLogIt before saving.")
    )
  }
}
