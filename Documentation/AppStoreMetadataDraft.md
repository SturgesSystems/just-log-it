# App Store Metadata Draft — JustLogIt

Draft copy for App Store Connect. Claims below are aligned with [README.md](../README.md) and [Privacy.md](Privacy.md). Re-audit privacy answers against the **deployed** Cloudflare Worker and USDA behavior before submission.

**Do not claim fully hands-free Siri save.** Release 1 Siri / Shortcuts only starts a log: food text (and optional consumed time) hand into the ordinary reviewed Log flow. Nothing is persisted until the person confirms in-app.

---

## Name

**JustLogIt**

(Character limit: 30. Current name fits.)

---

## Subtitle options

Pick one (30 characters max). Prefer short, benefit-first wording.

| # | Subtitle | Chars | Notes |
| --- | --- | --- | --- |
| 1 | **Private food log, USDA nutrition** | 32 | Slightly over 30 — shorten if used. |
| 1a | **Private food log, USDA data** | 28 | Recommended default. |
| 2 | **On-device food logging** | 23 | Emphasizes local interpretation. |
| 3 | **Log food. Stay private.** | 24 | Brand / privacy tone. |
| 4 | **Natural language food log** | 26 | Highlights how you describe food. |
| 5 | **Local nutrition logging** | 24 | Storage + privacy angle. |
| 6 | **USDA-backed food diary** | 23 | Authority of FoodData Central. |

**Recommended primary:** `Private food log, USDA data`
**Recommended alternate A/B:** `Log food. Stay private.`

---

## Promotional text (optional, up to 170 characters)

Can be updated without a new binary.

> No accounts. No ads. Describe what you ate; JustLogIt interprets on device, grounds nutrition in USDA FoodData Central, and keeps your log on your iPhone. Optional Apple Health write-back. Start a log with Siri—then review and save in the app.

*(~168 characters; trim if Connect counts differ.)*

Shorter variant:

> Private, on-device food logging with USDA nutrition. Optional Apple Health. Ask Siri to start a log—you always confirm before save.

---

## Description

App Store description (up to 4,000 characters). Plain text for Connect; markdown here is for editing only.

### Primary description (ready to paste)

```
JustLogIt is a low-friction, privacy-first food logger for iPhone.

Describe what you ate in everyday language. JustLogIt interprets your description with Apple’s on-device Foundation Models when available, helps you pick an authoritative USDA FoodData Central match, resolves the amount you actually ate, and saves a durable nutrition snapshot on your device.

PRIVACY FIRST
• No accounts
• No advertising
• No tracking or behavioral analytics
• Food logs and nutrition snapshots stay on your iPhone
• Interpretation of your original food text runs on device

When you search FoodData Central, only the resulting food search terms are sent transiently to retrieve USDA matches. JustLogIt does not run a separate cloud nutrition pipeline for your diary.

HOW LOGGING WORKS
1. Say or type what you ate—for example, “two scrambled eggs” or “a turkey sandwich.”
2. Review suggested USDA matches and choose the right food. The app never silently picks one for you.
3. Confirm the portion, review calories and nutrients, then save.
4. Browse, search, and manage entries in your local log.

If on-device interpretation isn’t available, manual search and manual nutrition entry still work.

USDA FOODDATA CENTRAL
Nutrition comes from USDA FoodData Central after you select a match. Portions are resolved deterministically from servings, grams, counts, and common whole fractions so the saved snapshot reflects what you confirmed—not a guess left unreviewed.

OPTIONAL APPLE HEALTH
Apple Health sync is optional, write-only, and off by default. When you enable it in Settings, confirmed nutrition can be written from your device to your Health store. JustLogIt does not read your Health data. A denied or failed Health write never removes the entry you already saved locally.

SIRI & SHORTCUTS
You can start a food log with Siri or Shortcuts: say “Log food in JustLogIt,” then tell Siri what you ate. Siri supplies the food text you provide (and optionally when you ate it). JustLogIt then opens the ordinary reviewed Log flow so you can interpret, choose a USDA match, check the portion, and save. There is no silent save from Siri. You stay in control of confirmation.

BUILT FOR iOS
Designed for a simple Log → review → Entries workflow with settings you can understand: privacy-respecting defaults, optional Health, and clear paths when the network or on-device model isn’t available.

Your food log is yours. Just log it.
```

