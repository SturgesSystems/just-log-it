# UI bug log

This is the durable ledger for defects found during user-level UI acceptance testing. Add a bug immediately when observed; do not rely on chat history or screenshots alone. One bug should describe one independently fixable behavior.

## Severity and status

| Severity | Meaning |
| --- | --- |
| S0 — Blocker | Data loss, crash, security/privacy violation, or the primary logging journey cannot complete |
| S1 — Major | A required interaction is unavailable or produces a materially wrong result with no reasonable workaround |
| S2 — Moderate | The interaction works with friction, misleading feedback, accessibility failure, or a practical workaround |
| S3 — Minor | Visual polish, copy, alignment, or low-impact inconsistency |

Valid statuses are **Open**, **Investigating**, **Fix in progress**, **Ready to verify**, **Fixed**, **Deferred**, and **Cannot reproduce**. A code change is not sufficient for **Fixed**: the original reproduction steps must pass on a named build.

## Open bugs

### UI-001 — A fraction of a sized container is logged as the fraction in ounces

- Severity: S1 — Major
- Status: Ready to verify
- Owner: Parser/resolution sub-agent
- Found in: `bc9d067`, Xcode 27 beta / iOS 27, iPhone 17 Pro Simulator
- Area: Log / USDA
- Evidence: User walkthrough; regression coverage added in `JustLogItCoreTests`

Reproduction:

1. Start on a configured Log screen using the real on-device Foundation Model.
2. Enter `About half a 12-ounce bottle of Fairlife chocolate milk` and continue.
3. Choose the appropriate USDA food and proceed to nutrition review.
4. Inspect the interpreted and consumed amount.

Expected:

The app keeps the fraction and container size as separate facts and calculates half of 12 ounces, or approximately 6 ounces consumed.

Actual:

The model output could represent the amount as `0.5 ounce`, causing the resolver to calculate nutrition for one-half ounce instead of half of the 12-ounce bottle.

Notes:

The parser guidance now gives explicit fraction/container semantics, and serving resolution now prioritizes `fractionOfWhole × containerSize` over a conflicting primary quantity. Deterministic regression tests cover the incorrect model shape and the household-serving fallback. Automated tests exist; the original real Foundation Model walkthrough remains pending before this can be marked Fixed.

Verification:

- Fix commit: `874df33`
- Verified by: Automated core regression tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-002 — A canceled or superseded Log operation can replace the current UI state

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: Concurrency sub-agent
- Found in: `bc9d067`, source audit
- Area: Log / USDA
- Evidence: `LogViewModel` uses one cancelable `operation`, but completed/error paths have no operation identity or generation guard

Reproduction:

1. Start a Log parse, USDA search, or food-details request under a slow connection.
2. Tap **Cancel**, or start a newer search/selection before the first request completes.
3. Allow the older provider/model request to return or fail after the newer UI state is visible.
4. Observe whether the older operation changes the stage, message, results, or selected details.

Expected:

After cancellation or supersession, only the newest operation may mutate visible Log state. An obsolete completion or error must be ignored.

Actual:

Cancellation is requested, but an underlying operation that returns a non-cancellation result or error can still reach a catch/state-assignment path and overwrite the idle or newer flow.

Notes:

The view model now invalidates operations with a monotonically increasing generation and ignores canceled or superseded completions. Deterministic tests cover a parser failure after cancellation and an older details failure after a newer selection succeeds. Automated tests exist; manual slow-operation verification of the original reproduction remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Automated app unit tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Deterministic regression tests pass; manual original reproduction pending

### UI-003 — Quantity clarification rejects the locale decimal separator

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: Localized-number sub-agent
- Found in: `bc9d067`, source audit
- Area: Log / Accessibility
- Evidence: `resolveWithServings()` and `resolveWithGrams()` previously parsed the field directly with `Double(String)`; fixed in code via `LocalizedNumberParser`

Reproduction:

1. Set the simulator to a locale that uses a comma decimal separator, such as French.
2. Reach **How Much Did You Eat?** for a USDA result.
3. Enter `1,5` servings or `150,5` grams with the locale-appropriate decimal keyboard.
4. Tap **Review Nutrition**.

Expected:

