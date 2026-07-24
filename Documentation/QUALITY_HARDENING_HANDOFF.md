# JustLogIt quality-hardening handoff and execution plan

Last updated: 2026-07-17

This is the ordered execution plan for taking the current working tree from a strong deterministic MVP to a trustworthy TestFlight build. Work top-to-bottom. Do not skip a correctness gate to pursue latency or visual polish.

## Current baseline

- Branch: `enhancements`
- The working tree intentionally contains the current integrated feature and test work. Preserve unrelated edits and do not reset the tree.
- Xcode: `/Applications/Xcode-beta.app`
- Target runtime: iOS 27 beta
- Core: 115/115 tests passed before this plan began.
- App tests: 96 executed, zero failures, one intentional physical-device parser-evaluation skip.
- UI: 9/9 full flow tests passed; native keyboard dismissal also passed as a focused run.
- LoggingEval: 6/6 tests passed.
- Real Mac Foundation Models smoke results are useful for candidate selection, not iPhone latency acceptance.
- Repository secret scan passed. Never print, commit, or copy values from `Config/Secrets.xcconfig`.

## 2026-07-16 simulator continuation

Canonical CI now selects a scheme-compatible iPhone Simulator by UDID instead of depending on a
developer's local simulator name. The complete local command, including UI smoke, passes: 205 Core
tests (10 XCTest plus 195 Swift Testing), 181 app tests with one intentional physical-device
evaluation skip, 20 LoggingEval tests, 18 Backend tests plus typecheck, repository secret scan, and
one UI smoke test.

Canonical Xcode test invocations also unset and command-line-blank USDA credential settings. A
captured verbose CI log was audited to contain no nonempty USDA credential value; do not rely on a
source-tree secret scan alone because Xcode build phases print their environment.

The Simulator-safe P1/P2 defects found during the post-hybrid audit are complete:

- Food-log persistence now has one rollback boundary around entry insertion, recognized-food
  upsert/linking, and save. A failure-injected test proves the context is clean afterward and a
  retry cannot persist or double-count the failed attempt.
- Interactive parser acquisition now bypasses an unfinished speculative prewarm for both the
  established 22-field parser and the six-field semantic proposer. The late prepared resource is
  discarded, duplicate preparation stays suppressed, and fresh/transcript-free session ownership
  is preserved. The blocked-prewarm regression passes on Simulator.
- Unexpected, non-cancellation errors from a future semantic proposer now become the existing
  typed manual-search recovery without a retry or invented request; cancellation still propagates.
- PhotosPicker transfer ownership is generation-guarded. A superseded or cancelled transfer cannot
  reach the model or clear the newer selection even if its loader ignores cancellation.
- SwiftData container construction runs off the main actor while publication, UI-test reset, retry
  generation, and stale-completion rejection remain main-actor controlled.
- Health write/delete intent must be durably saved before the external operation. Save/fetch
  failures roll back honestly, retain retryable sync identity/version state, and emit only closed,
  content-free operation categories.
- USDA cache and transport failures emit closed cache/transport outcomes. DNS and host-connectivity
  failures join the offline category; original errors still propagate and cache failures never
  block a successful upstream response.
- Composite remembered choices retain the normalized component lookup signature instead of the
  differently worded USDA description. They may rank the intended result first but never select it
  silently.
- The hybrid coordinator, app, and evaluator now consume one shared post-validation terminal
  resolution. Evaluated route accuracy therefore describes the same clarification, composite,
  search, or manual-recovery path the user receives.
- Physical XCTest attachments now record content-free token counts and observable prewarm,
  session-acquisition, response, mapping, extraction, routing, and grounding/merge durations. They
  still make no model-loading or time-to-first-token claim.
- The redacted consolidated promotion report validates exact block/case/repeat coverage, compares
  deterministic-first and hybrid separately against production using closed correctness/route/USDA
  terminal dimensions, and fails closed on tampering, missing pairs, unsafe differences, or focused
  matrices. Exact content equivalence remains an ephemeral private human review.
- Model use case and reasoning policy are independent evaluation dimensions. The iOS shipping
  default remains capability-aware light reasoning; disabled reasoning is Debug/evaluation-only
  and is absent from the Release app.

Focused, atomic, resumable physical-runner support is complete: filtered candidate/warm/case/family
blocks use a recorded seed, atomic manifests, report checksums, interruption restart, and
revision-safe resume. The complete 19-scenario UI suite passes in one uninterrupted Simulator test
process on the current tree. All remaining hybrid promotion evidence requires an attended
foreground iPhone session; do not replace it with more Simulator runs. Siri Spike A remains
deliberately sequenced after hybrid acceptance.

