#!/bin/bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  exit 0
fi

fail() {
  echo "error: Release product verification failed. $1" >&2
  exit 1
}

app_path="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
plist_path="$app_path/Info.plist"
executable_path="$app_path/${EXECUTABLE_NAME:?}"

[[ -f "$plist_path" ]] || fail "The processed Info.plist was not found."
[[ -f "$executable_path" ]] || fail "The application executable was not found."

if /usr/libexec/PlistBuddy -c 'Print :USDADebugAPIKey' "$plist_path" >/dev/null 2>&1; then
  fail "The processed Info.plist contains the debug USDA key field."
fi

if [[ ! -r "$plist_path" ]]; then
  fail "The processed Info.plist is not readable by the post-build verifier."
fi

processed_proxy=$(/usr/libexec/PlistBuddy -c 'Print :ProxyBaseURL' "$plist_path" 2>/dev/null) \
  || fail "The processed Info.plist has no proxy URL."
processed_host=$(/usr/libexec/PlistBuddy -c 'Print :ProxyAllowedHost' "$plist_path" 2>/dev/null) \
  || fail "The processed Info.plist has no allowed-host pin."

if [[ -z "$processed_proxy" || -z "$processed_host" ]]; then
  fail "The processed Info.plist has an empty proxy URL or allowed-host pin."
fi

if [[ "$processed_proxy" != "${PROXY_BASE_URL:-}" || "$processed_host" != "${PROXY_ALLOWED_HOST:-}" ]]; then
  fail "Processed proxy configuration does not match the validated build settings."
fi

if strings "$executable_path" | grep -E -q 'USDADebugAPIKey|USDA_API_KEY'; then
  fail "The Release executable contains a debug USDA credential marker."
fi

# Prefer the executable check above. Whole-app traversal is best-effort because
# user-script sandboxing only grants the exact Info.plist and executable inputs.
if [[ -r "$plist_path" ]] && strings "$plist_path" 2>/dev/null | grep -E -q 'USDADebugAPIKey|USDA_API_KEY'; then
  fail "The Release Info.plist contains a debug USDA credential marker."
fi
