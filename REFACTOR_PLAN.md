# Refactor Plan — whale-file decomposition

Status: planned. Branch `fix/recover-overhaul-green` (green baseline already committed).
Goal: split the oversized files into cohesive, concern-based files **without changing behavior**,
keep the suite green, then push.

## Principles

- **Extension splits, not re-architecture.** `LogViewModel` is one cohesive `@MainActor` async
  state machine (shared `@Published` state + a `generation` cancellation token). Split the *file*
  via `extension LogViewModel { }` across multiple files — do **not** break the type into separate
  service objects. That would add indirection and cross-object state passing without reducing
  complexity.
- **Behavior-preserving.** Every changed line traces to "moved code," not "improved code." No
  drive-by edits to adjacent logic, comments, or formatting.
- **Access-level cost:** Swift `private` members are file-scoped. Moving methods that touch them
  into another file requires promoting the shared state/helpers from `private` → module-`internal`
  (default). Keep everything `internal` at most — do not make anything `public`.
- **Verify after each pass:** `swift test` (Core) and/or
  `xcodebuild test -scheme JustLogIt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:JustLogItTests`.
  Run UI tests only after LogView/flow changes. Keep the tree buildable at every commit.
- **pbxproj:** app target uses **classic manual** registration (not synchronized groups). Each new
  *app-target* file needs 4 pbxproj entries — use the `pbxadd.py` helper pattern (PBXBuildFile,
  PBXFileReference, Log/Entries group child, app Sources build-phase entry). **Core-package files
  need no pbxproj edits** (SPM auto-discovers).

## Targets (current sizes)

| File | Lines | Plan |
|---|---|---|
| `LogViewModel.swift` | 1240 | Split into core + concern extensions; move pure helpers to Core |
| `LogView.swift` | 1194 | Extract remaining subviews into files (WIP already pulled 3 out) |
| `EntriesView.swift` | 650 | Separate view from grouping/formatting logic |

---

## Pass 1 — Mechanical, zero-risk (do first)

1. `ConversationTurn` enum → `ConversationTurn.swift` (pure model, no VM deps).
2. `MockFoodDataProvider` (bottom of LogViewModel.swift) + `MockFoodParser` (bottom of
   FoundationModelsFoodParser.swift) → one `LogTestingDoubles.swift`. These are `-ui-testing`
   doubles that shouldn't live in shipping source files. Requires promoting
   `MockFoodDataProvider` from `private` → `internal`.

New app-target files → register via pbxadd. **Verify:** unit build+test.

## Pass 2 — Pure helpers to Core (no pbxproj)

3. `LogViewModel.clarificationParseInput(...)` (static, pure string/prompt builder, lines ~308–333)
   → move into `JustLogItCore` (e.g. `ClarificationPromptBuilder`), add a focused unit test there.
   Update the one call site in `submitClarificationAnswer`.

**Verify:** `swift test` in Core + unit build+test.

## Pass 3 — LogViewModel extension splits

Promote the shared `private` stored state and small helpers to `internal`, then move method groups
to `extension LogViewModel` files. Suggested grouping (by the MARKs/concerns already present):

- `LogViewModel.swift` — stored props, `Stage`/`FailureKind` enums, `init`/`deinit`, public entry
  points (`submit`, `proposeFromImage`, `editUserMessage`, `reset`, `cancel`), and the
  operation-generation helpers (`beginOperation`/`invalidateOperation`/`isCurrentOperation`,
  `appendUserTurn`/`appendSystemTurn`, `clearPipelineState`).
- `LogViewModel+Interpretation.swift` — `submitFlow`, `clarificationReparseFlow`,
  `runInterpretation`, `imageProposalFlow`, `routeInterpretationDecision`.
- `LogViewModel+Search.swift` — `searchManually`, `select`, `runSearch`, `manualSearchFlow`,
  `search`, `selectionFlow`, plus the `FoodSearchProvider`/details conformance if present.
- `LogViewModel+Clarification.swift` — `submitClarificationAnswer`,
  `chooseClarificationSuggestion`, `presentInterpretationClarification`,
  `clearInterpretationClarification`, `canSubmit…`/`canResolve…`.
- `LogViewModel+Quantity.swift` — `resolveWithServings/Grams`, `resolveQuantityEntry`,
  `applyQuantitySuggestion`, `apply(_:)`, `presentQuantityClarification`.
- `LogViewModel+Composite.swift` — `beginCompositeSession`, `advanceCompositeQueue`,
  `finishCompositeAssembly`, `commitCompositeComponentIfNeeded`, `setCompositeComponents`,
  `clearCompositeSession`.
- `LogViewModel+Review.swift` — `continueFromReview`, `presentReview`,
  `refreshConsumedAtInference`, when-eaten (`submitWhenEaten`, `applyWhenEatenSuggestion`,
  `whenEatenSuggestionChips`), save (`makeRecord`, `markSaved*`, `loggingSourceText`,
  `rememberConfirmedSelectionIfPossible`).

Do this in **2–3 sub-commits** (e.g. Interpretation+Search, then Clarification+Quantity, then
Composite+Review), building after each so a compile error is easy to localize. Register each new
file via pbxadd. **Verify:** unit build+test after each sub-commit.

## Pass 4 — LogView subview extraction

Extract the remaining large subviews out of `LogView.swift` into files (mirroring the WIP that
already pulled `ChatComponents`/`FoodResultViews`/`CameraImagePicker`). Candidates:
`nutritionReviewCard`, `confirmationCard`, `recoveryCard`, the composer, and the manual-search
section — as `private` subviews in `extension LogView` files or small dedicated `View` structs.
Keep all `accessibilityIdentifier`s and rendered text **identical** (UI tests assert exact strings
like "Here's what I'll log", "Confirm this log?", "Couldn't read that", "recovery-title",
"usda-result-…"). **Verify:** unit build + **UI suite** (run twice — it must stay re-runnable).

## Pass 5 — EntriesView

Separate presentation from logic: move grouping/section/date-formatting helpers into their own
type/file (Core if pure), leave `EntriesView` as the view. **Verify:** unit build+test.

## Finish

- Full green: `swift test` (Core) + `JustLogItTests` + `JustLogItUITests` (twice).
- Remove this plan file (or keep if useful) before the final push, per preference.
- Push `fix/recover-overhaul-green` to origin.

## Explicitly NOT doing

- Re-architecting the state machine into service objects.
- "Improving" adjacent code, error handling, or the disciplined-but-long services
  (`USDAFoodDataProvider`, etc.) that are cohesive, not cruft.
