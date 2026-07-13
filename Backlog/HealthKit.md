# P2 — HealthKit

## Current status

- [x] Deferred authorization behind an explicit Settings toggle
- [x] Write-only food correlation with every supported USDA nutrient
- [x] Local-first saves with pending, synced, denied, and failed states
- [x] Stable per-entry and per-nutrient sync identifiers
- [x] Added sugar retained locally rather than double-counted as total sugar
- [ ] Reconciliation after relaunch for pending writes
- [ ] Compensating HealthKit deletion when a synced entry is deleted
- [ ] Versioned replacement workflow when entry editing ships
- [ ] Physical-device acceptance test of the system permission sheet

## Outcome

Optionally write confirmed nutrition to Apple Health without making HealthKit a dependency of local logging.

- Deferred authorization at first enabled write
- Food `HKCorrelation` with supported dietary samples
- Stable sync identifier and incrementing version
- Local-first save with pending, synced, denied, and failed states
- Compensating edit/delete workflow for app-owned samples
- Retry and reconciliation tests
- HealthKit-specific privacy and purpose text review
