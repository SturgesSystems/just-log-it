# iOS 27 Siri AI integration spike

**Status:** implementation in progress / partial (Spike A foreground handoff)
**Date:** July 16, 2026 (status refreshed July 18, 2026)
**Scope:** make JustLogIt useful from Siri without weakening its nutrition, privacy, or confirmation rules

## Executive summary

JustLogIt can integrate with Siri now through App Intents. The best first release is not a fully autonomous, hands-free food logger. It is a two-level experience:

1. Ship a dependable **Start Food Log** App Shortcut. Siri captures a phrase such as “Log two scrambled eggs in JustLogIt,” launches JustLogIt with that text, and the existing review flow resolves the USDA match, quantity, and time before saving.
2. Then add a **Quick Log Food** intent that can finish in Siri only when the deterministic pipeline has one safe interpretation. It must show the proposed food, serving, time, calories, and macros and ask for confirmation before persistence. Any ambiguity continues in the app.

This split fits the current product. JustLogIt deliberately separates probabilistic food interpretation from deterministic USDA selection, serving math, persistence, and HealthKit sync. Voice input should enter that same workflow; it should not create a second nutrition pipeline inside an intent.

There is an important iOS 27 limitation: Apple’s new conversational Siri AI actions use system-defined App Schemas so Siri knows the meaning of an action. Apple currently publishes domains for things such as calendar, messages, notes, photos, reminders, and system search, but not a nutrition or food-journal create action. We should not pretend a food log is a note merely to adopt `.notes.createNote`. A custom App Shortcut can still be invoked through Siri using registered phrases and semantic phrase matching, while `.system.searchInApp` is a legitimate schema for opening JustLogIt’s own entry search. We should treat a future nutrition/health schema as an upgrade path, not a launch dependency.

## What iOS 27 provides

App Intents are the integration boundary for Siri, Apple Intelligence, Shortcuts, Spotlight, widgets, and related system experiences. In the iOS 27 generation, Siri can:

- find app content represented as App Entities;
- perform schema-conforming App Intents using natural language;
- use app-provided on-screen entity context; and
- pass transferable entity values between apps.

App Shortcuts combine an App Intent with suggested invocation phrases. The system uses semantic similarity, so phrases close to the donated examples can match without JustLogIt implementing speech recognition or natural-language routing.

The new APIs also let an intent declare background/foreground modes, force execution in the main app process, request confirmation, and opt into extended background execution with progress reporting. The latter is beta and should be unnecessary for the first foreground-assisted flow.

Relevant Apple material:

