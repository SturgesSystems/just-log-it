#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT/Scripts/resolve-physical-iphone.rb"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_fixture() {
  local path="$1"
  shift
  ruby -rjson -e '
    path = ARGV.shift
    devices = ARGV.each_slice(6).map do |identifier, udid, state, platform, reality, device_type|
      {
        "identifier" => identifier,
        "properties" => {
          "connection" => { "state" => state },
          "hardware" => {
            "udid" => udid,
            "platform" => platform,
            "reality" => reality,
            "deviceType" => device_type
          }
        }
      }
    end
    File.write(path, JSON.generate({
      "info" => { "outcome" => "success" },
      "result" => { "devices" => devices }
    }))
  ' "$path" "$@"
}

assert_output() {
  local expected="$1"
  shift
  local actual
  actual="$(ruby "$RESOLVER" "$@")"
  [[ "$actual" == "$expected" ]] || {
    echo "expected output:" >&2
    printf '%s\n' "$expected" >&2
    echo "actual output:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  }
}

assert_failure() {
  local expected_message="$1"
  shift
  local stderr_file="$TMP_DIR/stderr"
  if ruby "$RESOLVER" "$@" >"$TMP_DIR/stdout" 2>"$stderr_file"; then
    echo "expected resolver to fail" >&2
    exit 1
  fi
  grep -Fq "$expected_message" "$stderr_file" || {
    echo "expected failure containing: $expected_message" >&2
    cat "$stderr_file" >&2
    exit 1
  }
}

ONE="$TMP_DIR/one.json"
write_fixture "$ONE" \
  "11111111-2222-4333-8444-555555555555" "00008123-001A2B3C4D5E6001" connected iOS physical iPhone \
  "SIMULATOR-ID" "SIMULATOR-UDID" connected iOS virtual iPhone \
  "IPAD-ID" "IPAD-UDID" connected iOS physical iPad \
  "OFFLINE-ID" "OFFLINE-UDID" disconnected iOS physical iPhone

EXPECTED=$'11111111-2222-4333-8444-555555555555\n00008123-001A2B3C4D5E6001'
assert_output "$EXPECTED" "$ONE"
assert_output "$EXPECTED" "$ONE" "11111111-2222-4333-8444-555555555555"
assert_output "$EXPECTED" "$ONE" "00008123-001a2b3c4d5e6001"
assert_failure "is not a connected physical iPhone" "$ONE" "IPAD-ID"
assert_failure "is not a connected physical iPhone" "$ONE" "UNKNOWN-ID"

TWO="$TMP_DIR/two.json"
write_fixture "$TWO" \
  "CORE-ONE-IDENTIFIER-000000000001" "00008123-001A2B3C4D5E6001" connected iOS physical iPhone \
  "CORE-TWO-IDENTIFIER-000000000002" "00008120-001B6E991AF0802E" connected iOS physical iPhone
assert_failure "more than one iPhone is connected" "$TWO"
assert_output $'CORE-TWO-IDENTIFIER-000000000002\n00008120-001B6E991AF0802E' "$TWO" "CORE-TWO-IDENTIFIER-000000000002"

EMPTY="$TMP_DIR/empty.json"
write_fixture "$EMPTY" "IPAD-ID" "IPAD-UDID" connected iOS physical iPad
assert_failure "no connected physical iPhone was found" "$EMPTY"

INVALID="$TMP_DIR/invalid.json"
printf '%s' '{not json' > "$INVALID"
assert_failure "devicectl returned invalid JSON" "$INVALID"

echo "Device identifier resolution tests passed."
