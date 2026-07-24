import AppIntents
import Foundation

/// Opens the Entries tab with a search query (system in-app search schema).
struct SearchFoodLogsIntent: ShowInAppSearchResultsIntent {
  static let title: LocalizedStringResource = "Search Food Logs"
  static let description = IntentDescription(
    "Opens JustLogIt and searches your food log entries."
  )
  static var searchScopes: [StringSearchScope] { [.general] }
  static let supportedModes: IntentModes = [.foreground(.deferred)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  static var parameterSummary: some ParameterSummary {
    Summary("Search food logs for \(\.$criteria)")
  }

  @Parameter(
    title: "Search",
    description: "Food name or keywords to find in your log.",
    requestValueDialog: IntentDialog("What should I search for in your food log?")
  )
  var criteria: StringSearchCriteria

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
    let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
    coordinator.beginSearch(query: term)
    if term.isEmpty {
      return .result(
        dialog: IntentDialog("Opening your food logs in JustLogIt.")
      )
    }
    return .result(
      dialog: IntentDialog("Searching JustLogIt for \(term).")
    )
  }
}
