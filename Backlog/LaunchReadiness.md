# P1 — Public launch readiness

- [x] Worker scaffold uses an outbound header allowlist, returns `no-store`/`nosniff`, and has automated header-boundary tests
- [ ] Deploy the Worker with its encrypted USDA secret and verify the production route, failure behavior, and rollback
- [ ] Confirm USDA production capacity and rate-limit attribution
- [ ] Audit deployed Cloudflare visitor-IP handling, Managed Transforms, invocation/custom logs, Logpush, and account-level request logging
- [ ] Validate privacy-label answers against deployed behavior
- [ ] Publish privacy policy and support URL
- [ ] Add production abuse controls without persistent user identifiers
- [ ] Accessibility audit on multiple text sizes, VoiceOver, Voice Control, keyboard, contrast, and dark mode; baseline implementation is not acceptance
- [x] Add generation-based cancellation/stale-result guards and deterministic parser/selection regression tests
- [ ] Manually verify cancellation and stale-result behavior with slow real model/network operations
- [x] Add DEBUG-only Foundation Models and USDA duration/signpost instrumentation; build-for-testing passes
- [ ] Establish physical-device cold/warm performance baselines and complete TestFlight crash/performance review
- [ ] Prompt evaluations against the final iOS 27 system model
- [x] Cache reads fail open and Settings provides a confirmed cache-clear action
- [ ] Add automated corrupted-cache, expiry, write-failure, and disk-pressure recovery tests
- [x] Configure a non-placeholder AppIcon asset in the application target
- [ ] Complete final icon rendering review, screenshots, attribution, and App Store metadata
- [ ] Secret scan of repository and archived release binary

The checked items describe repository implementation, not deployment or App Store acceptance. Production Worker/privacy configuration, physical-device behavior, and final visual/accessibility review remain launch gates.
