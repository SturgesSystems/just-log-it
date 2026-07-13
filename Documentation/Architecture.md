# Architecture

JustLogIt separates probabilistic interpretation from deterministic nutrition work.

```text
SwiftUI feature state
        ↓
Application workflow
        ↓
Domain types and deterministic services
        ↓
Protocols
        ↓
Foundation Models / USDA / SwiftData implementations
```

The Foundation Model may identify food, brand, descriptors, and quantity language. It never supplies nutrition, ranks USDA records, selects a record, or performs persisted arithmetic.

After grounding, a deterministic `ClarificationPolicy` in JustLogItCore decides whether a draft may proceed to USDA search, needs a clarification question, requires edit, or falls back to manual entry. Empty identity and multi-food drafts never silently search. Missing quantity alone still proceeds because portion resolution happens after USDA selection via `ServingResolution`.

When the policy returns `.clarify`, `LogViewModel` enters `.awaitingClarification` with an `activeQuestion` and keeps a transient `FoodInterpretationDraft`. User freeform or suggested answers flow through `applyUserAnswer` and re-decision; only `.proceed` starts USDA search. Require-edit and fallback-manual still use the existing recovery card.

After a confirmed USDA save, `RememberedFoodCatalog` stores a normalized lookup signature → FDC ID mapping (UserDefaults). Later searches apply a bounded ranker boost for matching FDC IDs only; the person still chooses the match. Settings can clear remembered matches without deleting log entries.

`Packages/JustLogItCore` has no SwiftUI, SwiftData, FoundationModels, or HealthKit dependency and can be tested from Command Line Tools.

`HealthKitNutritionWriter` maps every supported USDA nutrient to its exact HealthKit dietary type and writes one food correlation. `HealthSyncCoordinator` keeps logging local-first and persists pending, synced, denied, failed, or deletion-pending state. Authorization is requested only from explicit user actions: enabling sync in Settings or tapping **Try Apple Health Again** for a denied/failed entry. Automatic entry saving and reconciliation never present permission UI, and the app requests write access only.

On launch and foreground activation, pending and retryable failed writes reconcile only while Health sync is enabled. Automatic retries use persisted bounded backoff. Deleting a synced entry first persists a tombstone containing its stable app-owned sync identity; the local entry remains until Health cleanup succeeds. Health deletion uses exact `HKMetadataKeySyncIdentifier` predicates for the correlation and nutrient samples, and HealthKit independently restricts deletion to objects saved by this app.

The Cloudflare Worker directory is a credential-shielding boundary with strict request validation, controlled outbound headers, no application cache/database of food queries, header-based USDA authentication (`X-Api-Key`), redirect rejection, JSON-only success responses, 2 MiB upstream body limits, and a fail-closed singleton Durable Object that stores only `{epochHour, count}` for a 900 requests/hour global USDA budget. It is not production infrastructure until it is deployed with an encrypted USDA secret and its Cloudflare logging, transforms, visitor metadata, privacy behavior, route/rollback, and operational limits are audited.

The disk food cache is disposable acceleration, never entry history. Cache decode/expiry failure falls through to the configured provider, and the user can clear it without deleting logs. Corruption, disk-pressure, and migration recovery still require launch-level testing.

DEBUG builds emit content-free signposts for Foundation Models availability, session creation, generation, deterministic mapping, and USDA search. Release builds contain no performance logger. See [`Performance.md`](Performance.md) for device measurement boundaries and thresholds.