The app accepts the decimal separator presented by the current locale and calculates nutrition from the entered value.

Actual:

Was: direct `Double` parsing rejected the comma value and showed **Enter a valid number of USDA servings.** or **Enter a valid gram amount.** Clarification fields now share `LocalizedNumberParser` with Manual Entry so locale decimal separators are accepted in code.

Notes:

Manual Entry already normalized `Locale.current.decimalSeparator`; clarification fields now use the same `LocalizedNumberParser`. Deterministic unit tests cover locale-aware parsing. Automated tests exist; a locale-specific Simulator walkthrough of the original reproduction remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Automated `LocalizedNumberParser` unit tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-004 — Apple Health retry can be unavailable or silently do nothing

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: HealthKit/UI sub-agent
- Found in: `bc9d067`, source audit
- Area: Entries / HealthKit
- Evidence: Entry detail calls `HealthSyncCoordinator.syncIfEnabled`; the coordinator immediately returns when the Settings preference is off, and denied entries do not receive the failed-state retry button

Reproduction:

1. Produce an entry whose Apple Health status is **Needs attention**, then turn **Save nutrition to Apple Health** off in Settings.
2. Return to the entry detail and tap **Try Apple Health Again**.
3. Observe that the status and error do not change and no explanation or route to Settings appears.
4. Separately, deny Health access and inspect an entry with **Access not granted** status.

Expected:

Retry either performs a real authorization/write attempt or clearly explains what must be enabled and offers a useful recovery route. A denied entry should also have an understandable recovery path.

Actual:

The visible retry can no-op when the preference is off because the coordinator returns before updating state. A denied entry displays its status/error but no retry action.

Notes:

Retry now returns a visible outcome. When sync is off, the app explains that it must be enabled and offers Settings; denied and failed entries both expose retry. Retry requests authorization only after the explicit button tap and routes unresolved access to Settings without reading Health data. Automated Health sync tests exist; Simulator acceptance of the original reproduction remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Automated HealthKit/coordinator tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-005 — Apple Health sync preference is persisted before authorization finishes

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: HealthKit/UI sub-agent
- Found in: `bc9d067`, source audit
- Area: Settings / HealthKit
- Evidence: The Settings toggle binds directly to `@AppStorage`; its change launches asynchronous authorization and only resets the preference after a denied result or error

Reproduction:

1. Start with **Save nutrition to Apple Health** off and Health permission ungranted.
2. Turn the toggle on.
3. While the system authorization UI is still open, interrupt or terminate the app before authorization completes.
4. Relaunch and inspect the persisted preference, then save an entry if the toggle still appears enabled.

Expected:

The durable sync preference becomes enabled only after authorization completes with at least one writable nutrient, or an explicit pending state prevents sync from being represented as ready.

Actual:

The `@AppStorage` value becomes true as soon as the user flips the toggle, before the asynchronous authorization result is known. Interruption can leave the preference inconsistent with permission state.

Notes:

The Settings model now leaves the durable preference off while authorization is pending and persists it only after authorization reports that food and at least one nutrient can be written. Denial and failure leave both the visible and durable preference off. Automated coverage exists for preference gating; the original interruption walkthrough remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Automated Settings/Health preference tests where present
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Code fix landed; automated tests exist; manual original reproduction pending

### UI-006 — Fresh Log screen has redundant hierarchy and an unclear manual-entry affordance

- Severity: S3 — Minor
- Status: Ready to verify
- Owner: Fresh-screen polish sub-agent
- Found in: `bc9d067`, user walkthrough
- Area: Log / Accessibility
- Evidence: Fresh-launch visual inspection and `LogView` source audit

Reproduction:

1. Delete and reinstall the app, then launch to the default Log tab.
2. Read the top-to-bottom hierarchy and inspect the composer without VoiceOver.
3. Determine how to log nutrition manually from the visible controls and supporting copy.

Expected:

The first screen has one clear primary heading, concise human language about privacy/on-device behavior, and an immediately understandable manual-entry affordance.

Actual:

The navigation title **Log Food** is followed by the competing large heading **What did you eat?**. The phrase **Description interpreted on this device** reads as technical implementation copy. Manual Entry is represented visually by an unlabeled plus button, whose meaning is ambiguous without invoking its accessibility label.

