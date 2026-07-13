# JustLogIt continuation handoff

Last updated: 2026-07-12, America/New_York  
Prepared because the primary Codex task was approaching its weekly usage limit.  
Audience: a new implementation agent with no reliable access to the preceding conversation.

This is the authoritative continuation map, not proof that the product is finished. Read this entire document before editing. Then inspect the current worktree because several launch-hardening changes are intentionally uncommitted and have not completed compilation.

## 1. Immediate orientation

Repository:

- Local path: `/Users/james/Documents/JustLogIt`
- Git branch: `main`
- Remote: `https://github.com/jamessturges/JustLogIt.git`
- Repository is intended to remain private.
- Last committed and pushed revision: `874df33 Harden food interpretation and Health sync`
- Earlier commits: `bc9d067 Polish logging UI and add HealthKit sync`, `009a74e Build JustLogIt MVP`
- Current worktree: dirty by design. It contains an unfinished Release-security/privacy tranche and an unfinished parser-evaluation tranche. Do not discard, reset, or blindly overwrite it.
- Xcode: `/Applications/Xcode-beta.app`, Xcode 27.0 build `27A5218g`
- XcodeGen: 2.45.4
- Target OS: iOS 27 beta
- Production bundle identifier selected in the dirty worktree: `com.jamessturges.JustLogIt`

The product goal remains broad:

> Polish the app with first-principles design logic, work through the backlog in the best priority order, and do not call it complete until the actual user journeys have been rigorously verified.

The best next action is **not** a new feature. It is to validate and finish the two uncommitted launch-quality tranches without losing either one.

## 2. Non-negotiable user steering

Treat every item below as a product requirement unless the user explicitly changes it.

1. Use iOS 27 beta APIs and Xcode-beta. Earlier references to a non-beta or another OS version were superseded.
2. Interpretation should use Apple's on-device Foundation Models framework. Food logs remain local. Nutrition values come from USDA data, never from model invention.
3. The production app must not contain the USDA API key. A minimal Cloudflare Worker is acceptable as a credential-shielding proxy, but its privacy and rate-limit implications must be described honestly.
4. Never commit API keys, local secrets, provisioning assets, certificates, or environment-specific values.
5. Do not claim “no data collected” merely because the app has no analytics. A USDA query transits Cloudflare and USDA; deployed logging, IP metadata, and retention must be audited before final privacy-label claims.
6. Work directly on `main`; this is currently a two-person project. The GitHub repository should remain private.
7. Use Simulator for UI development and user-flow testing. The user asked to stop relying on the physical iPhone for ordinary UI work. A compatible physical device may still be intrinsically required for final Foundation Models/HealthKit qualification, but do not silently change the testing strategy.
8. Before declaring completion, perform a genuine user-style click-through. Compilation and unit tests are not substitutes for tapping every expected interaction.
9. Log bugs as they are found in `Documentation/UIBugs.md`. A bug is not `Fixed` until its original reproduction passes on a named build and destination.
10. Give honest UI feedback. Remove AI-sounding filler, internal diagnostics, dead ends, misleading recovery messages, redundant hierarchy, and ambiguous controls.
11. Prefer sub-agents for bounded implementation and bug fixes when available. The primary thread should coordinate, review, verify, and integrate.
12. The logging view should feel like a modern chat composer, but not imitate chat superficially or obscure nutrition choices.
13. Conversation-first navigation with logging as the main view and a sidebar containing searchable recognized foods plus Settings at the bottom is backlogged, not yet implemented.
14. USDA results must be ranked for relevance deterministically. Do not use the on-device model to rewrite nutrition or silently remove USDA results.
15. Parsing performance must be measured before optimizing. The user specifically suspects the parser prompt may be slow.
16. Parser quality must be tested rigorously for sensible behavior, hallucinations, source grounding, latency, and repeatability. A real evaluation harness is required.
17. A food may eventually be a composition of ingredients. Never silently guess hidden oil or ingredient amounts. Composite foods are backlogged.
18. Photo-assisted identification and low-confidence clarification/confirmation are backlogged. Photo proposals must feed the same deterministic review flow; they must not directly become nutrition facts.
19. HealthKit sync is optional, write-only, and off by default. Write every USDA nutrient with a semantically matching HealthKit dietary type. Added sugar remains local because there is no distinct HealthKit added-sugar type.
20. Keep working in backlog priority order, but close correctness, privacy, Release, and acceptance gates before undertaking broad P2/P3 feature expansion.