No P0 issue was found in this audit. The interrupted 2026-07-16 physical parser run is background
stress evidence only and is not a promotion result. Its replacement protocol and required runner
improvements are recorded in `Documentation/REAL_IPHONE_ACCEPTANCE_RUNBOOK.md`.

## Non-negotiable product rules

1. Incorrect nutrition is worse than asking one focused question.
2. A count is not a USDA serving unless USDA supplies a defensible count-to-mass relationship.
3. Remembered choices and ranking may order results; they are not permission to choose nutrition silently.
4. Model output is a proposal. Swift validates quantities, provenance, routing, and nutrition math.
5. Photos and food text remain on device. Only a user-approved derived food query may reach USDA.
6. Observability must be content-free and local. Never log food text, queries, brands, images, FDC IDs, entry UUIDs, headers, response bodies, or Health data.
7. A temporary in-memory save must never be described as durable.
8. Do not weaken grounding, clarification, or session isolation for a speculative speed improvement.

## Execution order

### 1. Eliminate silent quantity and portion assumptions — DO NOT SHIP

Status: Complete — Core 136/136, LoggingEval 8/8, and focused app quantity flow 3/3 pass.

Problems:

- Quantity-free foods with multiple materially different USDA portions can become an arbitrary `1 serving`.
- Incidental USDA metadata can break an otherwise ambiguous small/medium/large tie.
- Explicit counts can be multiplied by a generic gram serving without evidence that one item equals one serving.
- Size-mismatched household fallbacks can equate `small` and `large` items.
- Numeric product identity can be misread as quantity (`7 Layer Dip`, `7 Up`, `1% milk`).
- Bowls, plates, and glasses are currently treated as exact serving multiples without a household bridge.

Required changes:

- Apply the bare `1 serving` default only when the selected food exposes one unambiguous serving basis suitable for a generic serving.
- Compare all materially compatible portion rows for ambiguity before metadata tie-breaking.
- Require an explicit count/household/portion bridge before converting item counts to gram servings.
- Preserve requested size qualifiers through fallback resolution; incompatible sizes must clarify.
- Make quantity recovery reject percentages, product-name numerals, and numeric brand/product tokens unless an amount/unit relationship is explicit.
- Treat meal vessels as approximate only when a defensible basis exists; otherwise clarify.

Acceptance tests:

- Bare scrambled eggs with cup/small/large portions asks for amount/size.
- Unsized eggs remain ambiguous even when one portion has richer modifier/measure metadata.
- `2 cookies` plus only a generic `100 g serving` does not become `200 g`.
- `2 small eggs` does not use a `1 large egg` household fallback.
- `7 Layer Dip`, `7 Up`, and `1% milk` do not recover quantities of 7, 7, and 1.
- Existing Big Mac, Oreo, two-large-eggs, explicit grams, branded serving, fraction/container, and culinary-density regressions remain green.

Verification:

```sh
cd Packages/JustLogItCore
swift test
```

### 2. Tighten USDA auto-selection — DO NOT SHIP

Status: Complete — conservative selection policy is integrated; weak, derivative, duplicate, close, and remembered matches stay in the picker.

Problems:

- A single derivative match such as `JASMINE RICE PUDDING` can auto-select for `jasmine rice`.
- Multiple close matches can bypass the picker without a meaningful rank margin.

Required changes:

- Auto-selection must consume explicit rank confidence/mismatch information rather than repeat a looser token-containment rule.
- Safe candidates are limited to an exact stated brand/product identity or a clearly dominant exact food form.
- Single-result responses are not inherently trustworthy.
- Any remembered match keeps the picker visible.

Acceptance tests:

- A lone derivative food remains in the picker.
- Multiple exact generic variants remain in the picker without a meaningful margin.
- Exact branded products may still auto-select when all stated identity evidence matches.
- Rice, Oreo/composite, remembered-food, and choose-different regressions remain green.

### 3. Make persistence truthfulness and navigation deterministic — DO NOT SHIP

Status: Complete — volatile saves are blocked with truthful UI, deterministic test launch coverage exists, and cross-tab paths replace stale destinations.

Problems:

- Volatile fallback mode permits saving and then says `Entry saved on this device`, although the entry disappears on process exit.
- Cross-tab entry/food links append onto an existing Entries navigation path and can create misleading Back stacks.

Required changes:

- Prefer disabling durable save while the store is volatile. If temporary logging remains available, label it explicitly before and after save.
- Add a deterministic UI-test launch mode for volatile storage.
- Replace or reset the Entries navigation path before handling a cross-tab destination.

Acceptance tests:

- A volatile-store UI test cannot produce a durable-success message.
- Persistent mode retains the existing save behavior.
- Repeated completion links replace the destination instead of stacking stale details.
- A local-store open failure preserves the original store bytes.

