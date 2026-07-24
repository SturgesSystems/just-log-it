# LoggingEval

Mac-side evaluation harness for JustLogIt’s deterministic logging pipeline:

1. Parse a food description with **Foundation Models** (default when available), ground it, or use `--fake-parse` / `--parsed-json`
2. Apply the same source-aware `ParsedQuantityRecovery` and safe one-serving default as the app
3. Build a USDA search query via `FoodSearchQueryBuilder`
4. Search FoodData Central over HTTPS
5. Rank results with `FoodSearchResultRanker`
6. Apply the app's conservative `FoodSearchAutoSelect` policy; report `pickerRequired` when the
   user must choose instead of treating the first ranked result as selected
7. Fetch details and resolve serving only for a high-confidence automatic selection
8. Check that explicit source quantities survived, energy is present, and resolved grams are valid
9. Print a JSON report to stdout with raw input redacted by default

Depends only on **JustLogItCore** (no HealthKit / SwiftUI).

## Requirements

- Xcode 27 beta on macOS 27 (the evaluator records iOS 27 Foundation Models usage metrics)
- Network access to `api.nal.usda.gov`
- A USDA FoodData Central API key in the environment (never commit the key)

## Environment

| Variable       | Required | Description                                      |
|----------------|----------|--------------------------------------------------|
| `USDA_API_KEY` | yes      | FoodData Central API key                         |
| `DEVELOPER_DIR`| recommended | Point at Xcode beta when multiple Xcodes exist |

```sh
export USDA_API_KEY='your-development-key'
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## Run

From the repository root:

```sh
./Scripts/run-logging-eval.sh "2 large eggs" "1 cup rice"
```

Or with the sample corpus:

```sh
./Scripts/run-logging-eval.sh --corpus Tools/LoggingEval/corpus/sample.txt
```

Direct package invocation:

```sh
cd Tools/LoggingEval
swift run logging-eval --corpus corpus/sample.txt
```

Raw food descriptions are omitted from JSON by default. For a local diagnostic artifact only, opt
in explicitly and do not commit the resulting report:

```sh
./Scripts/run-logging-eval.sh --include-input "2 large eggs"
```

Compare the same corpus across prompt, model-use-case, and reasoning-policy candidates:

```sh
./Scripts/run-logging-eval.sh \
  --prompt-profile leanCandidate \
  --model-use-case contentTagging \
  --reasoning-policy disabled \
  --corpus Tools/LoggingEval/corpus/sample.txt
```

Accepted values are `production|leanCandidate`, `general|contentTagging`, and
`capabilityAwareLight|disabled`. The defaults match the shipping parser: `production`, `general`,
and `capabilityAwareLight`. Unlike the Release app, this standalone evaluation executable retains
`disabled` in Release builds so the comparison is available without changing app configuration.

Select the interpretation architecture independently from its prompt/model configuration:

```sh
./Scripts/run-logging-eval.sh \
  --parser-candidate hybrid \
  --corpus Tools/LoggingEval/corpus/sample.txt
```

`--parser-candidate` accepts `baseline|deterministic-first|hybrid` and defaults to `baseline`.
`deterministic-first` mirrors the production wrapper: promoted deterministic families skip model
inference, while excluded inputs invoke the existing 22-field baseline exactly once. Its case reports
include `deterministicFastPathUsed` and `deterministicFastPathFamily`; fallback cases retain the
baseline warm-state, prewarm latency, and token metrics. Each run executes exactly one candidate.
Run the command separately for each candidate and compare the JSON reports; the evaluator never
performs unused inference before or after a selected result. Hybrid reports include the typed route,
route reasons, and whether the semantic model was invoked for each case. Hybrid and
deterministic-first reports also expose `deterministicExtractionLatencyMs` and
`routeDecisionLatencyMs`. Semantic cases add `semanticGroundingAndMergeLatencyMs`; search-bound
cases add `timeToUSDADispatchMs` immediately before the provider call.

Measure the production-style prewarmed path explicitly:

```sh
./Scripts/run-logging-eval.sh \
  --warm-state prewarmed \
  --corpus Tools/LoggingEval/corpus/sample.txt
