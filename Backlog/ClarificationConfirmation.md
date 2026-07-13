# P2 — Clarification and confirmation engine

## Outcome

Create one input-agnostic decision layer that turns uncertain text, future photo observations, recognized foods, and composite drafts into a user-confirmed `ParsedFoodRequest` before USDA lookup or nutrition calculation.

This foundation should ship before photo-assisted identification. Adding another probabilistic input without a consistent correction path would make uncertainty harder to see and errors easier to save.

## Draft contract

The engine accepts evidence plus a proposed interpretation; it does not own Foundation Models, camera, USDA, or persistence.

- Evidence source: typed text, photo-derived observation, remembered food, or explicit user edit
- Proposed food identity, optional brand, preparation, descriptors, quantity, unit, container/fraction facts, and possible component foods
- Field-level provenance: directly stated, visually observed, deterministic derivation, selected USDA record, remembered value, or user-confirmed
- Field-level confidence: `confirmed`, `high`, `uncertain`, or `unknown`
- Explicit ambiguity codes such as missing quantity, conflicting units, multiple foods, uncertain brand, uncertain preparation, hidden ingredient question, or no plausible identity
- Deterministic validation findings kept separate from model confidence

Do not treat a model-generated numeric probability as calibrated truth. Confidence should be derived from observable evidence and validation rules, and only explicit user confirmation moves a field to `confirmed`.

## Question policy

Ask only a question whose answer can materially change USDA selection, portion calculation, component structure, or whether the entry is safe to save.

1. Resolve food identity or multiple-food boundaries.
2. Resolve quantity and unit/container contradictions.
3. Resolve preparation, brand, or component facts only when they materially affect matching or nutrition.

Prefer one targeted question with suggested answers and an **Edit manually** path. Preserve free-form entry for answers that do not fit the choices. Never ask the user to confirm facts they already stated unambiguously.

Limit automatic clarification to two follow-up turns per draft. After two unresolved turns, offer direct field editing, manual nutrition, a simpler USDA search, or cancellation. Do not loop, silently choose, or degrade into a confident-looking guess.

## Confirmation and editing UX

- Show a compact summary of the proposed food and amount, with uncertain fields called out in plain language.
- For photos, identify the proposal as an observation rather than a fact: **This looks like…**.
- Let the user select a suggestion, type a replacement, adjust quantity/unit, split or combine foods, and remove a proposed component.
- Require explicit confirmation before USDA search when identity is uncertain or multiple foods are proposed; otherwise allow the existing candidate/review flow to be the confirmation boundary.
- Announce each question and validation error to VoiceOver without rereading the whole transcript.
- Maintain logical focus order, 44-point targets, Dynamic Type layouts, hardware-keyboard submit/cancel, Reduce Motion, and non-color uncertainty cues.

## Deterministic gates

Before USDA or nutrition work:

- Require a nonempty food identity or an explicit manual-entry choice.
- Reject nonfinite, zero, and negative quantities.
- Normalize locale-aware numbers and known units without inventing conversions.
- Validate fraction/container relationships and preserve both values.
- Prevent contradictory units from being combined without a user choice.
- Require explicit component boundaries for composite aggregation.
- Ground brands, quantities, and descriptors in the supplied evidence or user edits.

The model may propose. Deterministic code validates and routes. The user resolves material ambiguity.

## Persistence and privacy boundaries

- Clarification drafts, questions, candidate answers, confidence, and photo-derived observations are transient.
- Do not write a food-log entry, recognized food, remembered composite, or HealthKit sample until final confirmation.
- Do not persist an original photo by default. A confirmed entry may retain source type and concise user-approved description, not model reasoning or an internal conversation transcript.
- Cancellation discards the draft. App termination may restore only a minimal local draft if the user has opted into draft restoration; never sync it to a backend.
- Performance/diagnostic logs contain state names and durations only, never evidence content.

## Phased implementation

### Phase 1 — Typed state and validators

- Define evidence, provenance, confidence, ambiguity, question, answer, and confirmed-request types.
- Move quantity/unit/container grounding and locale validation behind a reusable validator.
- Add a deterministic policy that decides confirm, clarify, edit, or fallback.

### Phase 2 — Text integration

- Route current Foundation Models output through the engine.
- Replace one-off clarification states with generic question/answer state while preserving USDA and manual fallbacks.
- Instrument clarification count, abandonment, and correction locally in test builds only; add no analytics.

### Phase 3 — Composite and photo adapters

- Accept component proposals and photo observations through the same contract.
- Keep source-specific parsing outside the engine.

### Phase 4 — Accessibility and resilience

- Verify relaunch/cancellation, stale async results, VoiceOver announcements, Dynamic Type, locale input, offline USDA, model-unavailable, and maximum-turn fallback.

## Tests

- Policy table tests for each ambiguity and confidence combination
- No-question cases for complete, grounded text
- Targeted question selection and priority tests
- Two-turn maximum and deterministic fallback tests
- Locale quantity, fraction/container, conflicting unit, and invalid numeric tests
- Text/photo parity tests that produce the same confirmed request from equivalent evidence
- User edit overriding every model-proposed field and provenance update tests
- Cancellation, stale-response, restoration, and no-persistence-before-confirmation tests
- VoiceOver labels/order and Dynamic Type UI tests for questions, choices, errors, and edit controls

## Activation criteria

- Existing text logging accuracy does not regress across the parsing corpus.
- Every known material ambiguity has an edit or fallback path and no automated loop exceeds two turns.
- Deterministic validation prevents USDA/nutrition work on invalid or contradictory quantities.
- User tests show the questions are understood and materially reduce incorrect selections without unacceptable logging abandonment.
- Accessibility and privacy review passes before this becomes a dependency for photo input.
