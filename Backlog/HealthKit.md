# P2 — HealthKit

## Outcome

Optionally write confirmed nutrition to Apple Health without making HealthKit a dependency of local logging.

- Deferred authorization at first enabled write
- Food `HKCorrelation` with supported dietary samples
- Stable sync identifier and incrementing version
- Local-first save with pending, synced, denied, and failed states
- Compensating edit/delete workflow for app-owned samples
- Retry and reconciliation tests
- HealthKit-specific privacy and purpose text review
