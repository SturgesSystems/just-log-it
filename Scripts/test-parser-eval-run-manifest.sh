#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t justlogit-parser-manifest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

CORPUS="$TMP/Corpus.swift"
MANIFEST="$TMP/manifest.json"
cat > "$CORPUS" <<'SWIFT'
let cases = [
  .init(id: "simple.one", category: .simpleFood, input: "one"),
  .init(id: "simple.two", category: .simpleFood, input: "two"),
  .init(id: "unsafe.one", category: .promptInjection, input: "unsafe")
]
SWIFT

ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" create \
  --manifest "$MANIFEST" \
  --corpus-source "$CORPUS" \
  --corpus-version 1.3.0 \
  --candidates baseline22Field,hybrid \
  --warm-states cold,prewarmed \
  --model-use-cases general \
  --reasoning-policies capabilityAwareLight,disabled \
  --families simpleFood \
  --order-seed 42 \
  --repeats 2 \
  --include-input 0 \
  --probe 0 \
  --commit test --patch-hash clean --xcode-version test --sdk-version 27.0

ruby -rjson -e '
  value = JSON.parse(File.read(ARGV.fetch(0)))
  abort "wrong block count" unless value.fetch("blocks").length == 8
  abort "filter leaked" unless value.fetch("resolvedCaseOrder").sort == ["simple.one", "simple.two"]
  abort "raw input enabled" if value.fetch("includesInputText")
  abort "missing planned state" unless value.fetch("blocks").all? { |block| block.fetch("status") == "planned" }
  abort "reasoning policy missing" unless value.fetch("blocks").map { |block| block.fetch("reasoningPolicy") }.uniq.sort == ["capabilityAwareLight", "disabled"]
' "$MANIFEST"
ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" verify-revision \
  --manifest "$MANIFEST" --commit test --patch-hash clean
[[ "$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field caseIDs)" == "" ]]
[[ "$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field families)" == "simpleFood" ]]
[[ "$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" config --manifest "$MANIFEST" --field reasoningPolicies)" == "capabilityAwareLight,disabled" ]]
if ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" verify-revision \
  --manifest "$MANIFEST" --commit changed --patch-hash clean >/dev/null 2>&1; then
  echo "error: resume accepted a changed revision" >&2
  exit 1
fi

NEXT="$(ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" next --manifest "$MANIFEST")"
BLOCK_ID="${NEXT%%$'\t'*}"
ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" running --manifest "$MANIFEST" --block "$BLOCK_ID"
ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" reset-running --manifest "$MANIFEST"

ruby -rjson -e '
  block = JSON.parse(File.read(ARGV.fetch(0))).fetch("blocks").first
  abort "running block not interrupted" unless block.fetch("status") == "interrupted"
  abort "attempt not recorded" unless block.fetch("attempts") == 1
' "$MANIFEST"

ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" running --manifest "$MANIFEST" --block "$BLOCK_ID"
REPORT="$TMP/report.json"
RESULT="$TMP/result.xcresult"
printf '{"ok":true}\n' > "$REPORT"
mkdir "$RESULT"
printf 'marker\n' > "$RESULT/Info.plist"
ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" complete \
  --manifest "$MANIFEST" --block "$BLOCK_ID" --report "$REPORT" --result "$RESULT"
ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" next --manifest "$MANIFEST" >/dev/null

printf '{"tampered":true}\n' > "$REPORT"
if ruby "$ROOT/Scripts/parser-eval-run-manifest.rb" next --manifest "$MANIFEST" >/dev/null 2>&1; then
  echo "error: checksum validation accepted a modified completed report" >&2
  exit 1
fi

echo "Parser evaluation manifest planner/resume tests passed."
