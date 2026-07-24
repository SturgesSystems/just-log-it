# iOS 27 App Intents cheat sheet (JustLogIt)

Practical notes for agents shipping Siri / Shortcuts against the iOS 27 SDK. Prefer the live types under `JustLogIt/AppIntents/` over older spike snippets.

## Rules of the road

| Topic | JustLogIt rule |
| --- | --- |
| Modes | Dynamic foreground for reviewed logging; background-first for read-only summaries |
| Process | Main app only (`allowedExecutionTargets = .main`) |
| Schemas | **No nutrition schema.** Do **not** fake food logs as notes/journal (no `.notes.createNote`) |
| Search | `.system.searchInApp` **does** exist — use `ShowInAppSearchResultsIntent` |
| Persistence | Intents queue handoff only; UI confirmation still owns SwiftData + HealthKit |
| Bootstrap | Never open the model container from `JustLogItApp.init` or dependency factories |

Recheck beta symbols against the installed Xcode SDK before inventing new APIs.

## Modes & targets

```swift
static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

static let allowedExecutionTargets: IntentExecutionTargets = .main
static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
```

- **`.background + .foreground(.dynamic)`** — Siri resolves required parameters first; `perform()` explicitly calls `continueInForeground` only when UI review is needed. Correct for review-first logging and background read-only summaries.
- **`.main`** — required because handoff touches `AppNavigation`, SwiftUI, Foundation Models path, cache, and (later) SwiftData. Do not assume extension/widget isolation.
- Avoid background / long-running intents for food log create until a real shared workflow + confirmation path exists.

## Phrase grammar (App Shortcuts)

Donated phrases **must** include `\(.applicationName)`. In the installed Xcode 27 beta,
the metadata exporter accepts interpolated intent parameters only when their value is an
`AppEntity` or `AppEnum`. A free-form `String` slot can compile in Swift but halts metadata
export. Use fixed donated phrases and let the required `@Parameter` dialog collect free-form text.

```swift
// ✅ Correct for a required free-form String parameter
"Log food in \(.applicationName)"
"Add food to \(.applicationName)"
"Start a food log in \(.applicationName)"

// ❌ Metadata export failure / fragile
"Log \(\.$foodDescription) in \(.applicationName)" // String is not AppEntity/AppEnum
"Log food in JustLogIt"                            // hard-coded name; skip app token
"Log food"                                         // no applicationName — unreliable
```

Semantic matching tolerates nearby wording; still register several natural phrases. Until a nutrition schema exists, plan on the person saying the app name for reliable zero-setup routing.

`ParameterSummary` uses the same `\(\.$…)` form:

```swift
static var parameterSummary: some ParameterSummary {
  Summary("Log \(\.$foodDescription)") {
    \.$consumedAt
  }
}
```

## Schemas: what exists / what does not

| Schema / surface | Use for JustLogIt? |
| --- | --- |
| Custom `AppIntent` + `AppShortcutsProvider` | **Yes** — Start Food Log |
| `.system.searchInApp` via `ShowInAppSearchResultsIntent` | **Yes** — search existing entries |
| Nutrition / food-journal create schema | **No** — not in the catalog |
| `.notes.createNote` or other journal-ish domains | **No** — do not misuse as food log |
| Future health/nutrition schema | Upgrade path only; re-check SDK |

Search intent shape (shipping idea):

```swift
struct SearchFoodLogsIntent: ShowInAppSearchResultsIntent {
  static var searchScopes: [StringSearchScope] = [.general]
  static let supportedModes: IntentModes = [.foreground(.deferred)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main

  @Parameter(title: "Search")
  var criteria: StringSearchCriteria
  // perform → coordinator.beginSearch(query: criteria.term)
}
```

## Sendable / dependency pitfalls

App Intents resolve `@Dependency` across process boundaries. Treat this as the sharp edge of the spike.