### Claims checklist (internal)

| Claim | Source / limit |
| --- | --- |
| No accounts / ads / analytics / tracking | Privacy.md, README |
| On-device interpretation of food text | Foundation Models when available; manual path otherwise |
| Logs stored locally | SwiftData; no CloudKit accounts |
| USDA search sends only search terms | Privacy.md; Worker must match production audit |
| User chooses USDA result | Never silent auto-select |
| Health optional, write-only, off by default | README, Privacy.md |
| Siri starts log only; no silent save | ManualSiriAcceptance.md, Privacy.md |

---

## Keywords

App Store keywords field: comma-separated, **100 characters max**, no spaces after commas in Connect (spaces after commas waste budget). Do not repeat the app name.

### Recommended set (~99 characters)

```
food log,nutrition,calorie,USDA,diary,tracker,privacy,local,Health,meal,macros,portion
```

Count check (no spaces):
`food log,nutrition,calorie,USDA,diary,tracker,privacy,local,Health,meal,macros,portion` ≈ 89–99 depending on Connect’s space rules—prefer **no spaces after commas**:

```
food log,nutrition,calorie,USDA,diary,tracker,privacy,local,Health,meal,macros,portion
```

### Alternate keyword pool (swap if ASO testing suggests)

- food diary
- food tracker
- calorie tracker
- meal log
- macro tracker
- FoodData Central
- Apple Intelligence
- Siri
- offline
- no account

Avoid trademark misuse and competitor brand names. “Apple Intelligence,” “Siri,” and “Health” may be acceptable as feature terms; follow current App Review guidance at submission time.

---

## What’s New — first Siri-capable build

Use for the first release that ships **Start Food Log** (or equivalent) App Shortcut / Siri handoff. Keep honest: start + review, not hands-free complete logging.

### Short (preferred for What’s New)

```
• Start a food log with Siri or Shortcuts—say what you ate and JustLogIt opens the reviewed Log flow
• Optional when-eaten time from Shortcuts carries into review before you save
• Same on-device interpretation, USDA match, portion check, and confirm-before-save path as typing
• Nothing is saved until you confirm in the app
```

### Medium

```
You can now start logging from Siri or Shortcuts.

Say “Log food in JustLogIt,” then answer Siri’s question about what you ate. JustLogIt receives the food description you provide (and an optional consumed time), then opens the ordinary Log experience so you can review interpretation, pick a USDA match, confirm the portion, and save.

There is no silent or fully hands-free save from Siri—you stay in control of every confirmed entry. Privacy defaults are unchanged: on-device interpretation when available, local storage, optional write-only Apple Health, and USDA lookup only for the food search terms needed to find a match.
```

### One-liner (if space is tight)

```
Start a food log with Siri—then review and save in JustLogIt. No silent saves.
```

---

## Privacy nutrition labels narrative

Narrative for App Store Connect privacy questions and the public privacy policy. Must match [Privacy.md](Privacy.md). **Re-audit against deployed Cloudflare + USDA retention before final answers.**

### User-facing summary (recommended)

> No accounts. No analytics. No tracking. Your food log stays on your device. When you search FoodData Central, only the resulting food search terms are sent transiently to retrieve USDA matches.

### Data practices (for nutrition labels / questionnaire)