## 3. Product truth and intended primary journey

The core hypothesis is that a person can log one food faster by describing it naturally while retaining control over the authoritative database match and consumed amount.

Expected primary flow:

1. The person describes one food in a bottom composer.
2. Apple's on-device model interprets only lookup-relevant structure: food/product, explicit brand, descriptors, preparation, and quantity language.
3. A deterministic source-grounding layer removes generated facts unsupported by the current message.
4. A deterministic query builder constructs USDA search terms.
5. The app explicitly submits one USDA request. It never searches on every keystroke.
6. A deterministic client-side ranker reorders the complete USDA result set for relevance. It never filters nutrition records or changes USDA values.
7. The person chooses the USDA match. The app never silently selects one.
8. Details are fetched after selection.
9. Serving resolution and nutrition arithmetic are deterministic.
10. If quantity cannot be safely resolved, the app asks for a focused clarification.
11. The person reviews nutrition before saving.
12. A SwiftData snapshot is saved locally first.
13. If Health sync is enabled and authorized, supported nutrients are also written to Apple Health. Health failure never discards the local entry.

Manual USDA search and manual nutrition entry must remain usable when Foundation Models is unavailable or interpretation fails.

## 4. Architecture and trust boundaries

The central architectural rule is:

> The model interprets language; deterministic code decides what is grounded, queries USDA, resolves servings, calculates nutrition, persists data, and writes HealthKit.

Important locations:

- App and feature code: `JustLogIt/`
- Log UI and state machine: `JustLogIt/Features/Log/`
- Entries UI: `JustLogIt/Features/Entries/`
- Settings UI: `JustLogIt/Features/Settings/`
- Foundation Models adapter: `JustLogIt/Services/FoundationModelsFoodParser.swift`
- USDA provider/cache: `JustLogIt/Services/USDAFoodDataProvider.swift`
- HealthKit writer/coordinator: `JustLogIt/Services/HealthKitNutritionWriter.swift`, `JustLogIt/Services/HealthSyncCoordinator.swift`
- Pure deterministic package: `Packages/JustLogItCore/`
- App unit tests: `JustLogItTests/`
- UI tests: `JustLogItUITests/`
- Cloudflare Worker scaffold: `Backend/`
- Product backlog: `Backlog/`
- UI defect ledger: `Documentation/UIBugs.md`
- Manual acceptance script: `Documentation/ManualAcceptanceTest.md`
- Performance gates: `Documentation/Performance.md`
- Privacy language: `Documentation/Privacy.md`
- Generated project source: `project.yml`

`Packages/JustLogItCore` deliberately has no SwiftUI, SwiftData, FoundationModels, or HealthKit dependency. Keep parsing-grounding, query construction, ranking, serving resolution, and nutrition calculations deterministic and independently testable there whenever practical.

## 5. What is already committed and believed to work

Commit `874df33` is the latest pushed baseline. It contains:

- Chat-style Log UI and native keyboard behavior.
- Manual nutrition entry, Entries, and Settings.
- SwiftData entry snapshots.
- Optional HealthKit write-only integration for 39 supported dietary quantities.
- Health lifecycle safeguards: pending reconciliation, bounded retries, deletion tombstones, and exact sync-identifier cleanup.
- Deterministic source grounding of Foundation Models output.
- Protection against stale cross-request product/quantity facts, including the observed Fairlife-to-Oreo leak.
- Unit aliases, mixed fractions, written fractions, and approximation markers.
- Deterministic USDA result relevance ranking. Oreo cookies outrank a McFlurry that merely contains Oreo cookies.
- DEBUG-only duration instrumentation for model availability, session creation, response, mapping, and USDA lookup. It records durations/outcomes, not food text or API values.
- A durable UI bug ledger and a manual acceptance checklist.
- Backlog documents for clarification/confirmation, composites, conversation navigation, offline data, remembered foods, photo identification, HealthKit, and a possible USDA mirror.

Most recent verified evidence before the current dirty tranche:

- 23/23 `JustLogItCore` tests passed.
- Strict Swift formatting/lint and `git diff --check` passed.
- Generic iOS Simulator `build-for-testing` passed.
- Generic iOS Simulator Release build passed.
- The project performed a real Debug USDA lookup using the user's ignored local key.

Do not stretch these results. They prove the committed baseline, not the current dirty tree and not final UI acceptance.

