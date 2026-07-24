# Session shipped inventory

**Date:** 2026-07-18
**Scope:** Multi-agent Siri / App Intents / Entries summary work, inventoryed from files on disk.
**Rule:** Only what exists in the tree. Nothing invented as “done” from plans or comments alone.

**How to continue:** [`AGENT_CONTINUATION_2026-07-18.md`](AGENT_CONTINUATION_2026-07-18.md) — next steps, risks, resume prompt, verify commands.

---

## Executive summary

| Track | Status on disk |
| --- | --- |
| **Spike A** — Siri/Shortcuts foreground handoff into reviewed Log | **Shipped as code + unit tests.** Physical-device Manual Siri exit gate still open. |
| **Spike B** — shared headless `FoodLoggingWorkflow` | **Incomplete.** `FoodLogRepository` is a transactional save helper; workflow extract from `LogViewModel` did **not** land. |
| **Spike C** — in-Siri confirm-and-save (`QuickLogFoodIntent`) | **Stub only.** `isDiscoverable = false`; always opens reviewed Log; no USDA resolve, no persist from intent. |
| **Search / summary intents** | **Partial.** Search opens Entries with a query seed. Today’s nutrition can speak totals **only if** the app store is already bound; otherwise tab open + dialog. |
| **Entries day card** | **Shipped** (`DayNutritionSummaryView` + `TodayNutritionSnapshot`). |
| **Live Activity / Watch** | **Docs only** — deferral recommendations; no product targets. |

**Product rule held across shipped paths:** no nutrition persistence until the person confirms in-app (or, for Spike C future, until an explicit in-Siri confirm). Intents do not open SwiftData in `App.init`.

---

## 1. Spike A — foreground food-log handoff (landed)

### 1.1 Typed pending handoff

| File | What it does |
| --- | --- |
| [`JustLogIt/App/PendingFoodLog.swift`](../JustLogIt/App/PendingFoodLog.swift) | `PendingFoodLog`: `description`, optional `consumedAt`, `source` (`.siri` / `.shortcut` / `.inApp`). |
| [`JustLogIt/App/AppNavigation.swift`](../JustLogIt/App/AppNavigation.swift) | Process seam: `pendingFoodLog`, `pendingSearchQuery`, `beginPendingFoodLog` / `takePendingFoodLog`, `logAgain`, `beginPendingSearch` / `takePendingSearchQuery`, `showEntries`, entry/food selection. |

### 1.2 App Intents + coordinator

| File | What it does |
| --- | --- |
| [`JustLogIt/AppIntents/StartFoodLogIntent.swift`](../JustLogIt/AppIntents/StartFoodLogIntent.swift) | **Start Food Log** — background-first with dynamic foreground; Siri collects required Food and optional When Eaten, then opens reviewed nutrition; rejects empty food; `coordinator.beginLog(..., source: .siri)`; no SwiftData, no save. |
| [`JustLogIt/AppIntents/SiriFoodLogCoordinator.swift`](../JustLogIt/AppIntents/SiriFoodLogCoordinator.swift) | Facade over `AppNavigation`: `beginLog`, `takePending`, `beginSearch`, `showEntries`, `attach`. Injectable navigation for tests; production uses shared. |
| [`JustLogIt/AppIntents/JustLogItShortcuts.swift`](../JustLogIt/AppIntents/JustLogItShortcuts.swift) | **Registered App Shortcuts only:** (1) Log Food → `StartFoodLogIntent`; (2) Today's Nutrition → `GetTodayNutritionSummaryIntent`. **Search Logs is not registered here.** |
| [`JustLogIt/AppIntents/AppIntentsRegistration.swift`](../JustLogIt/AppIntents/AppIntentsRegistration.swift) | `registerJustLogItAppDependencies()` → `AppDependencyManager` + `SiriFoodLogCoordinator.shared`. |
| [`JustLogIt/AppIntents/FoodLogIntentDonation.swift`](../JustLogIt/AppIntents/FoodLogIntentDonation.swift) | Best-effort `StartFoodLogIntent.donate()` after successful local save; skipped under UI testing. |

**Log Food phrases** (from `JustLogItShortcuts`; `\(.applicationName)` → JustLogIt).
The required free-form Food parameter is collected by the intent dialog because Xcode 27 metadata
export accepts phrase interpolation only for `AppEntity` / `AppEnum` values:

