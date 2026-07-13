# Parser evaluation

On-device Foundation Models quality cannot be established by mocked unit tests alone. Mocked tests prove deterministic grounding, ranking, and arithmetic. They cannot prove that the system model interprets natural-language food descriptions sensibly, avoids unsupported inventions, or stays within latency bounds.

## Corpus policy

- Corpus file: `JustLogItTests/ParserEvaluationCorpus.swift`
- Current version: `1.0.0`
- Cases cover simple foods, brands, quantities, mixed fractions, multiple foods, compounds, context changes, ambiguity, non-food input, prompt injection, impossible values, cross-clause binding, and hallucination traps.
- Every case has a stable ID. Add a regression case for every observed production failure and bump the corpus version when case expectations change in a way that invalidates historical comparisons.

## Expectations

Deterministic expectations:

- Required product tokens when a food is expected
- Source grounding via `ParsedFoodRequestGrounder`
- Disposition classes such as accept, clarify, clarify-or-reject, multiple-or-reject, reject, and human review

Human-review cases:

- Ambiguous or multi-interpretation prompts that still need a person to judge “sensible”
- Not counted as automatic failures solely because the model chose one reasonable interpretation

## Prompt profiles

`FoundationModelsPromptProfile` currently exposes:

- `.production` — the shipping instruction text and the parser default
- `.leanCandidate` — a shorter experimental instruction set

The lean profile is report-only until comparative on-device evidence shows it is eligible. Prompt character count and CI compilation are never sufficient to ship a prompt change.

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
| Stability across repeats | ≥ 90% |
| p95 latency | ≤ 15 seconds |

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

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
export RUN_ON_DEVICE_PARSER_EVAL=1
export PARSER_EVAL_REPEATS=2
# optional, local only:
# export PARSER_EVAL_INCLUDE_INPUT=1

xcodebuild \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -destination 'platform=iOS,id=<device-udid>' \
  -only-testing:JustLogItTests/OnDeviceParserEvaluationTests \
  test
```

Retain the `.xcresult` bundle and the JSON XCTest attachment from the run. Record results in the table below rather than claiming quality from a single anecdotal prompt.

## Results log

| Date | OS build | Device | Model availability | Corpus | Repeats | Profile | Source grounded | Invented facts | Required fields | Behavior | Stability | p50 ms | p95 ms | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | — | — | 1.0.0 | — | production | — | — | — | — | — | — | — | Not yet run |
| — | — | — | — | 1.0.0 | — | leanCandidate | — | — | — | — | — | — | — | Not yet run |

## Hard rules

1. Do not adopt `.leanCandidate` from prompt length alone.
2. Do not relax hallucination thresholds to make a run green.
3. Do not treat Simulator UI smoke tests as parser quality evidence.
4. Re-run the same corpus version after every prompt or schema change before adoption.
5. Keep deterministic grounding after model generation even when the model improves.