### 4. Version the food-detail cache

Status: Complete — cache schema v2 is active, legacy entries miss safely, and all 9 focused cache tests pass.

Problem: detail cache files written before complete USDA portion retention decode with `foodPortions == []` and remain active for up to 30 days.

Required changes:

- Add an explicit cache schema version to keys, envelopes, or the directory name.
- A schema bump must make older incompatible detail entries miss safely.
- Keep cache clearing user-visible and non-destructive to logs.

Acceptance tests:

- Old-version detail envelopes are ignored.
- Current search/detail hits, TTLs, corruption fallback, write failure, and 500-file bound remain green.

### 5. Add real USDA HTTP and DTO contract tests — DO NOT SHIP

Status: Complete — 14/14 real provider boundary/DTO tests pass, including all source families, error/transport cases, safe request construction, and all 40 canonical nutrient keys/units.

Required fixtures:

- Redacted Branded, Foundation, FNDDS, and SR Legacy search/detail JSON.
- Multiple `foodPortions` rows, nullable fields, label nutrients, per-100 g nutrients, energy alternatives, and representative vitamins/minerals.

Required assertions:

- Direct and proxy request path/body/header behavior.
- 400, 401/403, 404, 429 with sanitized `Retry-After`, 5xx, timeout, non-HTTP, malformed JSON, and valid nullable responses.
- Portion amount/gram-weight mapping and label/per-100 g merging.
- Every supported nutrient and canonical unit.
- No secret or raw upstream body reaches UI-facing errors.

Implementation note: inject a controlled `URLSession`/`URLProtocol` boundary into the concrete provider; current domain-object mocks do not test decoding.

### 6. Establish persistent schema migrations and save boundaries — DO NOT SHIP AFTER FIRST BETA

Status: Partially complete — real disk close/reopen coverage passes for USDA, manual-equivalent, and composite records. Migration is blocked on capturing actual legacy stores because multiple materially different shipped schemas all identify themselves as SwiftData `1.0.0`.

Required changes/tests:

- Adopt `VersionedSchema` and an explicit `SchemaMigrationPlan` before external users accumulate data.
- Build an old-schema fixture, close it, open it with the current schema, and verify entries, recognized foods, nutrients, composites, and Health deletion tombstones.
- Add a disk-backed close/reopen test for a normal save.
- Complete Manual Entry through Save and reopen the exact stored record.
- Complete a full composite parse → per-component selection/quantity → aggregate → save → reopen flow.

Completed evidence:

- Disk-backed USDA, manual-equivalent, and two-component composite transactions are closed, reopened through a new `ModelContainer`, and verified with recognized-food linkage (11/11 focused tests plus 1/1 strengthened timestamp/retry test).
- The remaining composite requirement is the full UI/view-model assembly path, not persistence serialization.

Migration safety note:

- Do not add a nominal V1→V4 `SchemaMigrationPlan` over the present model types. Historical commits changed the persisted shape while retaining SwiftData's default schema version `1.0.0`, so a conventional chain may not identify the actual store checksum and could strand data.
- Capture real store fixtures from each shipped shape first. Reconstruct immutable historical schemas and prove fixture opens. If SwiftData cannot distinguish the duplicate-version variants, migrate a copy through an explicit compatibility importer into a fresh versioned store, validate record counts/IDs/payloads, preserve the original backup, and only then atomically swap.

### 7. Harden the exposed photo path

Status: In progress — protocol injection, bounded one-time downsampling, and cancellation/concurrency tests are under focused verification.

Until this section passes, hide photo input from release builds or treat it as experimental.

Required changes:

- Introduce an injectable `FoodImageProposing` protocol.
- Downsample once, off the UI executor, to a measured maximum dimension; share the bounded representation with the model and transcript.
- Do not retain original multi-megabyte photo data longer than the active proposal requires.
- Preserve caption recovery and cancellation generation guards.

Acceptance tests:

- Large image downsampling and orientation.
- Image → clarification/search using a fake proposer.
- Low-confidence, multi-food, unavailable, refusal, timeout, and invalid-image paths.
- A superseded photo completion cannot replace a newer text/photo flow.
- USDA receives only the derived query; never image bytes.
- No photo is persisted in a completed entry.

### 8. Add canonical CI and close test-reliability gaps

Status: Partially complete — canonical `Scripts/ci.sh`, isolated HealthKit preferences, a
continuation-based authorization gate, pinned UI locale, credential-blanked Xcode invocations, and
robust Simulator resolution are in place. Core 205/205, app 180 passed plus one intentional
physical-device skip, LoggingEval 20/20, Backend 18/18 plus typecheck, secret scan, and UI smoke 1/1
pass. The 19-scenario automated UI suite also passes across focused reruns; Xcode beta hung its
Simulator runner between cases, so this is not represented as one uninterrupted suite result.
Release/archive validation passed earlier in this revision series but is not yet part of the single
`Scripts/ci.sh` command.

