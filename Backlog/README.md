# Product backlog

This folder is the durable product backlog for JustLogIt. It deliberately separates the smallest useful product from launch hardening and later bets so infrastructure work does not obscure the core product hypothesis.

## Priority definitions

- **P0 — MVP:** required to validate natural-language logging end to end.
- **P1 — Launch gate:** required before a broad public App Store release.
- **P2 — Next:** valuable after the core flow is validated.
- **P3 — Explore:** evidence-driven investments that need a spike first.

## Backlog index

| Priority | Area | Outcome | Trigger |
| --- | --- | --- | --- |
| P0 | [MVP](MVP.md) | Parse, select, calculate, review, and save | Now |
| P1 | [Launch readiness](LaunchReadiness.md) | Safe public distribution | Core flow passes device tests |
| P2 | [Conversation-first navigation](ConversationNavigation.md) | Logging home with adaptive sidebar and reusable foods | Core flow is stable enough to restructure navigation |
| P2 | [Clarification and confirmation](ClarificationConfirmation.md) | One safe correction path for uncertain text and photo proposals | Text ambiguity policy is validated; required before photo input |
| P2 | [Composite foods and ingredients](CompositeFoods.md) | Confirmed prepared dishes or deterministic component totals | Multi-component demand justifies persistence and editing complexity |
| P2 | [HealthKit](HealthKit.md) | Optional nutrition write-back | Users value retained entries |
| P2 | [Offline data](OfflineData.md) | Private/offline USDA lookup | Offline demand is demonstrated |
| P2 | [Remembered foods](RememberedFoods.md) | Faster repeat logging | Repeat-query rate is material |
| P3 | [Photo-assisted identification](PhotoAssistedFoodIdentification.md) | Private on-device photo proposals feeding the normal review flow | Clarification foundation and physical-device image API spike pass |
| P3 | [USDA mirror](USDAMirror.md) | Remove live USDA quota dependency | Quota, privacy, or reliability justifies it |

Items move between files only with a short note explaining the evidence or constraint that changed their priority.
