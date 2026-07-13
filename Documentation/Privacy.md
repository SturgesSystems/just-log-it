# Privacy

JustLogIt has no accounts, advertising, tracking, or behavioral analytics. Original food text is interpreted by Apple's model on device. Entries and nutrition snapshots are stored locally.

USDA lookup is not an entirely on-device operation. The app sends only a deterministic food search query to the configured service. The production Worker must disable invocation and custom logs, avoid identifiers and request persistence, remove visitor-IP headers from upstream requests, and retain the USDA key only as an encrypted secret.

Recommended user-facing language:

> No accounts. No analytics. No tracking. Your food log stays on your device. When you search FoodData Central, only the resulting food search terms are sent transiently to retrieve USDA matches.

The App Store privacy response must be re-audited against the deployed Cloudflare and USDA behavior before submission.
