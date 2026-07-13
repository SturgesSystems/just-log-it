#!/bin/bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  exit 0
fi

fail() {
  echo "error: Release configuration is invalid. $1" >&2
  exit 1
}

valid_host() {
  local host="$1"
  local label
  local labels
  [[ "$host" == *.* ]] || return 1
  [[ "$host" != .* && "$host" != *. && "$host" != *..* ]] || return 1
  IFS='.' read -r -a labels <<< "$host"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

if [[ -n "${USDA_API_KEY:-}" || -n "${INFOPLIST_KEY_USDADebugAPIKey:-}" ]]; then
  fail "A direct USDA credential or debug plist setting is present."
fi

proxy_url="${PROXY_BASE_URL:-}"
allowed_host="${PROXY_ALLOWED_HOST:-}"

if [[ -z "$proxy_url" || -z "$allowed_host" ]]; then
  fail "A proxy URL and separate allowed-host pin are required."
fi

if ! valid_host "$allowed_host"; then
  fail "The allowed-host pin is malformed."
fi

if [[ ! "$proxy_url" =~ ^https://([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?)/?$ ]]; then
  fail "The proxy must be a root-only HTTPS URL without user info, port, query, or fragment."
fi

proxy_host="${BASH_REMATCH[1]}"
valid_host "$proxy_host" || fail "The proxy host is malformed."
proxy_host_lower=$(printf '%s' "$proxy_host" | tr '[:upper:]' '[:lower:]')
allowed_host_lower=$(printf '%s' "$allowed_host" | tr '[:upper:]' '[:lower:]')

if [[ "$proxy_host_lower" != "$allowed_host_lower" ]]; then
  fail "The proxy host does not match the allowed-host pin."
fi

case "$proxy_host_lower" in
  localhost|*.localhost|example|*.example|example.com|*.example.com|*.invalid|*.test)
    fail "Placeholder and local proxy hosts are not allowed in Release."
    ;;
esac

if [[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" == com.example.* ]]; then
  fail "The placeholder bundle identifier is not allowed in Release."
fi
