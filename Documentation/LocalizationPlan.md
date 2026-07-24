# Localization plan (groundwork)

JustLogIt is English-first today. Nearly all user-facing copy is hard-coded in SwiftUI views, App Intents, HealthKit messaging, and on-device model prompts. This document inventories string categories, names the hard parts that block a naive String Catalog pass, and outlines a phased approach. **It is not a commitment to ship non-English locales in the next release.**

**Bias:** prefer this plan over a mass migration to `Localizable.xcstrings`. Ship catalog work only when a concrete locale and QA budget exist.

## Current state (as of this document)

| Area | Status |
|------|--------|
| String Catalog (`Localizable.xcstrings`) | **Not present** |
| `String(localized:)` / `Text("key")` catalog keys | **Not used** in app UI |
| App Intents titles / dialogs | `LocalizedStringResource` / `IntentDialog` (catalog-ready **once** a catalog exists and keys are extracted) |
| App Shortcut phrases | English string literals in `JustLogItShortcuts` |
| Number entry | `LocalizedNumberParser` already respects `Locale` decimal/grouping separators |
| Relative time, unit aliases, model prompts | English-centric hard-coded lexicons and `@Guide` text |

Resources live under `JustLogIt/Resources/` (assets, plists, privacy). `project.yml` sources the whole `JustLogIt/` tree; a future catalog file can sit next to other resources **without** special XcodeGen rules, but converting call sites is the real cost.

### Optional pilot (deferred)

A low-risk pilot would be **5–10 highly visible strings** from:

1. Log empty state (`LogView.emptyState`) — e.g. “What did you eat?”, Siri tip chip, privacy chip
2. Settings → Siri & Shortcuts section header/footer and three bullet labels

**Not done in this groundwork pass** so we avoid a half-migrated UI (catalog + hundreds of remaining literals) without a target locale or screenshot QA. When a pilot is warranted:

1. Add `JustLogIt/Resources/Localizable.xcstrings` (default English).
2. Regenerate the Xcode project if needed (`xcodegen generate`).
3. Replace only those literals with `String(localized:)` / `Text` catalog keys; keep keys stable and descriptive.
4. Do **not** extract Foundation Models prompts, unit lexicons, or parser evaluation corpora into the catalog.

---

## User-facing string categories

### 1. Chrome and navigation

Tabs, titles, and shell chrome that appear on every launch.

| Examples | Primary locations |
|----------|-------------------|
| “Log”, “Entries”, “Settings” | `RootTabView` |
| “JustLogIt”, “Entries”, “Settings”, “Manual Entry” | `LogView`, `EntriesView`, `SettingsView`, `ManualEntryView` |
| Volatile-store banner, Health lifecycle banner, “Dismiss” | `RootTabView` |

### 2. Log empty state and onboarding tips

First-run and empty conversation copy; often the first impression of product voice.

| Examples | Primary locations |
|----------|-------------------|
| “What did you eat?” | `LogView.emptyState`, composer placeholder |
| “Chat like you would with a friend…” | `LogView.emptyState` |
| “Try saying” + example chips | `LogView` (examples are also **parser sample inputs**) |
| “Say “Log food in JustLogIt” with Siri” | `LogView.emptyState` |
| “Food interpretation stays on this iPhone” | `LogView.emptyState` |
| USDA not configured warning | `LogView`, `SettingsView` |

### 3. Log conversation UI

Composer, cards, clarification, review, success.

| Examples | Primary locations |
|----------|-------------------|
| Placeholders: “What did you eat?”, “Reply…”, “e.g. 2 hours ago”, “Search USDA…” | `LogView+Composer` |
| Actions: “Confirm log”, “Start over”, “Manual”, “Log another food”, “Enter nutrition manually”, “Take photo”, “Choose photo” | Composer / cards |
| Cards: “When did you eat this?”, “How much did you eat?”, “USDA matches”, “Confirm this log?”, “Logged”, “Saved on this device.” | `LogView+Cards` |
| Errors from parser / photo / AI availability | `FoundationModelsFoodParser`, `FoundationModelsImageFoodProposer`, photo load paths |