## 6. Known test-infrastructure trap

Repeated `xcodebuild test` runs on the iOS 27 Simulator have hung in Xcode's test-run finalizer. The prior agent retried this enough times to establish that blindly repeating it wastes time and makes the work appear stuck.

Use this order:

1. Pure package tests.
2. Swift formatting and static checks.
3. Generic Simulator `build-for-testing` to prove app/test compilation.
4. Focused Simulator test execution only when necessary, with a bounded timeout and one active runner.
5. User-level Simulator interaction via XCUITest/Computer Use after the build is stable.

Never launch multiple concurrent `xcodebuild test` jobs against the same Simulator. If the finalizer hangs again, capture the evidence, terminate the one runner, and continue with build-for-testing plus bounded focused tests. Do not misreport a hung runner as passing or failing application behavior.

## 7. Current dirty worktree: preserve it

At handoff time `git status --short` reported:

```text
 M .gitignore
 M Config/Base.xcconfig
 M Config/Secrets.xcconfig.example
 M Documentation/Privacy.md
 M JustLogIt.xcodeproj/project.pbxproj
 M JustLogIt/Resources/Info.plist
 M JustLogIt/Services/AppConfiguration.swift
 M JustLogIt/Services/FoundationModelsFoodParser.swift
 M JustLogIt/Services/USDAFoodDataProvider.swift
 M JustLogItTests/AppConfigurationTests.swift
 M README.md
 M project.yml
?? Config/Debug.xcconfig
?? Config/Release.xcconfig
?? JustLogIt/Resources/Info-Debug.plist
?? JustLogIt/Resources/PrivacyInfo.xcprivacy
?? JustLogItTests/ParserEvaluationCorpus.swift
?? JustLogItTests/ParserEvaluationHarnessTests.swift
?? Scripts/
```

The two tranches are described separately below. They share the generated project but otherwise have limited overlap.

### 7.1 Release configuration and privacy hardening tranche

Implemented but not fully rebuilt after the last fix:

- `Config/Base.xcconfig`
  - Contains shared metadata only.
  - Sets `PRODUCT_BUNDLE_IDENTIFIER = com.jamessturges.JustLogIt`.
  - No longer imports secrets or defines USDA/proxy values.
- `Config/Debug.xcconfig`
  - Includes Base.
  - Optionally includes ignored `Config/Secrets.xcconfig`.
  - May define a Debug proxy or Debug-only USDA key.
- `Config/Release.xcconfig`
  - Includes Base.
  - Does not include Secrets and does not define a USDA key.
  - Accepts only injected `PROXY_BASE_URL` and `PROXY_ALLOWED_HOST`.
- `JustLogIt/Resources/Info-Debug.plist`
  - The only app plist containing `USDADebugAPIKey`.
- `JustLogIt/Resources/Info.plist`
  - Release plist has proxy URL and allowed-host pin.
  - It has no debug USDA key field.
- `JustLogIt/Services/AppConfiguration.swift`
  - Reads/represents the direct key only under `#if DEBUG`.
  - Validates an absolute root-only HTTPS URL.
  - Rejects user info, ports, query, fragment, and non-root paths.
  - Release requires an exact separate host pin.
- `JustLogIt/Services/USDAFoodDataProvider.swift`
  - Direct USDA endpoint and its `api_key` URL construction exist only under `#if DEBUG`.
- `Scripts/validate-release-configuration.sh`
  - Release pre-build guard.
  - Rejects missing proxy/pin, unsafe URL shapes, pin mismatch, placeholder/local hosts, direct USDA settings, and placeholder bundle identifiers.
  - Failure output does not echo values.
- `Scripts/verify-release-product.sh`
  - Post-build guard for processed Release plist and binary/app marker strings.
- `.gitignore`
  - Expanded for secret xcconfig variants, `.env*`, archives, provisioning profiles, certificates, and private keys.
- `JustLogIt/Resources/PrivacyInfo.xcprivacy`
  - Minimal required-reason manifest declaring same-app `UserDefaults` with reason `CA92.1`.
  - This reason was verified against the installed Xcode 27 schema.
  - Do not add file timestamp, disk space, boot time, or active keyboard categories without new source evidence.
- `README.md` and `Documentation/Privacy.md`
  - Updated to distinguish Debug direct key from Release proxy.
  - Correctly explain xcconfig URL escaping.
  - Avoid declaring an empty collected-data inventory before deployed Cloudflare/USDA behavior is audited.
