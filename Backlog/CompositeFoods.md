# P2 — Composite foods and ingredients

## Outcome

Represent a logged dish as either one authoritative food record or a confirmed collection of ingredient/component snapshots. Support fried eggs plus explicit cooking fat, sandwiches, salads, recipes, and restaurant dishes without silently inventing hidden ingredients or amounts.

## Core rules

- A component exists only when the user stated, selected, or confirmed it, or when an authoritative single prepared-food record represents the whole dish without decomposition.
- Never add oil, butter, dressing, sauce, bread, cheese, condiments, fillings, or recipe quantities merely because they are common.
- Preserve uncertainty and ask a targeted question when a missing component can materially change nutrition. Let the user omit it explicitly.
- Nutrition always comes from confirmed USDA/manual snapshots and deterministic arithmetic, never from a language or image model.
- A composite is reviewed as one log action; its components remain inspectable and editable before confirmation.

## One record versus decomposition

Prefer one authoritative USDA prepared-food record when:

- It closely matches the stated dish, preparation, brand/restaurant item, and serving basis.
- The user did not provide ingredient quantities that should override the prepared record.
- Decomposition would require guessing hidden components or would imply false precision.
- The record is the product the user recognizes, such as an exact packaged item or restaurant listing.

Prefer decomposition when:

- The user explicitly lists components or builds a recipe/sandwich/salad.
- Component quantities are known or can be confirmed with a bounded clarification.
- No credible whole-dish USDA record exists, or the available record materially conflicts with the described ingredients.
- The person needs to edit, omit, substitute, or reuse components independently.

If both approaches are plausible, show the consequence plainly: **Use one prepared-food match** or **Build from ingredients**. Do not mix a whole-dish record with its children, which would double-count nutrition.

## Proposed model

### Composite draft

- Local draft ID and user-facing name
- Source evidence: text, photo observation, remembered composite, recipe/manual edit, or USDA prepared-food choice
- Components in explicit display/order sequence
- Draft-level ambiguity and confirmation state
- Optional consumed multiplier for scaling a remembered recipe

### Component

- Stable local component ID and optional parent ID
- Confirmed display name and quantity/resolution
- Provenance for identity and quantity: user-stated, user-confirmed, USDA selection, manual, remembered, or deterministic derivation
- Confidence/ambiguity from the clarification engine; only confirmed components may be saved
- Immutable nutrition snapshot, calculation basis, source/FDC metadata, and component-level approximation flag
- Optional child components within the nesting limits

Do not store model reasoning. Provenance describes the evidence boundary, not a chain-of-thought explanation.

## Nesting and scale limits

- Support at most two composite levels below the logged root; flatten deeper imported/remembered recipes for review.
- Limit a confirmed log to 20 leaf components. Above that, require grouping, a whole-dish record, or manual aggregate nutrition.
- Prevent cycles in remembered composite references.
- Aggregation traverses leaves exactly once. A node with its own aggregate nutrition cannot also contribute child nutrition.
- Scale quantities through one explicit root multiplier; preserve original component snapshots and record the applied multiplier.

## Confirmation and editing UX

- Present the dish name, total amount, and an ordered ingredient list with quantity, source, and uncertainty cues.
- Allow add, remove, rename, replace USDA match, switch prepared-record/decomposed mode, edit quantity, and mark a component intentionally omitted.
- Ask about hidden ingredients only when material and bounded: for **fried eggs**, ask whether to include cooking fat rather than adding a default tablespoon of butter.
- Make totals update deterministically after each edit and label approximate totals.
- Require explicit final confirmation. Cancellation leaves no entry or HealthKit write.
- At large Dynamic Type and with VoiceOver, each component exposes name, amount, calories where available, uncertainty, edit, reorder, and remove actions in a stable order.

## Nutrition aggregation