- Log food in JustLogIt
- Add food to JustLogIt
- Log what I ate in JustLogIt
- Start a food log in JustLogIt

### 1.3 Log tab consumption

| File | Behavior |
| --- | --- |
| [`JustLogIt/Features/Log/LogView.swift`](../JustLogIt/Features/Log/LogView.swift) | `onAppear` / `onChange(pendingFoodLog)` → `consumePendingFoodLog()`. In-progress conversation → top banner (`siri-pending-banner` / Start / Dismiss). Idle/completed → `applyPendingFoodLog`: seed input + optional `consumedAt` (“From Siri”), then **auto-`submitComposer()` for `.siri` / `.shortcut`**; **focus only for `.inApp`**. Empty-state Siri tip card. |
| [`JustLogIt/Features/Log/LogViewModel.swift`](../JustLogIt/Features/Log/LogViewModel.swift) / `LogViewModel+Internals.swift` | Preserves clear handoff `consumedAt` through interpretation. |
| [`JustLogIt/Features/Log/LogView+Composer.swift`](../JustLogIt/Features/Log/LogView+Composer.swift) | Confirm save via `FoodLogRepository`; post-save Health + `FoodLogIntentDonation`. |

### 1.4 Deep links (Shortcuts / local testing)

| File | Behavior |
| --- | --- |
| [`JustLogIt/App/DeepLinkRouter.swift`](../JustLogIt/App/DeepLinkRouter.swift) | `justlogit://log?food=&at=` → `PendingFoodLog` with `source: .shortcut`; food max 500 chars; optional ISO-8601 `at`. Contract doc: [`DeepLinks.md`](DeepLinks.md). |
| [`JustLogIt/App/JustLogItApp.swift`](../JustLogIt/App/JustLogItApp.swift) | Early dependency registration; `onOpenURL` → `AppNavigation.shared.beginPendingFoodLog` (survives bootstrap; no store open). |
| [`JustLogIt/Resources/Info.plist`](../JustLogIt/Resources/Info.plist), [`Info-Debug.plist`](../JustLogIt/Resources/Info-Debug.plist) | URL scheme `justlogit`. |

### 1.5 Settings — Siri & Shortcuts section

| File | Content |
| --- | --- |
| [`JustLogIt/Features/Settings/SettingsView.swift`](../JustLogIt/Features/Settings/SettingsView.swift) | Section **“Siri & Shortcuts”**: fixed phrase “Log food in JustLogIt”; explains that Siri asks what was eaten and that the app never auto-saves; Shortcuts lists “Log Food”. Privacy footer also mentions Siri/Shortcuts. |

### 1.6 Manual acceptance + static check

| File | Role |
| --- | --- |
| [`Documentation/ManualSiriAcceptance.md`](ManualSiriAcceptance.md) | Physical-device checklist (warm/cold handoff, consumed time, cancel, VoiceOver, regression). Automated physical install/launch/deep-link evidence is recorded; Siri voice cases are still pending. Search is documented as a system in-app-search surface, not a registered App Shortcut. |
| [`Scripts/check-siri-spike-a.sh`](../Scripts/check-siri-spike-a.sh) | **Exists.** Static presence check for Spike A sources + `struct StartFoodLogIntent`. Does **not** run Siri, simulator, or device. |

### 1.7 Spike A unit tests (present)

| File | Coverage (approx.) |
| --- | --- |
| [`JustLogItTests/AppNavigationFoodLogTests.swift`](../JustLogItTests/AppNavigationFoodLogTests.swift) | 11 tests: `logAgain`, begin/take pending, empty rejection, open entry/food, replace pending, equality, `showEntries`. |
| [`JustLogItTests/StartFoodLogIntentTests.swift`](../JustLogItTests/StartFoodLogIntentTests.swift) | 10 tests: coordinator isolate/attach/empty, intent perform trim/empty/source, GetTodayNutritionSummary opens Entries (± bound store). |
| [`JustLogItTests/DeepLinkRouterTests.swift`](../JustLogItTests/DeepLinkRouterTests.swift) | 8 tests: parse food/time, reject invalid URLs, apply through `AppNavigation` with `.shortcut`. |
| Overlap | Some begin/take pending cases also live in `AppConfigurationTests` (duplicate ownership). |

