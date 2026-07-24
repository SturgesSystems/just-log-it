# Manual UI acceptance test

This is the release-level, user-driven UI pass for JustLogIt. Run it on an iPhone simulator from a clean install using the production app configuration. Automated UI tests complement this pass but do not replace it.

Log every unexpected behavior in [`UIBugs.md`](UIBugs.md) as soon as it is observed. Continue testing when the failure is non-destructive; otherwise stop the affected scenario and preserve the app state for diagnosis.

## Siri / App Shortcuts

This document does **not** cover Siri or Shortcuts invocation. For App Shortcut discovery, warm/cold handoff, consumed-time preservation, cancellation, and related negatives, use the full checklist:

- **[`ManualSiriAcceptance.md`](ManualSiriAcceptance.md)** — prefers a physical iOS 27 device; phrases and actions must match `JustLogIt/AppIntents/JustLogItShortcuts.swift`.

## Test record

| Field | Value |
| --- | --- |
| Date | |
| Tester | |
| Commit | |
| Xcode / iOS build | |
| Simulator model | |
| Appearance | Light / Dark |
| Dynamic Type | Default / Accessibility size |
| USDA provider shown in Settings | |
| Result | Pass / Fail / Blocked |

## Preconditions

- Build and launch with `/Applications/Xcode-beta.app` on the current iOS 27 simulator runtime.
- Use a configuration that reports a USDA provider in Settings. Never paste or record an API key in this document or the bug log.
- Confirm the test can reach FoodData Central before beginning the USDA scenarios.
- Start from a deleted app unless a scenario says otherwise. Deleting the app is the canonical way to reset SwiftData, preferences, and cached food responses.
- Keep Apple Health permissions ungranted for this pass. Do not approve any nutrient type if a system authorization sheet appears.
- Record screenshots for visual defects and attach their paths to the associated bug.

## Acceptance rules

- Every visible control must respond once to one deliberate tap, have an understandable label, and produce visible feedback.
- Loading operations must be cancellable where the UI offers Cancel. No stale result may appear after cancellation.
- Keyboard dismissal must work through the native Done control and interactive downward scrolling wherever text can be entered. The keyboard must not obscure the active field or primary action.
- Text must not truncate, overlap, clip, or become unreachable at the tested Dynamic Type sizes.
- Destructive actions must require confirmation, and Cancel must leave data unchanged.
- A scenario passes only when every expected result is observed. Record any deviation before continuing.

## 1. Fresh launch and navigation

- [ ] Delete JustLogIt from the simulator, install it, and launch it.
- [ ] Confirm the Log tab is selected, the compact navigation title is **JustLogIt**, and **What did you eat?** is the only task-level heading.
- [ ] Confirm the empty state contains **What did you eat?**, the explanatory text, example prompts, and the privacy label.
- [ ] Confirm the bottom composer contains a visibly labelled **Manual** control, **Food and amount** field, and disabled Continue button.
- [ ] Confirm the screen has no transient error, stale conversation, clipped content, unexplained badge, or volatile-store warning.
- [ ] Open Entries. Confirm the empty state explains that no food is logged and offers **Log food**.
- [ ] Tap **Log food** and confirm it returns to Log.
- [ ] Open Settings, then return to Log and Entries. Confirm tab selection and navigation state remain coherent.
- [ ] Background and foreground the app. Confirm the current screen and in-progress non-sensitive text remain usable.

## 2. USDA configuration and happy path

