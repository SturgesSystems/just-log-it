#!/usr/bin/env bash
# Static presence check for Siri Spike A App Intents sources.
#
# Verifies the Spike A handoff files exist on disk. Does not invoke Siri,
# Shortcuts, a simulator, or a physical device.
#
# Usage:
#   ./Scripts/check-siri-spike-a.sh
#
# Exit codes:
#   0  all required files present
#   1  one or more required files missing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REQUIRED=(
  "JustLogIt/AppIntents/StartFoodLogIntent.swift"
  "JustLogIt/AppIntents/JustLogItShortcuts.swift"
  "JustLogIt/App/PendingFoodLog.swift"
  "JustLogIt/AppIntents/SiriFoodLogCoordinator.swift"
)

missing=()
present=()

for rel in "${REQUIRED[@]}"; do
  path="$ROOT/$rel"
  if [[ -f "$path" ]]; then
    present+=("$rel")
  else
    missing+=("$rel")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "error: Siri Spike A source check failed. Missing required file(s):" >&2
  for rel in "${missing[@]}"; do
    echo "  - $rel" >&2
  done
  if [[ ${#present[@]} -gt 0 ]]; then
    echo "Present:" >&2
    for rel in "${present[@]}"; do
      echo "  - $rel" >&2
    done
  fi
  exit 1
fi

# Cheap content sanity: documented intent type must appear in its source file.
if ! grep -q 'struct StartFoodLogIntent' \
  "$ROOT/JustLogIt/AppIntents/StartFoodLogIntent.swift"; then
  echo "error: StartFoodLogIntent.swift exists but does not declare struct StartFoodLogIntent." >&2
  exit 1
fi

echo "Siri Spike A files OK:"
for rel in "${present[@]}"; do
  echo "  $rel"
done
exit 0
