# P0 — MVP

## Product hypothesis

A person can describe one food naturally, identify the correct USDA match, resolve its quantity confidently, and save an accurate entry with less friction than conventional food logging.

## Required

- [x] iOS 27 SwiftUI application with Log, Entries, and Settings tabs
- [x] On-device Foundation Models parser using `@Generable` and `@Guide`
- [x] Clear model-unavailable and manual-search paths
- [x] Deterministic normalized USDA query construction
- [x] Explicit-submit USDA search; never search per keystroke
- [x] User chooses a USDA result; never silently select one
- [x] Food details fetched after selection
- [x] Deterministic mass, serving, count, and whole-fraction resolution
- [x] Focused clarification when quantity cannot be resolved
- [x] Nutrition review before saving
- [x] Manual nutrition entry
- [x] SwiftData entry snapshots that survive source-data changes
- [x] Entries list, detail, search, and deletion
- [x] Local search/detail cache
- [x] Minimal credential-shielding Worker with no request persistence
- [x] Domain unit tests and a representative mocked UI journey
- [x] VoiceOver labels, Dynamic Type, dark mode, and keyboard usability

## Not required for MVP

- HealthKit
- Full USDA mirror or downloadable dataset
- Worker database cache
- Accounts, analytics, advertising, or CloudKit
- Multi-food resolution
- Barcode, OCR, or image recognition
- Export, App Attest, and sophisticated alias learning

## Exit criteria

The app builds with Xcode 27, runs on a physical iOS 27 phone, completes the primary logging flow without secrets in source, passes automated tests, and handles parser/network failure through a usable manual path.
