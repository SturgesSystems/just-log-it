# Manual Siri handoff acceptance

Device checklist for **registered App Shortcuts** from `JustLogIt/AppIntents/JustLogItShortcuts.swift`: **Log Food** (`StartFoodLogIntent`) and **Today's Nutrition** (`GetTodayNutritionSummaryIntent`). `SearchFoodLogsIntent` remains a system in-app-search surface and is not a registered App Shortcut.

**Log Food** is the primary path: Siri/Shortcuts request food text (and optional consumed time) before dynamically bringing JustLogIt forward, then the ordinary reviewed Log flow opens and nothing is saved until the person confirms in-app. **Today's Nutrition** should finish in Siri when the app's live store is available; otherwise it opens Entries. System in-app search opens Entries. None of these read/handoff actions persist anything.

This pass is separate from the general UI checklist in [`ManualAcceptanceTest.md`](ManualAcceptanceTest.md). Automated intent tests complement this pass but do not replace device Siri validation.

Log every unexpected behavior in [`UIBugs.md`](UIBugs.md) as soon as it is observed.

## Test record

| Field | Value |
| --- | --- |
| Date | 2026-07-18 |
| Tester | Codex automated preflight + Computer Use physical-device inspection; voice round-trip still pending |
| Commit | `34b9d02` plus uncommitted Grok/Codex continuation work |
| Xcode / iOS build | Xcode 27 beta / iOS 27.0 (24A5380h) |
| Device model | iPhone 17 Pro Max (`iPhone18,2`) |
| Device type | Physical |
| Apple Intelligence available | Not yet verified |
| Result | In progress — automated physical checks passed; voice cases pending |

### Automated preflight — 2026-07-18

- [x] `./Scripts/ci.sh --check-siri-spike-a` passed: Core 200, app 277 (1 skipped), LoggingEval 20, backend 18.
- [x] Simulator pending-handoff UI test passed on iOS 27 simulator `05DC5079-48F0-4942-AB50-579343408F63`; “two scrambled eggs” reached the Log flow.
- [x] Unsigned generic iOS device build succeeded with Xcode 27 beta.
- [x] Physical iPhone paired and recognized as a compatible Xcode destination; Developer Mode is enabled.
- [x] Signed build installed and launched on the physical iPhone.
- [x] Signed app metadata contains discoverable `StartFoodLogIntent` and `GetTodayNutritionSummaryIntent` actions plus the four fixed Log Food phrase templates.
- [x] Post-diagnosis Xcode 27 generic-device build and App Intents metadata export pass with background + dynamic-foreground modes (`supportedModes: 9`) for both registered actions; focused intent tests pass 16/16. Physical voice behavior still requires retest after installing this build.
- [x] Cold physical deep-link handoff preserved the complete “two scrambled eggs” text, entered the normal reviewed pipeline, failed safely when USDA was not configured, and did not save silently.
- [x] Physical Shortcuts action discovery passed in Xcode Device Hub: `Start Food Log` and `Get Today's Nutrition Summary` appeared for JustLogIt.
- [x] `Start Food Log` exposed required **Food** and documented **When Eaten** as optional; running it with “two scrambled eggs” opened the ordinary reviewed Log flow, preserved the complete text, failed safely without USDA, and did not save silently.
- [ ] Siri voice round-trip remains pending. Two Computer Use attempts invoked the Siri orb and audibly spoke the fixed phrase, but neither produced a visible “What did you eat?” prompt or a fresh handoff. Do not mark this as Pass.

### Physical Shortcuts + Siri UI evidence — 2026-07-18

Xcode Device Hub controlled the wired physical iPhone. The Shortcuts action picker was used rather than the All Shortcuts filter, because the latter only searches user-created shortcut tiles.

| Evidence | Observation |
| --- | --- |
| [JustLogIt action discovery](ManualSiriAcceptanceScreenshots/2026-07-18-shortcuts-justlogit-actions.jpeg) | `Start Food Log` and `Get Today's Nutrition Summary` appeared. `Search Food Logs` also appeared in the action picker as the documented system-search action. |
| [Start Food Log parameters](ManualSiriAcceptanceScreenshots/2026-07-18-shortcuts-start-food-log-parameters.jpeg) | Detail sheet listed **Food** and described **When Eaten** as optional (“Leave blank to use now”). |
| [Configured Shortcuts action](ManualSiriAcceptanceScreenshots/2026-07-18-shortcuts-start-food-log-configured.jpeg) | Required **Food** was set to “two scrambled eggs”; the editor's expanded action did not surface **When Eaten** inline, though the detail sheet documented it. |
| [Reviewed Log handoff](ManualSiriAcceptanceScreenshots/2026-07-18-shortcuts-reviewed-log-handoff.jpeg) | Shortcuts reported that JustLogIt was opening for review; the full food text reached the ordinary Log conversation and USDA failed safely without a save. |
| [Inconclusive Siri invocation](ManualSiriAcceptanceScreenshots/2026-07-18-siri-invocation-inconclusive.jpeg) | Siri's orb showed JustLogIt, but the expected conversational prompt and a fresh answer handoff were not observed. |

