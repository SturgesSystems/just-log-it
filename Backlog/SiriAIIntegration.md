# P2 — Siri AI integration

## Status

**Spike A (foreground handoff): code complete; exit gate open (physical-device + matrix).**

Verified in tree under `JustLogIt/AppIntents/`, `JustLogIt/App/`, and Log:

| Piece | Location / behavior |
| --- | --- |
| Typed `PendingFoodLog` | `JustLogIt/App/PendingFoodLog.swift` — description, optional `consumedAt`, source (`.siri` / `.shortcut` / `.inApp`) |
| `StartFoodLogIntent` | Background + dynamic foreground, main-app only; Siri resolves food/time first, then app review; no SwiftData; no save |
| `JustLogItShortcuts` | Donates **Log Food** (`StartFoodLogIntent`) + **Today's Nutrition**; not Quick Log |
| `SiriFoodLogCoordinator` | Sendable dependency → `AppNavigation.pendingFoodLog` / search / Entries |
| Bootstrap | `registerJustLogItAppDependencies()` in `JustLogItApp.init`; store opens after first frame |
| Log consume | `LogView.applyPendingFoodLog` sets input + clear `consumedAt` inference; **auto-submits** for `.siri` / `.shortcut` only (`.inApp` focuses composer) |
| In-progress guard | Offers Start/Dismiss banner instead of clobbering an active conversation |
| Unit tests | `StartFoodLogIntentTests`, `AppNavigationFoodLogTests`, navigation cases in `AppConfigurationTests` / `DeepLinkRouterTests`; consumed-time survival through parse in `LogConversationTests` |

**Still open for Spike A (honest):** warm/cold launch on device, full failure matrix (cancellation, parser/provider down), VoiceOver pass, and physical-device Shortcuts discovery + Siri invocation per [`Documentation/ManualSiriAcceptance.md`](../Documentation/ManualSiriAcceptance.md). Exit gate not closed.

**Spike B:** not started — no `FoodLoggingWorkflow` type or extraction from `LogViewModel`.

**Spike C:** not started — `QuickLogFoodIntent` is a **non-discoverable stub** that only reuses the Spike A foreground handoff (`isDiscoverable = false`, not in `JustLogItShortcuts`). No in-Siri confirmation, nutrition, or save.

**Spike D:** partial scaffold — `SearchFoodLogsIntent` opens Entries + search query; `GetTodayNutritionSummaryIntent` now finishes in Siri when `TodayNutritionSnapshotSource` has a bootstrapped store, and dynamically opens Entries only when no snapshot is ready; `FoodLogEntryEntity` is on-screen only (query returns empty; not `IndexedEntity` / Spotlight). Cold background summary remains blocked on a safe shared/cached read model. No privacy review or full entity search.

Authoritative design handoff:
[`Documentation/SIRI_AI_INTEGRATION_SPIKE.md`](../Documentation/SIRI_AI_INTEGRATION_SPIKE.md)

**Continue / resume session:**
[`Documentation/AGENT_CONTINUATION_2026-07-18.md`](../Documentation/AGENT_CONTINUATION_2026-07-18.md) · inventory [`Documentation/SESSION_SHIPPED.md`](../Documentation/SESSION_SHIPPED.md)

## Outcome

Let a person begin a reviewed JustLogIt food log through Siri, then progressively support tightly
bounded confirmation and saving without creating a second nutrition pipeline or weakening USDA,
serving, persistence, HealthKit, privacy, and user-confirmation rules.

Siri supplies user-authored food text and an optional consumed time. JustLogIt remains authoritative
for interpretation, food selection, portion resolution, nutrition, persistence, and HealthKit.

## Activation gate

Do not treat compile-only App Intent declarations as done. Close Spike A only after:

- the production hybrid parser architecture is selected from the physical-device corpus;
- cold/prewarmed Foundation Models and end-to-end latency are recorded on the target iPhone;
- the hybrid route has no unsafe corpus disagreements or dead-end UI paths;
- the complete local software, Release/archive, and interactive UAT gates remain green; and
- the installed release-candidate iOS 27 SDK is rechecked for App Intent modes, phrase grammar,
  App Schemas, testing APIs, and execution-target behavior;
- physical-device Shortcuts discovery and Siri invocation of Start Food Log succeed per
  [`Documentation/ManualSiriAcceptance.md`](../Documentation/ManualSiriAcceptance.md).

## Ordered implementation

### A — Foreground handoff

