# Deep Links

Custom URL scheme for opening JustLogIt into a **reviewed** food-log handoff (Shortcuts, local testing, automation). Deep links never write nutrition or open SwiftData; they only queue a `PendingFoodLog` on `AppNavigation.shared` with source `.shortcut`.

## URL scheme registration

Scheme: **`justlogit`**

Declared in both:

- `JustLogIt/Resources/Info.plist` (Release)
- `JustLogIt/Resources/Info-Debug.plist` (Debug)

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.example.JustLogIt</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>justlogit</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
  </dict>
</array>
```

## Food log contract

```text
justlogit://log?food=<description>&at=<ISO-8601>
```

| Part | Required | Rules |
|------|----------|--------|
| Scheme | yes | `justlogit` (case-insensitive) |
| Host | yes | `log` (case-insensitive). Other hosts are ignored. |
| `food` | yes | URL-decoded food description. Trimmed; empty after trim → ignored. Capped at **500** characters (`DeepLinkRouter.maxFoodLength`). |
| `at` | no | ISO-8601 date-time (`withInternetDateTime`, with or without fractional seconds). Invalid or empty values are ignored; food still accepted. |

### Examples

```text
justlogit://log?food=two%20eggs
justlogit://log?food=oatmeal&at=2026-07-18T12:00:00Z
justlogit://log?food=tea&at=2026-07-18T12:00:00.250Z
```

### Rejected / no-op

- Wrong scheme (e.g. `https://…`)
- Wrong host (e.g. `justlogit://settings?…`)
- Missing `food`, empty `food`, or whitespace-only `food`
- Unparseable URL components

## Runtime path

```text
System opens justlogit://…
  → WindowGroup.onOpenURL (JustLogItApp)
  → DeepLinkRouter.parseFoodLog(from:)
  → AppNavigation.shared.beginPendingFoodLog(…)  // source: .shortcut, tab: .log
  → LogView.consumePendingFoodLog (after bootstrap / on appear)
  → existing LogViewModel review pipeline
```

Cold start is safe: `onOpenURL` only buffers on `AppNavigation.shared`. It does not open SwiftData. Bootstrap paints first; `LogView` consumes the pending handoff once the store is ready (same seam as Siri).

## Implementation

| Piece | Location |
|-------|----------|
| Pure parse | `JustLogIt/App/DeepLinkRouter.swift` — `parseFoodLog(from:)` |
| Handoff type | `JustLogIt/App/PendingFoodLog.swift` — source `.shortcut` |
| Navigation | `JustLogIt/App/AppNavigation.swift` — `beginPendingFoodLog` / `takePendingFoodLog` |
| Entry point | `JustLogIt/App/JustLogItApp.swift` — `.onOpenURL` |
| Tests | `JustLogItTests/DeepLinkRouterTests.swift` |

## Shortcuts / manual smoke

1. Install a Debug or Release build that includes the scheme.
2. In Safari or Shortcuts **Open URLs**, open
   `justlogit://log?food=two%20eggs&at=2026-07-18T12:00:00Z`
3. App should foreground (or cold-launch), select Log, and offer the pending phrase with Shortcut provenance (not silent save).
4. Confirm rejection: `justlogit://log` and `justlogit://settings?food=eggs` do nothing useful.

## Out of scope (current)

- Universal Links / associated domains
- Paths other than host `log`
- Silent auto-save without review
- Writing HealthKit or SwiftData from the URL handler
