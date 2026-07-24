# Performance measurement

JustLogIt separates on-device interpretation latency from USDA lookup latency. Local OSLog and
signpost diagnostics contain only closed categories, bounded counts, and bounded durations; they
never accept the food description, generated content, search query, FDC ID, API key, URL, or
response body.

## Instrumented phases

The `LocalObservability` category and signpost stream contains these static names:

| Marker | Boundary | Expected character |
| --- | --- | --- |
| `bootstrap_first_frame` | Bootstrap loading chrome appears | One-shot; wall-clock from BootstrapRootView creation |
| `bootstrap_container_open` | Detached SwiftData `ModelContainer` open | Signposted interval; must not block MainActor |
| `bootstrap` (`store_category=…`) | Published store result | Closed category + total bootstrap duration |
| `bootstrap_interactive` | Root tab chrome appears after container ready | One-shot; perceived time-to-interactive |
| `health_reconciliation` | Deferred launch/foreground Health reconcile | Signposted; intentionally delayed after first interactive paint |
| `parser_availability` | Read `SystemLanguageModel.default.availability` | Synchronous and negligible |
| `parser_prewarm` / `hybrid_semantic_prewarm` | Observable `prewarm` request | Framework work is opaque and may be lazy |
| `parser_session_acquisition` / `hybrid_session_acquisition` | Acquire or construct an app session | This is not a model-loading measurement |
| `parser_response` / `hybrid_semantic_response` | Guided generation through receipt of structured content | Dominant on-device model cost |
| `deterministic_extraction` | Extract source-grounded syntax | CPU-only |
| `route_decision` | Select the typed interpretation route | CPU-only |
| `semantic_grounding_and_merge` | Ground the semantic proposal and merge protected deterministic facts | CPU-only; present only after a proposal |
| `usda_request_dispatch` | Submit-to-provider-call boundary | One-shot interaction milestone |
| `usda_search_pipeline` | Entire configured provider call, including cache/network/decode | Cache- and network-dependent |
| `first_actionable_ui` | Submit-to-first actionable view-model state | State publication, not a rendered-frame timestamp |

Operation intervals record `duration_ms` and only a closed success, failure, or cancellation
outcome. Phase and interaction durations are clamped to zero through ten minutes. Interaction
and bootstrap milestones are one-shot: composite loops, retries, and repeated state writes do not
duplicate them.

## Launch path (perceived performance)

Cold launch is designed so the system launch screen never waits on SwiftData, Health, or Foundation
Models.

1. **`JustLogItApp.init`** — registers App Intent / Siri handoff dependencies only. No store open.
2. **`BootstrapRootView` first frame** — lightweight `BootstrapLoadingView` (launch mark +
   `ProgressView` + “Starting…”). Emits `bootstrap_first_frame`.
3. **Container open** — `ModelContainerBootstrap` schedules work via `Task.detached` (priority
   `.userInitiated`). The open is measured with `bootstrap_container_open` and classified with
   `recordBootstrap` (`persistent` / volatile / testing / failed). Unit test
   `testBootstrapBuildDoesNotBlockMainActor` guards that the builder does not occupy MainActor.
   Do **not** move `ModelContainer` construction onto MainActor “just in case”; the detached path
   is measured and intentional. Do **not** reopen a second container for App Intents.
4. **Interactive chrome** — `RootTabView` appears; emits `bootstrap_interactive`.
5. **Health reconciliation** — delayed ~300 ms after `RootTabView` appears, then signposted as
   `health_reconciliation`. Correctness is unchanged: pending writes/deletions still run on launch
   and when returning to `.active`.
6. **Parser prewarm** — `LogView` starts prewarm in `.task` after a short yield (~250 ms). The
   pool already runs `session.prewarm` on a detached executor so it does not pin MainActor; the
   delay only keeps speculative ANE/CPU work off the first Log layout/keystroke. Interactive
   submit still bypasses an unfinished prewarm via `OneShotPreparedResourcePool.acquire`.

Working launch budgets (product thresholds, re-baseline from device samples):

| Phase | Target | Investigation threshold |
| --- | --- | --- |
| `bootstrap_first_frame` | p95 ≤ 100 ms from BootstrapRootView | p95 > 250 ms |
| `bootstrap_container_open` (warm store) | p95 ≤ 150 ms | p95 > 500 ms or MainActor hitch |
| `bootstrap_interactive` | p95 ≤ 400 ms from BootstrapRootView | p95 > 1 s with a healthy store |
| Launch Health reconcile | Completes after first interactive paint | Blocks typing or first tab switch |

Apple does not expose Foundation Models model-load duration or time-to-first-token through the APIs
used here. Do not derive or label either metric. Report the observable prewarm, session-acquisition,
and response intervals separately; model loading may occur inside any framework-owned interval.

## Why parsing may be slow

- The established production fallback has 22 generated fields. Its guides and type description add
  prompt/schema work even for a short food. The experimental hybrid proposer deliberately narrows
  this to six semantic fields; physical-device comparison must determine the actual benefit.
- `representNilExplicitlyInGeneratedContent` asks both schemas to represent absent optional fields
  instead of silently omitting them. That improves predictable decoding but can increase structured
  output for simple foods.
- `maximumResponseTokens` is 500 for the 22-field baseline and 192 for the six-field semantic
  proposer. These are upper bounds, not preallocated costs; they do not make every request consume
  the cap, but they bound pathological or unexpectedly verbose output differently.
