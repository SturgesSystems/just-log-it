# System controls, Action Button, and Siri — Log Food

How JustLogIt’s **Start Food Log** App Intent surfaces for **Siri**, **Shortcuts**, the **Action Button**, and **Control Center** on **iOS 27**, and how to set those up as a user.

This is the product/setup companion to the handoff acceptance checklist in [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md). Architecture of the intent pipeline is summarized in [`Architecture.md`](Architecture.md) and the spike notes in [`SIRI_AI_INTEGRATION_SPIKE.md`](SIRI_AI_INTEGRATION_SPIKE.md).

---

## What the app registers today

| Piece | Location | Role |
| --- | --- | --- |
| `StartFoodLogIntent` | `JustLogIt/AppIntents/StartFoodLogIntent.swift` | Background-first, dynamic-foreground main-app intent. Siri collects required **Food** and optional **When Eaten**, then opens the reviewed nutrition flow. Never persists nutrition. |
| `JustLogItShortcuts` | `JustLogIt/AppIntents/JustLogItShortcuts.swift` | `AppShortcutsProvider` that donates the **Log Food** shortcut (and other shortcuts). |
| `SiriFoodLogCoordinator` | `JustLogIt/AppIntents/SiriFoodLogCoordinator.swift` | Handoff into `AppNavigation.pendingFoodLog` → reviewed Log tab. |
| Intent donation after save | `JustLogIt/AppIntents/FoodLogIntentDonation.swift` | Best-effort `StartFoodLogIntent.donate()` so Siri learns recurring phrases. |
| Deep link (optional) | `justlogit://log?food=…&at=…` | Same pending-log seam; useful for personal Shortcuts and testing. |

**Log Food** is the short title users see in system UIs. The full intent title is **Start Food Log**.

Registered Log Food phrases (application name substitutes for JustLogIt):

- Log food in JustLogIt
- Add food to JustLogIt
- Log what I ate in JustLogIt
- Start a food log in JustLogIt

Siri then asks **“What did you eat?”** Xcode 27 metadata export rejects interpolated
free-form `String` parameters in App Shortcut phrase templates.

There is **no** WidgetKit / ControlWidget target in this repo. Action Button and Control Center reach Log Food through **App Shortcuts** and the system **Shortcuts** app, not a first-party Control Center button shipped by JustLogIt.

---

## How the system surfaces “Log Food”

```text
Install + first launch JustLogIt
        ↓
AppShortcutsProvider donates “Log Food” (StartFoodLogIntent)
        ↓
┌───────────────────┬────────────────────┬──────────────────────────┐
│ Siri voice        │ Shortcuts app      │ Action Button / CC       │
│ “Log eggs in      │ Run action or      │ Assign Shortcut →        │
│  JustLogIt”       │ personal shortcut  │ Log Food / personal run  │
└─────────┬─────────┴─────────┬──────────┴────────────┬─────────────┘
          └───────────────────┴───────────────────────┘
                              ↓
       Siri collects Food / optional When Eaten in background
                              ↓
       StartFoodLogIntent.perform (dynamic foreground handoff)
                              ↓
              SiriFoodLogCoordinator.beginLog → Log tab review
                              ↓
              User confirms in-app (only then save / optional Health)
```

**Product rule (all entry points):** Siri, Shortcuts, Action Button, and Control Center only deliver a food phrase (and optional time). JustLogIt opens the **existing reviewed Log flow**. Nothing is written to the local store or Apple Health until the person confirms in the app.

---

## Prerequisites (users)

1. **iPhone on iOS 27** with JustLogIt installed from a current build.
2. Launch **JustLogIt once** after install so App Shortcuts can register.
3. Open **Shortcuts** → search **JustLogIt** or **Log Food** and confirm the action appears.
4. Siri enabled; device language/locale matching the phrases you will use.
5. For voice + Apple Intelligence phrase matching, prefer a device with **Apple Intelligence** available and enabled (same guidance as [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md)).

Simulator can show Shortcuts actions but is **not** authoritative for Action Button, full Siri, or Control Center behavior.

---

## Setup: Shortcuts app

1. Install and open JustLogIt once.
2. Open **Shortcuts**.
3. Search **JustLogIt**, **Log Food**, or **Start Food Log**.
4. Open **Log Food** / **Start Food Log**. Confirm parameters:
   - **Food** — required (what you ate, in your own words)
   - **When Eaten** — optional date-time
5. Run the action with a sample phrase (e.g. `two scrambled eggs`). JustLogIt should open on **Log** with that text ready for review — not already saved.

Optional: create a **personal shortcut** that runs JustLogIt’s Log Food action with a fixed Food value, or opens `justlogit://log?food=…` for one-tap logging of a recurring meal.

