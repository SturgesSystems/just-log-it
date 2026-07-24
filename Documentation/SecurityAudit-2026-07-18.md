# Security / Privacy Audit — 2026-07-18

**Repository:** JustLogIt (`/Users/james/Developer/just-log-it`)
**Scope:** git-tracked source, app privacy strings, privacy manifest, secret handling
**Secrets policy:** findings report path + rule only; no secret values printed

## Overall result: **PASS**

| Check | Result |
| --- | --- |
| Repository secret scan (script rules) | **PASS** |
| Accidental secret commits | **PASS** (none found) |
| Info.plist usage descriptions | **PASS** |
| PrivacyInfo.xcprivacy | **PASS** (with documentation note) |

No secret remediation was required.

---

## 1. Repository secret scan

### Procedure

- Invoked `./Scripts/scan-repository-secrets.sh` (scans `git ls-files`, excludes secrets file / binaries / lockfiles).
- The bash line-by-line scanner did **not finish within the automation wall-clock budget** (~5 minutes). Profiling shows cost scales with per-line bash `[[ =~ ]]` over the full tree (e.g. multi-second per large Swift/test file). This is a **scanner performance issue**, not a finding of embedded secrets.
- Equivalent scan of the **same five rules** against the same git-tracked, non-excluded corpus completed cleanly via `grep` (values redacted in tooling output).

### Rules covered

| Rule id | Pattern intent | Result |
| --- | --- | --- |
| `usda-api-key-assignment` | `USDA_API_KEY =` + long literal | **Clean** (only docs/scripts with allowlisted `your-development-key` placeholder) |
| `api-key-query-param` | `api_key=` + long token | **Clean** |
| `private-key-pem` | PEM private key header | **Clean** |
| `openai-style-key` | `sk-` + long token | **Clean** |
| `usda-nearby-long-secret` | USDA context + 24+ char quoted secret-like token | **Clean** |

### Grep survey (API keys / USDA / tokens / password)

Additional case-insensitive survey across app, backend, configs, tests, and docs found only:

- **Field names and plumbing:** `USDA_API_KEY`, `USDADebugAPIKey`, `debugUSDAAPIKey`, Worker `env.USDA_API_KEY`, header `X-Api-Key`.
- **Test / eval markers:** short non-production strings such as `test-secret`, `contract-test-key-not-a-secret`, `development-key` in unit tests and docs.
- **Parser “tokens”:** product/token counts in evaluation harness (not credentials).
- **HealthKit authorization** wording (not API credentials).
- **No** committed PEM keys, OpenAI-style `sk-…` keys, or long `api_key=` query literals in tracked source.

### Local (untracked) secret material

| Path | Git status | Notes |
| --- | --- | --- |
| `Config/Secrets.xcconfig` | **Ignored** (`.gitignore`: `Config/Secrets*.xcconfig`); not in index | Present locally for Debug. Contains non-empty `USDA_API_KEY` (length only inspected; value not recorded). Expected for local development. |
| `Backend/.dev.vars` | **Ignored** (`Backend/.gitignore`); not in index | Not required for this audit pass if absent; example is empty-key template. |
| `Config/Secrets.xcconfig.example` | Tracked | Empty `USDA_API_KEY=` + example proxy hosts only. |
| `Backend/.dev.vars.example` | Tracked | Empty `USDA_API_KEY=` only. |

**Pass criteria:** no real credentials in git-tracked source. **Met.**

**Operational note:** consider speeding up `Scripts/scan-repository-secrets.sh` (e.g. `grep`/`rg` first pass) so CI does not time out; LaunchReadiness already marks the source scan as done historically—re-run on faster tooling if CI enforces the script exit code under tight budgets.

---

## 2. Secret handling design (supporting evidence)

| Control | Status |
| --- | --- |
| Debug may inject `USDADebugAPIKey` via `Info-Debug.plist` → `$(USDA_API_KEY)` | **OK** — Debug-only plist |
| Release `Info.plist` has **no** debug API key field | **OK** |
| `Config/Release.xcconfig` does **not** `#include` Secrets and does not define `USDA_API_KEY` | **OK** |
| `Config/Debug.xcconfig` optional `#include? "Secrets.xcconfig"` | **OK** |
| `AppConfiguration` reads `USDADebugAPIKey` only under `#if DEBUG` | **OK** |
| Release path expects HTTPS privacy proxy (`ProxyBaseURL` + host pin); rejects user/password/query in proxy URL | **OK** |
| Backend Worker docs/tests: USDA key as `X-Api-Key` header, not query param; secrets via Wrangler / `.dev.vars` | **OK** (source-level) |
| Direct USDA `api_key` query allowed only on Debug/direct-eval clients | **OK** (not Release production path) |