- Greedy sampling and zero temperature improve determinism; they should not be assumed to produce a material latency reduction.
- A one-shot session may be prepared after the first Log render, deferred slightly so first layout
  and input are not contending with speculative prewarm. It is consumed by at most one food; later
  foods receive fresh sessions. Transcript-bearing sessions are never reused across logs, avoiding
  history leakage and cross-food contamination. The framework may still defer work until `respond`,
  which is why prewarm, session acquisition, and response are measured separately.
- The first request after reboot, model download/preparation, memory pressure, or model eviction can include model loading and compilation. Warm requests should be evaluated separately.
- Availability checking should be effectively free. `.modelNotReady` is a readiness result, not evidence that the availability call itself was slow.
- USDA begins only after successful parsing. Without separate markers, network time can be mistaken for model time. A disk-cached result and a live direct/proxy result are different populations.
- Simulator results are not representative of Apple Intelligence hardware, memory pressure, Neural Engine scheduling, or thermal behavior. UI-test builds also use a mock parser. Simulator measurements may diagnose state transitions and USDA networking, but they are not a launch gate for Foundation Models latency.

## Measurement procedure

### Physical device gate

Follow the attended, foreground, counterbalanced protocol in
[`REAL_IPHONE_ACCEPTANCE_RUNBOOK.md`](REAL_IPHONE_ACCEPTANCE_RUNBOOK.md). It also defines how to
classify interrupted runs, keep foreground latency separate from background/lifecycle stress, resume
atomic blocks, retain redacted artifacts, and make the promotion decision.

Run the repeatable correctness and parser-latency corpus first:

```sh
./Scripts/run-on-device-parser-eval.sh
```

Keep that command's `.xcresult`, redacted JSON attachment, and metadata together. Do not run it
under Instruments: the evaluation is the comparable correctness/latency record, while the steps
below are a separate energy, memory, and thermal follow-up with instrumentation overhead. Use the
same commit, device, OS build, and candidate when correlating the two records.

1. Use an Apple Intelligence-eligible iPhone running the target iOS 27 beta, with Apple Intelligence enabled and model availability reported as ready.
2. Build and run the Debug configuration from Xcode beta. Record commit, Xcode build, iOS build, device model, battery/Low Power Mode, and thermal state.
3. In Console, filter the device stream by the app subsystem and category `LocalObservability`. Alternatively, record the app with Instruments and inspect the matching points-of-interest intervals.
4. Do not enable private-data logging and do not attach broad network or prompt logs to a bug. The performance markers are sufficient.
5. For a cold sample, reboot the device, wait until Apple Intelligence reports ready, launch JustLogIt, and submit one prompt. Force-quitting the app alone is not guaranteed to evict the system model.
6. For warm samples, keep the device awake and submit at least 10 foods after one uncounted warm-up request. Include short generic, branded, preparation-specific, container-fraction, and approximate-quantity descriptions.
7. Measure USDA separately. Clear the downloaded cache before live-network samples; repeat the same query without clearing it for cached samples. Record whether the app uses direct Debug USDA or the production proxy.
8. Avoid charging-induced heat, active screen recording, concurrent builds, and other model-heavy apps. Discard and rerun samples taken during serious thermal throttling.
9. Report median, p95, maximum, failure count, and cold sample independently for each marker. Do not average cold and warm populations.

### Simulator diagnostic

1. Use the same Debug commit and record the Simulator runtime and host Mac.
2. Confirm whether the real model reports available. Runs using `-ui-testing` exercise `MockFoodParser` and must not be reported as Foundation Models timings.
3. Use Simulator data only to compare USDA cached/live calls, validate marker coverage, or investigate a gross regression. Never use it to accept or reject the physical-device model budget.

## Working budgets

These are product thresholds for measurement, not claims about beta framework guarantees. Re-baseline only from a documented device sample set.

| Phase | Target | Investigation threshold |
| --- | --- | --- |
| Availability | p95 ≤ 10 ms | p95 > 50 ms |
| Session acquisition | p95 ≤ 50 ms | p95 > 250 ms; determine whether work moved out of `respond` |
| Warm `FM respond` | median ≤ 2.5 s and p95 ≤ 5 s | p95 > 5 s or any routine sample > 8 s |
| Cold `FM respond` | complete ≤ 8 s | > 10 s, repeated failure, or readiness never settles |
| Mapping/grounding | p95 ≤ 20 ms | p95 > 100 ms |
| Cached USDA search | p95 ≤ 100 ms | p95 > 250 ms |
| Live USDA search | median ≤ 1 s and p95 ≤ 2.5 s | p95 > 3 s, excluding a documented upstream incident |
| Warm submit-to-matches | p95 ≤ 7.5 s | p95 > 8 s or no visible progress/cancel response |

Any failure, cancellation bug, incorrect nutrition, or privacy regression is evaluated independently of these latency budgets.

## Optimization decision order

Do not weaken parsing accuracy based on one Simulator run. Use measurements to make changes in this order:

1. Confirm the regression is in `FM respond`, not model readiness or USDA.
2. Compare cold and warm device samples and check thermal state.
3. Inspect actual generated response size in a local, private development experiment without adding content logging to the app.
4. Consider lowering the response-token cap only after the largest valid structured responses are known.
5. Evaluate shorter guides or non-explicit nil representation with an accuracy regression corpus, especially fractions, containers, brands, preparation, and multiple-food detection.
6. Consider session reuse or prewarming only with tests proving no history leakage, cross-food contamination, elevated memory pressure, or lifecycle regressions.
