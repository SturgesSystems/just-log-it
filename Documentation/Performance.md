# Performance measurement

JustLogIt separates on-device interpretation latency from USDA lookup latency. Debug builds emit duration-only performance intervals; they never log the food description, generated content, search query, FDC ID, API key, URL, or response body.

## Instrumented phases

The `Performance` log category and signpost stream contains these static names:

| Marker | Boundary | Expected character |
| --- | --- | --- |
| `FM availability` | Read `SystemLanguageModel.default.availability` | Synchronous and negligible |
| `FM session creation` | Construct a new `LanguageModelSession` with instructions | Usually small; initialization may be lazy |
| `FM respond` | Guided generation through receipt of structured content | Dominant on-device model cost |
| `FM mapping` | Validate, map, and deterministically ground generated fields | CPU-only and negligible |
| `USDA search` | Entire configured provider call, including disk-cache lookup, network, decode, and cache write | Cache- and network-dependent |

Every interval records `duration_ms` and only `success` or `failure`. Instrumentation is compiled under `#if DEBUG` and is absent from Release builds.

## Why parsing may be slow

- The guided schema has 17 fields. Field guides and the type description increase prompt/schema work even when the user enters a short food.
- `representNilExplicitlyInGeneratedContent` asks the model to represent absent optional fields instead of omitting them. That improves predictable decoding but increases structured output for simple foods.
- `maximumResponseTokens: 500` is an upper bound, not a preallocated cost. It does not make every request generate 500 tokens, but it allows pathological or unexpectedly verbose responses to run longer than the normal structure should require.
- Greedy sampling and zero temperature improve determinism; they should not be assumed to produce a material latency reduction.
- A new session is constructed for each food. This avoids conversation history and cross-food contamination, but does not reuse any session-level preparation. The framework may defer expensive initialization until `respond`, which is why both phases are measured.
- The first request after reboot, model download/preparation, memory pressure, or model eviction can include model loading and compilation. Warm requests should be evaluated separately.
- Availability checking should be effectively free. `.modelNotReady` is a readiness result, not evidence that the availability call itself was slow.
- USDA begins only after successful parsing. Without separate markers, network time can be mistaken for model time. A disk-cached result and a live direct/proxy result are different populations.
- Simulator results are not representative of Apple Intelligence hardware, memory pressure, Neural Engine scheduling, or thermal behavior. UI-test builds also use a mock parser. Simulator measurements may diagnose state transitions and USDA networking, but they are not a launch gate for Foundation Models latency.

## Measurement procedure

### Physical device gate

1. Use an Apple Intelligence-eligible iPhone running the target iOS 27 beta, with Apple Intelligence enabled and model availability reported as ready.
2. Build and run the Debug configuration from Xcode beta. Record commit, Xcode build, iOS build, device model, battery/Low Power Mode, and thermal state.
3. In Console, filter the device stream by the app subsystem and category `Performance`. Alternatively, record the app with Instruments and inspect the matching points-of-interest intervals.
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
| Session creation | p95 ≤ 50 ms | p95 > 250 ms; determine whether work moved out of `respond` |
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