- `project.yml` and generated `JustLogIt.xcodeproj/project.pbxproj`
  - Separate Debug/Release configs and plists.
  - Include privacy manifest and build guard phases.

Validation already performed on this tranche:

- Strict Swift formatting passed for the Release-related Swift edits.
- `bash -n` passed for both scripts.
- `plutil -lint` passed for all plists.
- Direct guard probes passed: missing config rejected, path rejected, pin mismatch rejected, synthetic key rejected, valid pinned HTTPS accepted.
- `git diff --check` passed at that point.
- XcodeGen generation succeeded.

The first Debug `build-for-testing` then failed only because Xcode's user-script sandbox denied reading `Scripts/validate-release-configuration.sh`. The agent added the script files as explicit build-phase inputs and regenerated the project. **No build was run after that correction.** This tranche is unverified until the builds below pass.

### 7.2 Parser evaluation and lean-prompt tranche

Implemented but not formatted, compiled, documented, or run:

- `JustLogIt/Services/FoundationModelsFoodParser.swift`
  - Extracts `FoundationModelsPromptProfile` with `.production` and `.leanCandidate`.
  - `.production` is the exact existing instruction text.
  - `.leanCandidate` is materially shorter.
  - `FoundationModelsFoodParser()` still defaults to `.production`.
  - The lean candidate has **not** been adopted.
- `JustLogItTests/ParserEvaluationCorpus.swift`
  - Versioned corpus `1.0.0`.
  - 40 cases across simple foods, brands, quantities, mixed fractions, multiple foods, compounds, context changes, ambiguity, non-food input, prompt injection, impossible values, cross-clause binding, and hallucination traps.
  - Expectations distinguish accept, clarify, clarify-or-reject, multiple-or-reject, reject, and human review.
- `JustLogItTests/ParserEvaluationHarnessTests.swift`
  - Deterministic corpus integrity and prompt-size checks.
  - A manual on-device suite gated by `RUN_ON_DEVICE_PARSER_EVAL=1`.
  - Skips when the system model is unavailable.
  - Defaults to two repeats; accepts 2–5 through `PARSER_EVAL_REPEATS`.
  - Runs production and lean profiles over the same corpus.
  - Scores source grounding, expected fields, unsupported inventions, expected behavior, stability, and latency.
  - Emits a JSON XCTest attachment using case IDs by default.
  - Includes raw input only when explicitly opted into with `PARSER_EVAL_INCLUDE_INPUT=1`.
  - Uses no external LLM judge.

Proposed production thresholds in the harness:

- Source grounding: 100%
- Unsupported invented facts: 0
- Required field accuracy: at least 90%
- Behavior accuracy: at least 85%
- Stability: at least 90%
- p95 latency: no more than 15 seconds

The lean candidate is report-only. It is eligible only if it has no safety regression, meets absolute thresholds, does not regress required-field or behavior scores, remains within two percentage points of production stability, and p95 latency is no more than 110% of production.

Critical state detail: the generated `.xcodeproj` currently references `ParserEvaluationCorpus.swift` but, at the final inspection, did **not** reference `ParserEvaluationHarnessTests.swift`. Regenerate with XcodeGen after formatting/compilation fixes.

No real Foundation Models evaluation has been run. Do not claim the current or lean prompt is good, fast, stable, or non-hallucinatory based solely on the corpus existing.

Likely compile hotspots called out by the implementing sub-agent:

- Xcode 27 spelling/availability of `XCTAttachment(contentsOfFile:)`.
- Swift 6 actor isolation in async XCTest.
- `Duration` helper style/access.
- `SystemLanguageModel.default.availability` pattern matching.
- Enum associated-value switch formatting.
- Corpus product-token expectations that may not satisfy the strict product-grounding rule.

## 8. Exact next actions, in order

Do not skip directly to feature work. Execute this sequence and update this document or the appropriate ledger with evidence.

### Step 1 — Preserve and inspect

```sh
cd /Users/james/Documents/JustLogIt
git status --short
git diff --check
git diff --stat
```

Read every dirty file. Confirm no unrelated user edits are being overwritten. Do not read or print the real local secret. It is correctly ignored; this was verified with `git check-ignore`.

### Step 2 — Format the new parser files and regenerate

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

