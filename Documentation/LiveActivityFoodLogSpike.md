# Live Activity “logging in progress” spike

**Status:** research / deferral recommendation
**Date:** July 18, 2026
**Scope:** whether ActivityKit Live Activities should show food-log progress on the Lock Screen / Dynamic Island, why that is low ROI next to Siri Spike A/B, and the narrow conditions under which it would earn its cost

## Executive summary

A Live Activity for “logging in progress” would surface intermediate states of a JustLogIt food log (interpreting, searching USDA, awaiting confirmation) outside the Log tab. On paper that matches Apple’s guidance for short-lived, glanceable tasks. In practice, JustLogIt’s logging loop is **short, interactive, and review-bound**: the person is usually already in the app choosing a USDA match, answering a clarification, or confirming nutrition before anything is saved.

Compared with **Siri Spike A** (start a reviewed log by voice) and **Spike B** (shared headless `FoodLoggingWorkflow`), Live Activities add a **second UI surface and a multi-target ActivityKit stack** without reducing the hard costs of logging: capture, grounding, USDA identity, portion math, and explicit confirmation. They do not start a log, do not replace typing, and must not auto-save.

**Recommendation:** do **not** build Live Activities for food-log progress now. Finish Spike A device acceptance and Spike B workflow extraction first. Revisit only if measured end-to-end latency (especially **live USDA search/details**) routinely leaves people waiting long enough that they leave JustLogIt and need a Lock Screen resume/status affordance.

Related docs:

- [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md) — Spikes A–D and product rules
- [`SPIKE_C_QUICK_LOG_NOTES.md`](SPIKE_C_QUICK_LOG_NOTES.md) — confirm-and-save in Siri (blocked on B)
- [`WATCH_COMPANION_SPIKE.md`](WATCH_COMPANION_SPIKE.md) — similar “second surface” deferral; no WidgetKit/App Group today
- [`Performance.md`](Performance.md) — parser vs USDA phase instrumentation
- [`Backlog/SiriAIIntegration.md`](../Backlog/SiriAIIntegration.md) — ordered Siri gates
- [`Architecture.md`](Architecture.md) — intents and UI as thin adapters; no silent nutrition

---

## What a Live Activity would try to do

Hypothetical product shape (not a commitment):

| Phase shown | Example Lock Screen / Island copy | Real app state |
| --- | --- | --- |
| Interpreting | “Understanding your food…” | Foundation Models / hybrid parse in flight |
| Clarifying | “Need a quick detail…” | `awaitingClarification` / policy question |
| Searching USDA | “Looking up nutrition…” | `usda_search_pipeline` (cache or network) |
| Choose match | “Pick a food match” | Candidate list ready; needs person input |
| Ready to confirm | “Review and save” | Nutrition preview; no persistence yet |
| Failed / offline | “Couldn’t reach food data” | Provider error; recover in app |

Taps would open JustLogIt into the **existing** Log conversation (same handoff discipline as Siri pending log), never write SwiftData or HealthKit from the Activity itself.

That surface is optional chrome around a pipeline that already has in-app progress and recovery UI. The question is leverage, not technical impossibility.

---

## Why ROI is low next to Siri Spike A/B

### 1. The bottleneck is capture and confirmation, not status chrome

JustLogIt is deliberately **review-first**. Nutrition is authoritative only after USDA grounding, serving resolution, and an explicit save. A Live Activity that says “logging…” does not:

- replace launch + navigation + typing (Spike A does);
- enable a safe confirm-and-save path outside the Log UI (Spike C, which needs Spike B);
- reduce clarification turns, USDA ambiguity, or portion mistakes.

Siri Spike A attacks the highest-friction step for hands-busy moments: **getting food words into the reviewed flow**. Spike B is the **architectural** investment that unlocks Siri confirmation, keeps UI and intents on one pipeline, and pays for every later adapter (Shortcuts, Watch handoff, future background work). Live Activities neither start logs nor complete them under product rules.