- [ ] In Settings, confirm **Provider** does not read **Not configured** and no USDA-unavailable warning appears.
- [ ] Return to Log, enter `1 medium banana`, and submit with the keyboard action or Continue button.
- [ ] Confirm parsing and USDA-search progress are visible without freezing navigation.
- [ ] If multiple matches appear, confirm the first five are readable and tappable. If **Show N More** appears, expand it and use **Show Fewer Matches** to collapse it.
- [ ] Choose a plausible raw banana result. Confirm selection feedback appears and food details load.
- [ ] If quantity clarification appears, test both segments: enter a valid serving count, switch to Grams, enter a valid mass, then switch back to the intended unit.
- [ ] Confirm the decimal keyboard has a native **Done** action and that dragging the transcript downward dismisses it interactively.
- [ ] Tap **Review Nutrition**. Confirm food, amount, calories, protein, carbohydrate, fat, USDA attribution, and FDC ID are legible and internally plausible.
- [ ] Tap **Choose a Different Food**, confirm the match flow is restored, then reselect and return to review.
- [ ] Tap **Save Entry** once. Confirm **Food Logged** appears and the save control cannot be triggered twice.
- [ ] Tap **Log Another Food**. Confirm the composer returns to a clean idle state.
- [ ] Open Entries and confirm the banana appears once with its amount, source, time, calories, and protein where available.

## 3. Composer and keyboard behavior

- [ ] On an idle Log screen, focus **Food and amount**. Confirm the field is visible above the keyboard and Continue becomes enabled only for non-whitespace input.
- [ ] Enter multiple lines up to the composer limit. Confirm the composer grows without covering the transcript or tab bar.
- [ ] Tap **Done** in the keyboard toolbar. Confirm focus clears without submitting or deleting the text.
- [ ] Focus the field again and drag the transcript downward. Confirm interactive keyboard dismissal.
- [ ] Submit through the keyboard return/continue action. Confirm it behaves the same as the Continue button and submits only once.
- [ ] During a parsing, search, or details-loading state, tap **Cancel**. Confirm the operation ends promptly and no late result replaces the idle screen.
- [ ] Tap an example prompt. Confirm it becomes the submitted user description and does not duplicate or leave the composer active.

## 4. USDA recovery paths

Use a query that is unlikely to match, or temporarily disable the simulator network if necessary. Restore connectivity immediately afterward.

- [ ] Produce a no-match or connection failure. Confirm the recovery heading and explanation distinguish the failure in plain language.
- [ ] Confirm **Search USDA** is focused or readily focusable and cannot submit empty or whitespace-only text.
- [ ] Enter simpler terms and submit from the keyboard. Confirm a new search begins and the old failure does not remain on top of valid results.
- [ ] Produce an interpretation failure and tap **Edit Description**. Confirm the original description is editable in the primary composer.
- [ ] From a USDA search/no-result failure, tap **Edit Search**. Confirm focus moves to the preserved USDA terms without starting an unrequested lookup.
- [ ] From a selected-food details failure, tap **Search Again**. Confirm a new search begins and returns to selectable matches or an accurate USDA recovery state.
- [ ] From a failure, tap **Enter Manually**. Confirm the manual-entry sheet opens and can be cancelled back to the recovery state without data loss.
- [ ] In the result chooser, open **Other Options**, exercise **Edit Description**, and confirm the app returns to an editable idle state.
- [ ] Re-enter the chooser, open **Other Options**, and confirm **Enter Nutrition Manually** opens the manual sheet.

## 5. Manual entry

- [ ] Open Manual Entry from the **Manual** control beside the Log composer.
- [ ] Confirm **Save** is disabled with empty required fields.
- [ ] Enter a food name and amount. Use Next/Previous to move between fields and verify the active field remains visible.
- [ ] Enter invalid and negative nutrition values. Confirm inline validation is specific, Save remains disabled, and no entry is created.
- [ ] Enter valid calories and optional protein, carbohydrates, and total fat. Toggle **Approximate** and adjust the date/time.
- [ ] Use **Done** and interactive scrolling to dismiss the keyboard. Confirm entered values remain intact.
- [ ] Tap **Cancel**. Confirm the sheet dismisses and no entry appears in Entries.
- [ ] Reopen Manual Entry and save a valid record. Confirm the sheet dismisses and the Log screen shows a saved confirmation.
- [ ] Confirm the manual record appears once in Entries with **Manual** as its source and the chosen date/time grouping.

## 6. Entries search, detail, and deletion