xcrun swift-format format --in-place \
  JustLogIt/Services/FoundationModelsFoodParser.swift \
  JustLogItTests/ParserEvaluationCorpus.swift \
  JustLogItTests/ParserEvaluationHarnessTests.swift

xcodegen generate

rg -n 'ParserEvaluationCorpus|ParserEvaluationHarnessTests|PrivacyInfo' \
  JustLogIt.xcodeproj/project.pbxproj
```

Both parser evaluation files and the privacy manifest must appear in the generated project.

Run the repository's existing strict formatting/lint convention over all relevant Swift files. Do not assume the formatter run proves compilation.

### Step 3 — Run pure deterministic tests first

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swift test --package-path Packages/JustLogItCore
```

Expected baseline from the previous commit: 23 passing tests. If the count changes, explain why.

### Step 4 — Compile Debug app and all test bundles

Prefer a generic destination first because it avoids Simulator runner instability:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -quiet \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -destination 'generic/platform=iOS Simulator' \
  build-for-testing
```

The previous sub-agent suggested `name=iPhone 17 Pro`, but generic Simulator is sufficient for the first compilation gate and has historically been more reliable.

If the build fails:

1. Fix actual Swift compile failures in the parser harness.
2. If a script sandbox denial remains, declare exact build-phase input files in `project.yml` and regenerate. Prefer exact `Info.plist` and executable inputs for the post-build verifier if directory traversal is denied.
3. Do not globally disable `ENABLE_USER_SCRIPT_SANDBOXING` merely to make the scripts work unless no scoped input declaration can work, and document the reasoning if forced.

### Step 5 — Compile a Release product through both guards

Use a nonsecret syntactically valid placeholder under a real-looking app-owned host. This only validates the build boundary; it does not assert deployment exists.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -quiet \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  PROXY_BASE_URL='https://proxy.justlogit.app' \
  PROXY_ALLOWED_HOST='proxy.justlogit.app' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This command must exercise both the pre-build and post-build guards.

Then locate the built `.app` without printing secrets and assert:

- Processed Release `Info.plist` includes proxy URL and allowed host.
- It does not include `USDADebugAPIKey`.
- Release executable/app strings do not contain `USDADebugAPIKey`, `USDA_API_KEY`, or the direct-query marker `api_key` from app code.
- Release build settings do not define `DEBUG` or a meaningful `USDA_API_KEY`.

Be careful: scan booleans/markers, not environment values. Never dump all build settings or all strings into chat if that could expose a local value.

### Step 6 — Run focused app tests if the runner cooperates

At minimum compile the test bundle. If running tests, start with the smallest deterministic parser/configuration subset and use a bounded timeout:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:JustLogItTests/ParserEvaluationCorpusTests \
  -only-testing:JustLogItTests/AppConfigurationTests \
  test
```

If the Xcode 27 finalizer hangs, stop the one runner and report that the execution result is unavailable. Do not retry indefinitely.

### Step 7 — Document the parser evaluation harness

Add `Documentation/ParserEvaluation.md` covering:

- Why model quality cannot be established through mocked unit tests.
- Corpus versioning policy.
- Deterministic expectations versus human-review cases.
- Default redaction and the explicit raw-input opt-in.
- Production and lean adoption thresholds.
- Simulator/model-availability caveat.
- Exact compatible-device command.
- How to retain the `.xcresult` and JSON attachment.
- A results table with OS build, device, model availability, corpus version, repeats, prompt profile, rates, and p50/p95 latency.
- A hard rule that the lean prompt cannot ship based only on prompt character count or CI compilation.

### Step 8 — Run the real parser evaluation when an eligible destination exists

The physical iPhone previously discovered was:

- iPhone 17 Pro Max
- iOS 27.0 build `24A5380h`
- CoreDevice identifier `DF747E72-7C06-57D5-8D12-7038FC96CDC8`
- UDID `00008150-000A5D691AC0401C`
- Paired, Developer Mode enabled, but last observed as unavailable/offline.

The earlier diagnosis was that the phone was not connected, not that signing was inherently broken. The user later asked to skip the real phone for ordinary UI work. Do not force this step without acknowledging that steering. First attempt the manual suite on the Simulator only if `SystemLanguageModel.default.availability` is actually `.available`; otherwise record the skip and defer real-model qualification until the user permits/connects an eligible device.

When allowed, set:

```text
RUN_ON_DEVICE_PARSER_EVAL=1
PARSER_EVAL_REPEATS=2
```

