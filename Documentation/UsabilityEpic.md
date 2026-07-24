# Usability epic — task DAG

Status key: `[ ]` open · `[~]` in progress · `[x]` done

## P0 — Crash / correctness

1. [x] Diagnose Apple Health crash (SIGABRT on `requestAuthorization` via `_throwIfAuthorizationDisallowedForSharing`)
2. [x] Catch/disallow-safe HealthKit authorization + softer unit mapping (no `preconditionFailure`)
3. [x] Tests for authorization failure → user-visible error, no crash

## P1 — Chat logging UX

4. [ ] Conversation transcript model (user turns + system turns) with stable IDs
5. [ ] Edit user message → rewind transcript from that turn and re-run flow
6. [ ] “When did you eat?” stage with suggestions Just now / An hour ago / freeform → `consumedAt`
7. [ ] Explicit confirm before save (no auto-save from review alone)
8. [ ] After save: tappable links to log entry + recognized food

## P1 — Entries dual model

9. [ ] `RecognizedFoodRecord` SwiftData model (food identity, FDC, recency)
10. [ ] Entries tab: segment Foods | Logs (or sections); logs navigate to entry detail; foods to food detail
11. [ ] Populate recognized food on confirmed USDA/manual save

## P1 — Composites

12. [ ] Core composite draft types (components, aggregate nutrients)
13. [ ] Policy/parser multi-food → multi-component draft (no silent hidden ingredients)
14. [ ] Save composite log entry linking component foods; Entries show composite logs

## P2 — Image

15. [ ] PhotosPicker + optional camera affordance on Log composer
16. [ ] Foundation Models image attachment adapter (availability-gated)
17. [ ] Map photo proposal → clarification engine (`.photoObservation`); never invent nutrition

## P2 — Mac evaluation harness

18. [ ] Command-line / package tool: parse (FM if available) → USDA search → pick first → serving sanity checks
19. [ ] Document run instructions; keep secrets out of repo

## Verification

20. [ ] Core tests green; focused app tests; build-for-testing; secret scan
21. [ ] UIBugs: leave Fixed only after manual repro (do not mark Fixed from unit tests)