**Not covered by automated tests on disk:** LogView consume policy, banner Start/Dismiss, idle-draft wipe, double-pending while banner visible, cold-start-through-bootstrap integration, real Siri/Shortcuts discovery.

---

## 2. Related intents & entities (partial / stubs)

All under [`JustLogIt/AppIntents/`](../JustLogIt/AppIntents/):

| File | Discoverable / Shortcuts | Actual behavior |
| --- | --- | --- |
| `StartFoodLogIntent.swift` | Yes — **Log Food** | Reviewed Log handoff only. |
| `GetTodayNutritionSummaryIntent.swift` | Yes — **Today's Nutrition** | If `TodayNutritionSnapshotSource.loadTodayIfAvailable()` returns a snapshot, Siri speaks `spokenSummary` without opening the app; otherwise dynamically opens Entries. Does **not** open a second `ModelContainer`. |
| `SearchFoodLogsIntent.swift` | **Not** in `JustLogItShortcuts` | `ShowInAppSearchResultsIntent`: `beginSearch(query:)` → Entries search seed. No persist. |
| `QuickLogFoodIntent.swift` | `isDiscoverable = false`; not in shortcuts | **Spike C stub:** same `beginLog` path as Start Food Log. |
| `FoodLogEntryEntity.swift` | Entity type present | On-screen `.appEntityIdentifier` on entry rows/detail. `EntityQuery` returns **empty** (stub). **Not** `IndexedEntity` / Spotlight. |
| `FoodLogIntentDonation.swift` | N/A | Post-save donation only. |
| `AppIntentsRegistration.swift` | N/A | Coordinator dependency only. |

**Today's Nutrition phrases** (actual `JustLogItShortcuts`):

- How much have I eaten today in JustLogIt
- Today's nutrition in JustLogIt
- Show today's nutrition summary in JustLogIt
- What are my calories today in JustLogIt

---

## 3. Entries day nutrition UI (landed)

| File | Role |
| --- | --- |
| [`JustLogIt/Services/TodayNutritionSnapshot.swift`](../JustLogIt/Services/TodayNutritionSnapshot.swift) | Pure aggregate from caller's context; `spokenSummary`; `TodayNutritionSnapshotSource` bind/unbind to live container after bootstrap. |
| [`JustLogIt/Features/Entries/DayNutritionSummaryView.swift`](../JustLogIt/Features/Entries/DayNutritionSummaryView.swift) | Card: today entry count, calories, P/C/F chips + proportion bar; empty strip when history exists but nothing today. A11y id `today-nutrition-summary`. |
| [`JustLogIt/Features/Entries/EntriesView.swift`](../JustLogIt/Features/Entries/EntriesView.swift) | Wires day summary row; consumes `pendingSearchQuery` into `searchText`; consumes entry/food selection navigation. |
| [`JustLogIt/App/JustLogItApp.swift`](../JustLogIt/App/JustLogItApp.swift) | Binds/unbinds `TodayNutritionSnapshotSource` with container lifecycle. |
| [`JustLogItTests/TodayNutritionSnapshotTests.swift`](../JustLogItTests/TodayNutritionSnapshotTests.swift) | Snapshot math + source bind/unbind (~11 tests). |

---

## 4. Persistence seam for later Siri spikes (partial Spike B)

| File | What landed | What did **not** land |
| --- | --- | --- |
| [`JustLogIt/Persistence/FoodLogRepository.swift`](../JustLogIt/Persistence/FoodLogRepository.swift) | Transactional insert + recognized-food upsert + save/rollback. Used by Log confirm + Manual entry. | Headless parse/search/serving workflow. |
| [`JustLogItTests/FoodLogRepositoryTests.swift`](../JustLogItTests/FoodLogRepositoryTests.swift) | Repository commit/rollback coverage. | Intent save path (none exists yet). |

**Spike B honest status:** repository comment names future Siri adapters, but there is **no** `FoodLoggingWorkflow` type/file in the repo. `LogViewModel` still owns parse → clarify → USDA → review orchestration. Workflow extract = **incomplete**.

---

## 5. Spike C status (blocked / stub)

| Artifact | Status |
| --- | --- |
| [`JustLogIt/AppIntents/QuickLogFoodIntent.swift`](../JustLogIt/AppIntents/QuickLogFoodIntent.swift) | Stub implementation only. |
| [`Documentation/SPIKE_C_QUICK_LOG_NOTES.md`](SPIKE_C_QUICK_LOG_NOTES.md) | Design: confirmation UI requirements; blocked on Spike B. |
| In-Siri confirm UI | Not implemented. |
| Intent persistence | Not implemented. |

