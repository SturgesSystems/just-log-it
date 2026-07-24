#!/usr/bin/env bash
# Canonical local/hosted CI entry point for JustLogIt.
#
# Usage:
#   ./Scripts/ci.sh
#   ./Scripts/ci.sh --ui-smoke
#   ./Scripts/ci.sh --destination 'platform=iOS Simulator,id=<simulator-UDID>'
#   ./Scripts/ci.sh --check-siri-spike-a
#
# Environment overrides:
#   DEVELOPER_DIR                  Xcode developer directory.
#   IOS_SIMULATOR_DESTINATION      Explicit xcodebuild Simulator destination string.
#   UI_SMOKE=1                     Run the UI smoke test.
#   UI_SMOKE_TEST                  XCTest identifier for the smoke test.
#   SKIP_NPM_INSTALL=1             Reuse an existing Backend/node_modules.
#   CHECK_SIRI_SPIKE_A=1           Run static Spike A App Intents file check.
#
# App Intents notes:
#   Sources under JustLogIt/AppIntents/ belong to the JustLogIt app target
#   (project.yml sources: JustLogIt) and compile during the app unit-test
#   xcodebuild step. No separate App Intents compile step is required.
#   CI never requires physical-device Siri. For a cheap static presence check
#   of Spike A files (no Siri/device), run:
#     ./Scripts/check-siri-spike-a.sh
#   or pass --check-siri-spike-a / set CHECK_SIRI_SPIKE_A=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_SIMULATOR_DESTINATION="${IOS_SIMULATOR_DESTINATION:-}"
UI_SMOKE="${UI_SMOKE:-0}"
UI_SMOKE_TEST="${UI_SMOKE_TEST:-JustLogItUITests/LoggingFlowUITests/testFreshLogScreenHasOnePromptAndVisibleManualEntry}"
SKIP_NPM_INSTALL="${SKIP_NPM_INSTALL:-0}"
CHECK_SIRI_SPIKE_A="${CHECK_SIRI_SPIKE_A:-0}"

usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui-smoke)
      UI_SMOKE=1
      shift
      ;;
    --check-siri-spike-a)
      CHECK_SIRI_SPIKE_A=1
      shift
      ;;
    --destination)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --destination requires an xcodebuild destination string." >&2
        exit 2
      fi
      IOS_SIMULATOR_DESTINATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

run_step() {
  local title="$1"
  shift
  echo
  echo "==> $title"
  "$@"
}

resolve_ios_simulator_destination() {
  local temporary_directory simctl_json compatible_destinations simulator_udid
  temporary_directory="$(mktemp -d)"
  simctl_json="$temporary_directory/simctl.json"
  compatible_destinations="$temporary_directory/destinations.txt"

  # Both commands are read-only. Filtering to a CoreSimulator UDID prevents CI
  # from ever selecting a connected physical iPhone shown by xcodebuild.
  if ! xcrun simctl list devices available --json >"$simctl_json"; then
    rm -rf "$temporary_directory"
    return 1
  fi
  if ! xcodebuild \
    -project "$ROOT/JustLogIt.xcodeproj" \
    -scheme JustLogIt \
    -showdestinations >"$compatible_destinations"; then
    rm -rf "$temporary_directory"
    return 1
  fi

  if ! simulator_udid="$(ruby "$ROOT/Scripts/resolve-ios-simulator.rb" "$simctl_json" "$compatible_destinations")"; then
    rm -rf "$temporary_directory"
    return 1
  fi
  rm -rf "$temporary_directory"
  printf 'platform=iOS Simulator,id=%s\n' "$simulator_udid"
}

run_core_tests() {
  xcrun swift test --package-path "$ROOT/Packages/JustLogItCore"
}

run_app_unit_tests() {
  # Builds the JustLogIt app target (including any App Intents sources under
  # JustLogIt/AppIntents/) then runs JustLogItTests. Physical Siri is not used.
  env \
    -u USDA_API_KEY \
    -u FOODDATA_CENTRAL_API_KEY \
    xcodebuild test \
      -project "$ROOT/JustLogIt.xcodeproj" \
      -scheme JustLogIt \
      -destination "$IOS_SIMULATOR_DESTINATION" \
      -only-testing:JustLogItTests \
      USDA_API_KEY= \
      INFOPLIST_KEY_USDADebugAPIKey=
}

run_logging_eval_tests() {
  xcrun swift test \
    --package-path "$ROOT/Tools/LoggingEval" \
    -Xswiftc -target \
    -Xswiftc arm64-apple-macos27.0
}

run_backend_tests() (
  cd "$ROOT/Backend"
  if [[ "$SKIP_NPM_INSTALL" != "1" ]]; then
    npm ci
  fi
  npm run check
  npm test
)

run_ui_smoke() {
  env \
    -u USDA_API_KEY \
    -u FOODDATA_CENTRAL_API_KEY \
    xcodebuild test \
      -project "$ROOT/JustLogIt.xcodeproj" \
      -scheme JustLogIt \
      -destination "$IOS_SIMULATOR_DESTINATION" \
      -only-testing:"$UI_SMOKE_TEST" \
      USDA_API_KEY= \
      INFOPLIST_KEY_USDADebugAPIKey=
}

if [[ -z "$IOS_SIMULATOR_DESTINATION" ]]; then
  IOS_SIMULATOR_DESTINATION="$(resolve_ios_simulator_destination)"
  echo "Selected simulator destination: $IOS_SIMULATOR_DESTINATION"
else
  case "$IOS_SIMULATOR_DESTINATION" in
    *"platform=iOS Simulator"*) ;;
    *)
      echo "error: CI destination must use platform=iOS Simulator; physical devices are not allowed." >&2
      exit 2
      ;;
  esac
  echo "Using explicit simulator destination: $IOS_SIMULATOR_DESTINATION"
fi

run_step "Repository secret scan" "$ROOT/Scripts/scan-repository-secrets.sh"
run_step "Physical-device identifier resolver tests" "$ROOT/Scripts/test-device-id-resolution.sh"
run_step "Simulator destination resolver tests" "$ROOT/Scripts/test-ios-simulator-resolution.sh"
run_step "Parser evaluation manifest tests" "$ROOT/Scripts/test-parser-eval-run-manifest.sh"
run_step "Parser evaluation promotion-report tests" ruby "$ROOT/Scripts/test-parser-eval-promotion-report.rb"
run_step "JustLogItCore tests" run_core_tests
run_step "iOS app unit tests ($IOS_SIMULATOR_DESTINATION)" run_app_unit_tests
run_step "LoggingEval tests" run_logging_eval_tests
run_step "Backend typecheck and tests" run_backend_tests

if [[ "$CHECK_SIRI_SPIKE_A" == "1" ]]; then
  run_step "Siri Spike A static file check" "$ROOT/Scripts/check-siri-spike-a.sh"
else
  echo
  echo "==> Siri Spike A static check skipped (pass --check-siri-spike-a or set CHECK_SIRI_SPIKE_A=1)"
fi

if [[ "$UI_SMOKE" == "1" ]]; then
  run_step "UI smoke ($UI_SMOKE_TEST)" run_ui_smoke
else
  echo
  echo "==> UI smoke skipped (pass --ui-smoke or set UI_SMOKE=1 to run it)"
fi

echo
echo "All requested CI checks passed."