### 2. Sessions are usually in-foreground and short

Typical single-food path:

1. Person is in Log (or just handed off from Siri).
2. Parse and optional clarification run while they watch the conversation.
3. USDA candidates appear; they pick or edit.
4. They confirm and leave.

Live Activities excel when the person **leaves the app** during a multi-minute task (ride, order, workout, timer). JustLogIt’s useful wait is often **sub-second to a few seconds** on warm path (on-device parse + disk-cached USDA), with the rest of the time spent on **interactive** steps that require the full Log UI anyway. Showing those steps on the Lock Screen duplicates the conversation without shortening it.

### 3. Platform and engineering cost is real

Today the product is a **single iOS app target** with no WidgetKit extension, no ActivityKit adoption, and no App Group (same baseline as the Watch companion spike). A credible Live Activity would require roughly:

| Work | Why it exists |
| --- | --- |
| Activity attributes + ActivityKit lifecycle | Start, update, end, stale, and dismissal rules |
| Live Activity UI (Widget extension target) | Compact / expanded / Lock Screen presentations |
| State projection from Log pipeline | Map stages without leaking food text into inappropriate surfaces if privacy policy tightens |
| Foreground ↔ Activity sync | Avoid dual sources of truth; cancel Activity when session ends or app dismisses draft |
| Cold launch deep link into in-progress log | Same care as Siri pending handoff; no store open in `JustLogItApp.init` |
| QA matrix | Dynamic Island devices vs not; Always On; Focus; VoiceOver; failed USDA; double-start; background kill |
| Signing / scheme / CI surface | Second product UI to archive and smoke-test |

That is multi-day work for **status presentation**, not for logging correctness. Spike B’s 5–8 engineering days buy a shared workflow used by UI, Siri, and any future surface. Live Activity days buy a billboard.

### 4. Product and privacy friction for little gain

- **No silent nutrition.** An Activity must never imply the food is “logged” until confirm-and-save. Easy to misword (“Logged eggs…” vs “Review eggs…”).
- **Sensitive content on Lock Screen.** Food phrases and macros may be visible to bystanders; defaults should stay coarse (“Review food in JustLogIt”) unless the person opts into richer content—extra settings and review.
- **Ambiguity stages need rich UI.** USDA choice lists, quantity fields, and manual nutrition do not fit Live Activity layouts; the person still opens the app.
- **Rate limits and errors** need recovery actions already designed in-app; the Activity can only nudge return-to-app.

### 5. Priority order already chosen

From the Siri and hybrid plans:

1. **Spike A** — phrase → reviewed Log; no save without confirm; physical-device UAT still open.
2. **Spike B** — headless `FoodLoggingWorkflow` + transactional repository.
3. **Spike C** — bounded confirm-and-save in Siri for narrow safe cases.

Live Activities are orthogonal chrome. Shipping them before A/B competes for the same engineering attention without unblocking hands-free logging or hybrid quality gates.

### Rough comparison

| Investment | User-visible win | Architectural leverage | Relative cost |
| --- | --- | --- | --- |
| **Spike A** (finish UAT) | Start log by voice / Shortcuts | Proves system handoff + cold launch | Low–medium; mostly validation |
| **Spike B** | None alone; enables C and clean adapters | Single pipeline for UI + intents | Medium–high; high reuse |
| **Spike C** | Confirm safe logs in Siri | Consumes B | Medium after B |
| **Live Activity “in progress”** | Glance while waiting outside app | Low; presentation only | Medium; new extension + QA |

**Conclusion:** A and B dominate on ROI. Live Activity is a polish layer for a latency problem that is not yet the product’s binding constraint.

---

## When Live Activities *would* make sense

Revisit this spike only if **evidence** shows people regularly wait **outside** JustLogIt during an unfinished log, and that wait is dominated by work that is not interactive choice UI.

### Primary trigger: long USDA waits