1. Resolve each leaf against its confirmed USDA/manual snapshot and consumed quantity.
2. Normalize nutrient keys/units through `JustLogItCore`.
3. Sum like nutrients with decimal-safe deterministic arithmetic and reject nonfinite/negative values.
4. Distinguish zero from unavailable; a missing nutrient in one component must not be represented as a known zero.
5. Retain both leaf snapshots and the computed root snapshot so history does not change when USDA or a remembered recipe changes.
6. Recompute only while editing a draft or creating an explicit new entry version.

## Remembered composites

- A confirmed composite may be saved as a local reusable template only through an explicit action.
- Templates retain component identities, baseline quantities, provenance, and nutrition snapshots plus a schema/version number.
- Reusing a template creates a new draft; it never logs immediately. The user can scale, substitute, remove, or refresh a USDA component before confirmation.
- Editing a template does not mutate historical entries. Updating a template creates a new template version or explicitly replaces the reusable definition.
- Forgetting a template never deletes entry history.

## HealthKit

Write one HealthKit food correlation for the confirmed root, containing the aggregated supported nutrient samples. Do not write child correlations or child dietary samples separately, which would double-count the same meal.

Keep component detail in JustLogIt only. Use the root entry’s existing stable sync identifier/version. Edits create the same compensating replacement workflow planned for normal entry editing; component changes must not produce partial HealthKit updates.

## Persistence and migration

- Add versioned composite-entry and component-snapshot storage without changing the meaning of existing single-food entries.
- Existing records migrate as root entries with no children; do not synthesize a one-item component unless a future query/API requires it.
- Enforce parent ownership, stable ordering, depth/leaf limits, no cycles, and delete cascades locally.
- Store the root aggregate snapshot alongside child snapshots and an aggregation-version identifier.
- A failed migration preserves readable single-food history and disables composite editing rather than deleting or recomputing entries.
- Composite drafts remain transient until confirmation; photo data and clarification transcripts are not persisted with the entry.

## Phased implementation

### Phase 1 — Domain and arithmetic

- Define draft/component/provenance/snapshot types in `JustLogItCore`.
- Implement validation, depth/cycle limits, scaling, missing-nutrient semantics, and aggregation tests.

### Phase 2 — Persistence and entry detail

- Add versioned SwiftData models/migration and read-only component display for seeded fixtures.
- Keep existing single-entry paths unchanged.

### Phase 3 — Text creation and editing

- Integrate the clarification engine for explicit multi-food text and material hidden-ingredient questions.
- Add prepared-record versus ingredients choice and full component editor.

### Phase 4 — Remembered composites and photo adapter

- Add reusable templates, scaling/substitution, and later accept confirmed photo component proposals.
- Add aggregate-only HealthKit write/reconciliation.

## Tests

- Prepared-record/decompose policy table, including exact branded, restaurant, generic recipe, and insufficient-evidence cases
- Fried eggs with explicit fat, fat omitted, and fat question declined; no default ingredient may appear
- Sandwich, salad, recipe scaling, and mixed-unit component fixtures
- Depth, 20-leaf, cycle, double-counting, aggregate-node/child exclusivity, and overflow tests
- Missing-versus-zero nutrient semantics and deterministic aggregation across all nutrient keys
- Snapshot immutability after USDA/template changes and template version/reuse tests
- SwiftData migration, cascade, ordering, rollback, corrupt-depth, and existing single-entry compatibility tests
- HealthKit test proving one root correlation and no child writes
- User edit/cancel, VoiceOver, Dynamic Type, reorder, destructive confirmation, and stale async response UI tests

## MVP activation criteria

- Real user logs show meaningful demand for multi-component dishes that cannot be served safely by one prepared-food record or separate entries.
- Clarification and confirmation engine is stable; single-food logging and USDA accuracy remain the priority until then.
- Component aggregation, persistence migration, and aggregate-only HealthKit behavior have deterministic test coverage.
- A usability pass shows people understand prepared-record versus ingredient-built totals and can correct every component before saving.
- No tested prompt or photo fixture silently creates a hidden ingredient or amount.
- Median composite completion time and abandonment remain acceptable compared with logging components separately; thresholds are set during the product spike.