One canonical command/CI matrix must run:

- JustLogItCore tests
- iOS app tests
- LoggingEval tests
- Backend typecheck/tests
- repository secret scan
- Release configuration/archive validation
- UI smoke on merge or nightly

Reliability cleanup:

- Replace the remaining `UserDefaults.standard` test mutation with an isolated suite.
- Replace busy `Task.yield()` polling with controlled continuations or short-sleep expectations.
- Pin UI-test language/locale and prefer identifiers/exact values over broad text containment.
- Split UI-test reset and persistent-store launch arguments so relaunch persistence can be tested.

### 9. Add privacy-safe local observability

Status: In progress — the typed, content-free unified logging/signpost boundary now covers parser,
bootstrap, Health reconciliation, USDA cache outcomes, and USDA transport categories. Performance
and scale measurements remain physical-device work.

Use unified logging/signposts. Do not add a third-party analytics or logging SDK.

Required local events/intervals:

- Bootstrap first frame, container-open duration, time-to-interactive, and volatile fallback category.
- Parser availability, warm/cold acquisition, response duration, token usage, clarification route code, cancellation requested, and cancellation exit.
- USDA cache hit/miss, disk decode, network, response decode, ranking, detail load, HTTP status category, result count, rank gap, and auto-select reason.
- Save outcome, Health write/delete outcome, reconciliation fetched/eligible counts, retry count, and duration.
- Photo input byte count/dimensions, downsample duration, model duration, and retained-memory observation without image content.

Cache failures, Health persistence/reconciliation failures, and bootstrap fallback are no longer
silently swallowed. Remaining observability work is measurement coverage, signpost review in
Instruments, and confirming that no content appears in device logs.

### 10. Optimize only after measurement

Status: Pending

The implementation sequence for balancing deterministic parsing, on-device Foundation Models, and optional PCC escalation is defined in `Documentation/HYBRID_INTERPRETATION_PLAN.md`. Follow its baseline and shadow-evaluation gates rather than changing the shipping parser directly from prompt-length intuition.

Measurement order:

1. Physical-iPhone Foundation Models cold, prewarmed, first-submit-during-prewarm, clarification reparse, cancellation, and repeated-log runs.
2. Startup container-open/time-to-interactive with realistic history.
3. Photo decode/model peak memory.
4. Cached/live USDA phase timings.
5. Health reconciliation with 0, 10, 1,000, and 10,000 entries.
6. Entries tab/search/scroll with 1,000 and 10,000 entries.

Strong A/B candidates:

- Remove generated `searchTerms`; grounding immediately rebuilds it from product identity.
- Compare `.general` and `.contentTagging` on the full corpus. The five-case Mac smoke favors content tagging but is not sufficient evidence.
- Replenish one unused prewarmed session only if repeated physical-device parses justify the energy/memory cost.

Do not lower the 500-token ceiling, remove explicit nil representation, reuse transcript-bearing sessions, or ship the lean prompt without corpus evidence.

### 11. Release and privacy gates

Status: Pending

- Deploy the Worker with an encrypted USDA secret and verify production/rollback behavior.
- Verify Cloudflare invocation logs, Logpush, visitor-IP transforms, account logging, and Durable Object quota behavior.
- Add executable invariants that keep Worker request logging disabled and `Cache-Control: no-store` intact.
- Publish privacy/support URLs and validate App Store privacy answers against deployed behavior.
- Run the physical-iPhone parser corpus and HealthKit write/delete smoke.
- Complete VoiceOver, Dynamic Type, dark mode, contrast, reduced motion, and Voice Control audits.
- Build/archive Release and scan the final product for secret markers.

## Known observability and documentation cleanup

- `Documentation/Performance.md` still says `FM session creation` and 17 generated fields; current code uses session acquisition/prewarm and 22 fields.
- Worker README documents a page-size limit of 25 while Worker code accepts 50. Pick one contract and test it.
- Backlog language that says USDA is never auto-selected no longer matches current product behavior; update it after the tightened policy is decided.

## Handoff protocol

For each section:

1. Add a failing regression first.
2. Implement the smallest deterministic fix.
3. Run the focused test, then the full owning suite.
4. Run `git diff --check`.
5. Update this document’s status and record exact counts/results.
6. Log newly observed user-visible defects in `Documentation/UIBugs.md`.
7. Do not mark a manual/device/deployment item complete from Simulator or source inspection alone.