| Topic | Draft answer |
| --- | --- |
| **Account** | Not used. No sign-in. |
| **Advertising** | None. No ad SDKs. |
| **Tracking** | None. No behavioral analytics or third-party tracking SDKs. |
| **Food log / nutrition entries** | Stored **on device** (local database). Not uploaded to a JustLogIt account (there is none). |
| **On-device interpretation** | Original food text is interpreted by Apple’s model **on device** when Foundation Models is available. |
| **Product interaction / analytics** | No advertising or behavioral analytics products. Do not declare analytics collection unless a future build adds it. |
| **USDA / FoodData Central** | Not fully on-device. App sends **deterministic food search queries** (search terms only) to the configured service (production: credential-shielding proxy → USDA). Intended: transient retrieval of matches; no user accounts or food-log diary upload. Finalize “Data Not Linked to You” / contact-info answers only after production Worker audit (no invocation/custom logs retaining bodies, no user identifiers, no request persistence, no visitor-IP leakage to upstream, USDA key as encrypted secret only). |
| **Apple Health** | Optional; **write-only**; **disabled by default**. When enabled, confirmed nutrition is written from the device to the user’s Health store. JustLogIt does **not** read Health data. Permission is per nutrient type. Failed/denied Health write does not delete the local entry. Health is **not** authorized from a Siri invocation; only an already-enabled, non-interactive sync may follow a **confirmed** local save. |
| **Siri / App Intents / Shortcuts** | Optional input path. System supplies user-authored food text and optional consumed time. JustLogIt remains authoritative for interpretation, USDA selection, portion, calculation, and persistence. Release 1: handoff into reviewed Log flow only—**no silent save**. Food history is **not** published to Spotlight by default. |
| **Identifiers** | No account ID. Production path must not attach advertising IDs or analytics user IDs (app includes none). |
| **Diagnostics** | App-source posture: privacy-safe observability categories only; no analytics SDK. Do not claim “no diagnostics APIs” beyond what the privacy manifest and binary audit support. |
| **Privacy manifest** | Declares same-app `UserDefaults` with required-reason `CA92.1`. Does **not** yet assert an empty collected-data inventory—finalize only after production Cloudflare/USDA audit. Current app-source audit: no direct required-reason use of file timestamp, disk space, system boot time, or active keyboard APIs. |
| **Health deletion** | Deleting a JustLogIt entry removes only Health samples that carry that entry’s exact JustLogIt sync identifiers. Never queries or deletes other apps’ nutrition records. |

### Nutrition labels — draft classification (pending production audit)

Until the Worker audit is signed off, treat network food-search as:

- **Data type:** Product interaction / search content (food search terms only)—not full diary export.
- **Linked to user:** Should be **not linked** if production truly sends no account, device advertising ID, or persistent user key.
- **Used for tracking:** **No** (no cross-app tracking).
- **Purpose:** App functionality (retrieve USDA matches).

**Do not submit “Data Not Collected” as a blanket claim** while USDA search exists. Prefer precise “data not linked to you” for transient search terms **after** audit, plus local-only for the food log itself.

### Optional Health section (Settings / App Store privacy detail)

> Apple Health sync is optional, write-only, and disabled by default. When enabled, confirmed nutrition is written directly from the device to your Health store. JustLogIt does not read Health data.

---

## Screenshot script — logging chat flow (6 frames)

Capture on a current iPhone frame (e.g. 6.7" and 6.5" as required by Connect). Use a clean sample day; no real personal data. Prefer Light Mode consistency unless showing Dark Mode as a seventh optional shot. Overlay marketing captions **on the store frame**, not burned into the app UI unless designed as in-app empty states.

**Narrative arc:** describe food → interpret → USDA choice → portion → review → saved.