**Note:** Assistant bubbles may show model-authored `clarificationPrompt` text. That is **not** static catalog copy; see [Foundation Models English bias](#foundation-models-english-bias).

### 4. Entries list, detail, and day summary

| Examples | Primary locations |
|----------|-------------------|
| “No entries yet”, “Log food”, “No matching entries”, “Clear search” | `EntriesView` |
| “No recognized foods yet”, “No matching foods” | `EntriesView` |
| “Today”, “cal”, “No meals logged today”, macro labels | `DayNutritionSummaryView`, `EntriesRows` |
| “Composite”, FDC captions, delete confirmations | Rows / detail views |
| Data-type badges: “Branded”, “Survey”, “Foundation food”, … | `EntryDetailView`, `FoodResultViews` (mapping USDA English type strings) |

### 5. Settings

| Section | Examples | Location |
|---------|----------|----------|
| Food data | Provider label, clear cache / remembered, footers | `SettingsView` |
| Apple Health | Toggle, authorization messages, long footer | `SettingsView`, `HealthSyncSettingsModel`, `HealthKitNutritionWriter` |
| **Siri & Shortcuts** | “Say “Log food in JustLogIt””, “Opens JustLogIt for review — never auto-saves”, Shortcuts tip, long footer | `SettingsView` |
| Privacy / About | Privacy bullets, version, “USDA FoodData Central” | `SettingsView` |
| Alerts | Clear cache / remembered confirmations and result toasts | `SettingsView` |

Siri section copy **documents English example phrases**. Localized UI must stay aligned with **actually donated** App Shortcut phrases for that language (see [Siri and App Shortcuts](#siri-and-app-shortcuts)).

### 6. App Intents, dialogs, and Shortcuts metadata

Already typed as localizable resources where Apple expects them:

| Intent / provider | Strings |
|-------------------|---------|
| `StartFoodLogIntent` | title “Start Food Log”, description, parameter titles (“Food”, “When Eaten”), request dialogs, result dialog |
| `GetTodayNutritionSummaryIntent` | title, description, parameter summary, result dialog |
| `SearchFoodLogsIntent` | title, description, “Search” parameter |
| `JustLogItShortcuts` | App Shortcut **phrases**, `shortTitle` |

Phrase donation is a **separate** localization problem from UI catalogs (below).

### 7. Accessibility labels and hints

VoiceOver strings often duplicate visible labels with extra detail (“Selected food, …”, “Time, …. Tap to edit.”). Localize with the same keys or dedicated accessibility keys so labels do not drift from visible text.

### 8. System-adjacent product names (usually leave untranslated)

Keep stable product/brand tokens unless marketing requires otherwise:

- JustLogIt
- USDA / FoodData Central / FDC
- Apple Health / Apple Intelligence / HealthKit
- Shortcuts (system app name may be localized by the OS)

UI sentences that **mention** these names still need surrounding sentence localization.

### 9. Non–user-facing English (do not put in String Catalog)

| Kind | Why |
|------|-----|
| Foundation Models `@Guide` / system prompts | Model instruction English; see hard parts |
| `ClarificationPromptBuilder` conversation scaffolding | Model input, not UI |
| Observability / os_log categories | Debugging |
| Parser evaluation corpus (`ParserEvaluationCorpus`) | English test fixtures |
| USDA description matching tokens, dataType heuristics | External English dataset vocabulary |
| Internal keys (`JustLogItSource` metadata, preference keys) | Persistence / Health metadata |

---

## Hard parts

### Nutrition units and formatting

**Display**

- UI uses short English abbreviations heavily: `cal`, often `g` for macros in rows/summary.
- “approx.” chips and “Approximate quantity” accessibility labels.
- Serving copy mixes USDA household strings (often English from FoodData Central) with app-authored phrases (“USDA serving · …”, “Converts using USDA serving when needed”).
- Manual entry and review show nutrient names (calories, protein, carbs, fat, …) in English section footers and field labels.

**Input / parsing**

- `LocalizedNumberParser` already handles locale decimals (e.g. `1,5` in `fr_FR`) — keep this; do not force `.` only.
- Unit **lexicons** (oz, ounce, g, gram, cup, tablespoon, serving, …) live in grounding, quantity recovery, and evidence extraction under `JustLogItCore`. Non-English speakers will type local units (`g`, `ml`, `cucharada`, `Unze`) that must map to the same internal canonical units used for USDA serving math.
- Photo / model guides explicitly forbid inventing grams/ounces; unit vocabulary in guides is English-centric.

**Recommendations**

1. Separate **display formatting** (`MeasurementFormatter` / custom format styles, localized nutrient names) from **canonical internal units** (always SI-ish / USDA-aligned enums or normalized strings).
2. Build a locale-aware unit alias table for parsing; keep evaluation corpora per locale later.
3. Do not translate USDA raw descriptions for matching; optionally pretty-print or capitalize for display only.
4. Decide product policy for energy: keep kcal as “cal” vs locale-preferred kJ (HealthKit path must stay consistent).

### Relative time and meal labels

`RelativeTimeParser` and `MealTimeInference` understand English phrases only (`just now`, `2 hours ago`, `yesterday`, meal names, etc.). Composer placeholder “e.g. 2 hours ago” teaches English patterns.

Localizing the **placeholder** without expanding parsers would mislead users. Relative time localization is a **core + tests** project, not a catalog-only change.

### Siri and App Shortcuts

Release 1 is foreground handoff: Siri/Shortcuts supply user-authored food text and optional time; JustLogIt reviews before save. That architecture is locale-agnostic; **invocation phrases are not**.

#### What must be localized for Siri

| Asset | Mechanism | Notes |
|-------|-----------|--------|
| Intent title, description, parameter titles | `LocalizedStringResource` + String Catalog | Shortcuts UI language |
| Intent dialogs / result speech | `IntentDialog` / dialog strings | Spoken or shown by Siri |
| **App Shortcut phrases** | `AppShortcutsProvider` `phrases:` | **Primary discovery path** for “Log … in JustLogIt” style invocation |
| `shortTitle` / system image metadata | Provider metadata | Shortcuts gallery |

#### Phrase localization strategies

Apple requires App Shortcut phrases to include `\(.applicationName)` (app name token). Semantic matching helps nearby wording in the **same language**, but:

1. **Per-locale phrase lists**
   Donate phrases for each supported language (String Catalog / localized phrase resources as supported by the SDK). Example pattern stays “\<action\> … in \(.applicationName)” so routing is unambiguous without a nutrition App Schema.

2. **UI/docs must match donated phrases**
   Settings and Log currently teach the fixed English phrase “Log food in JustLogIt”; Siri then requests the free-form food parameter. When phrases localize, **update these tips from the same source of truth** (or generate tip strings per locale) so Settings never teaches a phrase Siri will not accept.

3. **Do not claim generic “log food” without app name**
   Architecture and spike docs already warn that bare “log that I ate …” may not route to JustLogIt. That remains true across languages until a food-log App Schema exists.

4. **Parameter conversation**
   `StartFoodLogIntent` asks “What food would you like to log?” when food is empty. Localize dialogs; food **content** stays user language and still flows into the English-biased parser (below).

5. **Device language / Siri language QA**
   `ManualSiriAcceptance.md` already requires device language/locale to match test phrases. Each shipped locale needs a physical-device phrase matrix (cold launch, semantic near-misses, empty food).

6. **Shortcuts action names vs spoken phrases**
   Settings mentions Shortcuts listing a “Log Food” style action; keep Shortcuts-visible titles and donated phrases consistent per locale.

7. **Future in-Siri confirm/save**
   Release 2+ spoken confirmations (“That’s approximately 285 calories. Log it?”) multiply localization surface and must reuse the same unit/nutrition formatting rules as the app.

### Foundation Models English bias

On-device interpretation (`FoundationModelsFoodParser`, image/semantic proposers, clarification re-parse prompts) is instructed in **English**:

- `@Generable` / `@Guide` descriptions use English food examples and English negative lists (“who cares”, “idk”, “n/a”, “leftovers”).
- System-style instructions tell the model to write **one natural user-facing clarification question** shown **verbatim** in chat.
- `ClarificationPromptBuilder` wraps turns in English scaffolding (“Original user message:”, “Assistant asked:”, …).
- Non-food detectors and multi-item heuristics in core often assume English conjunctions / patterns (“with”, “and”, …).

**Implications**

| Risk | Detail |
|------|--------|
| User writes in another language | Model may still extract product names (multilingual capability varies by Apple FM build) but guides and few-shot style are English-optimized. |
| Clarification UI language | Prompts ask for a “natural” question; the model may answer in English even when the user wrote Spanish/French/etc. |
| Empty productName policy | English placeholder lists may not catch local fillers; false “foods” or missed identity gaps. |
| Evaluation | `ParserEvaluationCorpus` and LoggingEval are English-only gates today. |

**Recommendations (when targeting a locale)**

1. Treat FM prompts as a **separate localization workstream** from String Catalog (prompt packs per locale, not `NSLocalizedString`).
2. Prefer structured flags (`quantityNeedsClarification`) + **app-authored** localized question templates over freeform model prose when quality bar is high.
3. Keep nutrition authoritative path (USDA + deterministic math) language-agnostic; never let the model invent nutrient numbers regardless of locale.
4. Add non-English smoke cases to parser eval before claiming locale support.
5. Document in privacy/release notes that interpretation quality may be strongest for English until prompt packs land.

### USDA and external English data

FoodData Central descriptions, brands, and data types are predominantly English. Search terms derived from user input may be non-English; match quality may degrade. Ranking/remembered signatures store user-facing text as entered — no automatic translation layer. Product decision: ship locale UI first with English USDA results, or invest in query translation (privacy-sensitive; prefer on-device only if ever).

### Pluralization, dates, and lists

Use iOS formatters rather than hand-built English:

- Entry grouping section titles, “Used N×”, relative `lastUsedAt` (already uses `FormatStyle` in places).
- Strings with embedded counts (“\(n) of \(m)”) need stringsdict / catalog plural rules per locale.
- Avoid assembling sentences from fragments without ICU-aware catalogs.

### Accessibility and Dynamic Type

Localization often lengthens German/French strings; keep empty-state and Settings footers flexible (already use multi-line text in many places). Re-test VoiceOver labels after translation so they stay concise.

### Tests and automation

- UI tests and accessibility identifiers use stable IDs (good — prefer IDs over English button titles).
- Any test that asserts visible English copy must become locale-aware or stay English-scheme-only.
- Core unit tests for relative time and units need parallel fixtures per supported language.

---

## Phased approach (recommended)

### Phase 0 — Groundwork (this document)

- [x] Inventory categories and hard parts.
- [x] Record App Shortcut / Siri phrase strategy requirements.
- [ ] No mass String Catalog migration.
- [ ] Optional UI pilot deferred until a target locale is chosen.

### Phase 1 — Infrastructure only

When a first locale is scheduled:

1. Add `Localizable.xcstrings` under `JustLogIt/Resources/`.
2. Confirm XcodeGen / CI pick up the catalog (usually automatic via `JustLogIt/` sources).
3. Enable the locale in project / Xcode localization settings.
4. Establish key naming convention (e.g. `settings.siri.footer`, `log.empty.title`) and ban raw English keys that equal display text long-term if desired.

### Phase 2 — High-visibility static UI

Migrate in this order for maximum user impact and minimal engine risk:

1. Tabs + navigation titles
2. Log empty state + Settings (including Siri section, with phrase alignment)
3. Entries empty / search empty states
4. Alerts and Health Settings messages
5. Remaining Log cards / Manual Entry chrome

Leave model prompts and unit lexicons for later phases.

### Phase 3 — App Intents + Siri phrases

1. Extract intent metadata and dialogs into the catalog.
2. Donate **localized** App Shortcut phrases; re-run physical-device acceptance per language.
3. Align in-app Siri tips with donated phrases.
4. Update `ManualSiriAcceptance.md` with a per-locale phrase matrix.

### Phase 4 — Quantities, units, relative time

1. Expand unit alias tables and relative-time lexicons.
2. Localize nutrient/unit **display** via formatters.
3. Extend parser eval / LoggingEval with non-English smoke sets.

### Phase 5 — Foundation Models prompt packs (optional / hard)

1. Locale-specific guides and clarification scaffolding **or** template-based clarification UI.
2. Policy for mixed-language user input.
3. Explicit quality bar: do not market full locale support until smoke eval passes.

---

## Explicit non-goals (until scheduled)

- Translating the entire app in one PR.
- Localizing USDA food descriptions.
- Localizing debug-only provider strings beyond user-visible Settings labels.
- Claiming Siri works for a language without donated phrases + device QA.
- Relying on the model alone to produce correctly localized clarification copy.

---

## File map (quick reference)

| Concern | Paths |
|---------|--------|
| Settings Siri UI | `JustLogIt/Features/Settings/SettingsView.swift` |
| Log empty state | `JustLogIt/Features/Log/LogView.swift` |
| Composer / cards | `JustLogIt/Features/Log/LogView+Composer.swift`, `LogView+Cards.swift` |
| Entries empty states | `JustLogIt/Features/Entries/EntriesView.swift` |
| App Shortcuts phrases | `JustLogIt/AppIntents/JustLogItShortcuts.swift` |
| Start Food Log intent | `JustLogIt/AppIntents/StartFoodLogIntent.swift` |
| Other intents | `GetTodayNutritionSummaryIntent.swift`, `SearchFoodLogsIntent.swift` |
| FM parser prompts | `JustLogIt/Services/FoundationModelsFoodParser.swift` |
| Relative time | `Packages/JustLogItCore/.../RelativeTimeParser.swift`, `MealTimeInference.swift` |
| Locale-aware numbers | `JustLogIt/Services/LocalizedNumberParser.swift` |
| Siri acceptance | `Documentation/ManualSiriAcceptance.md` |
| Siri architecture | `Documentation/SIRI_AI_INTEGRATION_SPIKE.md`, `Backlog/SiriAIIntegration.md` |
| Privacy wording | `Documentation/Privacy.md` |

---

## Success criteria for “locale-ready” (future checklist)

A language is ready for external testers only when:

1. Static UI for Log / Entries / Settings is catalog-backed and reviewed.
2. App Shortcut phrases are donated for that language; physical Siri invocation works with documented tips.
3. Number entry works with that locale’s decimal separator.
4. Critical unit phrases the product claims to support are parsed.
5. Known FM limitations are documented; no false claim of parity with English interpretation quality.
6. UITests still pass under the English scheme; optional locale snapshot tests if maintained.

---

## Related docs

- [`Architecture.md`](Architecture.md) — Siri as input adapter, not nutrition authority
- [`Privacy.md`](Privacy.md) — on-device interpretation, USDA search boundary, Siri handoff
- [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md) — device language must match test phrases
- [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md) — phrase design and schema limits
- [`ParserEvaluation.md`](ParserEvaluation.md) — English evaluation gates today