---

## Setup: Action Button → Log Food

Supported on Action Button hardware (e.g. iPhone 15 Pro and later models that expose the control). Steps vary slightly by iOS build; labels below match the common iOS 18+ / iOS 27 path.

1. Complete [Shortcuts discovery](#setup-shortcuts-app) so **Log Food** is registered.
2. Open **Settings → Action Button**.
3. Choose **Shortcut** (not Camera, Flashlight, etc.).
4. Under app shortcuts / JustLogIt (or search), select **Log Food**.
   - If the system only lists *personal* shortcuts, create a personal shortcut that runs JustLogIt → **Log Food**, then assign that personal shortcut.
5. Press the Action Button:
   - If **Food** is empty, the system should prompt for what you ate (intent dialog: “What did you eat?”).
   - JustLogIt then comes to the foreground on the Log tab for review.
6. Confirm or cancel in-app. Cancel must leave **no** new entry.

### Action Button tips

- Prefer assigning the **system-donated** Log Food App Shortcut when it appears, so you get the same parameters and dialogs as Siri.
- A personal shortcut with a **pre-filled Food** string is useful for a frequent meal (e.g. “morning oats”) but less flexible than prompting each press.
- Action Button does **not** save nutrition by itself; it only starts the reviewed flow.

---

## Setup: Control Center → Log Food

JustLogIt does **not** ship a native Control Center control (`ControlWidget`). Users still get one-tap access via the system **Shortcuts** control.

1. Complete [Shortcuts discovery](#setup-shortcuts-app).
2. Optionally create a personal shortcut named e.g. **Log Food** that runs JustLogIt’s Log Food action (with or without a default Food).
3. Open **Control Center** (swipe down from the top-right).
4. Tap **Edit** / the **+** control gallery (wording depends on iOS build).
5. Add a **Shortcut** (or **Open App** / **Run Shortcut**) control from the gallery.
6. Configure that control to run **Log Food** (donated) or your personal shortcut.
7. Tap the control from Control Center → same handoff as Shortcuts: app opens for review; no silent save.

### Control Center tips

- Place the control on the first Control Center page for quick access while eating.
- Lock Screen / Action Button + Control Center can all point at the same personal shortcut so muscle memory stays consistent.
- If the gallery does not list JustLogIt by name, use **Run Shortcut** and pick the personal shortcut that wraps Log Food.

---

## Setup: Siri (voice)

After install and first launch:

| You say | Expected result |
| --- | --- |
| “Log two scrambled eggs in JustLogIt” | Opens Log with that phrase for review |
| “Add a turkey sandwich to JustLogIt” | Same handoff path |
| “Start a food log in JustLogIt” | Opens Log; system or app asks for food if missing |
| “How much have I eaten today in JustLogIt” | Separate **Today’s Nutrition** shortcut (summary / Entries handoff — not Log Food) |

Include **“in JustLogIt”** for reliable routing. There is no system food-journal App Schema; generic “log that I ate eggs” may not choose JustLogIt.

Full warm/cold/cancellation matrix: [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md).

---

## Behavior contract (all system entry points)

| Concern | Behavior |
| --- | --- |
| Persistence | None until in-app confirm/save |
| Nutrition authority | USDA / manual path in-app; never Siri/model as source of record |
| HealthKit | Optional post-save; no authorization sheet from Siri/Action Button alone |
| Execution | Main app, background-first with dynamic foreground (`supportedModes: [.background, .foreground(.dynamic)]`, `allowedExecutionTargets: .main`) |
| Empty Food | Intent requests a value (`needsValueError` / “What did you eat?”); no empty entry |
| Optional When Eaten | Preserved into review when supplied |
| In-progress Log conversation | Pending phrase shown as banner (Start / Dismiss) rather than wiping work blindly |

---

## ControlWidget API notes (developers)

Checked against the **iOS 27** SDK (`WidgetKit` / `AppIntents` in Xcode 27). Controls for Control Center / related system surfaces are the iOS 18+ `ControlWidget` family.

### What the SDK provides

- `ControlWidget` + `StaticControlConfiguration` / `AppIntentControlConfiguration`
- `ControlWidgetButton(action:label:)` where `action` is an `AppIntent` or `OpenIntent`
- `ControlWidgetToggle` with `SetValueIntent` (not relevant to Log Food)
- Display metadata: `.displayName`, `.description`, optional `.promptsForUserConfiguration()`
- `ControlConfigurationIntent` for configurable controls

Illustrative shape (not in tree):

```swift
import AppIntents
import SwiftUI
import WidgetKit

struct LogFoodControl: ControlWidget {
  static let kind = "com.example.JustLogIt.logFood"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: StartFoodLogIntent()) {
        Label("Log Food", systemImage: "fork.knife.circle")
      }
    }
    .displayName("Log Food")
    .description("Start a reviewed food log in JustLogIt.")
  }
}
```

### Why JustLogIt does not ship this yet

| Barrier | Detail |
| --- | --- |
| **Not one-file / not trivial `project.yml`** | Controls live in a **Widget Extension** (own target, bundle id, Info.plist, signing, `WidgetBundle` / `@main`). That is multi-file project plumbing, not a single Swift file in the app target. |
| **Required Food parameter** | `StartFoodLogIntent` requires `foodDescription`. A Control Center tap has no speech context; the system may prompt, but UX is weaker than Siri. A polished control usually wants a **parameterless** “open Log” intent or `OpenIntent`, which is a small product API addition—not a free re-export of today’s intent. |
| **Foreground + main-app only** | Intent already correctly opens the main app. A widget extension must **not** reimplement persistence; it should only invoke the shared App Intent. Sharing types cleanly across app + extension is extra packaging work. |
| **User path already works** | Action Button → Shortcut and Control Center → Run Shortcut already invoke the donated App Shortcut without a ControlWidget. |

### If we add a native control later

1. Add a `JustLogItControls` (or widgets) extension target in `project.yml` with WidgetKit.
2. Prefer either:
   - **Button → existing `StartFoodLogIntent`** and accept system prompting for Food, or
   - **New parameterless intent** / deep link that only opens the Log composer (better one-tap empty start).
3. Keep background + dynamic-foreground modes / main-app execution so Siri collects parameters first while interpretation, USDA, and save stay in the app.
4. Do **not** open SwiftData from the extension for Log Food.
5. Re-verify Control Center gallery listing, Action Button assignment, and the [`ManualSiriAcceptance.md`](ManualSiriAcceptance.md) no-auto-save rules on a physical iOS 27 device.

Until that ships, document and support the **Shortcuts / Action Button** path above; do not claim a first-party Control Center icon in App Store or Settings copy.

---

## Related intents (not Action Button primary)

Also donated via `JustLogItShortcuts` (optional to assign as shortcuts; not the Log Food primary):

| Short title | Intent | Purpose |
| --- | --- | --- |
| Log Food | `StartFoodLogIntent` | Reviewed food log handoff (this document) |
| Today's Nutrition | `GetTodayNutritionSummaryIntent` | Speaks a live summary without opening the app when ready; dynamically opens Entries as a cold-store fallback |
| Search Logs | `SearchFoodLogsIntent` | Entries search handoff |

`QuickLogFoodIntent` is a **stub** (not discoverable / not in `JustLogItShortcuts`). Do not wire Action Button or Control Center to it.

---

## Troubleshooting

| Symptom | What to try |
| --- | --- |
| Log Food missing in Shortcuts / Action Button picker | Launch JustLogIt once; force-quit Shortcuts and reopen; reinstall build; confirm device is iOS 27 with App Intents from this binary |
| Action Button does nothing | Settings → Action Button is **Shortcut** and points at Log Food or a personal shortcut that runs it |
| App opens but no food text | Food parameter empty or cancelled prompt; try Shortcuts with an explicit Food string |
| Entry appeared without confirming | File as release blocker in [`UIBugs.md`](UIBugs.md) — violates Spike A contract |
| Control Center has no JustLogIt icon | Expected without `ControlWidget`; add a **Run Shortcut** control instead |
| Simulator Action Button / CC | Prefer physical device; mark blocked if hardware/control chrome unavailable |

---

## Source map

| Concern | Path |
| --- | --- |
| Intent | `JustLogIt/AppIntents/StartFoodLogIntent.swift` |
| App Shortcuts phrases / short titles | `JustLogIt/AppIntents/JustLogItShortcuts.swift` |
| Handoff coordinator | `JustLogIt/AppIntents/SiriFoodLogCoordinator.swift` |
| Dependency registration | `JustLogIt/AppIntents/AppIntentsRegistration.swift`, `JustLogIt/App/JustLogItApp.swift` |
| Pending log + navigation | `JustLogIt/App/PendingFoodLog.swift`, `JustLogIt/App/AppNavigation.swift` |
| Log consume / banner | `JustLogIt/Features/Log/LogView.swift` |
| Deep link | `JustLogIt/App/DeepLinkRouter.swift` |
| In-app education copy | `JustLogIt/Features/Settings/SettingsView.swift` (Siri & Shortcuts section) |
| Physical acceptance | `Documentation/ManualSiriAcceptance.md` |
| Project targets | `project.yml` (single iOS app; no widget extension) |
