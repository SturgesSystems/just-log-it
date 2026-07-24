# watchOS companion spike

**Status:** research / deferral recommendation
**Date:** July 18, 2026
**Scope:** what a thin Watch glance could do for JustLogIt, what it costs, and why it is not next

## Executive summary

JustLogIt is an **iPhone-first** app. Food logging depends on reviewed interpretation (Foundation Models when available), USDA grounding, portion math, and explicit confirmation before SwiftData save. That workflow is a poor fit for a full watchOS target today.

A useful Watch surface is possible, but only as a **companion glance + handoff**, not a second nutrition app:

| Surface | Value | Risk |
| --- | --- | --- |
| Complication / Smart Stack: **today’s calories** | Glanceable progress without opening the phone | Needs shared summary data; stale or wrong totals erode trust |
| App Intent on Watch: **start log with phrase** | “Log two eggs in JustLogIt” from wrist | Same contract as phone Spike A; must open phone review, never auto-save |
| Full Watch app (composer, USDA pickers, Health auth) | Low relative value | High cost; duplicates pipeline; worse input UX |

**Recommendation:** do **not** scaffold a watchOS target now. Finish and validate **phone Siri Spike A** (and, for real calorie numbers, a shared summary read path). Capture requirements here; revisit Watch after those seams exist and physical-device Siri acceptance is green.

Related docs:

- [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md) — phone App Intents plan and spikes A–D
- [`Backlog/SiriAIIntegration.md`](../Backlog/SiriAIIntegration.md) — ordered Siri implementation gates
- [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md) — device acceptance for Start Food Log
- [`Architecture.md`](Architecture.md) — intents as thin adapters only
- [`Privacy.md`](Privacy.md) — no silent nutrition; Siri is input, not authority

---

## Reality check: why a full Watch app is too heavy

Current product facts (as of this spike):

1. **Single iOS application target** (`project.yml`: `TARGETED_DEVICE_FAMILY: "1"`, deployment iOS 27). No watchOS product, no WidgetKit extension, no App Group entitlement.
2. **SwiftData lives in the phone app sandbox** (`Application Support/JustLogIt/default.store`). Nothing else can read it.
3. **Logging is review-first.** `StartFoodLogIntent` already encodes the product rule: capture phrase + optional time, open the reviewed Log flow, **do not persist**. Watch must not invent a silent-save path.
4. **Today’s “nutrition summary” intent is still a navigation handoff.** `GetTodayNutritionSummaryIntent` opens the Entries tab; it does **not** compute or return calorie totals from the store. A complication that shows “1240 kcal” needs a real shared summary, not that intent as shipped.
5. **Heavy dependencies do not belong on Watch:** Foundation Models parsing, USDA proxy/network, HealthKit write authorization UI, full Log conversation UI. Shipping them on watchOS multiplies targets, signing, testing, and battery/thermal surface area for little MVP gain.
6. **Team focus.** Hybrid interpretation quality, physical-iPhone UAT, and Siri handoff are higher leverage. Watch is a multiplier on those, not a substitute.

A full Watch logging client would effectively be a second app with a worse keyboard and the same hard problems (ambiguity, USDA choice, confirmation). That is out of scope for the near term.

---

## Preferred thin companion: what watchOS could do

Assume Apple’s Watch/App Intents generation that pairs with the project’s **iOS 27** App Intents stack (confirm exact APIs against the installed Xcode/watchOS SDK before implementation). Two surfaces deliver almost all practical value.

### 1. Start a log with a phrase (App Intent handoff)

**User value:** from the wrist or Watch Siri, capture food words without typing on the phone.

**Behavior (mirrors phone Spike A):**

- Intent parameters: required free-text **Food**, optional **When Eaten**.
- Execution: **foreground / open companion iPhone app** (or equivalent “continue on iPhone”) with the same `PendingFoodLog` handoff used by `StartFoodLogIntent` / `SiriFoodLogCoordinator`.
- Dialog: short acknowledgment (“Opening JustLogIt to review that food”) — not a nutrition claim.
- **No** SwiftData write, **no** USDA call, **no** HealthKit authorization from the Watch intent alone.
- Cancellation before in-app save creates no entry (same acceptance bar as [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md)).

**Phrase examples (same discipline as phone):**

- “Log food in JustLogIt” (then answer the requested Food parameter)
- “Add food to JustLogIt” (then answer the requested Food parameter)
- Prefer `\(.applicationName)` in donated App Shortcut phrases until a real food-log App Schema exists.

**Implementation shape (when ready):**

- Prefer **sharing the same App Intent type** (`StartFoodLogIntent`) from a small shared framework or the phone app’s intent definition so Watch does not fork product rules.
- If Watch requires a separate target to host intents/complications, keep the intent **thin**: only queue pending log + open iOS. All interpretation stays on iPhone.
- Do **not** run Foundation Models or USDA on Watch for v1.

### 2. Show today’s calories (complication / Smart Stack / glance)

**User value:** wrist glance of progress without unlocking the phone and navigating Entries.

**Display candidates (v1):**

