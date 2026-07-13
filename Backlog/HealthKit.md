# P2 — HealthKit

## Current status

- [x] Deferred authorization behind an explicit Settings toggle
- [x] Write-only food correlation with every supported USDA nutrient
- [x] Local-first saves with pending, synced, denied, and failed states
- [x] Stable per-entry and per-nutrient sync identifiers
- [x] Added sugar retained locally rather than double-counted as total sugar
- [x] Explicit retry action requests authorization only after the user taps it and returns visible recovery/Settings guidance
- [x] Bounded reconciliation on launch/foreground for pending and retryable failed writes
- [x] Compensating HealthKit deletion with durable tombstones and bounded retry
- [ ] Versioned replacement workflow when entry editing ships
- [ ] Physical-device acceptance test of the system permission sheet

## Outcome

Optionally write confirmed nutrition to Apple Health without making HealthKit a dependency of local logging.

- Deferred authorization from explicit Settings or retry actions
- Food `HKCorrelation` with supported dietary samples
- Stable sync identifier and incrementing version
- Local-first save with pending, synced, denied, and failed states
- Explicit Settings enablement and entry-detail retry authorization; background/local save never presents permission UI
- Compensating deletion workflow for app-owned samples; versioned replacement remains deferred
- Deterministic retry, reconciliation, backoff, and tombstone tests
- HealthKit-specific privacy and purpose text review
