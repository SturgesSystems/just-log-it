#!/usr/bin/env bash
# Run the privacy-safe Foundation Models parser comparison on one physical iPhone.
#
# This command intentionally does not record Instruments energy or thermal data. See
# Documentation/Performance.md after this correctness/latency run completes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_BETA_PATH="${XCODE_BETA_PATH:-/Applications/Xcode-beta.app}"
DEVICE_ID=""
REPEATS=2
INCLUDE_INPUT=0
DRY_RUN=0
VALIDATE_ONLY=0
PROBE_ONLY=0
OUTPUT_DIR=""
RESUME=0
CORPUS_VERSION="1.4.0"
CORPUS_TEST_IDENTIFIER="JustLogItTests/OnDeviceParserEvaluationTests/testConfiguredCandidatesOnDevice"
PROBE_TEST_IDENTIFIER="JustLogItTests/OnDeviceParserEvaluationTests/testParserEvaluationLaunchConfigurationProbe"
TEST_IDENTIFIER="$CORPUS_TEST_IDENTIFIER"
CANDIDATES="baseline22Field,deterministicFirst,hybrid"
WARM_STATES="cold,prewarmed"
MODEL_USE_CASES="general"
REASONING_POLICIES="capabilityAwareLight"
CASE_IDS=""
FAMILIES=""
ORDER_SEED=0
RUN_CONFIGURATION_OVERRIDDEN=0
EVALUATION_SCHEME="JustLogItParserEvaluation"
EVALUATION_SCHEME_FILE="$ROOT/JustLogIt.xcodeproj/xcshareddata/xcschemes/$EVALUATION_SCHEME.xcscheme"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/run-on-device-parser-eval.sh [options]

Runs corpus 1.4.0 on a connected physical iPhone using Xcode-beta. Candidate,
warm-state, model-use-case, and reasoning-policy combinations run as atomic, resumable blocks. Raw food text is
omitted from artifacts by default.

Options:
  --device-id <ID>      Use this connected physical iPhone. Accepts the hardware
                        UDID shown by Xcode or the CoreDevice identifier shown by
                        devicectl. With no ID, exactly one iPhone must be connected.
  --output-dir <path>   Durable artifact directory. Default:
                        ~/Library/Developer/JustLogIt/ParserEvaluation/<timestamp>
  --repeats <2-5>       Repetitions per corpus case (default: 2).
  --candidates <CSV>    Focus blocks to baseline22Field, deterministicFirst,
                        and/or hybrid.
  --warm-states <CSV>   Focus blocks to cold and/or prewarmed.
  --model-use-cases <CSV>
                        Focus blocks to general and/or contentTagging.
  --reasoning-policies <CSV>
                        Compare capabilityAwareLight and/or disabled. Default keeps
                        the production capability-aware light behavior.
  --case <ID>           Include a stable corpus case ID. May be repeated.
  --family <NAME>       Include a corpus category. May be repeated. Case and
                        family filters are combined as a union.
  --order-seed <UINT>   Reproducible candidate, warm-state, and case order
                        (default: 0).
  --resume <path>       Resume an existing run directory. Checksum-validated
                        complete blocks are skipped; interrupted blocks restart.
  --include-input       Include raw corpus prompts in the local JSON attachment.
                        Never commit or share that artifact.
  --dry-run             Perform every preflight, then print the planned run.
  --configuration-probe Run a zero-inference physical launch-configuration probe.
  --validate-only       Validate Xcode, corpus, and unit-only scheme without querying a device.
  -h, --help            Show this help.

Optional environment:
  XCODE_BETA_PATH       Xcode beta app path (default: /Applications/Xcode-beta.app).