- [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)
- [Build intelligent Siri experiences with App Schemas (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/240/)
- [App schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains)
- [Accelerating app interactions with App Intents](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents)
- [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
- [Explore advanced App Intents features (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/343/)
- [App Intents Testing](https://developer.apple.com/documentation/appintentstesting)

All iOS 27 APIs and schema availability should be rechecked against the release Xcode SDK. Several referenced Apple pages are still marked beta.

## Proposed user experiences

### Release 1: Start a log with Siri

Example requests:

- “Siri, log two scrambled eggs in JustLogIt.”
- “Siri, add a turkey sandwich to JustLogIt.”
- “Siri, start a food log in JustLogIt.”

`StartFoodLogIntent` accepts a required food description and an optional consumed date. It puts those values into an app-level pending-log request, selects the Log tab, and opens the app. The current logging conversation performs interpretation, clarification, USDA selection, serving resolution, confirmation, persistence, and optional HealthKit sync.

This is valuable even though the final tap occurs in the app: Siri replaces launch, navigation, and initial typing while JustLogIt keeps its existing safety checks. The app already has most of the handoff seam in `AppNavigation.pendingLogText` and `LogView.consumePendingLogText()`.

The current seam should evolve from `String?` to a value type:

```swift
struct PendingFoodLog: Sendable, Equatable {
  let description: String
  let consumedAt: Date?
  let source: Source

  enum Source: Sendable { case siri, shortcut, inApp }
}
```

The intent should use deferred foreground mode and execute in the main app target. It should never open SwiftData synchronously from `JustLogItApp.init`; the app intentionally moved store opening off the first-frame path.

### Release 2: Confirm and save inside Siri

`QuickLogFoodIntent` uses the same input parameters, plus an explicit policy that defaults to `reviewBeforeSaving`. It calls a shared `FoodLoggingWorkflow` and handles one of four typed outcomes:

```text
readyForConfirmation -> show food, amount, time, calories/macros -> confirm -> save
needsClarification    -> ask a bounded question or continue in JustLogIt
needsFoodChoice       -> show a small USDA choice list or continue in JustLogIt
cannotComplete        -> explain the issue and continue in JustLogIt
```

Silent creation is not recommended. Food-name interpretation, USDA identity, and serving conversion can all change the nutrition result materially. The confirmation is also the right place to disclose an approximate result.

Only a narrow request should complete without opening the app. A candidate must have:

- one food, not a composite meal;
- an explicit or safely resolved quantity;
- no outstanding clarification from `ClarificationPolicy`;
- one remembered or uniquely high-confidence USDA match;
- usable USDA details and serving math; and
- an explicit confirmation from the person.

Composite meals, missing amounts, close USDA choices, photo input, manual nutrition, parser/model unavailability, and service failures should move to the app with all captured input preserved.

#### Concrete target flow

For a mature composite-capable implementation, the ordinary case should require one request and one confirmation:

> **Person:** “Siri, log that I ate 2 hard-boiled eggs and 3 slices of bacon in JustLogIt.”
>
> **Siri:** “I found 2 large hard-boiled eggs and 3 regular cooked bacon slices, eaten now. That’s approximately 285 calories. Log it?”
>
> **Person:** “Yes.”
>
> **Siri:** “Done. I logged it in JustLogIt.”

JustLogIt, not Siri, splits the request into components, chooses or recalls USDA identities, resolves the two quantities, calculates component and meal nutrition, and creates the composite record. The confirmation states assumptions that materially affect nutrition. It should not enumerate every USDA implementation detail.

If one assumption is genuinely ambiguous, Siri asks one bounded question, such as “For the bacon, should I use regular cooked bacon or a specific brand?” If the request still needs a USDA choice or more involved correction, the intent continues in JustLogIt with the original text, inferred time, and completed work preserved. Release 1 always takes this foreground continuation path; the fully voice-based composite path belongs after the shared workflow and confirmation work.

### Invocation wording: must the person name JustLogIt?

For the first App Shortcut implementation, plan on **yes** for reliable zero-setup invocation. The registered phrases use Apple’s `\(.applicationName)` token, producing requests such as “Log two eggs in JustLogIt.” Current App Shortcut tooling requires that token in donated phrases; the exact rule still needs to be compiled against the release iOS 27 SDK.

We can provide behavioral hints, but should not promise that they remove the app name:

- Donate matching in-app logging actions so Siri AI can learn patterns and make proactive suggestions. Donations are behavioral cues, not a deterministic default-app setting.
- Register several natural App Shortcut phrases so semantic matching tolerates nearby wording.
- Let a power user create or invoke a personal Shortcut named “Log Food.” They may then say “Run Log Food,” but that requires user setup and invokes the shortcut by name rather than Siri independently choosing JustLogIt.
- If Apple adds a nutrition/food-log App Schema, adopt it. A matching schema would let Siri understand the generic action and use history to disambiguate which app should perform it.

Because today’s schema catalog has no food-log creation contract, a bare “Log that I ate two eggs” is ambiguous across nutrition, notes, reminders, and other apps. Siri AI may learn or suggest JustLogIt in some circumstances, but the product must not claim that generic wording will route reliably. The supported launch phrase should include “in JustLogIt” until real-device iOS 27 testing proves a dependable alternative.

### Release 3: Find and summarize existing entries

Create a lightweight `FoodLogEntryEntity` backed by the stable `FoodLogEntryRecord.id`. Expose only fields that are useful and appropriate outside the app: display name, quantity, consumed time, calories, protein, carbohydrate, and fat. Do not expose HealthKit synchronization diagnostics or raw USDA payload details.

Two actions are useful:

- adopt `.system.searchInApp` for requests such as “Show breakfast entries in JustLogIt”; this opens the app’s Entries experience with a structured filter;
- add custom Shortcut actions such as **Get Today’s Nutrition Summary** and **Find Food Logs** that return structured values to Shortcuts.

Because there is no matching food-log entity schema today, do not promise that Siri AI will answer arbitrary questions across every indexed entry. Validate the actual SDK and device behavior before enabling Spotlight semantic indexing for potentially sensitive nutrition history. Start with explicit in-app search and opt-in summary actions.

## How this fits the current code

The current UI owns too much orchestration for direct intent execution. `LogViewModel` performs parsing, clarification, USDA search, selection, serving resolution, and record construction; `LogView+Composer.confirmLog()` performs SwiftData insertion, recognized-food upsert, save, and HealthKit handoff. An intent must not instantiate a view model and simulate UI stages.

Extract these seams:

```text
Siri / App Shortcut          SwiftUI Log flow
         \                     /
          FoodLoggingWorkflow
          - parse and ground
          - clarification policy
          - search and rank
          - load details
          - resolve serving
          - calculate nutrients
                    |
          FoodLogRepository
          - insert entry
          - upsert recognized food
          - save transaction
                    |
          HealthSyncCoordinator
          - optional, local-first follow-up
```

Suggested types and locations:

```text
JustLogIt/AppIntents/
  JustLogItShortcuts.swift
  StartFoodLogIntent.swift
  QuickLogFoodIntent.swift              (release 2)
  SearchFoodLogsIntent.swift             (release 3)
  FoodLogEntryEntity.swift               (release 3)

JustLogIt/Features/Log/
  FoodLoggingWorkflow.swift
  FoodLoggingOutcome.swift

JustLogIt/Persistence/
  FoodLogRepository.swift
  AppDataStore.swift
```

`FoodLoggingWorkflow` should depend on the existing protocols and deterministic services rather than global state: `FoodDescriptionParsing`, `FoodDataProviding`, `RememberedFoodStoring`, `ClarificationPolicy`, `FoodSearchResultRanker`, `ServingResolutionService`, and `NutritionCalculator`. `LogViewModel` becomes an adapter that renders workflow outcomes as conversation stages. The intents become separate adapters that render the same outcomes as dialogs, choices, confirmations, or a foreground continuation.

Use a single lazy `AppDataStore`/repository dependency registered with `AppDependencyManager` as early as practical. The dependency may await the asynchronous bootstrap container; it must not create a competing container for the same store or undo the existing fast-first-frame design. Register the logging workflow and navigation coordinator too. iOS 27’s `allowedExecutionTargets = .main` is appropriate because the flow uses the app’s Foundation Models, SwiftData, configuration, cache, and navigation state.

## Intent shape for the first spike

Illustrative code only; compile the final declarations against the installed iOS 27 SDK because the APIs are beta:

```swift
import AppIntents

struct StartFoodLogIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Food Log"
  static let description = IntentDescription("Starts a reviewed food log in JustLogIt.")
  static let supportedModes: IntentModes = [.foreground(.deferred)]
  static let allowedExecutionTargets: IntentExecutionTargets = .main

  @Parameter(title: "Food")
  var foodDescription: String

  @Parameter(title: "When Eaten")
  var consumedAt: Date?

  @Dependency private var siriCoordinator: SiriFoodLogCoordinator

  @MainActor
  func perform() async throws -> some IntentResult {
    siriCoordinator.beginLog(description: foodDescription, consumedAt: consumedAt)
    return .result()
  }
}

struct JustLogItShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartFoodLogIntent(),
      phrases: [
        "Log \(.$foodDescription) in \(.applicationName)",
        "Add \(.$foodDescription) to \(.applicationName)",
        "Start a food log in \(.applicationName)"
      ],
      shortTitle: "Log Food",
      systemImageName: "fork.knife.circle"
    )
  }
}
```

If the SDK does not allow the parameter placeholder in App Shortcut phrases in this exact form, keep a generic launch phrase and let Siri resolve the intent’s required `Food` parameter conversationally.

## Persistence, HealthKit, and privacy rules

- Save locally first, using the same SwiftData transaction and `RecognizedFoodRecord.upsert` path as the UI.
- Preserve the existing HealthKit preference. A Siri invocation must not trigger a new HealthKit authorization sheet. After a confirmed local save, `HealthSyncCoordinator.syncIfEnabled` may perform the same non-interactive follow-up used by the app.
- Never write nutrition supplied by Siri or an Apple language model. Siri supplies the person’s words and parameters; JustLogIt’s existing pipeline supplies the USDA identity and deterministic nutrition.
- Keep photo logging in the app for now. Voice-only error recovery for image permissions, image interpretation, multiple foods, and USDA choice is too complex for the first release.
- Do not include a person’s food history in Spotlight by default during the initial spike. Evaluate the visibility, deletion, reindexing, device-lock, and privacy behavior first. If indexing ships, update and delete indexed entities transactionally with local records.
- Continue the existing privacy boundary: food text/search terms may reach the configured USDA proxy; the on-device Foundation Model performs interpretation. Document Siri/Apple Intelligence processing accurately in the privacy disclosure after on-device testing.

## Failure and cancellation behavior

An App Intent is an out-of-process entry point even when its implementation runs in the main app. It can be cancelled, launched while the app is cold, run without a configured USDA provider, or hit the provider’s 12-second search/detail timeouts.

The intent adapter should translate typed failures into short user-facing outcomes and preserve the original request for foreground continuation. It should check cancellation between parse, search, details, and save. Persistence should happen only after confirmation and as one transaction; cancellation before commit creates no entry. HealthKit remains a post-save state machine, so Health failure never rolls back the local log.

The initial foreground-assisted intent should comfortably fit normal runtime limits. If the later background quick-log path regularly approaches 30 seconds because of model inference plus network calls, first reduce work and foreground earlier. Evaluate `LongRunningIntent` only after measurements; it is a beta API requiring progress reporting, not a blanket timeout escape hatch.

## Testing plan

1. Unit-test `FoodLoggingWorkflow` with the existing parser/provider doubles. Cover exact single food, missing quantity, multiple foods, close USDA matches, parser unavailable, network failure, and cancellation.
2. Unit-test `FoodLogRepository` with an in-memory SwiftData container. Verify one transaction creates the entry and recognized-food link, and that duplicate intent execution cannot accidentally double-save after a retry.
3. Add App Intents integration tests using `AppIntentsTesting` in the UI-test bundle. Apple says these tests execute through the same cross-process App Intents stack used by Siri and Shortcuts.
4. Validate the action shape in Shortcuts, then invocation in Spotlight, then full Siri behavior on a physical Apple Intelligence-capable device.
5. Test cold launch, locked device, airplane mode, Foundation Models unavailable, USDA proxy unavailable, cancellation during each stage, declined confirmation, Health sync off/on/denied, VoiceOver, and several locales.
6. Run the existing parser evaluation corpus and logging regression suite. Voice entry must not change in-app interpretation or serving results.

Proposed acceptance cases for release 1:

- “Log two scrambled eggs in JustLogIt” opens the Log tab with the complete phrase and preserves a provided consumed time.
- A cold launch reaches the same state without opening SwiftData synchronously in `App.init`.
- Cancelling before handoff creates no local or Health record.
- Existing UI logging behaves identically.

Proposed acceptance cases for release 2:

- A remembered, unambiguous single food produces a nutrition preview and saves exactly once only after confirmation.
- Any ambiguous, composite, or unresolved request continues in the app with no partial record.
- Siri-supplied content never becomes authoritative nutrition data.

## Delivery plan and estimate

### Spike A — foreground handoff (in progress / partial)

About 2–4 engineering days; **coding largely landed, exit gate open**.

Present in tree (verify under `JustLogIt/AppIntents/` and app navigation):

- `PendingFoodLog` (description, optional `consumedAt`, source);
- `StartFoodLogIntent` + `JustLogItShortcuts` (background + dynamic foreground, main app target; parameters resolve before app review);
- pending seam is `AppNavigation.pendingFoodLog` (not string-only `pendingLogText`);
- dependency registration without opening SwiftData in bootstrap;
- Log tab consumes pending text into the composer (no save before user confirmation);
- unit tests for navigation / intent handoff (`AppNavigationFoodLogTests`, `StartFoodLogIntentTests`).

Still open for Spike A:

- apply supplied `consumedAt` into the review flow (value is carried, not yet applied);
- warm/cold launch, VoiceOver, and full failure-matrix testing;
- physical-device Shortcuts discovery and Siri invocation;
- consolidate any duplicate coordinator / `PendingFoodLog` definitions if both `App/` and `AppIntents/` copies remain.

This proves discovery, invocation, cold launch, navigation, and device eligibility with very little nutrition risk — once device UAT closes the exit gate.

### Spike B — shared headless workflow (**not started**)

About 5–8 engineering days:

- extract workflow outcomes from `LogViewModel` without behavior drift;
- centralize persistence in a repository;
- adapt the existing SwiftUI flow to the shared service;
- add broad regression tests.

This is the main architectural investment and is useful beyond Siri.

### Spike C — Siri confirmation and save (**not started**; blocked on Spike B)

About 4–7 additional engineering days after Spike B:

- implement bounded clarification/choice and confirmation UI;
- add idempotency and cancellation handling;
- measure model/network runtime;
- perform Siri and accessibility qualification.

### Spike D — entry search and summaries (**scaffold only**)

About 4–6 engineering days, plus privacy review:

- early foreground stubs: `SearchFoodLogsIntent`, `GetTodayNutritionSummaryIntent` (open app / Entries; no shared store read);
- still needed: `FoodLogEntryEntity`, privacy review, real opt-in summaries, Spotlight decision.

## Decision log

- **Use App Intents, not legacy SiriKit custom intents.** App Intents are Apple’s current Siri/Apple Intelligence integration boundary.
- **Ship foreground handoff first.** It delivers a useful Siri workflow while keeping JustLogIt’s reviewed logging contract.
- **Do not adopt the Notes schema for food entries.** The semantic contract is wrong and could produce brittle or misleading behavior.
- **Do not create a parallel Siri nutrition engine.** Extract and share the current workflow.
- **Do not auto-save an inferred USDA choice.** Confirm meaningful nutrition mutations and continue ambiguous work in the app.
- **Keep HealthKit downstream and permission-neutral.** Siri changes how a log starts, not how Health authorization works.
- **Defer broad Spotlight indexing.** Food history is sensitive and the current schema catalog has no precise nutrition entity.

## Open questions to validate in code

1. Does the release iOS 27 SDK add a health, nutrition, journal-entry, or generic record schema that is absent from the current catalog?
2. What exact App Shortcut phrase grammar does the installed SDK accept for a free-text food parameter?
3. Can the first intent reliably install a pending navigation request before the asynchronous SwiftData bootstrap completes on a cold launch?
4. How often does the real Foundation Models + USDA path exceed the normal background budget on supported devices?
5. Which quick-log confidence rule is strict enough to avoid surprising USDA selections? This should be measured from the existing evaluation corpus, not chosen by intuition.
6. What nutrition-history exposure, if any, is acceptable in Spotlight and Siri under JustLogIt’s privacy promise?

## Recommendation

Spike A code is in the tree; finish device UAT and the remaining handoff polish before calling it done. Plan Spike B next as the architectural prerequisite for hands-free confirmation-and-save (Spike C). Do not market “Siri can log anything hands-free” until Spike C passes real-device ambiguity, cancellation, idempotency, and privacy tests.
