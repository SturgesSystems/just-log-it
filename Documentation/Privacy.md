# Privacy

JustLogIt has no accounts, advertising, tracking, or behavioral analytics. Original food text is interpreted by Apple's model on device. Entries and nutrition snapshots are stored locally.

USDA lookup is not an entirely on-device operation. The app sends only a deterministic food search query to the configured service. The production Worker must disable invocation and custom logs, avoid identifiers and request persistence, remove visitor-IP headers from upstream requests, and retain the USDA key only as an encrypted secret.

Recommended user-facing language:

> No accounts. No analytics. No tracking. Your food log stays on your device. When you search FoodData Central, only the resulting food search terms are sent transiently to retrieve USDA matches.

The App Store privacy response must be re-audited against the deployed Cloudflare and USDA behavior before submission.

Apple Health sync is optional, write-only, and disabled by default. When enabled, confirmed nutrition is written directly from the device to the user’s Health store. JustLogIt does not read Health data. HealthKit permissions are controlled per nutrient type, and a denied or failed write does not remove the locally saved entry.

Siri and App Intents are an optional input path, not a separate nutrition pipeline. When a person starts a log through Siri or Shortcuts, the system supplies user-authored food text and an optional consumed time. JustLogIt remains authoritative for interpretation, USDA selection, portion resolution, nutrition calculation, and persistence. Release 1 hands the request into the ordinary reviewed Log flow; there is no silent save from Siri. After handoff, food text is still interpreted by Apple’s on-device Foundation Models when available, then grounded through the same USDA and confirmation path used for typed input. Food history is not published to Spotlight by default. Optional HealthKit write-back remains user-gated and is never authorized from a Siri invocation; only an already-enabled, non-interactive sync may follow a confirmed local save.

The app privacy manifest declares same-app `UserDefaults` access with required-reason code `CA92.1`. It intentionally does not assert an empty collected-data inventory: that declaration must be finalized only after the production Cloudflare and USDA retention behavior is audited. The current app-source audit found no direct use of required-reason file timestamp, disk-space, system-boot-time, or active-keyboard APIs.

When someone deletes a nutrition entry that JustLogIt previously saved to Apple Health, the app removes only Health objects carrying that entry’s exact JustLogIt sync identifiers. If Health cleanup fails, the local entry and a local retry tombstone remain until cleanup can be retried; JustLogIt never queries or deletes another app’s nutrition records.