| Complication / widget | Content |
| --- | --- |
| Modular / rectangular | “Today · 1,240 kcal” |
| Circular | “1240” with app glyph |
| Corner / inline | kcal only |
| Smart Stack | Today’s calories + optional protein |

**Hard rules:**

- Totals are **derived only from confirmed local entries** (same snapshots as the Entries list), never from Siri/model guesses.
- If summary data is missing, locked, or stale beyond a defined budget, show a **neutral empty/placeholder** state — not a fabricated zero that looks authoritative when the phone has data the Watch cannot see.
- Macros optional; calories-only is enough for the first glance.
- Tapping the complication opens the **iPhone** Entries/today view (or Watch deep link that immediately hands off), consistent with `GetTodayNutritionSummaryIntent`’s product intent.

**What this is not:**

- Not a Watch-side charting product.
- Not live HealthKit as the source of truth for JustLogIt totals (Health remains optional write-back; local logs remain authoritative).
- Not “ask Watch Siri how much protein I had” across full history without privacy review (same caution as Siri Spike D / Spotlight).

### Explicit non-goals for a first Watch companion

- Full Log conversation, USDA picker, manual nutrition editor on Watch
- Silent or one-tap save of inferred nutrition from the wrist
- Photo logging on Watch
- Independent Watch-only database
- Replacing phone Siri with Watch-only voice logging
- Publishing food history to system search/Spotlight by default

---

## Shared App Group requirements

Nothing on Watch can show truthful “today calories” or share a pending draft without a **shared container** (or an equivalent transfer path). Today there is **no** App Group.

### What must move to a shared container

| Data | Why | Suggested form |
| --- | --- | --- |
| **Today nutrition summary** | Complication timeline / widget snapshot | Small Codable blob: `date` (start of day in user calendar), `calories`, optional macros, `entryCount`, `updatedAt` |
| **Optional pending log draft** | Watch-started phrase if phone is not yet foregrounded | Same fields as `PendingFoodLog` (description, consumedAt, source), short TTL |
| **Not** full SwiftData store (v1) | Avoid dual-writer ModelContainer races and migration hell across processes | Phone remains sole writer of entries |

### Entitlements and configuration

1. Create an App Group, e.g. `group.com.example.JustLogIt` (replace with production team reverse-DNS when not using the example prefix).
2. Enable the capability on:
   - JustLogIt iOS app
   - any Widget / Watch / App Intent extension that reads the summary
3. Point **summary** storage at the group container (file or `UserDefaults(suiteName:)`). Prefer an atomic file write for the summary snapshot.
4. **Do not** casually relocate the full SwiftData store into the App Group for v1. That couples Watch, widgets, intents, and the main app to one multi-process store and fights the current async bootstrap / single-container design called out in Siri Spike A comments on `GetTodayNutritionSummaryIntent`.

### Ownership and refresh rules

```text
iPhone app (sole entry writer)
    │ on successful FoodLogRepository save / delete / day rollover
    ▼
write TodayNutritionSummary → App Group
    │
    ├─► WidgetKit / Watch complication timeline reload
    └─► optional: Watch app reads snapshot only

Watch “start log” intent
    │ write PendingFoodLog → App Group (optional) + open iOS
    ▼
iPhone consumes pending → existing reviewed Log flow → save → refresh summary
```

- **Phone writes summary** after every confirmed local mutation that affects today’s totals (and on foreground if the calendar day rolled).
- **Watch/complication only reads** the snapshot.
- If the phone never opens after install, the complication stays empty — acceptable; do not scrape HealthKit as a silent substitute without an explicit product decision.
- File protection / lock screen: complication may show **last successfully written** snapshot while device is locked; document that behavior and avoid writing sensitive free-text food names into the complication’s visible timeline entries (calories/macros only on the face).

### Why full shared SwiftData is the wrong first step

- Multi-process `ModelContainer` for the same store needs careful coordination; the app already avoids racing bootstrap with a second container for intents.
- Watch has tighter memory/disk budgets; co-locating the whole history is unnecessary for “today’s kcal.”
- Migrations and volatile-fallback behavior in `ModelContainerFactory` are phone-centric; extending them to Watch multiplies failure modes.

App Group + **summary projection** is the minimal shared-data design.

---

## Why phone Siri Spike A is a prerequisite

Watch should **reuse** the phone handoff contract, not invent a parallel one.

### What Spike A already (or must) prove

From [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md) and the current `AppIntents/` code:

| Spike A concern | Watch dependency |
| --- | --- |
| `PendingFoodLog` (description, consumedAt, source) | Watch phrase logging needs the same type and navigation seam |
| `StartFoodLogIntent` foreground deferred, main app execution | Watch “log food” is the same intent semantics with a different invocation surface |
| No persistence before in-app confirmation | Product rule Watch must not weaken |
| Cold launch without sync SwiftData in `App.init` | Opening from Watch is often a cold/background launch |
| Shortcuts discovery + physical-device Siri acceptance | If phone phrase → review fails, Watch will fail the same way with worse debugging |
| `SiriFoodLogCoordinator` / `AppNavigation` as single handoff owner | Avoid a second pending-log channel unique to Watch |

### What Spike A does **not** yet give Watch (honest gaps)

