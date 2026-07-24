# Parser evaluation

On-device Foundation Models quality cannot be established by mocked unit tests alone. Mocked tests prove deterministic grounding, ranking, and arithmetic. They cannot prove that the system model interprets natural-language food descriptions sensibly, avoids unsupported inventions, or stays within latency bounds.

## Corpus policy

- Corpus file: `JustLogItTests/ParserEvaluationCorpus.swift`
- Current version: `1.4.0`
- Version 1.4.0 adds Siri-style framing, meal-time composites, brand Big Mac, sized-container
  fractions, and generic rice ambiguity cases. Version 1.3.0 aligned identity-free non-food and
  prompt-injection cases with the shared post-policy terminal route: they require editable manual
  recovery rather than being reported as a clarification the app never presents.
- Cases cover simple foods, brands, quantities, mixed fractions, multiple foods, compounds, context changes, ambiguity, non-food input, prompt injection, impossible values, cross-clause binding, and hallucination traps.
- Every case has a stable ID. Add a regression case for every observed production failure and bump the corpus version when case expectations change in a way that invalidates historical comparisons.

## Expectations

Deterministic expectations:

- Required product tokens when a food is expected
- Source grounding via `ParsedFoodRequestGrounder`
- Disposition classes such as accept, clarify, clarify-or-reject, multiple-or-reject, reject, and human review
- Actual pre-USDA routing through `FoodInterpretationValidator` and `ClarificationPolicy`: direct search, composite handoff, or blocked
- An authoritative typed terminal route for every case: deterministic search, on-device semantic,
  clarification, composite, manual search, or PCC candidate

Behavior scoring uses that real routing boundary. An identity-free non-food response is safe when it remains grounded and blocks USDA search; a multi-food response is safe when it enters composite handoff; and an ambiguous response is not credited merely for omitting a quantity if the app would silently proceed to USDA.

Typed route scoring is intentionally stricter than broad behavior scoring. Two outcomes can both
block USDA while still representing different product behavior; for example, a manual-search
fallback does not satisfy a case that expects a focused clarification. Reports include
`expectedRoute` and `routeCorrect` on every observation. Typed candidates must reach 100% route
accuracy before promotion, and a per-case route mismatch counts as an unsafe disagreement.

The `simple.eggs.written` regression requires “Two large scrambled eggs” to retain quantity `2` with an egg-compatible unit. Substituting `1 serving` fails required-field accuracy even if the food identity itself is correct.

Human-review cases:

- Ambiguous or multi-interpretation prompts that still need a person to judge “sensible”
- Not counted as automatic failures solely because the model chose one reasonable interpretation

## Prompt profiles

`FoundationModelsPromptProfile` currently exposes:

- `.production` — the shipping instruction text and the parser default
- `.leanCandidate` — a shorter experimental instruction set

The lean profile is report-only until comparative on-device evidence shows it is eligible. Prompt character count and CI compilation are never sufficient to ship a prompt change.

The iOS 27 harness also compares the `.general` and `.contentTagging` model use cases. Production remains `.general` until corpus results demonstrate that content tagging preserves both field accuracy and clarification routing.

The standalone evaluator also has an independent architecture dimension:

- `--parser-candidate baseline` runs the existing 22-field model-first parser.
- `--parser-candidate deterministic-first` runs the production deterministic allowlist first and
  falls back to the existing 22-field parser exactly once for excluded inputs.
- `--parser-candidate hybrid` runs deterministic routing and invokes the six-field semantic proposer
  only for semantic-required cases.

Run candidates separately. A single case must never execute both inference architectures in one
pipeline. Deterministic-first JSON reports add `deterministicFastPathUsed` and
`deterministicFastPathFamily`; fallback cases preserve baseline warm/prewarm and token metrics.
Hybrid JSON reports include `interpretationRoute`, `routeReasons`, and `modelInvoked`.
They also separate complete hybrid parse latency from the observable Foundation Models prewarm,
session-acquisition, and complete-response intervals. When inference runs, the iOS XCTest attachment
records the response's input, cached-input, output, reasoning, and total token counts directly from
Foundation Models usage. A deterministic fast path correctly leaves model timing and token fields
`null`; an errored response can have response latency while usage remains `null`. The app's normal
production path continues emitting only content-free signposts and never creates the evaluation
recorder.
Both Core-backed candidates report deterministic extraction and route-decision latency. Hybrid
semantic cases additionally report grounding/merge latency, and baseline model cases report the
app-owned generated-content mapping interval. Search-bound cases report elapsed time immediately
before USDA provider dispatch. Foundation Models does not expose model-loading duration or time to
first token through the APIs in use, so those metrics are intentionally absent rather than inferred
from prewarm, session acquisition, or response time.