Instrument and watch (see [`Performance.md`](Performance.md)):

- `usda_search_pipeline` and related transport outcomes (timeout, offline, rate-limited);
- submit → first actionable UI when cache misses and the proxy/USDA path is cold or degraded;
- repeated detail fetches for multi-candidate or composite flows (future).

Live Activities become plausible when, on real devices in production-like conditions:

- **p95 live USDA path** (uncached search + details needed before review) is **multi-second enough** that people background the app mid-pipeline (order-of-magnitude guide: sustained waits on the order of **several seconds to tens of seconds**, not sub-second warm cache hits); and/or
- **rate limiting / retries** leave a log “pending food data” while the person uses another app; and/or
- a future **offline pack miss + slow network** or **USDA mirror lag** creates the same out-of-app wait pattern.

In that world, a minimal Activity is a **wait + resume** affordance:

- Start when a USDA-bound stage begins and the person may leave.
- Update only coarse phase (“Looking up nutrition…”, “Ready to review”, “Try again when online”).
- End on confirm, cancel, or terminal failure.
- Tap → open Log conversation at the same draft (no new nutrition authority).

Still not: auto-save, HealthKit from the Activity, or full USDA pickers on the Lock Screen.

### Secondary triggers (weaker)

| Trigger | Why weaker |
| --- | --- |
| Very slow first Foundation Models response after cold/eviction | Still usually in-app; prewarm and hybrid work address root cause better than a billboard |
| Composite meal logging with many sequential USDA lookups | Real latency risk later; fix batching/workflow first; Activity only if out-of-app waits remain |
| Background / extended App Intent execution | Prefer finishing Spike B/C and measuring intent budgets; Activity might pair with progress APIs later, not replace them |
| Marketing / “modern iOS” aesthetics | Not a product reason for JustLogIt |

### Explicit non-triggers

Do **not** start Live Activities because:

- the in-app spinner feels plain;
- competitors show Live Activities for unrelated domains;
- Spike A is unfinished and a Live Activity seems like “more Siri ecosystem”;
- someone wants Always On calories (that is a **widget / summary** problem—see Watch companion spike—not a log-progress Activity).

---

## If revisited: thin design rules

When (and only when) the latency evidence holds:

1. **One Activity per active log draft**, ended aggressively on save/cancel/timeout.
2. **Coarse, privacy-safe copy by default**; optional richer food text behind an explicit setting if ever needed.
3. **Same pending/conversation identity** as the Log tab and Siri handoff—no parallel draft store invented only for ActivityKit.
4. **No persistence, no HealthKit, no USDA authority** in the extension.
5. **Prefer starting the Activity only when a stage is expected to be slow** (e.g. live USDA after cache miss), not on every keystroke or every parse.
6. **Measure before/after:** rate of backgrounding during USDA, time-to-return, and whether Activity taps actually resume unfinished logs (vanity impressions do not count).
7. **Do not block Spike A/B/C** on Activity work; treat as a later polish epic with its own acceptance bar.

---

## Decision

| Decision | Detail |
| --- | --- |
| **Build Live Activities for “logging in progress” now?** | **No** |
| **Why** | Low ROI vs finishing Siri Spike A and extracting Spike B; sessions are review-interactive; platform cost is a new UI surface without starting or safely completing logs |
| **Revisit when** | Measured **long USDA (or equivalent network) waits** regularly push people out of the app mid-log, and a Lock Screen resume/status would clearly reduce abandoned drafts |
| **Until then** | Invest in hybrid/parser latency where it matters in-app, USDA cache and proxy reliability, Spike A UAT, and Spike B shared workflow |

**Bottom line:** Live Activities are a good fit for long waits the person does not supervise. JustLogIt’s food log is still a short, supervised review. Siri A/B attack real friction and architecture; “logging in progress” on the Lock Screen can wait until USDA (or similar) latency makes leaving the app a common, measured behavior.