- [x] Add a typed `PendingFoodLog` carrying description, optional consumed time, and source.
- [x] Replace the string-only pending-navigation seam without losing or auto-submitting drafts.
- [x] Add `StartFoodLogIntent` and `JustLogItShortcuts` using supported iOS 27 APIs.
- [x] Execute in the main app and defer foreground presentation; do not synchronously open SwiftData
      from `JustLogItApp.init`.
- [x] Route Siri text into the existing reviewed Log workflow with no persistence before confirmation
      (`LogView` auto-submits for `.siri` / `.shortcut`).
- [ ] Test warm/cold launch, cancellation, missing parameters, parser/provider unavailability,
      VoiceOver, and preservation of a supplied consumed time **on device / full matrix**
      (unit coverage exists for intent handoff, empty description, trim, consumed-time seam,
      and parse-time preservation; not a substitute for ManualSiriAcceptance).
- [ ] Validate discovery in Shortcuts and invocation through Siri on a physical device.

Exit gate: “Log two scrambled eggs in JustLogIt” reaches the ordinary reviewable Log flow with the
complete phrase and optional time preserved, creates no record on cancellation, and causes no
regression in normal in-app logging.

Notes on A (code vs gate):

- **In code:** handoff path is implemented end-to-end from intent → coordinator → navigation →
  Log auto-submit, with unit tests on the seam.
- **Not closed:** physical-device Shortcuts/Siri discovery, warm/cold launch, VoiceOver, and the
  compound failure matrix in ManualSiriAcceptance. Do not mark Spike A done from compile/unit green alone.

### B — Shared headless workflow

- [ ] Extract typed `FoodLoggingWorkflow` outcomes from `LogViewModel` without behavior drift.
- [ ] Centralize entry/recognized-food persistence in one transactional, idempotent repository.
- [ ] Keep SwiftUI and App Intent adapters thin and dependent on the same parser, USDA, ranking,
      serving, nutrition, and clarification services.
- [ ] Prove cancellation and retry cannot partially or doubly persist a log.

Exit gate: existing UI behavior and parser/USDA/serving results are unchanged while the same workflow
can be exercised without constructing a view model.

**Reality check:** no `FoodLoggingWorkflow` symbol or file exists. `LogViewModel` remains the
sole logging orchestrator. Spike C is blocked on this.

### C — Confirm and save in Siri

- [ ] Implement `QuickLogFoodIntent` only for one safe, fully resolved food
      (today: stub → same `beginLog` foreground path as Start Food Log; not discoverable).
- [ ] Present food, amount, consumed time, calories, macros, and approximation before confirmation.
- [ ] Continue ambiguous, composite, unavailable, or choice-requiring requests in JustLogIt with all
      captured input preserved.
- [ ] Save locally exactly once after explicit confirmation; HealthKit remains optional post-save
      follow-up and must not present authorization from a background invocation.
- [ ] Measure runtime and foreground early rather than using long-running execution as a timeout
      escape hatch.

Exit gate: no silent nutrition creation, no Siri/model-authored nutrition, no duplicate save, and no
loss of the original request during foreground continuation.

Stub reference: `JustLogIt/AppIntents/QuickLogFoodIntent.swift` and
[`Documentation/SPIKE_C_QUICK_LOG_NOTES.md`](../Documentation/SPIKE_C_QUICK_LOG_NOTES.md).

### D — Search and summaries

- [ ] Revalidate whether iOS 27 provides a legitimate food/nutrition schema.
- [ ] Add entry entities, in-app search integration, and opt-in structured summaries only after a
      privacy review of Spotlight/Siri exposure, deletion, locking, and reindexing.

Scaffold in tree (not checked above):

- `SearchFoodLogsIntent` — foreground open Entries + pending search query.
- `GetTodayNutritionSummaryIntent` — open Entries; spoken summary only if
  `TodayNutritionSnapshotSource` is bound (no second `ModelContainer`).
- `FoodLogEntryEntity` + empty `EntityQuery`; SwiftUI `.appEntityIdentifier` on entry UI;
  not Spotlight-indexed.
- `FoodLogIntentDonation` after successful in-app save (donations only).

## Non-goals for the first Siri release

- Fully autonomous hands-free logging
- Silent save
- Photo logging through Siri
- Pretending a food log is a notes/reminders schema
- Publishing food history to Spotlight by default
- A separate Siri-specific parser, USDA selector, nutrition calculator, or persistence path