LoggingEval applies the production `FoodSearchAutoSelect` policy after ranking. A weak, generic,
derivative, or competing top result is reported as `selectionStatus: pickerRequired`; the evaluator
does not fetch details, default a serving, or pretend that the ranked result was selected. Raw case
`input` is omitted by default. Pass `--include-input` only for a temporary local report whose prompt
content you explicitly accept, matching the iOS harness's opt-in redaction policy.

For the physical-device XCTest harness, select any candidate set explicitly:

```sh
PARSER_EVAL_CANDIDATES=baseline22Field,deterministicFirst,hybrid
```

The default remains `baseline22Field`. `deterministicFirst` runs the exact shipping Core
`DeterministicFirstFoodParser` with the production 22-field parser as its fallback. Its fallback is
invocation-tracked, so each observation records `deterministicFastPathUsed`,
`deterministicFastPathFamily`, and `modelInvoked` even when the fallback throws. Summaries report
`deterministicFastPathRate` and `modelInvocationRate`. A prewarmed deterministic-first run prewarms
the production fallback; a fast-path case still invokes the model zero times.

When multiple candidates are requested, each is a separate labeled observation; no candidate calls
another candidate. Candidate promotion requires zero paired unsafe disagreements, so a bad case
cannot be hidden inside an acceptable aggregate rate. Context-change cases include their prior user
prelude in semantic context while grounding remains limited to the current user input; the
deterministic-first wrapper receives those as distinct `semanticContext` and `groundingText` values.

Reasoning policy is also an explicit evaluation dimension. `capabilityAwareLight` is the shipping
behavior: request `.light` only when the selected model advertises reasoning support. `disabled`
always omits a reasoning level so its latency, token use, and quality can be compared without
changing prompts or candidates. The disabled policy exists only in Debug evaluation builds; the
Release app has no setting, environment variable, or alternate case that can select it.

## Redaction

By default, evaluation JSON attachments use case IDs and scores without raw food text.

Set `PARSER_EVAL_INCLUDE_INPUT=1` only when you explicitly accept raw prompt text in a local test artifact. Do not commit those artifacts.

## Thresholds

Production profile absolute gates:

| Metric | Threshold |
| --- | --- |
| Source grounding | 100% |
| Unsupported invented facts | 0 |
| Required field accuracy | ≥ 90% |
| Behavior accuracy | ≥ 85% |
| Typed route accuracy | 100% for typed candidates |
| Stability across repeats | ≥ 90% |
| p95 latency | ≤ 15 seconds |

JSON reports include p50 and p95 latency. Token metric fields are part of the on-device report contract; they remain `null` when the parser surface cannot return response usage. The macOS `LoggingEval` executable records input, cached-input, output, reasoning, and total token counts directly.

Lean candidate eligibility additionally requires:

- No safety regression versus production on the same OS/model build
- Meets the absolute thresholds above
- Does not regress required-field or behavior scores versus production
- Stability within two percentage points of production
- p95 latency ≤ 110% of production p95

## Running deterministic gates

These do not call the system model:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:JustLogItTests/ParserEvaluationCorpusTests \
  test
