# Dark mode manual QA checklist

Use this after appearance-related UI changes. Run **both** Light and Dark (Settings → Developer → Dark Appearance, or Control Center), ideally with system Accent left as default and once with JustLogIt’s brand teal visible on Log chrome.

| Field | Value |
| --- | --- |
| Date | |
| Tester | |
| Commit | |
| Device / Simulator | |
| iOS | |
| Result | Pass / Fail |

## How to run

1. Build and launch JustLogIt on a simulator or device.
2. Toggle **Light → Dark** (or dark → light) without relaunching when possible; re-check any screen that looked wrong after a cold start.
3. Prefer a session that already has at least one logged entry so Entries has list content.
4. Record failures in [`UIBugs.md`](UIBugs.md) with a screenshot of the broken appearance.

## Pass criteria

- No pure-white or pure-black panels that flash the wrong appearance.
- Body text remains legible on its background (especially chat bubbles and chips).
- Soft fills (chips, cards, hairlines, shadows) remain visible enough to separate surfaces — they may be subtle, but not missing.
- Accent-tinted surfaces use **white** (or system prominent-button labels), not `.primary`, on solid brand fills.
- Reduce Motion: card shadows may disappear; content and borders must still read.

---

## 1. Cold launch / bootstrap

- [ ] **Light:** Launch mark, “JustLogIt”, “Starting…”, privacy footer legible on `LaunchBackground`.
- [ ] **Dark:** Same; white labels stay on the darker brand wash (not system white page).
- [ ] After load, tab bar + tint match brand accent in both appearances.

## 2. Log — empty state

- [ ] Canvas uses grouped background (not a hard-coded white sheet).
- [ ] Example chips: primary text on elevated assistant fill; hairline visible.
- [ ] Siri callout: accent wash + primary text; readable in dark (wash is stronger in dark).
- [ ] Privacy capsule: secondary text on chip fill.
- [ ] USDA-not-configured banner (if shown): orange text on orange 12% fill still readable in dark.

## 3. Log — conversation chrome

- [ ] User bubbles: **white** label on solid brand teal gradient (not washed-out / not `.primary`).
- [ ] Begin **Edit** on the first food description: white ring on the bubble; text contrast still good (fill stays solid).
- [ ] Assistant bubbles: primary text on `secondarySystemGroupedBackground`; border visible.
- [ ] Typing bubble + Stop control: secondary text/icon readable; card edge visible.
- [ ] Assistant cards (clarification chips, when-eaten, quantity, USDA picker, review, confirm, recovery, completion): card fill elevates from canvas; hairline/shadow present in dark.

## 4. Log — USDA picker card

- [ ] Filter field on tertiary fill readable in both appearances.
- [ ] Result rows: primary title, secondary metadata; soft accent stroke still visible in dark.
- [ ] Scrollable list does not paint a white inset.

## 5. Log — composer dock

- [ ] Ultra-thin material dock adapts; top hairline visible against transcript.
- [ ] Text field fill is elevated (not invisible against material).
- [ ] Send / primary actions (`borderedProminent`) keep legible labels on accent and green confirm tints.
- [ ] Disabled send state still distinguishable in dark.
- [ ] Quantity unit menu + amount field match composer field treatment.

## 6. Log — manual entry sheet

- [ ] Form uses system grouped styling (no hard-coded white form).
- [ ] Error label (red) and volatile warning (orange) readable on form background.
- [ ] Keyboard toolbar controls visible.

## 7. Entries — Logs pane

- [ ] Segmented control + search field system chrome OK in dark.
- [ ] **Today** summary card: elevated fill, border, and (when motion allowed) shadow visible on grouped list.
- [ ] Macro chips (P/C/F) and proportion bar colors readable on card.
- [ ] Empty-today strip: secondary text on tertiary fill.
- [ ] Entry rows: primary names, secondary brand/macros; composite badge accent-on-accent-wash.
- [ ] Empty / no-match states: ContentUnavailable + prominent buttons OK.

## 8. Entries — Foods pane

- [ ] Recognized food rows match Log/Entries text hierarchy in dark.
- [ ] Empty / no-match states OK.

## 9. Entry detail

- [ ] List sections, macro summary tiles (`tertiarySystemFill`), composite accent label.
- [ ] Destructive Delete control readable.
- [ ] Health status section secondary copy readable.

## 10. Food detail

- [ ] List content OK.
- [ ] Bottom “Log this food again” bar (`.bar` material + prominent button) readable above tab bar / home indicator.

## 11. Settings

- [ ] List / section headers / footers system adaptive.
- [ ] Orange warning icon when USDA not configured.
- [ ] Remembered match rows secondary captions.
- [ ] Health toggle and status copy.
- [ ] Siri / Privacy / About labels and hierarchical icons.

## 12. System banners (Root)

- [ ] Volatile-store banner (if force-enabled in a test build): **black** text on solid orange — intentional; remains high-contrast in dark.
- [ ] Health lifecycle material banner: caption + dismiss control readable in both appearances.

## 13. Appearance flip while in-flow

- [ ] Mid-conversation (review or USDA picker), switch Light ↔ Dark: no stuck white panels, bubbles recolor correctly, composer stays usable.
- [ ] Entries with Today card open: elevation/border update without blanking.

## 14. Optional stress

- [ ] Increase text size one accessibility step; re-check user bubble and Today card wrapping.
- [ ] Reduce Motion on: shadows may clear; borders and fills still separate surfaces.

---

## Known intentional hard-codes (not bugs)

| Location | Choice | Why |
| --- | --- | --- |
| `ChatUserBubble` | `.foregroundStyle(.white)` on brand fill | Accent bubble needs fixed light label; `.primary` would go black in light mode |
| `BootstrapLoadingView` | White labels on `LaunchBackground` | Brand splash is dark teal in both light and dark assets |
| `RootTabView` volatile banner | Black text on `.orange` | High-contrast warning on a solid semantic orange fill |
| Card shadows | `Color.black.opacity(...)` | Black shadows are correct elevation; intensity is appearance-tuned |

## Recent fixes (audit baseline)

- User edit state no longer washes accent to ~50% opacity under white text; editing uses a white stroke ring on solid brand fill.
- `ChatPalette.hairline` resolves separator alpha by interface style so card/bubble borders do not vanish in dark mode.
- `DayNutritionSummaryView` stroke + shadow intensify in dark mode (and respect Reduce Motion).