## Prerequisites

- [ ] Physical **iOS 27** device preferred (see [Simulator limits](#simulator-limits)).
- [ ] Device supports and has **Apple Intelligence** enabled where the product depends on it for Siri AI phrase matching.
- [ ] Build and install from **Xcode 27** (beta path as used by the project, e.g. `/Applications/Xcode-beta.app`) with the release-candidate iOS 27 SDK.
- [ ] JustLogIt is installed from a clean or known-good build; USDA provider is configured in Settings for full in-app review (not required solely for handoff-to-composer checks).
- [ ] Siri is enabled; the device language/locale match the phrases you will test.
- [x] **Shortcuts discovery:** after first launch of the installed build, open the **Shortcuts** app and confirm JustLogIt actions appear (see [Shortcuts phrase discovery](#shortcuts-phrase-discovery)).
- [ ] Keep Apple Health authorization **ungranted** for negative Health cases unless a scenario explicitly requires otherwise.
- [ ] Do not paste or record API keys in this document or the bug log.

## Simulator limits

- [ ] Treat Simulator Siri as **non-authoritative**. App Intents may appear in Shortcuts on Simulator, but full Siri voice invocation, cold-launch handoff, and Apple Intelligence phrase matching often require a **physical device**.
- [ ] If Simulator cannot complete a case, mark it **Blocked (device required)** rather than Pass.
- [ ] Shortcuts UI inspection (action title, parameters) may still be useful on Simulator when Siri itself is unavailable.

## Shortcuts phrase discovery

Validate that donated App Shortcut phrases from `JustLogItShortcuts` are visible before relying on voice. Source of truth: `JustLogIt/AppIntents/JustLogItShortcuts.swift` (application name resolves to **JustLogIt**).

### Log Food (`StartFoodLogIntent`)

- Intent title: **Start Food Log** · short title: **Log Food**
- Parameters: required **Food** (`foodDescription`); optional **When Eaten** (`consumedAt`, date/time)

- [x] Launch JustLogIt once after install (donations often register on first run).
- [x] Open **Shortcuts** → action picker → search for **JustLogIt** (or **Log Food** / **Start Food Log**).
- [x] Confirm the **Log Food** / **Start Food Log** action is listed.
- [x] Open the action and confirm it exposes required **Food** and optional **When Eaten**. The iOS 27 detail sheet lists both and labels **When Eaten** optional; the expanded editor only showed **Food** inline in this run.
- [ ] Confirm suggested phrases align with the provider (exact wording follows the installed SDK):
  - Log food in JustLogIt
  - Add food to JustLogIt
  - Log what I ate in JustLogIt
  - Start a food log in JustLogIt
- [ ] Invoke one of the fixed phrases and confirm Siri asks **“What did you eat?”** before opening the reviewed Log flow.
- [x] Run the action from Shortcuts with “two scrambled eggs” and confirm JustLogIt opens the ordinary reviewed Log flow with the complete text. With USDA unconfigured, the lookup failed safely and nothing saved silently.

### Today's Nutrition (`GetTodayNutritionSummaryIntent`)

- Intent title: **Get Today's Nutrition Summary** · short title: **Today's Nutrition**
- No parameters

- [x] Confirm **Today's Nutrition** / **Get Today's Nutrition Summary** is listed under JustLogIt.
- [ ] Confirm suggested phrases:
  - How much have I eaten today in JustLogIt
  - Today's nutrition in JustLogIt
  - Show today's nutrition summary in JustLogIt
  - What are my calories today in JustLogIt
- [ ] Optionally run the action from Shortcuts and confirm JustLogIt opens the **Entries** tab (dialog may report totals when the store is already available).

### Search Logs (`SearchFoodLogsIntent`) — system search only

- Intent title: **Search Food Logs**
- Parameter: **Search** (`criteria` / search term)

- [ ] Do **not** expect a Search Logs tile or donated phrase in Shortcuts.
- [ ] If exercising the system in-app-search surface, confirm a sample term opens **Entries** with that search applied (or Entries open when the term is empty).

### Not registered (do not expect in Shortcuts)

- [ ] **Quick Log Food** (`QuickLogFoodIntent`) is **not** in `JustLogItShortcuts` and is `isDiscoverable = false` — it must **not** appear as a separate discoverable log action. Do not treat it as an acceptance surface.
- [ ] **Search Food Logs** is a system `ShowInAppSearchResultsIntent`, not a registered App Shortcut.

## Acceptance rules

- **Log Food** handoff opens the **existing** reviewed Log workflow. No second nutrition pipeline.
- Siri/Shortcuts supply **user-authored text** and optional **consumed time** only for Log Food.
- **Today's Nutrition** speaks totals without opening the app when a live snapshot is available; on cold/unavailable bootstrap it opens Entries. **Search Logs** opens Entries. Neither creates entries.
- **No persistence** (local or Health) until the person confirms/saves in the app (Log Food path).
- Cancelling before save creates **no** entry.
- In-app logging behavior must remain unchanged when not using Siri.

---

## 1. Warm launch handoff (Log Food)

App is already running (or in memory) before invocation.

- [ ] With JustLogIt in the background on another tab if possible, invoke **“Log food in JustLogIt”**, then answer **“two scrambled eggs”** when Siri asks what you ate.
- [ ] App comes to foreground, **Log** tab is selected.
- [ ] The complete phrase (or equivalent food description) is present in the Log flow / composer path—not truncated to a fragment.
- [ ] Interpretation proceeds through the ordinary UI (or the text is ready for the normal submit path—no silent save).
- [ ] After reviewing, save once and confirm a single entry in Entries with expected description/amount context.

## 2. Cold launch handoff (Log Food)

App is force-quit / not running.

- [ ] Force-quit JustLogIt.
- [ ] Invoke **“Log food in JustLogIt”**, then answer **“two scrambled eggs”** when prompted.
- [ ] App launches to the Log flow with the full food description available for review.
- [ ] No hang, blank first frame forever, or crash on launch.
- [ ] No evidence of synchronous SwiftData open blocking first paint from app init (no long frozen launch attributable to store open in `App.init`).
- [ ] Complete review and save; confirm one entry only.

## 3. Consumed time preservation

- [ ] Invoke handoff with an explicit when-eaten if the phrase/UI allows (Shortcuts: set **When Eaten**; or Siri conversational parameter), e.g. food description **turkey sandwich** and a past time such as **yesterday at noon** / a specific datetime.
- [ ] Confirm JustLogIt opens Log with the food text **and** the supplied consumed time preserved into the review/save path (entry time matches what was provided, not silently replaced by “now” unless the UI shows that choice).
- [ ] Save and confirm Entries detail shows the preserved consumed time.

## 4. Alternate Log Food phrases and empty / minimal food

Phrases below mirror `JustLogItShortcuts` for `StartFoodLogIntent` (plus empty-parameter edge cases via Shortcuts UI).

- [ ] **“Log food in JustLogIt.”** → Siri asks what you ate; answer **“two scrambled eggs”**; Log handoff contains that answer.
- [ ] **“Add food to JustLogIt.”** → Siri asks what you ate; answer **“a turkey sandwich”**; Log handoff contains that answer.
- [ ] **“Log what I ate in JustLogIt.”** → Siri asks what you ate; answer with a food; Log handoff contains that answer.
- [ ] **“Start a food log in JustLogIt.”** → Siri/Shortcuts prompts for food (`What did you eat?`) before opening the reviewed flow.
- [ ] Empty or whitespace-only Food parameter (via Shortcuts if voice will not allow it): intent rejects empty food (`What did you eat?`); no crash; no empty entry saved; user can cancel or enter text in-app.
- [ ] Missing optional **When Eaten** defaults sensibly (typically “now” or app default) without error.

## 5. Today's Nutrition handoff

- [ ] Warm: invoke **“How much have I eaten today in JustLogIt.”** (or **“Today's nutrition in JustLogIt.”** / **“Show today's nutrition summary in JustLogIt.”** / **“What are my calories today in JustLogIt.”**).
- [ ] With the app/store already bootstrapped, Siri/Shortcuts speaks today’s totals and remains in Siri; it does not unnecessarily foreground the app.
- [ ] With no live snapshot (notably cold/background launch), a dialog says Entries are opening and the app foregrounds on **Entries**. Do not treat this fallback as an all-in-Siri cold-summary pass.
- [ ] Cold-launch the same phrase once; Entries opens without crash or permanent blank UI.
- [ ] No new entry is created by this intent.

## 6. System in-app-search handoff (optional)

- [ ] Confirm Search Food Logs does **not** appear as a donated Shortcuts tile or phrase.
- [ ] If the system exposes the `ShowInAppSearchResultsIntent` surface, search for **banana** with at least one known matching entry.
- [ ] App opens **Entries** with the search applied (matching rows visible when the term matches logged food).
- [ ] An empty system search opens Entries without inventing a query or crashing; dialog may say logs are opening.
- [ ] No new entry is created by this intent.

## 7. Cancellation — no records

- [ ] Start a Log Food Siri/Shortcuts handoff with a valid food phrase.
- [ ] Cancel before the app saves (dismiss Siri before open if applicable, or abandon the in-app flow via Cancel / leave without **Save Entry**).
- [ ] Confirm **no new** local entry in Entries.
- [ ] Confirm **no** HealthKit nutrition sample was written (Health app or JustLogIt entry detail; Health remains ungranted for this check).

## 8. Negative cases — no auto-save, no Health auth from Siri

- [ ] **No auto-save:** after Log Food handoff, leave the review/composer without confirming save. Force-quit and relaunch. Confirm no entry was created from Siri-supplied text alone.
- [ ] **No silent nutrition:** confirm nothing in the UI attributes calories/macros to Siri or a language model as the source of record; USDA/manual review path remains authoritative after interpretation.
- [ ] **No Health authorization from Siri alone:** with Health write never granted, complete a Siri handoff into the app. Confirm a **system Health authorization sheet does not appear** solely because of the Siri invocation (authorization remains an in-app Settings / explicit sync concern).
- [ ] Save a log with Health sync off; confirm local save succeeds and no claim of Health write.

## 9. VoiceOver

- [ ] Enable VoiceOver on the device.
- [ ] Invoke a Log Food handoff (Siri or Shortcuts).
- [ ] Confirm focus lands in a usable place on Log; food text and primary actions are reachable and labelled.
- [ ] Navigate to cancel or continue review without a dead end; save or abandon deliberately.
- [ ] Optionally invoke Today's Nutrition or exercise system in-app search once and confirm Entries focus is usable.
- [ ] Disable VoiceOver when finished.

## 10. Regression — in-app logging unchanged

- [ ] Without Siri, log `1 medium banana` (or another known-good phrase) through the normal composer.
- [ ] Confirm parse → match → review → save behaves as in [`ManualAcceptanceTest.md`](ManualAcceptanceTest.md) happy path.
- [ ] Confirm no duplicate entries or stuck pending Siri text after a prior handoff was cancelled.
- [ ] Confirm Entries search from the in-app field still works after any system-search handoff.

## 11. End-of-run integrity

- [ ] Force-quit and relaunch; saved entries from this pass persist; cancelled handoffs left no orphans.
- [ ] Review [`UIBugs.md`](UIBugs.md) for any defects filed during this pass.
- [ ] Set Test record **Result** to Pass only if all required physical-device cases passed (or were N/A with documented Simulator blocks) and no release-blocking Siri handoff defect remains.

---

## Phrase reference (`JustLogItShortcuts`)

Exact phrase templates from `JustLogIt/AppIntents/JustLogItShortcuts.swift`. `\(.applicationName)` → **JustLogIt** on device.

| shortTitle | Intent | Phrases |
| --- | --- | --- |
| **Log Food** | `StartFoodLogIntent` | Log food in JustLogIt · Add food to JustLogIt · Log what I ate in JustLogIt · Start a food log in JustLogIt |
| **Today's Nutrition** | `GetTodayNutritionSummaryIntent` | How much have I eaten today in JustLogIt · Today's nutrition in JustLogIt · Show today's nutrition summary in JustLogIt · What are my calories today in JustLogIt |
| Not registered | `SearchFoodLogsIntent` | System `ShowInAppSearchResultsIntent`; no donated App Shortcut phrases |

| Parameter (UI title) | Intent property | Notes |
| --- | --- | --- |
| **Food** | `foodDescription` | Required for Log Food; empty rejected with “What did you eat?” |
| **When Eaten** | `consumedAt` | Optional date/time on Log Food |
| **Search** | `criteria` | Search Logs term (`StringSearchCriteria`) |

---

## Acceptance map

| Case | Section |
| --- | --- |
| “Log food in JustLogIt” prompts for “two scrambled eggs,” then opens Log with the answer; optional time preserved | §§1–3 |
| Cold launch reaches same state without synchronous SwiftData in `App.init` | §2 |
| All Log Food App Shortcut phrases + empty food | §4 |
| Today's Nutrition → spoken warm summary / cold Entries fallback | §5 |
| Search Logs → Entries with/without term | §6 |
| Cancel before handoff/save creates no local or Health record | §7 |
| No silent save; Health remains permission-neutral | §8 |
| Existing UI logging behaves identically | §10 |
| Phrase list matches `JustLogItShortcuts` | Phrase reference |

**Out of scope:** in-Siri confirm-and-save, **Quick Log Food** (stub, not registered / not discoverable). Re-open those when Spike C (or equivalent) lands.