Leave `PARSER_EVAL_INCLUDE_INPUT` unset unless the user explicitly accepts raw prompt text in the local test artifact.

Do not adopt `.leanCandidate` merely because it is shorter. Adopt it only after the report proves eligibility and human-review cases have been inspected for sensible output.

### Step 9 — Finish Worker hardening

The Worker implementation did not begin before handoff. The read-only audit is complete and should be implemented next in `Backend/`.

Required bounded changes:

1. Send USDA authentication through the supported `X-Api-Key` request header, not an `api_key` URL query.
2. Keep the USDA origin and allowed paths pinned.
3. Set fetch redirect handling to `error`; never follow an upstream redirect containing the credential.
4. Keep the timeout active through response-body consumption, not merely until headers arrive.
5. Require an `application/json` success content type.
6. Enforce both declared `Content-Length` and streaming body limits. Proposed cap: 2 MiB.
7. Normalize upstream errors without returning upstream bodies, URLs, credentials, or diagnostics.
8. Preserve controlled inbound/outbound headers, `Cache-Control: no-store`, and `X-Content-Type-Options: nosniff`.
9. Test redirects, oversized responses, incorrect content type, timeout, 401, 403, 5xx, secret non-reflection, and success.

The USDA limit is 1,000 requests/hour per IP. All Worker requests can appear to USDA under shared egress, so a public Worker needs a global budget.

Smallest defensible design found in the audit:

- One singleton Cloudflare Durable Object under constant key `global`.
- Store only `{epochHour, count}`.
- Enforce a ceiling of 900 USDA requests/hour, leaving operational headroom.
- Fail closed if the binding is missing/unavailable.
- Do not store food queries or raw IP addresses.
- A per-colocation Rate Limit binding alone is not a global quota guarantee.
- Add `durable_objects.bindings` and a `migrations.new_sqlite_classes` entry to `Backend/wrangler.jsonc`.

This still needs deployment validation. Do not claim the Durable Object is deployed merely because configuration and tests exist.

Expected Worker files:

- `Backend/src/index.ts`
- `Backend/test/index.test.ts`
- `Backend/wrangler.jsonc`
- `Backend/README.md`
- `Backlog/LaunchReadiness.md`
- Possibly `Documentation/Architecture.md`

After implementation run the package's existing lint/typecheck/test/dry-bundle commands from `Backend/`. Inspect `Backend/package.json` for exact script names rather than guessing.

### Step 10 — Secret hygiene, commit, and push the tranche

Before staging:

- Verify `Config/Secrets.xcconfig` is ignored without reading it.
- Search tracked/source files for credential markers and obvious real values.
- Exclude ignored secrets, `Backend/node_modules`, build products, `.xcresult`, and derived data from scans and staging.
- Review every diff.
- Confirm the generated project matches `project.yml`.
- Confirm no test artifact with raw food text was added.

Only after Debug compilation, Release compilation/verification, deterministic tests, and Worker tests pass should this launch-hardening tranche be committed and pushed to `main`.

Suggested commit split if the diffs remain cleanly separable:

1. `Harden Release configuration and privacy manifest`
2. `Add parser quality evaluation harness`
3. `Harden USDA Worker boundary and global quota`

Because all changes share `project.yml`/`.pbxproj`, one reviewed integration commit is also acceptable. Never stage `Config/Secrets.xcconfig`.

## 9. Parser quality: engineering interpretation

The current design has a strong safety boundary but is not yet sufficient evidence of “sensible answers.”

Strengths:

- A fresh `LanguageModelSession` is constructed for each parse, reducing conversation-history contamination.
- Greedy sampling and temperature zero improve repeatability.
- Generated search terms are discarded.
- `ParsedFoodRequestGrounder` reconstructs search terms from a product grounded in current source text.
- Brands, preparation, descriptors, numeric/unit pairs, container facts, alternate quantities, approximation, and ambiguity notes are stripped unless current-source evidence supports them.

Known limitations the evaluation must expose:

- The generated schema requires a nonoptional `productName`; non-food requests may pressure the model to invent a food-like product.
- Word presence does not prove intent. Prompt injection can mention `pizza` or `banana`, allowing a generated product to be lexically grounded even though the user was not logging it.
- `containsMultipleFoods` is ultimately model-provided and only weakly corroborated by conjunction presence. “Mac and cheese” contains a conjunction but is normally one dish; “eggs, bacon” may contain multiple foods without a conjunction.
- The parser contract says “one principal food,” while multiple-food, non-food, and clarification outcomes are not modeled as a first-class result enum.
- A shorter instruction may not materially reduce latency because the 17-field generated schema and its `@Guide` descriptions contribute substantial prompt/schema work.