```

## Running the on-device suite

Requires an eligible destination where `SystemLanguageModel.default.availability` is `.available`. Prefer a physical iOS 27 device with Apple Intelligence enabled. Simulator is acceptable only when the system model is actually available there.

For the complete physical-iPhone comparison, use the repository runbook:

```sh
./Scripts/run-on-device-parser-eval.sh
```

Use [`REAL_IPHONE_ACCEPTANCE_RUNBOOK.md`](REAL_IPHONE_ACCEPTANCE_RUNBOOK.md) for the attended
foreground protocol, counterbalanced ordering, interruption/resume rules, separate lifecycle and
Instruments work, artifact handling, and promotion decision. The runner divides the matrix into
atomic candidate × warm-state × model-use-case × reasoning-policy blocks. It records resolved candidate and case
order, attempts/status, and report checksums in `run-manifest.json`. The host-only manifest
contract is tested by `./Scripts/test-parser-eval-run-manifest.sh`. After every non-probe block is
complete, the runner checksum-validates and consolidates the redacted attachments into
`promotion-report.json`. That report verifies exact case × repeat × candidate-profile coverage and
strict metric types before aggregation. It labels filtered, unpaired, or incomplete matrices
ineligible rather than presenting them as promotion-ready; even a complete automated safety pass
still requires the separate device review below. Its Ruby 2.6-compatible host contract is tested by
`ruby ./Scripts/test-parser-eval-promotion-report.rb`.

The consolidated per-case comparison pairs production separately with `deterministicFirst` and
`hybrid`. It classifies observable disagreements using only closed fields: correctness booleans,
typed route, parse/error outcome, and USDA terminal class. It never writes request/query text,
clarification prose, or a content fingerprint. Consequently, `both_acceptable` is not a claim that
the parsed requests or nutrition paths are identical; every meaningful comparison is marked for
private human review. Exact content requires an attended local rerun through visible UI or an
ephemeral debugger/test inspector; the redacted attachment cannot prove it. Convert any material
finding into a closed regression expectation without copying content into diagnostics.

It selects the sole connected physical iPhone. `--device-id` accepts either the hardware UDID
shown by Xcode (for example, `000081…`) or the CoreDevice identifier shown by `devicectl` (a UUID).
The runner reads structured `devicectl` JSON and maps either value to the hardware UDID required
by `xcodebuild`; it does not assume CoreDevice's top-level `identifier` is an Xcode destination ID.
It then preflights Xcode-beta and the iOS 27 SDK and runs corpus `1.4.0` with
`baseline22Field,deterministicFirst,hybrid` across `cold,prewarmed`. It treats the Foundation
Models availability skip as a failed preflight, retains the complete `.xcresult`, and exports and
validates the JSON XCTest attachment. Artifacts default to the private, durable
`~/Library/Developer/JustLogIt/ParserEvaluation/` directory. Raw prompt text is excluded unless
`--include-input` is explicitly passed; USDA key variables are removed from the test process.
The runner uses the shared `JustLogItParserEvaluation` scheme, which contains only the hosted unit
test target. This deliberately keeps `JustLogItUITests` and its separately provisioned XCTest
runner out of the physical-device build; `-only-testing` selects tests to execute but does not prune
other test targets from a scheme's build graph. Because a physical XCTest launch does not inherit
arbitrary variables from the `xcodebuild` shell process—and scheme values backed by ad hoc build
settings are not reliable here—the runner uses a two-stage XCTest flow. It runs
`build-for-testing` into the private artifact directory, copies the generated `.xctestrun` beside
its build products, writes the literal matrix into the hosted unit-test configuration's
`EnvironmentVariables`, audits that configuration for sensitive keys, and then runs
`test-without-building` from that exact file.

Useful non-running checks:

```sh
# Check Xcode-beta, the SDK, corpus contract, and unit-only scheme without querying a phone.
./Scripts/run-on-device-parser-eval.sh --validate-only

# Check a connected phone and print the planned matrix without installing or running the app.
./Scripts/run-on-device-parser-eval.sh --dry-run --device-id <hardware-udid-or-coredevice-id>

# Validate atomic planning, interruption reset, resume skipping, and checksum rejection.
./Scripts/test-parser-eval-run-manifest.sh

# Validate fail-closed redacted aggregation and conservative promotion labels.
ruby ./Scripts/test-parser-eval-promotion-report.rb
```

`--dry-run` performs only read-only enumeration and destination validation. It does not build,
install, launch, or test the app. Identifier-mapping fixtures can be run without a phone using
`./Scripts/test-device-id-resolution.sh`.

To verify physical XCTest launch-environment propagation without invoking Foundation Models or
running the corpus, use the runner's configuration probe:

```sh
./Scripts/run-on-device-parser-eval.sh \
  --configuration-probe \
  --device-id <hardware-udid-or-coredevice-id>