Notes:

The navigation bar now uses the compact app name **JustLogIt**, leaving **What did you eat?** as the only task-level heading. The privacy reassurance now reads **Your food log stays on this iPhone**. The bare plus is now a compact bordered **Manual** control with a compose icon, while preserving the **Enter nutrition manually** accessibility label and `manual-entry-button` identifier. Focused UI assertions exist; fresh-launch visual acceptance of the original reproduction remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Focused UI assertion
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated assertion present; manual original reproduction pending

### UI-007 — Recovery headline contradicts an on-device interpretation failure

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: Acceptance/recovery sub-agent
- Found in: `bc9d067`, iOS 27 / iPhone 17 Pro Simulator
- Area: Log / USDA
- Evidence: User walkthrough; `LogView.recoveryTitle` source audit

Reproduction:

1. Launch the configured app with the real on-device Foundation Model unavailable or failing.
2. On the fresh Log screen, tap **Two large scrambled eggs**.
3. Wait for the recovery card.
4. Compare its headline with its explanatory body.

Expected:

An interpretation failure has a headline such as **Couldn’t Interpret That**, and its recovery action offers **Edit Description**. USDA search, no-result, and details failures each present their own accurate title and action.

Actual:

The card headline says **Couldn’t Reach USDA** while its body says **On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually.** The title is inferred by scanning the message for words such as `search`, so recovery copy can accidentally select the wrong context.

Notes:

Failure context is now an explicit `LogViewModel.FailureKind` rather than a message-string heuristic. Parser, search, no-result, and details paths assign distinct kinds; the recovery card maps its title and primary action from that kind. Focused unit tests cover each failure boundary. Automated tests exist; the original real-model walkthrough remains pending before this is Fixed.

Verification:

- Fix commit: `874df33`
- Verified by: Automated app unit tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-008 — Foundation Model facts can leak from a prior food description

- Severity: S1 — Major
- Status: Ready to verify
- Owner: Parser/source-grounding sub-agent
- Found in: Working tree after `bc9d067`, Xcode 27 beta / iOS 27 Simulator
- Area: Log / Foundation Models / USDA
- Evidence: User screenshot showing `Oreo cookie` paired with `half a 12-ounce bottle`

Reproduction:

1. Log `About half a 12-ounce bottle of Fairlife chocolate milk` with the real on-device model.
2. Start another food and enter `An Oreo cookie`.
3. Continue to the interpreted result and USDA choices.
4. Inspect the quantity and structured interpretation.

Expected:

Every serving and lookup fact comes from the current description. `An Oreo cookie` may resolve as one cookie only when the current model output grounds that quantity/unit relationship; otherwise the app asks for clarification.

Actual:

The current product was `Oreo cookie`, but generated quantity text and serving facts retained `half a 12-ounce bottle` from the previous prompt, allowing unrelated facts to reach USDA selection and serving resolution.

Notes:

Generated output now passes through a deterministic source-grounding boundary. Product intent, brand, quantity/unit pairs, fraction/whole pairs, container and alternate quantities, quantity text, preparation, descriptors, approximation, and ambiguity notes are removed unless supported by the current source text. Generated search terms are discarded and rebuilt from grounded product intent. Numeric relationships must be forward and remain within one clause, while explicit measurement aliases and mixed written/numeric fractions preserve valid input. Pure adversarial regressions cover stale product and Oreo quantity contamination, cross-food and backward pairs, grounded single-cookie resolution, the valid sized-container case, unit aliases, mixed fractions, and approximation markers. Automated core tests exist; the original real-model Simulator walkthrough remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Core regression tests and build-for-testing
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-009 — Composite dishes can outrank the food the person actually named

- Severity: S1 — Major
- Status: Ready to verify
- Owner: USDA relevance sub-agent
- Found in: Working tree, iOS 27 / iPhone 17 Pro Simulator
- Area: Log / USDA
- Evidence: User screenshot showing `McDONALD’S, McFLURRY with OREO cookies` as the top result for `An Oreo cookie`

Reproduction:

1. Enter `An Oreo cookie` on the Log screen and continue.
2. Wait for USDA search results.
3. Inspect the first result.

Expected:

A cookie record with the requested Oreo food form ranks ahead of composite desserts that merely contain Oreo cookies as an ingredient or topping.

Actual:

USDA’s response order can place a McFlurry containing Oreo cookies above an Oreo cookie record, making the materially wrong food the easiest choice.

Notes:

Search results now receive a deterministic client-side relevance pass based on parsed product, preparation, descriptors, and an explicitly supplied brand. Complete food-form coverage is rewarded; descriptions that introduce the requested food after words such as `with` or `containing` are demoted as composites. Brand metadata influences ranking only when the parsed request contains a brand. Results are reordered but never removed, and nutrition remains entirely sourced from the selected USDA record. Deterministic core regression tests exist; the original screenshot reproduction remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Deterministic core regression tests
- Verified on: Xcode 27 beta, generic iOS Simulator build-for-testing (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-010 — Interrupted Apple Health writes can remain pending forever

- Severity: S2 — Moderate
- Status: Ready to verify
- Owner: HealthKit lifecycle sub-agent
- Found in: Working tree after `bc9d067`, source audit
- Area: Entries / HealthKit
- Evidence: A pending status was persisted before the asynchronous write, with no launch/foreground reconciliation path

Reproduction:

1. Enable Apple Health sync and begin saving a confirmed entry.
2. Terminate the app after the local status becomes pending but before completion is persisted.
3. Relaunch or foreground JustLogIt and inspect the entry.

Expected:

The app retries an interrupted app-owned write within a bounded policy and visibly reports success or remaining attention.

Actual:

The entry could remain in **Waiting to sync** indefinitely, with no automatic reconciliation or applicable retry control.

Notes:

Launch and foreground activation now reconcile pending and retryable failed writes only when Health sync remains enabled. Retry count and next-attempt date persist on the entry, automatic attempts stop after three failures, and a content-free banner reports the outcome. Protocol-fake reconciliation and bounded-backoff tests exist; the original interruption walkthrough remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Protocol-fake reconciliation and bounded-backoff tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-011 — Deleting a synced entry leaves its Apple Health nutrition behind

- Severity: S1 — Major
- Status: Ready to verify
- Owner: HealthKit lifecycle sub-agent
- Found in: Working tree after `bc9d067`, source audit
- Area: Entries / HealthKit
- Evidence: Entry deletion previously removed only the SwiftData record

Reproduction:

1. Save an entry successfully to Apple Health.
2. Delete the entry from its list or detail screen.
3. Inspect the corresponding Apple Health food and nutrient samples.

Expected:

JustLogIt removes its own matching Health correlation and nutrient samples without touching another source’s data. A failed cleanup remains recoverable and does not discard its retry identity.

Actual:

The local entry was deleted while its Apple Health copy remained, and no durable cleanup work was recorded.

Notes:

Deletion now persists a tombstone before attempting Health cleanup and keeps the local entry until cleanup succeeds. The writer uses exact per-entry `HKMetadataKeySyncIdentifier` predicates across the food correlation and supported nutrient types; HealthKit also restricts deletion to objects written by this app. Failed cleanup persists bounded retry state and remains visible. Protocol-fake tombstone retention and reconciliation tests exist; the original successful-write/delete walkthrough remains pending.

Verification:

- Fix commit: `874df33`
- Verified by: Protocol-fake tombstone retention and reconciliation tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated tests pass; manual original reproduction pending

### UI-012 — Choose a different food immediately re-selects the remembered match

- Severity: S1 — Major
- Status: Ready to verify
- Owner: USDA selection sub-agent
- Found in: `34b9d02`, Xcode 27 beta / iOS 27, iPhone 17 Pro Simulator
- Area: Log / USDA
- Evidence: Live Computer Use walkthrough

Reproduction:

1. Log a food whose USDA match has been remembered from a prior confirmation.
2. Reach the nutrition review card for that automatically selected match.
3. Tap **Choose a different food**.
4. Observe the brief thinking state and the next card.

Expected:

The app presents the ranked USDA match list so the person can choose an alternative. The remembered match may remain ranked first, but an explicit request to choose must not auto-select anything.

Actual:

The app performed another USDA search, applied remembered-match auto-selection again, and immediately returned to review with the same food. No alternative could be chosen.

Notes:

Remembered matches now influence ordering only; they never silently select nutrition data. Manual and choose-different searches also bypass high-confidence auto-selection while retaining relevance ranking. A focused view-model regression test covers the remembered-food path.

Verification:

- Fix commit: Working tree after `34b9d02`
- Verified by: Focused app unit test
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Dedicated remembered-food regression passes; manual original reproduction pending

### UI-013 — Custom meal time submits as “Just now”

- Severity: S1 — Major
- Status: Ready to verify
- Owner: Meal-time sub-agent
- Found in: `34b9d02`, Xcode 27 beta / iOS 27, iPhone 17 Pro Simulator
- Area: Log / Accessibility
- Evidence: Live Computer Use walkthrough

Reproduction:

1. Log a food and continue from nutrition review to **When did you eat this?**.
2. Set the custom time field to `2 hours ago`.
3. Tap **Send**.
4. Observe the user turn and confirmation time.

Expected:

The transcript says `2 hours ago`, and the pending entry's consumed time is approximately two hours in the past.

Actual:

The transcript said `Just now`, and the pending entry used the current time. The custom field's accessibility value had not reached its SwiftUI binding before the button action read it.

Notes:

The composer now resigns focus and waits one main-actor turn before submitting, allowing accessibility, dictation, and IME edits to commit. Focused model and UI regressions cover the custom phrase and resulting confirmation state.

Verification:

- Fix commit: Working tree after `34b9d02`
- Verified by: Focused app unit and UI regression tests
- Verified on: Xcode 27 beta / iOS 27 test targets (automated only)
- Result: Both focused regressions pass; manual original reproduction pending

### UI-014 — Explicit egg quantity can collapse to one unknown USDA serving

- Severity: S1 — Major
- Status: Ready to verify
- Owner: Quantity/USDA portions sub-agent
- Found in: Working tree after `34b9d02`, source and interaction review
- Area: Log / Foundation Models / USDA
- Evidence: User report for `Two large scrambled eggs`; deterministic regressions added

Reproduction:

1. Enter `Two large scrambled eggs` on the Log screen.
2. Choose the USDA scrambled-egg result.
3. Inspect the resolved amount and nutrition.

Expected:

The explicit count survives interpretation, and the resolver uses USDA's matching `large egg` portion row. If the available portions do not identify a safe size, the app asks rather than guessing.

Actual:

If the on-device model omitted the quantity, the app could default to `1 serving`. USDA details also exposed several portion rows while the app retained only one preferred serving, so `large egg` could be ignored in favor of an unrelated or unspecified amount.

Notes:

The app now conservatively recovers simple explicit quantities from the original text, refuses the one-serving default when unrecovered amount evidence remains, preserves all USDA portion rows, and matches count, unit, and size qualifiers. Ambiguous materially different sizes require clarification. Core, app-integration, and parser-evaluation regressions cover this path.

Verification:

- Fix commit: Working tree
- Verified by: Core and app integration tests
- Verified on: Xcode 27 beta / iOS 27 test target (automated only)
- Result: Automated regressions pass; original on-device-model walkthrough pending

### UI-015 — Foundation Models parsing fails when the selected model lacks reasoning

- Severity: S1 — Major
- Status: Ready to verify
- Owner: Foundation Models parser sub-agent
- Found in: Working tree, macOS 27 LoggingEval production/general run
- Area: Log / Foundation Models
- Evidence: Five evaluator parses failed with `The selected model does not support reasoning`

Reproduction:

1. Run LoggingEval with the real system model using the production prompt and general use case.
2. Parse any valid food description.
3. Observe the generation failure before structured food output is returned.

Expected:

The parser requests model features supported by the selected model and returns a
structured food interpretation.

Actual:

The app and evaluator unconditionally requested `.light` reasoning. The current
general system model does not advertise reasoning support, so every request failed.

Notes:

Both parsers now query `model.capabilities.contains(.reasoning)`. They request
`.light` only for a capable model and omit the reasoning level otherwise. The
evaluator continues recording response usage and reasoning-token metrics. A
deterministic policy test and evaluator source-parity assertions cover the gate.

Verification:

- Fix commit: Working tree
- Verified by: Deterministic app unit test and evaluator parity/build tests
- Verified on: Xcode 27 beta SDK / macOS 27 build
- Result: Automated compatibility gate passes; original real-model reproduction pending

### UI-016 — Manual Entry emits an invalid-frame warning during keyboard focus

- Severity: S3 — Minor
- Status: Open
- Owner: Unassigned
- Found in: Working tree, Xcode 27 beta / iOS 27, iPhone 17 Pro Simulator
- Area: Manual Entry / Keyboard
- Evidence: `/tmp/justlogit-hybrid-steeled-ui-final.log`

Reproduction:

1. Open **Manual Entry** on the iPhone 17 Pro Simulator.
2. Focus the food-name field, then move through the numeric fields with the keyboard visible.
3. Inspect the UI-test diagnostics.

Expected:

The form lays out and scrolls without geometry diagnostics.

Actual:

XCTest reports `Invalid frame dimension (negative or non-finite).` while the form is focusing or
scrolling a field. The complete interaction still succeeds, and no visual or hit-testing failure has
been reproduced. The warning occurs in both the normal validation and forced-volatile-store paths.

Notes:

The app contains no explicit negative frame calculation in `ManualEntryView`; this may be an iOS 27
SwiftUI Form/keyboard-toolbar or XCTest scrolling issue. Keep it open until an Instruments/layout
trace or a later SDK confirms the source. Do not suppress the diagnostic without understanding it.

Verification:

- Fix commit:
- Verified by: Complete 19-case UI suite (behavior passes; warning remains)
- Verified on: Xcode 27 beta / iOS 27, iPhone 17 Pro Simulator
- Result: User flow passes; diagnostic remains open

## Bug template

Copy this block beneath **Open bugs**. Give each bug a stable sequential ID such as `UI-001`; never reuse an ID.

```markdown
### UI-000 — Concise user-visible failure

- Severity: S0 / S1 / S2 / S3
- Status: Open
- Owner: Unassigned
- Found in: commit, Xcode/iOS build, simulator/device
- Area: Log / USDA / Manual Entry / Entries / Settings / HealthKit / Accessibility
- Evidence: screenshot, video, console, or none

Reproduction:

1. Start from a stated app/data/permission state.
2. Perform exact taps, typing, navigation, and timing.
3. Observe the failure.

Expected:

Describe what the user should see and what data should change or remain unchanged.

Actual:

Describe the visible behavior and any data/state impact. Quote exact UI text when relevant.

Notes:

Record frequency, workaround, suspected boundary, and related bug IDs without guessing a root cause.

Verification:

- Fix commit:
- Verified by:
- Verified on:
- Result:
```

## Fixed bugs

Move an item here only after manual verification of its original reproduction steps. Preserve its complete history, including owner, fix commit, verification environment, and evidence.

No fixed bugs logged yet.

## Test-run history

Add one row for every complete or aborted run of [`ManualAcceptanceTest.md`](ManualAcceptanceTest.md).

| Date | Commit | iOS / device | Result | Bugs opened | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-07-12 | `bc9d067` | iOS 27 / iPhone 17 Pro Simulator | Fail | UI-001–UI-007 | Partial user walkthrough and source audit; not a complete acceptance run |
| 2026-07-16 | Working tree | iOS 27 / iPhone 17 Pro Simulator | Pass (19/19) | UI-016 | Complete automated interaction suite, including grounded-approximation and unsafe-amount hybrid recovery; the known non-failing Manual Entry geometry warning remains |
| 2026-07-17 | Working tree | iOS 27 / iPhone 17 Pro Simulator | Pass (19/19 across focused reruns) | None | Initial full-suite attempt completed 15 passes and exposed one XCUI dropped-terminal-character failure before Xcode beta's Simulator runner hung; exact-value delivery hardening made the Manual Entry rerun pass, and the three unlaunched scenarios passed separately. UI-016's non-visible framework warning remains open. |
| 2026-07-17 | Working tree, corpus 1.3.0 | iOS 27 / iPhone 17 Pro Simulator | Pass (19/19) | None | One uninterrupted automated test process passed after post-policy terminal-route integration. Xcode beta hung only while finalizing the already-complete result and was terminated afterward. UI-016's non-visible framework warning remains open. |
