# JustLogIt continuation handoff

**Last updated:** 2026-07-13 (Grok / xAI session)  
**Audience:** Next implementer with no access to the prior chat.  
**Repo:** `/Users/james/Developer/just-log-it` · branch `main` · remote private GitHub.

This document supersedes older handoff sections that claimed “never auto-select USDA,” “always ask quantity,” and incomplete composite/photo/HealthKit behavior. Those product rules **changed** in this session.

---

## 1. Product in one paragraph

JustLogIt is a **privacy-first iOS food logger**. The person describes food in a **chat-style composer**. **Apple Foundation Models** (on-device) structure the text; **deterministic grounding + clarification policy** decide whether to search; **USDA FoodData Central** supplies nutrition; the person **reviews and confirms** before a **local SwiftData** save. Optional **Apple Health** write-back is off by default. No accounts, no analytics.

---

## 2. Orientation

| Item | Value |
|------|--------|
| Local path | `/Users/james/Developer/just-log-it` |
| Branch | `main` (work directly on main; two-person project) |
| Xcode | `/Applications/Xcode-beta.app` (iOS 27 / Xcode 27 beta) |
| Core package | `Packages/JustLogItCore` |
| Mac eval harness | `Tools/LoggingEval` + `Scripts/run-logging-eval.sh` |
| USDA key (Debug only) | `Config/Secrets.xcconfig` (**gitignored**) |
| Secrets scan | `./Scripts/scan-repository-secrets.sh` |

**Never commit** `USDA_API_KEY`, Secrets.xcconfig contents, or hardcode keys in source.

---

## 3. Non-negotiable product rules (current)

1. **iOS 27 beta** + Xcode-beta; Foundation Models on-device only for interpretation.
2. **Nutrition never invented** by the model — USDA (or manual entry) only.
3. **Production builds** must not embed the USDA API key (proxy or Debug direct key only).
4. **Chat UX:** real bubbles, bottom composer, no robotic status spam, no keyboard “Done” bar that fights focus.
5. **Composite meals** (cereal + milk, Big Mac + fries) are **one log** with multiple USDA lookups — not “pick one food.”
6. **High-confidence path (new):** default **1 serving** when amount missing; **auto-select** strong USDA matches; **infer meal time** when wording is clear — **show on review, skip extra questions**. User can override (different food / amount / confirm step).
7. **Generic one-word foods** (`rice`, `eggs`) with multiple hits still show the USDA picker.
8. **HealthKit:** optional, write-only, off by default. **Do not request** `HKCorrelationType.food` in `requestAuthorization` — authorize **dietary quantity types**, then **save** a Food correlation containing those samples.
9. **Simulator** for ordinary UI; physical device for Foundation Models / HealthKit qualification.
10. Log UI bugs in `Documentation/UIBugs.md`; don’t mark Fixed without reproduction.

---

## 4. What this session shipped (by theme)

### 4.1 Big Mac / serving resolution (`foodPortions`)

**Bug:** Survey / SR Legacy foods (e.g. Big Mac FDC `2706916`, `170720`) have **no** branded `servingSize` / `householdServingFullText`. Grams live on **`foodPortions`**. The app ignored portions → “USDA serving · Not provided” and “does not provide enough serving information” for **1 serving**.

**Fix:**