```

The probe asserts that the launched test process sees and can parse every matrix value. It creates
no model session and makes no USDA request. A missing probe marker is a test failure, not a silent
pass. Probe runs intentionally do not create a parser promotion report.

The script reports `hybridCandidateEligible` but preserves a completed report regardless of that
value; evaluation success is evidence collection, not automatic promotion. Energy, memory, and
thermal profiling are deliberately a separate Instruments session described in
`Documentation/Performance.md` so instrumentation overhead is not mixed into the correctness and
latency corpus.

For focused experiments, use `--candidates`, `--warm-states`, `--reasoning-policies`, repeatable `--case` and `--family`
filters, and `--order-seed`. Case and family filters form a union. The same seed gives paired blocks
the same deterministic case order. Resume an interrupted run with `--resume <run-directory>`;
completed blocks are skipped only after their JSON checksum validates. A direct command that only
exports shell variables is not a valid physical-device evaluation because those variables do not
cross the XCTest launch boundary.

The environment names consumed by the harness are:

```sh
export RUN_ON_DEVICE_PARSER_EVAL=1
export PARSER_EVAL_REPEATS=2
# default is general; use general,contentTagging for a model-use-case comparison
export PARSER_EVAL_MODEL_USE_CASES=general
# default is capabilityAwareLight; add disabled for a paired reasoning comparison
export PARSER_EVAL_REASONING_POLICIES=capabilityAwareLight,disabled
# default is cold; use cold,prewarmed for an explicit production-prewarm comparison
export PARSER_EVAL_WARM_STATES=cold,prewarmed
# compare the shipping architecture with both experimental endpoints
export PARSER_EVAL_CANDIDATES=baseline22Field,deterministicFirst,hybrid
export PARSER_EVAL_INCLUDE_INPUT=0
export PARSER_EVAL_CASE_IDS=simple.eggs.written,quantity.fraction.written
export PARSER_EVAL_FAMILIES=promptInjection,hallucinationTrap
export PARSER_EVAL_ORDER_SEED=42
```

Warm-state runs are reported separately and never pooled into one latency summary.
`cold` creates a fresh session with no prewarm. `prewarmed` invokes the shipping
parser's one-shot prewarm immediately before the measured parse; the measured
latency begins after prewarm returns. The default remains `cold` so existing runs
do not silently double in size or change meaning.

Reasoning observations and summaries are grouped by `reasoningPolicy`; promotion comparisons never
pool enabled and disabled results. The production promotion scope is evaluated against
`capabilityAwareLight`. Optional `disabled` blocks supply comparative evidence but cannot replace
the shipping-policy blocks. Usage reports still record the response's reasoning-token count,
including zero for models that do not reason.

Retain the `.xcresult` bundle and the JSON XCTest attachment from the run. Record results in the table below rather than claiming quality from a single anecdotal prompt.

## Results log

| Date | OS build | Device | Model availability | Corpus | Repeats | Profile | Reasoning policy | Warm state | Source grounded | Invented facts | Required fields | Behavior | Stability | p50 ms | p95 ms | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | — | — | 1.4.0 | — | production | capabilityAwareLight | cold | — | — | — | — | — | — | — | Not yet run |
| — | — | — | — | 1.4.0 | — | leanCandidate | capabilityAwareLight | cold | — | — | — | — | — | — | — | Not yet run |

## Hard rules

1. Do not adopt `.leanCandidate` from prompt length alone.
2. Do not relax hallucination thresholds to make a run green.
3. Do not treat Simulator UI smoke tests as parser quality evidence.
4. Re-run the same corpus version after every prompt or schema change before adoption.
5. Keep deterministic grounding after model generation even when the model improves.
6. Keep `Tools/LoggingEval` in schema, prompt-profile, model-use-case, and production reasoning-policy parity with the shipping parser; the deterministic suite enforces this source contract.
