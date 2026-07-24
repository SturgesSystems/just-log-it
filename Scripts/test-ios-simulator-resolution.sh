#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT/Scripts/resolve-ios-simulator.rb"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/simctl.json" <<'JSON'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
      {"udid":"OLD-BOOTED","name":"Old booted phone","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
      {"udid":"RENAMED-BOOTED","name":"JustLogIt Hybrid iPhone 17 Pro","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
      {"udid":"NEW-SHUTDOWN","name":"iPhone 17 Pro","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
      {"udid":"IPAD","name":"iPad mini","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro"},
      {"udid":"UNAVAILABLE","name":"Unavailable iPhone","state":"Shutdown","isAvailable":false,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}
    ]
  }
}
JSON

cat >"$TMP_DIR/destinations.txt" <<'TEXT'
Destinations compatible with the "JustLogIt" scheme:
  { platform:iOS, id:PHYSICAL-PHONE, name:iPhone }
  { platform:iOS Simulator, id:RENAMED-BOOTED, OS:27.0, name:JustLogIt Hybrid iPhone 17 Pro }
  { platform:iOS Simulator, id:NEW-SHUTDOWN, OS:27.0, name:iPhone 17 Pro }
  { platform:iOS Simulator, id:IPAD, OS:27.0, name:iPad mini }

Destinations incompatible with the "JustLogIt" scheme:
  { platform:iOS Simulator, id:OLD-BOOTED, OS:26.4, name:Old booted phone }
TEXT

actual="$(ruby "$RESOLVER" "$TMP_DIR/simctl.json" "$TMP_DIR/destinations.txt")"
[[ "$actual" == "RENAMED-BOOTED" ]] || {
  echo "expected RENAMED-BOOTED, got $actual" >&2
  exit 1
}

sed 's/state":"Booted"/state":"Shutdown"/' "$TMP_DIR/simctl.json" >"$TMP_DIR/all-shutdown.json"
actual="$(ruby "$RESOLVER" "$TMP_DIR/all-shutdown.json" "$TMP_DIR/destinations.txt")"
[[ "$actual" == "RENAMED-BOOTED" ]] || {
  echo "expected stable name-ordered RENAMED-BOOTED selection, got $actual" >&2
  exit 1
}

cat >"$TMP_DIR/no-compatible.txt" <<'TEXT'
Destinations compatible with the "JustLogIt" scheme:
  { platform:iOS, id:PHYSICAL-PHONE, name:iPhone }
TEXT
if ruby "$RESOLVER" "$TMP_DIR/simctl.json" "$TMP_DIR/no-compatible.txt" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
  echo "expected resolution without a compatible Simulator to fail" >&2
  exit 1
fi
grep -Fq "no available, scheme-compatible iPhone Simulator was found" "$TMP_DIR/stderr"

echo "Simulator destination resolution tests passed."