---

## 6. Documentation landed this theme

| Path | Kind |
| --- | --- |
| [`Documentation/ManualSiriAcceptance.md`](ManualSiriAcceptance.md) | Device checklist for registered shortcuts / handoff. |
| [`Documentation/SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md) | Spike plan A–D; status partial Spike A. |
| [`Documentation/SPIKE_C_QUICK_LOG_NOTES.md`](SPIKE_C_QUICK_LOG_NOTES.md) | Quick Log design notes. |
| [`Documentation/SESSION_REVIEW_SIRI_UI.md`](SESSION_REVIEW_SIRI_UI.md) | Uncommitted-tree review (risks, commit split). Review-only; not a ship gate. |
| [`Documentation/AppIntentsIOS27CheatSheet.md`](AppIntentsIOS27CheatSheet.md) | API cheat sheet. |
| [`Backlog/SiriAIIntegration.md`](../Backlog/SiriAIIntegration.md) | Ordered gates; Spike A partial; B–C not started; D scaffold. |
| [`Documentation/LiveActivityFoodLogSpike.md`](LiveActivityFoodLogSpike.md) | **Research / defer** — no ActivityKit code. |
| [`Documentation/WATCH_COMPANION_SPIKE.md`](WATCH_COMPANION_SPIKE.md) | **Research / defer** — no watchOS target. |
| [`Documentation/CONTINUATION_HANDOFF.md`](CONTINUATION_HANDOFF.md) | Broader product handoff (includes non-Siri session work). |

---

## 7. Scripts

| Script | Present | Behavior |
| --- | --- | --- |
| [`Scripts/check-siri-spike-a.sh`](../Scripts/check-siri-spike-a.sh) | **Yes** | Requires: `StartFoodLogIntent.swift`, `JustLogItShortcuts.swift`, `PendingFoodLog.swift`, `SiriFoodLogCoordinator.swift`; greps for `struct StartFoodLogIntent`. Exit 0 when files OK. |

No other `check-siri-*` scripts found under `Scripts/`.

---

## 8. File checklist (Siri / handoff / day summary primary)

### App

- `JustLogIt/App/AppNavigation.swift`
- `JustLogIt/App/PendingFoodLog.swift`
- `JustLogIt/App/DeepLinkRouter.swift`
- `JustLogIt/App/JustLogItApp.swift` (deps, `onOpenURL`, snapshot bind, lightweight bootstrap + launch milestones)
- `JustLogIt/App/RootTabView.swift` (shared navigation; `fork.knife` Log tab; liquid-glass bar materials)

### AppIntents (9 Swift sources)

- `AppIntentsRegistration.swift`
- `StartFoodLogIntent.swift`
- `SiriFoodLogCoordinator.swift`
- `JustLogItShortcuts.swift`
- `SearchFoodLogsIntent.swift`
- `GetTodayNutritionSummaryIntent.swift`
- `QuickLogFoodIntent.swift` (stub)
- `FoodLogIntentDonation.swift`
- `FoodLogEntryEntity.swift` (entity + empty query stub)

### Features / Services / Persistence

- `JustLogIt/Features/Log/LogView.swift` (consume, banner, empty-state tip, recent foods)
- `JustLogIt/Features/Log/RecentFoodsBar.swift` (up to 5 chips from RecognizedFood `@Query` / RememberedFood fallback; tap starts reviewed flow)
- `JustLogIt/Features/Log/LogView+Composer.swift` (repository + donation)
- `JustLogIt/Features/Log/ManualEntryView.swift` (repository save)
- `JustLogIt/Features/Settings/SettingsView.swift` (Siri & Shortcuts section)
- `JustLogIt/Features/Entries/DayNutritionSummaryView.swift`
- `JustLogIt/Features/Entries/EntriesView.swift` (summary + pending search)
- `JustLogIt/Features/Entries/EntriesRows.swift` / `EntryDetailView.swift` (entity identifiers)
- `JustLogIt/Services/TodayNutritionSnapshot.swift`
- `JustLogIt/Persistence/FoodLogRepository.swift`

### Tests

- `JustLogItTests/AppNavigationFoodLogTests.swift`
- `JustLogItTests/StartFoodLogIntentTests.swift`
- `JustLogItTests/DeepLinkRouterTests.swift`
- `JustLogItTests/TodayNutritionSnapshotTests.swift`
- `JustLogItTests/FoodLogRepositoryTests.swift`
- Related cases also in `AppConfigurationTests`, `LogConversationTests` (Siri `consumedAt` handoff mirror)

### Docs / Scripts

- `Documentation/ManualSiriAcceptance.md`
- `Documentation/SIRI_AI_INTEGRATION_SPIKE.md`
- `Documentation/SPIKE_C_QUICK_LOG_NOTES.md`
- `Documentation/SESSION_REVIEW_SIRI_UI.md`
- `Scripts/check-siri-spike-a.sh`

---

## 9. Explicitly not shipped

Do not treat these as done based on this session’s tree:

1. **`FoodLoggingWorkflow` extraction** (Spike B) — no type/file; UI still owns the pipeline.
2. **In-Siri confirm-and-save** (Spike C) — stub only.
3. **Silent or autonomous Siri logging** — intentionally absent.
4. **Search Logs as donated App Shortcut** — intent exists; not in `JustLogItShortcuts`.
5. **Store-backed `FoodLogEntryEntityQuery` / Spotlight indexing** — empty query; not indexed.
6. **Physical-device Siri/Shortcuts acceptance** — `ManualSiriAcceptance.md` test record empty.
7. **Automated LogView consume / banner / draft-wipe tests** — absent.
8. **Live Activity or watchOS companion** — docs only.
9. **Idempotent intent retry / background SwiftData from intents** — not required for Spike A; not built.

---

## 10. Spike map (honest)

```text
A  Foreground handoff ████████████░░░░  code + unit tests; device gate open
B  Headless workflow   ██░░░░░░░░░░░░░░  FoodLogRepository only; no workflow type
C  Quick log in Siri   █░░░░░░░░░░░░░░░  non-discoverable stub → same as A
D  Search / summary    ████░░░░░░░░░░░░  search handoff; summary if store bound;
                                         entity query empty; no Spotlight
```

---

## 11. End-to-end paths that actually work in code

1. **Siri / Shortcuts Log Food** → `StartFoodLogIntent` → coordinator → `pendingFoodLog` → Log tab → (optional banner) → seed + auto-submit interpretation → person confirms → `FoodLogRepository` → optional Health + intent donation.
2. **Deep link** `justlogit://log?food=…` → same pending path with `source: .shortcut`.
3. **In-app Log again** → `logAgain` → pending `.inApp` → focus composer only (no auto-submit).
4. **Today's Nutrition** → Entries tab; spoken macros only when bootstrap already bound the container.
5. **Search Food Logs intent** (if invoked by system search / testing, not via donated App Shortcut list) → Entries + search text.
6. **Entries list** shows today’s nutrition card from local entries.

---

## 12. Known honesty gaps (code vs copy)

Recorded so the next session does not over-claim:

| Surface | Nuance |
| --- | --- |
| Settings / ManualSiri “never auto-saves” | True for **persistence**. `.siri` / `.shortcut` **do auto-run interpretation** (`submitComposer`) when conversation not “in progress.” |
| `StartFoodLogIntent` always `source: .siri` | Runs from Shortcuts UI still labeled Siri. Deep links correctly use `.shortcut`. |
| Banner / inference label “From Siri” | Also used for shortcut provenance in places. |
| `ManualSiriAcceptance.md` Search Logs section | Ahead of `JustLogItShortcuts` (Search not registered). Prefer code as source of truth for donated phrases. |
| `Backlog/SiriAIIntegration.md` Spike D note | Slightly behind: GetTodayNutrition **can** read bound store via `TodayNutritionSnapshotSource` (still no second store / no entities). |

---

## Bottom line

This multi-agent session **did** land a real Spike A architecture on disk: typed pending handoff, Start Food Log + Shortcuts, coordinator, Log consume + in-progress banner, deep links, Settings education, day nutrition card/snapshot, repository save boundary, donation after save, unit tests, Manual Siri checklist, and `check-siri-spike-a.sh`.

It **did not** finish Spike B (workflow extract incomplete — repository only) or Spike C (stub). Search/summary/entity work is scaffold-to-partial. Device Siri acceptance remains an open exit gate.