This evaluation does not need a USDA key. USDA-related environment variables
are removed and the Debug build setting is explicitly blanked.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      [[ $# -ge 2 && -n "$2" ]] || die "--device-id requires a hardware UDID or CoreDevice identifier."
      DEVICE_ID="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 && -n "$2" ]] || die "--output-dir requires a path."
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --repeats)
      [[ $# -ge 2 && "$2" =~ ^[2-5]$ ]] || die "--repeats must be an integer from 2 through 5."
      REPEATS="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --candidates)
      [[ $# -ge 2 && -n "$2" ]] || die "--candidates requires a comma-separated value."
      CANDIDATES="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --warm-states)
      [[ $# -ge 2 && -n "$2" ]] || die "--warm-states requires a comma-separated value."
      WARM_STATES="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --model-use-cases)
      [[ $# -ge 2 && -n "$2" ]] || die "--model-use-cases requires a comma-separated value."
      MODEL_USE_CASES="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --reasoning-policies)
      [[ $# -ge 2 && -n "$2" ]] || die "--reasoning-policies requires a comma-separated value."
      REASONING_POLICIES="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --case)
      [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9._-]+$ ]] || die "--case requires a stable corpus case ID."
      CASE_IDS="${CASE_IDS:+$CASE_IDS,}$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --family)
      [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9]+$ ]] || die "--family requires a corpus category name."
      FAMILIES="${FAMILIES:+$FAMILIES,}$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --order-seed)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die "--order-seed must be an unsigned integer."
      ORDER_SEED="$2"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift 2
      ;;
    --resume)
      [[ $# -ge 2 && -n "$2" ]] || die "--resume requires an existing run directory."
      RESUME=1
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --include-input)
      INCLUDE_INPUT=1
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --configuration-probe)
      PROBE_ONLY=1
      TEST_IDENTIFIER="$PROBE_TEST_IDENTIFIER"
      RUN_CONFIGURATION_OVERRIDDEN=1
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ "$RESUME" == "1" && "$RUN_CONFIGURATION_OVERRIDDEN" == "1" ]]; then
  die "--resume cannot be combined with matrix, filter, probe, repeat, seed, or redaction options."
fi

if [[ "$PROBE_ONLY" == "1" ]]; then
  CANDIDATES="baseline22Field"
  WARM_STATES="cold"
  MODEL_USE_CASES="general"
  REASONING_POLICIES="capabilityAwareLight"
  CASE_IDS=""
  FAMILIES=""
fi

[[ "$CANDIDATES" =~ ^(baseline22Field|deterministicFirst|hybrid)(,(baseline22Field|deterministicFirst|hybrid))*$ ]] \
  || die "--candidates contains an unsupported value."
[[ "$WARM_STATES" =~ ^(cold|prewarmed)(,(cold|prewarmed))*$ ]] \
  || die "--warm-states contains an unsupported value."
[[ "$MODEL_USE_CASES" =~ ^(general|contentTagging)(,(general|contentTagging))*$ ]] \
  || die "--model-use-cases contains an unsupported value."
[[ "$REASONING_POLICIES" =~ ^(capabilityAwareLight|disabled)(,(capabilityAwareLight|disabled))*$ ]] \
  || die "--reasoning-policies contains an unsupported value."

[[ -x "$XCODE_BETA_PATH/Contents/Developer/usr/bin/xcodebuild" ]] \
  || die "Xcode-beta was not found at $XCODE_BETA_PATH. Set XCODE_BETA_PATH if it is elsewhere."
export DEVELOPER_DIR="$XCODE_BETA_PATH/Contents/Developer"

command -v ruby >/dev/null || die "ruby is required to validate JSON test artifacts."
command -v git >/dev/null || die "git is required to record the evaluated revision."
command -v plutil >/dev/null || die "plutil is required to configure the generated XCTest run file."

SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
[[ "$SDK_MAJOR" =~ ^[0-9]+$ && "$SDK_MAJOR" -ge 27 ]] \
  || die "the selected Xcode beta has iPhoneOS SDK $SDK_VERSION; iOS 27 or newer is required."

CORPUS_SOURCE="$ROOT/JustLogItTests/ParserEvaluationCorpus.swift"
[[ -f "$CORPUS_SOURCE" ]] || die "missing parser corpus: $CORPUS_SOURCE"
grep -Fq "static let version = \"$CORPUS_VERSION\"" "$CORPUS_SOURCE" \
  || die "expected parser corpus $CORPUS_VERSION; update this runbook when the corpus changes."

[[ -f "$EVALUATION_SCHEME_FILE" ]] || die "missing shared evaluation scheme: $EVALUATION_SCHEME_FILE"
grep -Fq 'BlueprintName = "JustLogItTests"' "$EVALUATION_SCHEME_FILE" \
  || die "$EVALUATION_SCHEME must include the JustLogItTests target."
if grep -Fq 'BlueprintName = "JustLogItUITests"' "$EVALUATION_SCHEME_FILE"; then
  die "$EVALUATION_SCHEME must not include JustLogItUITests; its xctrunner requires unrelated provisioning."
fi

if [[ "$VALIDATE_ONLY" == "1" ]]; then
  echo "Validated Xcode beta, iOS SDK $SDK_VERSION, parser corpus $CORPUS_VERSION, and unit-only evaluation scheme."
  echo "No device was queried and no test was run."
  exit 0
fi

if [[ -n "$DEVICE_ID" && ( ${#DEVICE_ID} -lt 20 || ! "$DEVICE_ID" =~ ^[A-Za-z0-9-]+$ ) ]]; then
  die "--device-id contains unsupported characters."
fi

DEVICE_SELECTOR="$DEVICE_ID"
umask 077
DEVICE_JSON="$(mktemp -t justlogit-devices.XXXXXX)"
trap 'rm -f "$DEVICE_JSON"' EXIT
xcrun devicectl list devices \
  --filter "State = 'connected' AND Platform = 'iOS' AND Reality = 'physical'" \
  --json-output "$DEVICE_JSON" \
  --omit-deprecated-fields-in-json \
  >/dev/null

if ! DEVICE_RESOLUTION="$(ruby "$ROOT/Scripts/resolve-physical-iphone.rb" "$DEVICE_JSON" "$DEVICE_SELECTOR")"; then
  exit 2
fi
CORE_DEVICE_ID="$(printf '%s\n' "$DEVICE_RESOLUTION" | sed -n '1p')"
DEVICE_ID="$(printf '%s\n' "$DEVICE_RESOLUTION" | sed -n '2p')"
[[ -n "$CORE_DEVICE_ID" && -n "$DEVICE_ID" ]] \
  || die "device resolution did not return both a CoreDevice identifier and hardware UDID."

DESTINATIONS="$(
  xcodebuild \
    -project "$ROOT/JustLogIt.xcodeproj" \
    -scheme "$EVALUATION_SCHEME" \
    -showdestinations 2>&1
)"
COMPATIBLE_DESTINATIONS="$(
  printf '%s\n' "$DESTINATIONS" \
    | awk '/Destinations incompatible/{exit} {print}'
)"
if ! printf '%s\n' "$COMPATIBLE_DESTINATIONS" \
  | grep -F "platform:iOS," \
  | grep -Fq "id:$DEVICE_ID,"; then
  die "$DEVICE_ID is not an eligible JustLogIt iOS destination in Xcode-beta. Check pairing, Developer Mode, OS support, and provisioning."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Preflight passed for physical iOS destination $DEVICE_ID."
  echo "CoreDevice identifier: $CORE_DEVICE_ID"
  echo "Planned matrix: corpus=$CORPUS_VERSION candidates=$CANDIDATES warmStates=$WARM_STATES modelUseCases=$MODEL_USE_CASES reasoningPolicies=$REASONING_POLICIES repeats=$REPEATS"
  echo "Focused cases: ${CASE_IDS:-all}; families: ${FAMILIES:-all}; order seed: $ORDER_SEED"
  echo "Configuration probe only: $([[ "$PROBE_ONLY" == "1" ]] && echo yes || echo no)"
  echo "Test scheme: $EVALUATION_SCHEME (unit-test target only)"
  echo "Raw input included: $([[ "$INCLUDE_INPUT" == "1" ]] && echo yes || echo no)"
  echo "No app was installed and no test was run."
  exit 0
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$HOME/Library/Developer/JustLogIt/ParserEvaluation/$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
if [[ "$RESUME" == "0" && -e "$OUTPUT_DIR" && -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  die "output directory already exists and is not empty: $OUTPUT_DIR"
fi
if [[ "$RESUME" == "1" && ! -f "$OUTPUT_DIR/run-manifest.json" ]]; then
  die "resume directory has no run-manifest.json: $OUTPUT_DIR"
fi

umask 077
mkdir -p "$OUTPUT_DIR"
BUILD_LOG="$OUTPUT_DIR/xcodebuild.log"
METADATA="$OUTPUT_DIR/run-metadata.txt"
MANIFEST="$OUTPUT_DIR/run-manifest.json"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
CONFIGURED_XCTESTRUN="$DERIVED_DATA/Build/Products/$EVALUATION_SCHEME-configured.xctestrun"

if [[ "$RESUME" == "0" ]]; then
  PATCH_HASH="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" revision-hash --root "$ROOT")"
  ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" create \
    --manifest "$MANIFEST" \
    --corpus-source "$CORPUS_SOURCE" \
    --corpus-version "$CORPUS_VERSION" \
    --candidates "$CANDIDATES" \
    --warm-states "$WARM_STATES" \
    --model-use-cases "$MODEL_USE_CASES" \
    --reasoning-policies "$REASONING_POLICIES" \
    --case-ids "$CASE_IDS" \
    --families "$FAMILIES" \
    --order-seed "$ORDER_SEED" \
    --repeats "$REPEATS" \
    --include-input "$INCLUDE_INPUT" \
    --probe "$PROBE_ONLY" \
    --commit "$(git -C "$ROOT" rev-parse HEAD)" \
    --patch-hash "$PATCH_HASH" \
    --xcode-version "$(xcodebuild -version | paste -sd ' ' -)" \
    --sdk-version "$SDK_VERSION"
  {
  echo "commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "worktree_dirty=$([[ -n "$(git -C "$ROOT" status --porcelain)" ]] && echo true || echo false)"
  echo "xcode_path=$XCODE_BETA_PATH"
  echo "xcode_version=$(xcodebuild -version | paste -sd ' ' -)"
  echo "iphoneos_sdk=$SDK_VERSION"
  echo "device_id=$DEVICE_ID"
  echo "core_device_id=$CORE_DEVICE_ID"
  echo "corpus_version=$CORPUS_VERSION"
  echo "candidates=$CANDIDATES"
  echo "warm_states=$WARM_STATES"
  echo "model_use_cases=$MODEL_USE_CASES"
  echo "reasoning_policies=$REASONING_POLICIES"
  echo "scheme=$EVALUATION_SCHEME"
  echo "repeats=$REPEATS"
  echo "includes_input_text=$([[ "$INCLUDE_INPUT" == "1" ]] && echo true || echo false)"
  echo "configuration_probe_only=$([[ "$PROBE_ONLY" == "1" ]] && echo true || echo false)"
  } > "$METADATA"
else
  PATCH_HASH="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" revision-hash --root "$ROOT")"
  ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" verify-revision \
    --manifest "$MANIFEST" --commit "$(git -C "$ROOT" rev-parse HEAD)" --patch-hash "$PATCH_HASH"
  REPEATS="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field repeats)"
  INCLUDE_INPUT="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field includeInput)"
  ORDER_SEED="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field orderSeed)"
  CASE_IDS="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field caseIDs)"
  FAMILIES="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field families)"
  REASONING_POLICIES="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field reasoningPolicies)"
  PROBE_ONLY="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field probe)"
  if [[ "$PROBE_ONLY" == "1" ]]; then
    TEST_IDENTIFIER="$PROBE_TEST_IDENTIFIER"
  fi
  ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" reset-running --manifest "$MANIFEST"
  echo "Resuming checksum-validated blocks from $MANIFEST"
fi

if [[ "$INCLUDE_INPUT" == "1" ]]; then
  echo "WARNING: the JSON attachment will contain raw corpus prompts. Keep this run local." >&2
fi
if [[ "$PROBE_ONLY" == "1" ]]; then
  echo "Running the zero-inference XCTest launch-configuration probe."
else
  echo "Running the on-device parser matrix. This can take a long time."
fi
echo "Artifacts: $OUTPUT_DIR"

set +e
env \
  -u USDA_API_KEY \
  -u FOODDATA_CENTRAL_API_KEY \
  -u INFOPLIST_KEY_USDADebugAPIKey \
  xcodebuild build-for-testing \
    -project "$ROOT/JustLogIt.xcodeproj" \
    -scheme "$EVALUATION_SCHEME" \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:"$TEST_IDENTIFIER" \
    USDA_API_KEY= \
    INFOPLIST_KEY_USDADebugAPIKey= \
    2>&1 | tee -a "$BUILD_LOG"
BUILD_FOR_TESTING_STATUS="${PIPESTATUS[0]}"
set -e

[[ "$BUILD_FOR_TESTING_STATUS" -eq 0 ]] \
  || die "build-for-testing failed (exit $BUILD_FOR_TESTING_STATUS). See $BUILD_LOG"

GENERATED_XCTESTRUNS="$(find "$DERIVED_DATA/Build/Products" -maxdepth 1 -type f -name '*.xctestrun' ! -name '*-configured.xctestrun' -print | sort)"
GENERATED_XCTESTRUN_COUNT="$(printf '%s\n' "$GENERATED_XCTESTRUNS" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$GENERATED_XCTESTRUN_COUNT" == "1" ]] \
  || die "expected exactly one generated .xctestrun, found $GENERATED_XCTESTRUN_COUNT. See $DERIVED_DATA/Build/Products"
GENERATED_XCTESTRUN="$(printf '%s\n' "$GENERATED_XCTESTRUNS" | sed -n '1p')"
cp "$GENERATED_XCTESTRUN" "$CONFIGURED_XCTESTRUN"

TEST_BLUEPRINT="$(plutil -extract JustLogItTests.BlueprintName raw -o - "$CONFIGURED_XCTESTRUN")"
[[ "$TEST_BLUEPRINT" == "JustLogItTests" ]] \
  || die "generated .xctestrun does not contain the expected hosted JustLogItTests configuration."

set_xctestrun_environment() {
  local key="$1"
  local value="$2"
  local path="JustLogItTests.EnvironmentVariables.$key"
  if plutil -extract "$path" raw -o - "$CONFIGURED_XCTESTRUN" >/dev/null 2>&1; then
    plutil -replace "$path" -string "$value" "$CONFIGURED_XCTESTRUN"
  else
    plutil -insert "$path" -string "$value" "$CONFIGURED_XCTESTRUN"
  fi
}

remove_xctestrun_environment() {
  local dictionary="$1"
  local key="$2"
  local path="JustLogItTests.$dictionary.$key"
  if plutil -extract "$path" raw -o - "$CONFIGURED_XCTESTRUN" >/dev/null 2>&1; then
    plutil -remove "$path" "$CONFIGURED_XCTESTRUN"
  fi
}

for dictionary in EnvironmentVariables TestingEnvironmentVariables; do
  remove_xctestrun_environment "$dictionary" USDA_API_KEY
  remove_xctestrun_environment "$dictionary" FOODDATA_CENTRAL_API_KEY
  remove_xctestrun_environment "$dictionary" INFOPLIST_KEY_USDADebugAPIKey
done

for dictionary in EnvironmentVariables TestingEnvironmentVariables; do
  plutil -extract "JustLogItTests.$dictionary" json -o - "$CONFIGURED_XCTESTRUN" \
    | ruby -rjson -e '
        environment = JSON.parse($stdin.read)
        sensitive = environment.keys.grep(/USDA|FOODDATA|API.?KEY|SECRET/i)
        abort "configured .xctestrun contains sensitive environment keys: #{sensitive.join(",")}" unless sensitive.empty?
      '
done

configure_matrix() {
  local candidate="$1"
  local warm_state="$2"
  local model_use_case="$3"
  local reasoning_policy="$4"
  set_xctestrun_environment RUN_ON_DEVICE_PARSER_EVAL 1
  set_xctestrun_environment PARSER_EVAL_REPEATS "$REPEATS"
  set_xctestrun_environment PARSER_EVAL_MODEL_USE_CASES "$model_use_case"
  set_xctestrun_environment PARSER_EVAL_REASONING_POLICIES "$reasoning_policy"
  set_xctestrun_environment PARSER_EVAL_WARM_STATES "$warm_state"
  set_xctestrun_environment PARSER_EVAL_CANDIDATES "$candidate"
  set_xctestrun_environment PARSER_EVAL_CASE_IDS "$CASE_IDS"
  set_xctestrun_environment PARSER_EVAL_FAMILIES "$FAMILIES"
  set_xctestrun_environment PARSER_EVAL_ORDER_SEED "$ORDER_SEED"
  set_xctestrun_environment PARSER_EVAL_INCLUDE_INPUT "$INCLUDE_INPUT"
  set_xctestrun_environment PARSER_EVAL_CONFIGURATION_PROBE "$PROBE_ONLY"

  plutil -extract JustLogItTests.EnvironmentVariables json -o - "$CONFIGURED_XCTESTRUN" \
    | ruby -rjson -e '
        environment = JSON.parse($stdin.read)
        expected = ARGV.each_slice(2).to_h
        abort "configured .xctestrun matrix mismatch" unless expected.all? { |key, value| environment[key] == value }
        sensitive = environment.keys.grep(/USDA|FOODDATA|API.?KEY|SECRET/i)
        abort "configured .xctestrun contains sensitive environment keys" unless sensitive.empty?
      ' \
        RUN_ON_DEVICE_PARSER_EVAL 1 \
        PARSER_EVAL_REPEATS "$REPEATS" \
        PARSER_EVAL_MODEL_USE_CASES "$model_use_case" \
        PARSER_EVAL_REASONING_POLICIES "$reasoning_policy" \
        PARSER_EVAL_WARM_STATES "$warm_state" \
        PARSER_EVAL_CANDIDATES "$candidate" \
        PARSER_EVAL_CASE_IDS "$CASE_IDS" \
        PARSER_EVAL_FAMILIES "$FAMILIES" \
        PARSER_EVAL_ORDER_SEED "$ORDER_SEED" \
        PARSER_EVAL_INCLUDE_INPUT "$INCLUDE_INPUT" \
        PARSER_EVAL_CONFIGURATION_PROBE "$PROBE_ONLY"
}

run_test_block() {
  local block_id="$1"
  local candidate="$2"
  local warm_state="$3"
  local model_use_case="$4"
  local reasoning_policy="$5"
  local block_dir="$OUTPUT_DIR/blocks/$block_id"
  local result_bundle="$block_dir/result.xcresult"
  local summary_json="$block_dir/test-summary.json"
  local attachments_dir="$block_dir/attachments"
  mkdir -p "$block_dir"
  find "$block_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  configure_matrix "$candidate" "$warm_state" "$model_use_case" "$reasoning_policy"
  ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" running --manifest "$MANIFEST" --block "$block_id"
  ACTIVE_BLOCK="$block_id"

  set +e
  env -u USDA_API_KEY -u FOODDATA_CENTRAL_API_KEY -u INFOPLIST_KEY_USDADebugAPIKey \
    xcodebuild test-without-building \
      -xctestrun "$CONFIGURED_XCTESTRUN" \
      -destination "platform=iOS,id=$DEVICE_ID" \
      -resultBundlePath "$result_bundle" \
      -only-testing:"$TEST_IDENTIFIER" \
      2>&1 | tee -a "$BUILD_LOG"
  local xcode_status="${PIPESTATUS[0]}"
  set -e
  [[ -d "$result_bundle" ]] || return 20

  xcrun xcresulttool get test-results summary --path "$result_bundle" > "$summary_json"
  local skipped_tests
  local test_result
  skipped_tests="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("skippedTests")' "$summary_json")"
  test_result="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("result")' "$summary_json")"
  if [[ "$PROBE_ONLY" == "1" ]]; then
    [[ "$xcode_status" -eq 0 && "$test_result" == "Passed" && "$skipped_tests" -eq 0 ]] || return 21
    local probe_report="$block_dir/configuration-probe.json"
    printf '{"configurationProbe":"passed"}\n' > "$probe_report"
    ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" complete \
      --manifest "$MANIFEST" --block "$block_id" --report "$probe_report" --result "$result_bundle"
    ACTIVE_BLOCK=""
    return 0
  fi
  [[ "$skipped_tests" -eq 0 && "$test_result" != "Skipped" ]] || return 22
  mkdir -p "$attachments_dir"
  xcrun xcresulttool export attachments --path "$result_bundle" \
    --output-path "$attachments_dir" >> "$BUILD_LOG" 2>&1 || return 23

  local report_json
  report_json="$(ruby -rjson -e '
    root, version, candidate, warm_state, reasoning_policy, repeats, include_input, expected_ids = ARGV
    files = Dir.glob(File.join(root, "**", "*.json")).reject { |path| File.basename(path) == "manifest.json" }
    reports = files.map do |path|
      parsed = JSON.parse(File.read(path)) rescue nil
      [path, parsed] if parsed && parsed["corpusVersion"]
    end.compact
    abort "expected one parser report" unless reports.length == 1
    path, report = reports.first
    abort "unexpected corpus version" unless report["corpusVersion"] == version
    abort "unexpected repeat count" unless report["repeats"] == Integer(repeats)
    abort "unexpected warm state" unless report.fetch("warmStates") == [warm_state]
    abort "unexpected reasoning policy" unless report.fetch("reasoningPolicies") == [reasoning_policy]
    abort "unexpected observation reasoning policy" unless report.fetch("observations").map { |item| item.fetch("reasoningPolicy") }.uniq == [reasoning_policy]
    abort "unexpected candidate" unless report.fetch("observations").map { |item| item.fetch("candidate") }.uniq == [candidate]
    actual_ids = report.fetch("observations").map { |item| item.fetch("caseID") }.uniq
    abort "unexpected case order" unless actual_ids == expected_ids.split(",")
    includes = include_input == "1"
    abort "input-redaction mismatch" unless report["includesInputText"] == includes
    abort "raw input appeared" if !includes && report.fetch("observations").any? { |item| item["input"] }
    puts path
  ' "$attachments_dir" "$CORPUS_VERSION" "$candidate" "$warm_state" "$reasoning_policy" "$REPEATS" "$INCLUDE_INPUT" \
    "$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("resolvedCaseOrder").join(",")' "$MANIFEST")")"

  ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" complete \
    --manifest "$MANIFEST" --block "$block_id" --report "$report_json" --result "$result_bundle"
  ACTIVE_BLOCK=""
  if [[ "$xcode_status" -ne 0 || "$test_result" != "Passed" ]]; then
    echo "Block $block_id completed with failing XCTest quality gates; retaining it as complete evidence." >&2
  fi
  return 0
}

ACTIVE_BLOCK=""
interrupt_active_block() {
  local status="$?"
  if [[ -n "$ACTIVE_BLOCK" ]]; then
    ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" interrupted \
      --manifest "$MANIFEST" --block "$ACTIVE_BLOCK" --reason runner_exit || true
  fi
  rm -f "$DEVICE_JSON"
  exit "$status"
}
trap interrupt_active_block EXIT INT TERM

while true; do
  NEXT_BLOCK="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" next --manifest "$MANIFEST")"
  [[ -n "$NEXT_BLOCK" ]] || break
  IFS=$'\t' read -r BLOCK_ID BLOCK_CANDIDATE BLOCK_WARM_STATE BLOCK_MODEL_USE_CASE BLOCK_REASONING_POLICY <<< "$NEXT_BLOCK"
  echo "Running block $BLOCK_ID (candidate=$BLOCK_CANDIDATE warmState=$BLOCK_WARM_STATE useCase=$BLOCK_MODEL_USE_CASE reasoningPolicy=$BLOCK_REASONING_POLICY)"
  if ! run_test_block "$BLOCK_ID" "$BLOCK_CANDIDATE" "$BLOCK_WARM_STATE" "$BLOCK_MODEL_USE_CASE" "$BLOCK_REASONING_POLICY"; then
    ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" interrupted \
      --manifest "$MANIFEST" --block "$BLOCK_ID" --reason test_or_artifact_failure
    ACTIVE_BLOCK=""
    die "block $BLOCK_ID did not finish cleanly; resume reruns it from the beginning."
  fi
done

echo "All checksum-validated parser evaluation blocks are complete."
echo "Run manifest: $MANIFEST"
if [[ "$PROBE_ONLY" == "1" ]]; then
  echo "Configuration probe complete; no parser promotion report was generated."
else
  PROMOTION_REPORT="$OUTPUT_DIR/promotion-report.json"
  ruby "$ROOT/Scripts/parser-eval-promotion-report.rb" \
    --manifest "$MANIFEST" --output "$PROMOTION_REPORT"
  echo "Consolidated redacted report: $PROMOTION_REPORT"
  echo "Next: perform the separate Instruments energy/thermal procedure in Documentation/Performance.md."
fi