```

`--warm-state` accepts `cold|prewarmed` and defaults to `cold`. The JSON report
records the requested run state and the state actually applied to every case
(`notApplicable` when parsing was skipped or faked). `parseLatencyMs` measures the complete selected
parser path after any requested prewarm, while `prewarmLatencyMs` records the separate prewarm call,
so cold and prewarmed results are not mislabeled.

### Pre-parsed JSON

When you already have structured parses (e.g. from Foundation Models on a device):

```sh
./Scripts/run-logging-eval.sh --parsed-json path/to/parsed.json
```

Accepted shapes:

```json
{
  "cases": [
    {
      "id": "eggs-1",
      "input": "Two large scrambled eggs",
      "parsed": {
        "productName": "scrambled eggs",
        "searchTerms": "scrambled eggs",
        "quantity": 2,
        "unit": "large",
        "descriptors": [],
        "isApproximate": false,
        "containsMultipleFoods": false
      }
    }
  ]
}
```

Or a bare `ParsedFoodRequest` / array of them.

Without `--parsed-json`, the harness uses **Foundation Models** on Mac when the selected model use
case is available (same generated schema, prompt profile, capability-aware light reasoning by
default, greedy sampling, and grounding as the iOS app). Pass `--reasoning-policy disabled` only for
the explicit evaluation comparison. Pass `--fake-parse` only for offline deterministic smoke tests.
A SwiftPM test compares the standalone schema, prompt profiles, model-use-case declarations, and
reasoning-policy implementation with the shipping source so drift fails loudly.

## Exit codes

| Code | Meaning                                      |
|------|----------------------------------------------|
| 0    | All cases passed checks                      |
| 1    | One or more cases failed, or runtime error   |
| 2    | Usage / missing inputs                       |

## Report fields

Each case includes `checks`:

- `energyNutrientPresent` — energy found on the USDA record / calculated nutrients
- `consumedGramsFinitePositiveWhenQuantityPresent` — when the parse had a quantity, resolution produced usable grams or servings
- `servingResolved` — `ServingResolutionService` returned `.resolved`
- `inputHadQuantity` — the parse included quantity or fraction
- `explicitSourceQuantityPreserved` — every concrete amount in the source survived the app-equivalent recovery/default boundary; this must be true for a case to pass
- `pickerRequired` — the ranked results require an explicit user choice; details and serving
  defaults were intentionally not evaluated

Reports retain `rawQuantity`/`rawUnit` from the grounded model parse and separately expose the effective `quantity`/`unit` evaluated downstream. `quantityRecoveredFromSource` and `quantityDefaultedToOneServing` make the transition explicit instead of hiding model omissions.

`selectionStatus` is `autoSelected`, `pickerRequired`, or `notRun`. The report still includes the
top-ranked USDA metadata for diagnosis when a picker is required, but it does not fetch that food's
details or represent it as the user's choice. `includesInputText` records whether `--include-input`
was used; per-case `input` is absent by default.

The top-level `reasoningPolicy` field labels every report so enabled and disabled runs are not pooled.
Foundation Models cases also report input, cached-input, output, reasoning, and total token counts.
`parseLatencyMs` measures the complete selected parser path. `semanticResponseLatencyMs` isolates model
generation when the hybrid route invokes the semantic proposer, while `prewarmLatencyMs` records the
separate prewarm call. Reports include p50/p95 values for both complete parsing and semantic response,
plus average token counts, so candidates can be compared with more than a single anecdotal duration.
Foundation Models does not expose model-loading duration or time to first token through the APIs
used here, so the evaluator does not invent either field.

## Security

- Never commit `USDA_API_KEY` or put it in source files.
- Use `Config/Secrets.xcconfig` only for the iOS Debug app; this harness reads the env var only.
- Raw prompt text is redacted by default. Use `--include-input` only for temporary local diagnosis,
  and never commit that output.