- [ ] With at least one USDA and one manual entry present, open Entries and focus **Food, brand, or description**.
- [ ] Search by a partial food name, by brand if available, and by original description. Confirm matching is case-insensitive and irrelevant rows disappear.
- [ ] Enter a query with no result. Confirm a clear empty-search state and **Clear search** action appear.
- [ ] Tap **Clear search**. Confirm all entries return and the query clears.
- [ ] Dismiss the search keyboard through interactive scrolling and the native keyboard control.
- [ ] Open the USDA entry detail. Confirm amount, logged time, source, original input, nutrition, and USDA metadata are present and readable.
- [ ] Return and open the manual entry detail. Confirm manual calculation/source information is accurate and no USDA section appears.
- [ ] In detail, tap Delete and then **Cancel**. Confirm the detail remains and the entry is unchanged.
- [ ] Return to the list, swipe an entry, tap Delete, then **Cancel**. Confirm the row remains.
- [ ] Repeat list deletion and confirm **Delete**. Confirm exactly the selected entry disappears and the other record remains.
- [ ] Delete the remaining entry from its detail view and confirm deletion. Confirm navigation returns to the Entries empty state.

## 7. Settings and cache confirmation

- [ ] Confirm Food data, Apple Health, Privacy, and About sections are present with no clipped footer text.
- [ ] Tap **Clear downloaded food cache**, then **Cancel**. Confirm no success alert appears and cached/logged content is unchanged.
- [ ] Tap it again and confirm **Clear Cache**. Confirm a result message appears and can be dismissed with **OK**.
- [ ] Repeat the clear operation. Confirm the app reports that the cache is already empty rather than failing.
- [ ] Confirm clearing the cache does not delete any previously retained entry used for this check.
- [ ] Confirm the version/build and FoodData Central attribution are present.

## 8. Apple Health UI without granting access

- [ ] In Settings, confirm **Save nutrition to Apple Health** is off by default and the footer describes write-only behavior.
- [ ] Turn the toggle on. Confirm progress feedback appears while the system authorization UI is requested.
- [ ] In the system sheet, grant no nutrient permissions and decline/close authorization using the available system action.
- [ ] Confirm JustLogIt returns to Settings without hanging, crashing, or claiming all nutrients are writable.
- [ ] Confirm the resulting explanatory message is understandable and the toggle state does not misrepresent authorization.
- [ ] Turn the toggle off. Confirm the message states that new entries stay in JustLogIt and existing Health data is unchanged.
- [ ] Save one new USDA entry with Health sync off. Confirm it saves locally and its detail does not claim it was written to Apple Health.

Do not validate successful Health writes in this pass. That requires an explicitly authorized physical-device test.

## 9. Dark Mode and Dynamic Type

Run the core launch, Log composer, chooser, review, Entries detail, Manual Entry, Settings, and all confirmation alerts in each practical configuration below.

- [ ] Dark Mode at the default text size: backgrounds, separators, tint, warnings, disabled controls, and nutrition values retain sufficient contrast.
- [ ] Light Mode at an Accessibility text size (prefer AX3): all content remains reachable by scrolling; controls do not overlap; important labels are not truncated.
- [ ] At Accessibility size, composer text wraps without hiding Continue, result rows remain distinguishable, and bottom actions remain reachable above the keyboard.
- [ ] At Accessibility size, Settings footers, entry nutrition, dialogs, and Manual Entry units remain understandable.
- [ ] Rotate once where the simulator/app supports it. Confirm no stuck keyboard, lost sheet, or permanently displaced safe-area content.

## 10. End-of-run integrity

- [ ] Force-quit and relaunch. Confirm saved entries persist and deleted entries do not return.
- [ ] Confirm a fresh USDA lookup still succeeds after clearing the cache.
- [ ] Confirm navigation, composer, and search remain responsive after the complete test journey.
- [ ] Review [`UIBugs.md`](UIBugs.md): every observed defect has severity, reproduction steps, expected/actual behavior, evidence, status, and an owner or explicit **Unassigned** value.
- [ ] Set the Test record result to Pass only if no open release-blocking defect remains.