No accidental secret commit to fix.

---

## 3. Info.plist privacy usage strings

Files: `JustLogIt/Resources/Info.plist`, `JustLogIt/Resources/Info-Debug.plist`.

| Key | Present | Justified by code? | Verdict |
| --- | --- | --- | --- |
| `NSCameraUsageDescription` | Yes | `CameraImagePicker`, composer “Take photo”, `AVCaptureDevice` auth | **Pass** — necessary |
| `NSPhotoLibraryUsageDescription` | Yes | `PhotosPicker` / photo selection in log composer | **Pass** — necessary |
| `NSHealthUpdateUsageDescription` | Yes | Write-only HealthKit nutrition writer + Settings enablement | **Pass** — necessary |
| Location / microphone / contacts / tracking / Face ID / Bluetooth / etc. | **No** | N/A | **Pass** — no unnecessary usage strings |

Notes:

- Health is **write-only** (`requestAuthorization(toShare:…, read: [])`); no `NSHealthShareUsageDescription` required for current design.
- Entitlement `com.apple.developer.healthkit` present; matches optional Health sync feature.
- Camera/photo strings align with photo-assisted food identification (implemented / in backlog path), not leftover placeholders.

**Result: PASS** — usage strings are minimal and match shipped capabilities.

---

## 4. PrivacyInfo.xcprivacy

File: `JustLogIt/Resources/PrivacyInfo.xcprivacy`.

| Declaration | Reason code | Code evidence | Verdict |
| --- | --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `UserDefaultsRememberedFoodStore`, Health sync preferences, schema epoch helpers | **Pass** — appropriate |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | `DiskCachedFoodDataProvider` / `FoodDataCacheIO.live` uses `.contentModificationDateKey` on app cache files | **Pass** — appropriate |
| `NSPrivacyCollectedDataTypes` / tracking domains | Absent | Intentional per `Documentation/Privacy.md` until production Cloudflare/USDA retention is audited | **Pass for source audit**; remains a **launch gate**, not a source fail |
| Tracking APIs / ATT | Absent | No accounts, ads, or analytics in app model | **Pass** |

### Documentation drift (non-blocking)

`Documentation/Privacy.md` and `Documentation/AppStoreMetadataDraft.md` state that the app-source audit found **no** direct required-reason **file timestamp** use. That sentence is **outdated**: cache expiry reads `contentModificationDate`, and the manifest correctly declares `FileTimestamp` / `C617.1`.

**Recommendation (optional follow-up):** update Privacy.md / App Store draft to mention cache mtime under `C617.1`. Not a privacy-manifest failure.

**Result: PASS**

---

## 5. Out of scope / remaining launch gates

These are **not** source-audit failures; listed for completeness against `Backlog/LaunchReadiness.md` and `Documentation/Privacy.md`:

- Deploy Worker with encrypted `USDA_API_KEY`; verify production route, logs, IP stripping, quota, rollback.
- Finalize App Store privacy nutrition labels against **deployed** Cloudflare + USDA behavior.
- Secret scan of **archived release binary** (separate from source scan).
- Publish privacy policy / support URL.

---

## 6. Summary

| Area | Pass/Fail | Summary |
| --- | --- | --- |
| Secrets in git-tracked source | **PASS** | No API keys, PEM keys, or long secret literals; only placeholders and env field names |
| Local secrets file hygiene | **PASS** | `Secrets.xcconfig` / `.dev.vars` ignored and untracked |
| Info.plist privacy strings | **PASS** | Camera, photos, Health update only — all used |
| PrivacyInfo.xcprivacy | **PASS** | UserDefaults + file timestamps justified; no tracking |
| Official scan script runtime | **Note** | Script rules clean via equivalent scan; bash script itself too slow for tight automation timeout |

**Audit conclusion: PASS.** No secret commits to reverse. No privacy string or manifest failures for the repository source snapshot on 2026-07-18.
