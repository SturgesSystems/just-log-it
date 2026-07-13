# LoggingEval

Mac-side evaluation harness for JustLogIt’s deterministic logging pipeline:

1. Parse a food description with **Foundation Models** (default when available), ground it, or use `--fake-parse` / `--parsed-json`
2. Build a USDA search query via `FoodSearchQueryBuilder`
3. Search FoodData Central over HTTPS
4. Rank results with `FoodSearchResultRanker`
5. Fetch details, resolve serving with `ServingResolutionService`
6. Check that energy is present and consumed grams are valid when quantity is known
7. Print a JSON report to stdout

Depends only on **JustLogItCore** (no HealthKit / SwiftUI).

## Requirements

- Xcode 27 beta (or a Swift 6.2 toolchain with macOS 15+)
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

Without `--parsed-json`, the harness uses **Foundation Models** on Mac when `SystemLanguageModel.default.availability` is `.available` (same production prompt + grounding as the iOS app). Pass `--fake-parse` only for offline deterministic smoke tests.

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

## Security

- Never commit `USDA_API_KEY` or put it in source files.
- Use `Config/Secrets.xcconfig` only for the iOS Debug app; this harness reads the env var only.
