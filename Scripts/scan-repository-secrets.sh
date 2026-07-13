#!/bin/bash
# Safe repository secret scanner for LaunchReadiness.
# Scans git-tracked source only. Prints path + rule id on match; never prints secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

findings=0

should_exclude() {
  local path="$1"
  case "$path" in
    Backend/node_modules/*|*/node_modules/*) return 0 ;;
    *.xcuserstate) return 0 ;;
    package-lock.json|*/package-lock.json|Package.resolved|*/Package.resolved) return 0 ;;
    Config/Secrets.xcconfig|*/Secrets.xcconfig) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.zip|*.gz|*.tgz|*.jar|*.wasm|*.bin) return 0 ;;
  esac
  return 1
}

# Lines that intentionally mention credential field NAMES (or documented placeholders)
# without embedding a real secret value.
is_allowlisted_line() {
  local line="$1"

  # Empty / whitespace-only assignment or build-setting expansion.
  if [[ "$line" =~ USDA_API_KEY[[:space:]]*=[[:space:]]*$ ]]; then
    return 0
  fi
  if [[ "$line" =~ USDA_API_KEY[[:space:]]*=[[:space:]]*[\'\"][\'\"][[:space:]]*$ ]]; then
    return 0
  fi
  if [[ "$line" =~ \$\(USDA_API_KEY\) ]]; then
    return 0
  fi

  # Documented placeholder values only (not real credentials).
  if [[ "$line" =~ USDA_API_KEY[[:space:]]*=[[:space:]]*[\'\"]?your-development-key[\'\"]?[[:space:]]*$ ]]; then
    return 0
  fi

  # Plist key name without a literal secret.
  if [[ "$line" =~ \<key\>USDADebugAPIKey\</key\> ]]; then
    return 0
  fi

  # Scripts/docs that scan for or discuss marker strings / field names.
  if [[ "$line" =~ USDADebugAPIKey\|USDA_API_KEY ]] \
    || [[ "$line" =~ USDA_API_KEY\|USDADebugAPIKey ]] \
    || [[ "$line" =~ \'USDADebugAPIKey\|USDA_API_KEY\' ]] \
    || [[ "$line" =~ \"USDADebugAPIKey\|USDA_API_KEY\" ]]; then
    return 0
  fi
  if [[ "$line" =~ INFOPLIST_KEY_USDADebugAPIKey ]]; then
    return 0
  fi
  if [[ "$line" =~ Print[[:space:]]*:USDADebugAPIKey ]]; then
    return 0
  fi
  if [[ "$line" =~ dictionary\[\"USDADebugAPIKey\"\] ]] \
    || [[ "$line" =~ dictionary\[\'USDADebugAPIKey\'\] ]]; then
    return 0
  fi

  # Type/env field references and empty overrides (no long literal assignment).
  if [[ "$line" =~ USDA_API_KEY:[[:space:]]*string ]] \
    || [[ "$line" =~ USDA_API_KEY\? ]] \
    || [[ "$line" =~ env\.USDA_API_KEY ]] \
    || [[ "$line" =~ overrides\.USDA_API_KEY ]] \
    || [[ "$line" =~ \{[[:space:]]*USDA_API_KEY: ]] \
    || [[ "$line" =~ USDA_API_KEY:[[:space:]]*\"\" ]] \
    || [[ "$line" =~ USDA_API_KEY:[[:space:]]*overrides ]]; then
    return 0
  fi

  # Test harness uses a short known marker, not a production credential shape.
  if [[ "$line" =~ USDA_API_KEY:[[:space:]]*overrides\.USDA_API_KEY[[:space:]]*\?\?[[:space:]]*\"test-secret\" ]]; then
    return 0
  fi

  # Narrative documentation of the field name (no assignment of a secret).
  if [[ "$line" =~ USDA_API_KEY ]] || [[ "$line" =~ USDADebugAPIKey ]]; then
    if [[ ! "$line" =~ USDA_API_KEY[[:space:]]*=[[:space:]]*[\'\"]?[A-Za-z0-9_-]{8,} ]] \
      && [[ ! "$line" =~ api_key=[A-Za-z0-9_-]{12,} ]] \
      && [[ ! "$line" =~ sk-[A-Za-z0-9]{20,} ]] \
      && [[ ! "$line" =~ BEGIN[[:space:]]+(RSA[[:space:]]+|OPENSSH[[:space:]]+)?PRIVATE[[:space:]]+KEY ]]; then
      # Mentions the name without matching a secret-assignment rule shape.
      return 0
    fi
  fi

  return 1
}

report_finding() {
  local path="$1"
  local rule_id="$2"
  printf '%s: %s\n' "$path" "$rule_id"
  findings=$((findings + 1))
}

# Rule patterns (content). Never echo the matching text — only path + rule id.
# usda-api-key-assignment: USDA_API_KEY\s*=\s*['"]?[A-Za-z0-9_-]{8,}
# api-key-query-param:      api_key=[A-Za-z0-9_-]{12,}
# private-key-pem:          BEGIN (RSA |OPENSSH )?PRIVATE KEY
# openai-style-key:         sk-[A-Za-z0-9]{20,}
# usda-nearby-long-secret:  USDA + long quoted secret-like token on same line

scan_file() {
  local path="$1"
  local line
  local lineno=0

  # Skip empty / unreadable / non-text.
  [[ -f "$path" && -r "$path" ]] || return 0
  if ! grep -Iq . "$path" 2>/dev/null; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))

    if is_allowlisted_line "$line"; then
      continue
    fi

    if [[ "$line" =~ USDA_API_KEY[[:space:]]*=[[:space:]]*[\'\"]?[A-Za-z0-9_-]{8,} ]]; then
      report_finding "$path" "usda-api-key-assignment"
      continue
    fi

    if [[ "$line" =~ api_key=[A-Za-z0-9_-]{12,} ]]; then
      report_finding "$path" "api-key-query-param"
      continue
    fi

    if [[ "$line" =~ BEGIN[[:space:]]+(RSA[[:space:]]+|OPENSSH[[:space:]]+)?PRIVATE[[:space:]]+KEY ]]; then
      report_finding "$path" "private-key-pem"
      continue
    fi

    if [[ "$line" =~ sk-[A-Za-z0-9]{20,} ]]; then
      report_finding "$path" "openai-style-key"
      continue
    fi

    # Hardcoded long secrets near USDA (same line): USDA context + 24+ char secret-like token.
    if [[ "$line" =~ [Uu][Ss][Dd][Aa] ]] \
      && [[ "$line" =~ [\'\"][A-Za-z0-9+/=_-]{24,}[\'\"] ]]; then
      report_finding "$path" "usda-nearby-long-secret"
      continue
    fi
  done <"$path"
}

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if should_exclude "$path"; then
    continue
  fi
  scan_file "$path"
done < <(git ls-files)

if [[ "$findings" -gt 0 ]]; then
  echo "error: repository secret scan found ${findings} finding(s)." >&2
  exit 1
fi

echo "ok: repository source secret scan clean."
exit 0