1. **Register early, register once** — `registerJustLogItAppDependencies()` (or equivalent) from app launch. Safe to call more than once; do not open SwiftData there.
2. **Prefer value / instance registration** over `@Sendable` factory closures:

   ```swift
   // ✅ Non-escaping instance — avoids capturing MainActor-isolated `shared` into a Sendable factory
   AppDependencyManager.shared.add(dependency: SiriFoodLogCoordinator.shared)

   // ⚠️ Factory form often forces Sendable captures of MainActor state → compile or runtime pain
   // AppDependencyManager.shared.add { SiriFoodLogCoordinator.shared }
   ```

3. **Coordinator facade** — intents depend on a thin `SiriFoodLogCoordinator` (handoff only), not `LogViewModel` or repositories. Shipping type is `@MainActor` + `@unchecked Sendable` as a pragmatic compromise; prefer a small `Sendable` protocol if you redesign.
4. **`perform()` is `@MainActor`** when touching navigation / UI seams.
5. **No dual containers** — dependency must not create a second SwiftData stack while the app bootstrap is still lazy.
6. **Tests** — inject a private navigation into the coordinator; do not race `AppNavigation.shared` under parallel test runs without isolation.

## Spike A paste-ready sketch (`StartFoodLogIntent`)

Matches JustLogIt’s product rule: capture phrase (+ optional time) → pending handoff → Log tab → **no persistence in the intent**.

```swift
import AppIntents
import Foundation

struct StartFoodLogIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Food Log"
  static let description = IntentDescription(
    "Starts a reviewed food log in JustLogIt. You’ll confirm nutrition before anything is saved."
  )
  static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @Parameter(
    title: "Food",
    description: "What you ate, in your own words",
    requestValueDialog: IntentDialog("What did you eat?")
  )
  var foodDescription: String

  @Parameter(title: "When Eaten", kind: .dateTime)
  var consumedAt: Date?

  @Dependency private var siriCoordinator: SiriFoodLogCoordinator

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$foodDescription)") {
      \.$consumedAt
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw $foodDescription.needsValueError(IntentDialog("What did you eat?"))
    }

    siriCoordinator.beginLog(
      description: trimmed,
      consumedAt: consumedAt,
      source: .siri
    )
    if systemContext.currentMode.canContinueInForeground {
      try await continueInForeground(
        IntentDialog("Opening JustLogIt to review nutrition before saving."),
        alwaysConfirm: false
      )
    }
    return .result(
      dialog: IntentDialog("Opening JustLogIt to review that food before saving.")
    )
  }
}

struct JustLogItShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartFoodLogIntent(),
      phrases: [
        "Log food in \(.applicationName)",
        "Add food to \(.applicationName)",
        "Log what I ate in \(.applicationName)",
        "Start a food log in \(.applicationName)",
      ],
      shortTitle: "Log Food",
      systemImageName: "fork.knife.circle"
    )
  }
}
```

## Agent checklist

- [ ] Reviewed logging uses background + dynamic foreground; read-only summaries finish in Siri when data is available; `allowedExecutionTargets` = `.main`
- [ ] Phrases use `\(.applicationName)`; interpolate only `AppEntity` / `AppEnum` parameters
- [ ] No nutrition schema; no journal/notes abuse; search via `.system.searchInApp` / `ShowInAppSearchResultsIntent`
- [ ] `@Dependency` registered without Sendable factory traps; no SwiftData in intent
- [ ] Intent never writes nutrition — only `PendingFoodLog` / search handoff
- [ ] Compile against installed iOS 27 SDK; physical-device Siri UAT before claiming phrase reliability

## Canonical paths

- `JustLogIt/AppIntents/StartFoodLogIntent.swift`
- `JustLogIt/AppIntents/JustLogItShortcuts.swift`
- `JustLogIt/AppIntents/SearchFoodLogsIntent.swift`
- `JustLogIt/AppIntents/SiriFoodLogCoordinator.swift`
- `JustLogIt/AppIntents/AppIntentsRegistration.swift`
- Longer design: `Documentation/SIRI_AI_INTEGRATION_SPIKE.md`