- `Packages/JustLogItCore/.../FoodPortionServing.swift` — prefer labeled serving; else best `foodPortion` → `servingSize` grams + household text.
- `JustLogIt/Services/USDAFoodDataProvider.swift` — decode `foodPortions`, resolve serving, scale per-serving nutrients.
- `Tools/LoggingEval/.../USDAClient.swift` — same mapping for the harness.
- `UnitConversion` / `ServingResolution` — `item` / `each` as count; generic whole-item counts match single-count households (e.g. “1 McDonald's Big Mac”).

**Do not** invent a cache schema version bump to “fix” stale details — user can clear food cache in Settings. Stale Big Mac details in disk cache can still show “Not provided” until cache clear or TTL expiry.

**Harness:** `export USDA_API_KEY=...` then  
`./Scripts/run-logging-eval.sh --parsed-json …` with quantity `1` / unit `serving` or `item` → Big Mac ~**205 g / ~535 kcal**.

### 4.2 Composite multi-food sessions

- Clarification policy **`beginComposite`** with `componentNames` (model) or inferred “X with/and Y”.
- `LogViewModel`: queue components, search each, commit snapshots, aggregate meal review.
- `CompositeComponentRequest` — `"1 Big Mac"` → product + quantity (don’t strip the count).
- `CompositeFoods.swift` — snapshots, nutrient aggregation, draft builder.
- Persistence: `FoodLogEntryRecord` composite flag + component payload; Entries UI shows **per-item macros + meal total**.

### 4.3 Logging defaults (less friction)

| File | Role |
|------|------|
| `LoggingDefaults.swift` | `ParsedQuantityDefault` (missing amount → **1 serving**); `FoodSearchAutoSelect` (multi-token match, brand, remembered FDC, single hit) |
| `MealTimeInference.swift` | “just ate/finished”, breakfast/lunch/dinner/tonight/afternoon → date + label; **`isClear`** skips when-eaten question |
| `RelativeTimeParser.swift` | freeform “just now”, “2 hours ago”, etc. |

**Auto-select rules (do not auto):** single generic token with multiple results (`rice`).  
**Auto-select (do):** “Big Mac”, remembered FDC, stated brand match, sole matching hit.

**Meal time:** if clear, show clock label on **review**; **Continue** jumps to **confirm** (no “When did you eat?”). If unclear, when-eaten chips include Just now / hour ago / Breakfast / Lunch / Dinner.

### 4.4 Chat UX

- Real transcript: user right, assistant left; cards for USDA picker, quantity, review, confirm.
- Photo in chat: `ConversationTurn.user(..., imageData:)` — image appears **immediately** on pick/camera.
- Keyboard: removed Done accessory that stole focus; **no** `simultaneousGesture` dismiss-on-tap (broke input). Use scroll-to-dismiss; **do not** force-focus or auto-scroll while focused.
- Composer: amount + unit + send for post-USDA quantity when still needed.
- Composite nutrition on review/confirm + Entries detail.

### 4.5 HealthKit authorization (important)

**Symptom:**  
`Authorization to share the following types is disallowed: HKCorrelationTypeIdentifierFood`

**Cause:** Requesting **Food correlation** in `toShare` is wrong. Apple authorizes **constituent quantity types** only; the app then **saves** an `HKCorrelation` of type food.

**Current code:** `HealthKitNutritionWriter` requests dietary quantities; save path writes Food correlation with authorized samples. Keep that model — do not “remove Food support.”

### 4.6 Bootstrap / launch

- `JustLogItApp` → `BootstrapRootView` → async-feeling boot of `ModelContainerFactory` (not in `App.init`).
- Schema epoch wipe for RecognizedFood + composites if needed.
- Boot cost is mainly **SwiftData open on MainActor** + tab tree/`@Query` — not FM/USDA.

### 4.7 Mac LoggingEval harness

- `Tools/LoggingEval` — FM parse (or `--parsed-json` / `--fake-parse`) → USDA → rank → resolve → JSON report.
- `Scripts/run-logging-eval.sh` sets macOS 26.4+ target for Generable APIs.
- Requires `USDA_API_KEY` in env (from Secrets for local use).

### 4.8 Other pieces present in the tree

- Remembered USDA selections (ranking boost only).
- Recognized foods dual list in Entries.
- Photo proposer (`FoundationModelsImageFoodProposer`) + camera/library.
- ObjC exception catcher around HealthKit auth (NSException → Swift error).
- Clarification policy multi-food / model-prompt routing (some unit tests may still expect older “clarify multi” vs `beginComposite` — see §7).

---

## 5. Primary happy paths (expected UX)

### A. “I just ate a Big Mac”

1. Parse → product Big Mac, default **1 serving**.
2. USDA search → auto-select **Big Mac (McDonalds)** (multi-token).
3. Details + `foodPortions` → ~205 g / macros.
4. Review shows food, **1 serving**, macros, **Just now**.
5. Continue → **confirm** (no when-eaten, no picker, no amount dock).
6. Confirm → local save (+ Health if enabled).

### B. “Big Mac and large fries”

1. Composite session; each component lookup.
2. Per-item macros + meal total on review.
3. Time inference from source if present.

### C. “rice” (ambiguous)

1. Default 1 serving in parse.
2. **Picker** (generic token, multiple hits).
3. After pick, resolve 1 serving if USDA has serving grams.
4. When-eaten only if message has no clear time.

### D. Photo

1. User bubble shows image immediately.
2. On-device propose → same clarification/search pipeline (no USDA for image bytes).

---

## 6. Key files map

| Area | Paths |
|------|--------|
| Chat UI | `JustLogIt/Features/Log/LogView.swift` |
| Flow VM | `JustLogIt/Features/Log/LogViewModel.swift` |
| USDA + cache | `JustLogIt/Services/USDAFoodDataProvider.swift` |
| FM text | `JustLogIt/Services/FoundationModelsFoodParser.swift` |
| FM image | `JustLogIt/Services/FoundationModelsImageFoodProposer.swift` |
| Health | `JustLogIt/Services/HealthKitNutritionWriter.swift`, `HealthSyncCoordinator.swift` |
| Bootstrap | `JustLogIt/App/JustLogItApp.swift`, `Persistence/ModelContainerFactory.swift` |
| Entries / meals | `JustLogIt/Features/Entries/EntriesView.swift` |
| Core policy | `ClarificationPolicy.swift`, `ServingResolution.swift`, `FoodPortionServing.swift` |
| Core defaults | `LoggingDefaults.swift`, `MealTimeInference.swift`, `CompositeComponentRequest.swift` |
| Eval | `Tools/LoggingEval/**`, `Scripts/run-logging-eval.sh` |
| Docs | `Documentation/Performance.md`, `ParserEvaluation.md`, `Architecture.md`, this file |

---

## 7. Known issues / follow-ups

1. **Stale USDA disk cache** after portion mapping — clear Settings → “Clear downloaded food cache” if Big Mac still shows “Not provided.”
2. **ClarificationPolicyTests** — several multi-food tests may still expect `.clarify` while product now prefers **`.beginComposite`** (eggs and bacon). Rebaseline tests to current policy.
3. **Amount edit after auto-default** — review shows amount; changing grams mid-review is possible via resolve path but not a dedicated “edit amount” control. Improve if users need it.
4. **Meal time** — breakfast/lunch/dinner use fixed local hours (8:00 / 12:30 / 18:30). Not calendar-aware beyond “today.”
5. **HealthKit** — full device UAT still required; Simulator often limited.
6. **Boot latency** — optional: open ModelContainer off MainActor; lazy tab content.
7. **Photo turns** — not text-editable; re-run from edit path is text-only.
8. **Composite + when-eaten** — meal-level time only (not per component).
9. Manual full chat UAT on Simulator for: Big Mac just ate, cereal+milk, rice picker, photo bubble, Health toggle permission sheet.

---

## 8. How to run / verify

```bash
# Core unit tests
cd Packages/JustLogItCore && swift test

# App unit tests (pick a listed sim from xcodebuild -showdestinations)
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -scheme JustLogIt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:JustLogItTests test

# Logging eval (needs key; never commit it)
export USDA_API_KEY="$(grep USDA_API_KEY Config/Secrets.xcconfig | cut -d= -f2- | tr -d ' \"')"
./Scripts/run-logging-eval.sh "1 Big Mac"
# Prefer --parsed-json for quantity-resolved cases when FM omits quantity

# Secret scan before push
./Scripts/scan-repository-secrets.sh
```

---

## 9. Trust boundaries (unchanged)

```
User text/photo
  → Foundation Models (on-device structure only)
  → Grounder (strip unsupported facts)
  → ClarificationPolicy (clarify / composite / proceed)
  → FoodSearchQueryBuilder + USDA (network)
  → FoodSearchResultRanker (+ remembered boost; optional auto-select)
  → FoodDetails (+ foodPortions → serving)
  → ServingResolution + NutritionCalculator
  → Review / Confirm → SwiftData
  → optional HealthKit Food correlation (after quantity auth)
```

Model never writes calories. Ranker never drops results. Auto-select only skips UI when confidence rules fire.

---

## 10. Suggested next work (priority)

1. Rebaseline/fix **ClarificationPolicyTests** for composite multi-food.
2. Simulator **manual UAT** of §5 paths; file UIBugs for anything sticky.
3. Optional **edit amount / edit time** on review when inference was applied.
4. HealthKit **on-device** permission + write smoke test.
5. Consider **background ModelContainer** open if “Starting…” still feels long.
6. Composite polish: fries size ranking, per-component failures.

---

## 11. Session note for the next human/agent

This Grok session moved JustLogIt from “always ask match + amount + time” toward **confident defaults with override**, fixed **real Big Mac USDA data** via **foodPortions**, built **composite meals** with **per-item macros**, fixed **HealthKit Food correlation auth**, and tightened **chat/keyboard/photo** UX. Prefer measuring before “optimizing” the FM prompt (`Documentation/Performance.md`). Prefer surgical diffs. Prefer honesty over green tests that encode obsolete product rules.

If something fails only on device with an old install: **clear food cache**, rebuild, re-test Big Mac before assuming portion mapping regressed.