Likely follow-up if the real corpus fails:

1. Do not relax hallucination thresholds to make the test green.
2. Introduce a typed interpretation outcome, such as accepted food / requires clarification / multiple foods / not a food request, instead of forcing every response into `ParsedFoodRequest`.
3. Keep deterministic validation after model generation.
4. Add focused non-model prechecks only when they are semantically defensible; avoid a brittle keyword blacklist.
5. Re-run the same versioned corpus and add a regression case for every observed failure.
6. Adopt any prompt/schema change only after production-vs-candidate comparison on the same OS/model build.

## 10. UI quality and acceptance state

The UI has improved substantially but has **not** completed a full acceptance pass. `Documentation/UIBugs.md` contains UI-001 through UI-011. Every one is currently `Ready to verify`; none is legitimately `Fixed` because the original user-level reproduction has not been rerun on a named stable build.

Important ledger hygiene issue: several bug entries still say “fix currently in the working tree” or have blank fix commits even though the code was committed in `874df33`. Update the metadata only after confirming which commit contains each fix; do not mark them Fixed until manual reproduction passes.

Required final Simulator pass lives in `Documentation/ManualAcceptanceTest.md` and covers:

- Fresh launch and navigation.
- Configured USDA happy path.
- Composer, keyboard dismissal, examples, and cancellation.
- Parser/search/no-result/details recovery.
- Manual entry.
- Entries search, detail, and deletion.
- Settings and cache confirmation.
- Health UI without granting access.
- Dark Mode and Dynamic Type.
- End-of-run data integrity.

Acceptance attitude:

- Tap every visible control once.
- Verify the keyboard dismisses through native gestures and submission.
- Inspect copy as a real user, not as the implementer.
- No raw errors, configuration keys, endpoint names, model jargon, or internal statuses should leak into normal UI.
- Every failure state needs a useful next action.
- No button may silently do nothing.
- Check that navigation always has a clear way back.
- Test fresh data and existing data.
- Check at least one network failure, one model failure, and one manual path.
- Check VoiceOver labels, large text truncation, contrast, dark mode, and touch targets.
- Log a separate bug immediately for every independently fixable failure.
- Delegate each bounded bug when possible, integrate, rebuild, and rerun its original reproduction.

Do not implement the large conversation-sidebar redesign before this pass unless the current structure itself blocks the primary journey. Its design is preserved in `Backlog/ConversationNavigation.md`.

## 11. HealthKit state

Committed HealthKit behavior is intentionally local-first and write-only.

- Setting is off by default.
- Enabling from Settings explicitly requests write authorization.
- Durable preference becomes enabled only after authorization reports useful writable types.
- Entry save persists locally regardless of Health result.
- Automatic reconciliation does not present authorization UI.
- Pending/failed writes use bounded persisted retry state.
- Deletion writes a tombstone before Health cleanup.
- Cleanup matches exact app-owned sync identifiers and does not read/delete other sources' records.
- Denied or failed entries expose an explicit retry/recovery path.

Still unproven:

- System permission-sheet behavior on a real eligible device.
- Correct samples visible in Apple Health for the complete supported nutrient mapping.
- Interruption/relaunch reconciliation under actual HealthKit.
- Actual deletion cleanup after a successful real write.
- Provisioning profile regeneration with HealthKit entitlement once the phone is connected.

Do not imply Simulator UI verification proves HealthKit persistence semantics.

## 12. Privacy and production boundary

Safe claims today:

- No accounts.
- No advertising SDK.
- No behavioral analytics in app source.
- Original food text is interpreted on device.
- Food logs and nutrition snapshots are stored locally.
- Apple Health is optional and write-only.
- Deterministic USDA search terms are sent externally for lookup.

Claims that are not yet proven:

- “No data collected” in the App Store legal sense.
- “Cloudflare retains nothing.”
- “USDA retains nothing.”
- “No IP metadata exists.”
- Production Worker route, secret binding, logging state, transforms, quota guard, and rollback.

Before public release:

- Deploy the Worker with an encrypted USDA secret.
- Verify route and rollback.
- Audit Cloudflare invocation/custom logs, Logpush, account-level logs, Managed Transforms, visitor IP headers, and retention.
- Confirm USDA production capacity/rate attribution or establish a contact/escalation path.
- Reconcile the deployed facts with App Store privacy answers.
- Publish a public privacy policy and support URL.
- Add the in-app link if required by the final product/legal decision.

The privacy manifest's `CA92.1` is a required-reason API declaration, not a complete App Store privacy answer.

## 13. Backlog priority after launch blockers

Current durable ordering:

### P0 — MVP correctness and acceptance

- Finish parser evaluation and address failures.
- Finish Release/Worker boundary.
- Complete the full user-style acceptance pass.
- Verify all UI-001–UI-011 reproductions.
- Complete accessibility audit.
- Establish eligible-device Foundation Models and HealthKit evidence.

### P1 — Public launch readiness

- Deploy/audit Worker and quota protections.
- Final privacy labels/policy/support URL.
- Cache corruption/expiry/write-failure/disk-pressure tests.
- Physical-device cold/warm performance baselines.
- TestFlight crash/performance review.
- Icon rendering, screenshots, attribution, and App Store metadata.
- Final repository and archive secret scan.

### P2 — Next product work

- Conversation-first navigation and recognized-food sidebar.
- Clarification/confirmation engine.
- Composite foods and ingredients.
- Remembered foods.
- Offline USDA essentials/complete packs.
- Remaining HealthKit product enhancements after real demand.

The clarification engine should precede photo logging and should likely precede full composite creation. It provides one typed place for low-confidence corrections, multiple-food decisions, and unsafe quantity ambiguity.

### P3 — Evidence-driven exploration

- Photo-assisted food identification.
- Full USDA mirror/hot storage.

Do not casually bundle the 3 GB USDA dataset into V1. A mirror/offline package is feasible but adds updates, indexing, storage, search quality, App Store size, and operational complexity before the core logging loop is proven.

## 14. Sub-agent decomposition for the next primary agent

If parallel agents are available, use non-overlapping ownership:

1. **Release verifier agent**
   - Own only Config, plist, AppConfiguration, provider conditional compilation, scripts, README/privacy manifest, and related tests.
   - Compile Debug and Release; return exact evidence.
2. **Parser evaluation agent**
   - Own FoundationModels parser profiles, corpus, harness, and parser evaluation documentation.
   - Fix compilation and run deterministic gates.
   - Never claim real-model results without an eligible run.
3. **Worker hardening agent**
   - Own only `Backend/` plus Worker-specific documentation/backlog edits.
   - Implement transport/body/quota tests and no-secret behavior.
4. **Primary agent**
   - Inspect diffs, prevent overlap, run integration build, commit/push, then conduct the Simulator acceptance pass.

When an acceptance bug appears, assign one bounded bug per agent and require reproduction, code/test evidence, and an explicit statement of what remains manually unverified.

## 15. Definition of done

Do not mark the overarching goal complete until evidence supports all of the following:

- The current tree is committed and pushed without secrets.
- Debug and Release compile with Xcode 27 beta.
- Release cannot resolve/embed the direct USDA key and fails safely without a valid pinned proxy.
- Worker transport and global quota boundary are implemented, tested, deployed, and audited—or the app is explicitly not called public-release ready.
- Core deterministic tests pass.
- App unit/UI test bundles compile.
- Real parser evaluation passes explicit safety/quality thresholds on the intended iOS 27 system model.
- Any adopted prompt change is supported by comparative results.
- A complete Simulator user acceptance run passes.
- Every observed bug has a durable ledger entry and original reproduction verification.
- VoiceOver, Dynamic Type, keyboard, dark mode, contrast, and touch targets have been manually audited.
- HealthKit behavior is qualified on a real eligible device.
- Privacy statements match deployed infrastructure behavior.
- Public policy/support URLs and App Store materials exist for launch.
- Backlog work requested as part of the persistent goal has either been implemented and verified or remains honestly active; success must not be redefined around the already-finished subset.

## 16. First response recommendation for the successor

A good successor should tell the user, briefly:

> I have the handoff and the current dirty worktree. I am preserving both unfinished tranches. I’ll first make the Release boundary and parser harness compile, then run deterministic and Release gates, harden the Worker, commit/push, and proceed to the full Simulator acceptance pass. I will not adopt the lean prompt or claim parser quality until the on-device corpus produces evidence.

Then perform the work. Do not spend another turn merely restating the plan.

