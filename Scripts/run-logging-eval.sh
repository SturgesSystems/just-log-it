#!/usr/bin/env bash
# Run the Mac-side logging evaluation harness (Tools/LoggingEval).
#
# Required environment:
#   USDA_API_KEY   USDA FoodData Central API key (never commit this value)
#
# Optional environment:
#   DEVELOPER_DIR  Prefer Xcode beta, e.g.
#                  /Applications/Xcode-beta.app/Contents/Developer
#
# Examples:
#   export USDA_API_KEY='your-development-key'
#   ./Scripts/run-logging-eval.sh "2 large eggs" "1 cup rice"
#   ./Scripts/run-logging-eval.sh --corpus Tools/LoggingEval/corpus/sample.txt
#   ./Scripts/run-logging-eval.sh --parsed-json /tmp/parsed.json
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_PATH="$ROOT/Tools/LoggingEval"

if [[ -z "${USDA_API_KEY:-}" ]]; then
  echo "error: USDA_API_KEY is not set. Export your FoodData Central key first." >&2
  echo "  Example: export USDA_API_KEY=…   # never commit the real value" >&2
  exit 2
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

if [[ $# -eq 0 ]]; then
  set -- --corpus "$PACKAGE_PATH/corpus/sample.txt"
fi

cd "$PACKAGE_PATH"
# Foundation Models Generable APIs require macOS 26.4+ deployment target.
exec xcrun swift run \
  -Xswiftc -target -Xswiftc arm64-apple-macos26.4 \
  logging-eval "$@"
