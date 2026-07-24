# Spike C — Quick Log Food (confirmation UI requirements)

**Status:** design / stub only
**Related:** [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md), [`Backlog/SiriAIIntegration.md`](../Backlog/SiriAIIntegration.md)
**Code stub:** `JustLogIt/AppIntents/QuickLogFoodIntent.swift`
**Blocked on:** Spike B — shared headless `FoodLoggingWorkflow`

## Purpose

Spike C is the **confirm-and-save in Siri** path for a narrow set of fully resolved single-food requests. It must not create a second nutrition pipeline or weaken USDA, serving, persistence, HealthKit, privacy, or confirmation rules.

Today the stub always continues to the same foreground path as `StartFoodLogIntent` (`SiriFoodLogCoordinator.beginLog` → reviewed Log tab). It is **not discoverable** and is **not** registered in `JustLogItShortcuts`.

## Product rules (non-negotiable)

1. **No silent nutrition creation.** Food interpretation, USDA identity, and serving conversion can change calories and macros materially. Persistence requires an explicit person confirmation that shows the proposed result.
2. **JustLogIt is authoritative for nutrition.** Siri supplies user-authored food text and optional consumed time only. Never treat model- or Siri-supplied nutrient numbers as ground truth.
3. **One local save after confirmation.** Cancellation before commit creates no entry. Retries must not double-save (idempotency / repository transaction).
4. **HealthKit stays downstream.** Optional, already-enabled, non-interactive sync after local save. A Siri invocation must not present Health authorization.
5. **Ambiguity continues in the app** with all captured input preserved (original text, inferred time, any completed workflow work).

## When in-Siri completion is allowed

Only when the shared workflow returns a single safe interpretation, roughly:

| Gate | Requirement |
|------|-------------|
| Structure | One food, not a composite meal (composite voice path is later) |
| Quantity | Explicit or safely resolved; no outstanding `ClarificationPolicy` question |
| Identity | One remembered or uniquely high-confidence USDA match |
| Details | Usable USDA details + serving math |
| Consent | Explicit confirmation after nutrition preview |

Everything else → foreground continuation (same as Spike A handoff).

Typical continue-in-app cases: composite meals, missing amounts, close USDA choices, photo input, manual nutrition, parser/model unavailability, network/service failures.

## Typed workflow outcomes (Spike B contract)

`QuickLogFoodIntent` must not reimplement parse/search/save. It adapts `FoodLoggingWorkflow` outcomes:

```text
readyForConfirmation -> show food, amount, time, calories/macros (+ approximation if needed)
                     -> requestConfirmation
                     -> save once via FoodLogRepository
needsClarification   -> one bounded Siri question, or continue in JustLogIt
needsFoodChoice      -> small USDA choice list in Siri, or continue in JustLogIt
cannotComplete       -> short explanation + continue in JustLogIt with input preserved
```

## Confirmation UI requirements (Siri / App Intents)

### Content the person must hear or see before “Yes”

The confirmation surface is the product safety boundary. It must include:

1. **Resolved food display name** (USDA-grounded description the app would save, not only the raw utterance).
2. **Amount / serving** (quantity + unit or household measure as resolved).
3. **Consumed time** (explicit parameter or “now” / inferred display).
4. **Energy and macros** at minimum: calories, protein, carbohydrate, fat (same formatting rules as in-app review).
5. **Approximation disclosure** when the result is approximate (volatile units, estimated quantity, etc.) — same policy as the in-app confirmation card.
6. A clear **confirm / cancel** choice (App Intent `requestConfirmation` or equivalent). Cancel leaves no local or Health record.

Example shape (illustrative):

> “I found 2 large hard-boiled eggs, eaten now. That’s approximately 155 calories, 13 g protein. Log it?”

Do **not** dump every USDA implementation detail (FDC id, full nutrient panel) into the spoken dialog. Keep confirmation concise; details remain available in the app.

### Interaction constraints

- Prefer **one request + one confirmation** for the happy path.
- At most **one bounded clarification** in Siri before continuing in-app (e.g. bacon brand vs regular cooked).
- Check **Task cancellation** between parse, search, details, confirmation, and save.
- Prefer **foreground early** over long-running background execution; measure model + USDA latency before considering extended execution APIs.
- Support **VoiceOver** and Dynamic Type for any visual confirmation UI Shortcuts may show; keep spoken dialog short enough for VoiceOver / Siri speech.

### What confirmation must never do

- Save on “ready” without a yes/confirm step.
- Auto-select among close USDA matches.
- Authorize HealthKit or change Health preferences.
- Persist partial drafts, recognized-food updates, or Health samples before final confirm.
- Claim the log is complete if only the app was opened for review.

## Stub vs future implementation

| Layer | Stub (now) | Spike C complete |
|-------|------------|------------------|
| Discoverability | `isDiscoverable = false` | Enable only when confirmation path is real; phrases carefully chosen so they don’t collide with Start Food Log unless intentional |
| App Shortcuts | Not in `JustLogItShortcuts` | Optional dedicated phrases after UAT; Start Food Log remains the dependable default |
| `perform()` | `beginLog` + review dialog | Workflow → confirm → save **or** `beginLog` continuation |
| Persistence | None | `FoodLogRepository` once after confirm |
| Donation | N/A (no save) | Same donation path as in-app successful log |

Stub dialog (current):

> “I'll open JustLogIt so you can review nutrition before saving.”

## Implementation checklist (when unblocked)

- [ ] Spike B: `FoodLoggingWorkflow` + typed outcomes; `LogViewModel` is a thin adapter
- [ ] Shared repository transaction used by UI and intent
- [ ] `QuickLogFoodIntent` maps outcomes to dialog / confirmation / foreground handoff
- [ ] Unit tests: unambiguous ready path, declined confirmation, cancellation mid-flight, no double-save
- [ ] Integration / device: Siri confirm, VoiceOver, cold launch, offline USDA, Foundation Models unavailable
- [ ] Set `isDiscoverable` and shortcuts only after real-device UAT
- [ ] Update privacy / App Store copy only when hands-free confirm actually ships

## Exit gate

No silent nutrition creation, no Siri/model-authored nutrition, no duplicate save, and no loss of the original request during foreground continuation.