- **Numeric today summary** for complications — still needs a repository query + App Group projection (closer to Siri Spike D “structured summary,” but can be smaller and phone-written only).
- **Shared headless `FoodLoggingWorkflow`** (Spike B) — required only if Watch ever confirms/saves on-wrist; **not** required for glance + start-log handoff.
- **App Group** — not part of Spike A; add only when a second process must read summary or pending draft.

### Ordering

```text
1. Phone Spike A green on device (phrase → reviewed Log, no silent save)
2. Optional: phone “today summary” as a real structured read (Shortcuts-return or in-app),
   still single-process
3. App Group + phone-written TodayNutritionSummary projection
4. WidgetKit complication on iPhone (proves snapshot + timeline without Watch hardware)
5. watchOS complication / thin intent host that reuses (1) and (3)
```

Skipping (1) means Watch work blocks on the same navigation, cold-launch, and privacy bugs under a heavier multi-target setup. Skipping (3)–(4) means a Watch calorie face is either fake or forces a premature shared-store project.

**Bottom line:** Watch is an **invocation and display adapter** on top of phone Siri handoff + a tiny shared summary. It is not an alternate architecture.

---

## Effort estimate

Estimates assume one engineer familiar with the repo; calendar time stretches if physical Watch hardware, provisioning, or SDK beta churn intervenes. **Do not start a watchOS target until steps 0–1 are done.**

| Step | Work | Effort | Depends on |
| --- | --- | --- | --- |
| **0** | Phone Siri Spike A acceptance (device) | *tracked in Siri spike* (~2–4 eng days if not done) | Hybrid quality gates |
| **1** | `TodayNutritionSummary` model + phone write on save/delete/day change; unit tests | 1–2 days | Stable `FoodLogEntryRecord` / repository |
| **2** | App Group entitlement; atomic snapshot file; no full store move | 0.5–1 day | Developer portal / signing |
| **3** | iOS WidgetKit complication / Lock Screen (calories only) — proves projection without Watch | 2–4 days | Steps 1–2 |
| **4** | watchOS **complication-only** or minimal Watch container that reads snapshot + opens companion | 3–6 days | Steps 1–3, Watch signing |
| **5** | Watch / shared **Start Food Log** intent → same pending handoff as phone | 1–3 days | Spike A + step 4 host |
| **6** | Full Watch app UI (log composer, lists, settings) | **10–25+ days** | Reject for now |
| **7** | On-Watch confirm-and-save (Spike C equivalent) | **8–15+ days** after Spike B | Reject for v1 companion |

### Bundled “thin companion” (recommended first Watch ship, later)

**Roughly 1.5–3 engineering weeks** after Spike A is green: summary projection + App Group + iOS widget proof + watchOS complication + start-log handoff + manual acceptance on iPhone+Watch pair.

### Full Watch client (not recommended)

**Multiple engineering months** once you include dual targets in CI, SwiftData or sync strategy, reduced UI for clarification/USDA, Health edge cases, and ongoing OS matrix testing. Poor ROI while the phone product is still absorbing hybrid-parser and Siri work.

### Cost drivers (easy to underestimate)

- Extra target in `project.yml` / XcodeGen, schemes, CI (`Scripts/ci.sh`), code signing
- App Group migration for existing installs (summary starts empty until phone opens once)
- Stale complication after deletes across midnight / time zone
- Privacy copy updates if Watch surfaces calories on a visible face
- Simulator Watch vs physical Watch behavioral gaps (parallel to Simulator Siri limits)

---

## Decision log

- **No watchOS target in-repo from this spike.** Documentation only; scaffolding is non-trivial and premature.
- **Phone Spike A is the prerequisite** for any “log with phrase from Watch” story.
- **Calories on wrist need an App Group summary projection**, not a shared full SwiftData store in v1.
- **Prefer iOS WidgetKit first** as a cheaper proof of the summary pipeline; Watch reuses the same snapshot.
- **Never auto-save nutrition from Watch.** Same confirmation and USDA authority rules as phone Siri.
- **Defer** on-Watch quick log, search entities, and Spotlight-style history until Siri Spikes B–D and privacy review land on phone.

## Open questions (resolve before implementation)

1. Exact watchOS / WidgetKit App Intents APIs and complication families available in the **release** Xcode paired with this project’s iOS 27 SDK.
2. Whether a single App Intent binary can be shared so Watch does not redeclare `StartFoodLogIntent`.
3. Minimum refresh policy: reload complication only on save, or also on a coarse timeline provider schedule?
4. Production App Group identifier and team IDs (replace `com.example` placeholders).
5. Is Lock Screen / Watch face exposure of daily calories acceptable under the product’s privacy bar without PIN-gated hide?

## Recommendation

**Spike doc only; do not scaffold Watch code now.**

Next product engineering order:

1. Finish and pass **phone Siri Spike A** physical acceptance.
2. If glanceable calories matter before Watch, add a **phone-written today summary** and optionally an **iOS complication**.
3. Only then add App Group + watchOS thin companion (complication + start-log handoff).

Revisit this document when Spike A is green or when a concrete user demand for wrist calories outweighs the multi-target cost.