| Frame | Screen / state | Capture setup | Overlay caption (suggested) |
| --- | --- | --- | --- |
| **1** | **Log tab — empty / ready composer** | Fresh log conversation; cursor or clear composer; subtle empty guidance if present. | **Describe what you ate** · Everyday language, not a barcode hunt |
| **2** | **After submit — interpretation / assistant reply** | User bubble: `two scrambled eggs` (or similar). Assistant turn showing understood food / clarifying only if needed—prefer a clean success path. | **On-device understanding** · Interpretation stays on your iPhone |
| **3** | **USDA match list** | Multiple FoodData Central results visible; one clear best match (e.g. egg, scrambled) without implying silent auto-pick—selection chrome or “choose” affordance visible if possible. | **You pick the USDA match** · Authoritative FoodData Central results |
| **4** | **Portion / quantity resolution** | Portion UI with a sensible amount (e.g. 2 large eggs / gram weight). | **Confirm the amount** · Servings, grams, or counts—resolved clearly |
| **5** | **Nutrition review before save** | Calories + key macros visible; **Save** (or equivalent) not yet committed—or mid-tap freeze without success toast. | **Review, then save** · Nothing lands in your log until you confirm |
| **6** | **Entries list (or entry detail) after save** | New entry visible with description, time, and nutrition snapshot; optional quiet Settings note is **not** required in-frame. | **Your log, on device** · Local history you can search and manage |

### Optional alternate frame (replace #1 or add to tablet set)

- **Siri handoff (honest):** Log tab with prefilled food text from Shortcuts/Siri **and** review UI still required—caption: **Start with Siri. Confirm in the app.** Do **not** show a “Saved via Siri” success that implies silent save.

### Shot list notes

- Do not show API keys, Debug proxy hosts, or developer Settings toggles.
- Do not show Health permission sheets unless a separate “Works with Apple Health” marketing frame is approved; if shown, pair with “Optional · Write-only · Off by default.”
- Prefer VoiceOver-friendly large Dynamic Type only if the layout still reads in a screenshot.
- Record the exact build number and locale used for each asset set.

---

## Support & legal URL placeholders

Replace before submission. README lists public privacy-policy and support URLs as external shipping requirements.

| Field | Placeholder | Notes |
| --- | --- | --- |
| **Support URL** | `https://example.com/justlogit/support` | Required. Should include how to contact, OS requirements (iOS 27+ / Apple Intelligence notes), and that logs are local. |
| **Marketing URL** (optional) | `https://example.com/justlogit` | Product page; can match landing. |
| **Privacy Policy URL** | `https://example.com/justlogit/privacy` | Must reflect Privacy.md + production Worker audit. Include USDA search-terms-only language and optional Health. |
| **EULA** | Standard Apple EULA **or** `https://example.com/justlogit/terms` | Custom only if needed. |

### Support page outline (for when URLs go live)

1. What JustLogIt is (privacy-first food log).
2. Requirements: recent iOS; on-device model when available; manual path otherwise.
3. How to log (type or start with Siri → always review → save).
4. USDA / network: only food search terms leave the device for matches.
5. Apple Health: optional, write-only, off by default.
6. Contact: `support@example.com` (placeholder).
7. Link to privacy policy.

### Contact email placeholder

`support@example.com` — set in App Store Connect App Information.

---

## App Review notes (draft)

Short notes for the Review team (not public):

```
JustLogIt is a privacy-first food logger. No account is required.

Primary path: Log tab → enter a food description → choose a USDA FoodData Central match → confirm portion → save. Entries are stored on device.

USDA access: Release builds call our HTTPS proxy (not a client-embedded USDA key). Search sends food search terms only.

Apple Health: optional, write-only, disabled by default. Review can leave Health off; logging still works fully offline for the local diary after matches are obtained (or via manual nutrition entry).

Siri / App Intents: “Start Food Log” (or Log Food) hands food text into the in-app Log flow. There is no silent save from Siri; confirmation happens in the app.

Demo food text: “two scrambled eggs” or “turkey sandwich.”
```

---

## Pre-submission gate (copy)

- [ ] Privacy policy URL live and consistent with production Worker audit
- [ ] Support URL live
- [ ] Nutrition labels re-checked against deployed Cloudflare + USDA behavior
- [ ] Screenshots match current Log conversation UI
- [ ] What’s New does **not** claim hands-free or silent Siri save
- [ ] Subtitle ≤ 30 characters
- [ ] Keywords ≤ 100 characters
- [ ] Health and Siri copy match Privacy.md

---

*Draft only. Not a substitute for legal review or App Store Connect field validation at upload time.*
