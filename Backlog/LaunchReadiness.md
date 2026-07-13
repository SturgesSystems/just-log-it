# P1 — Public launch readiness

- [x] Worker scaffold uses an outbound header allowlist, returns `no-store`/`nosniff`, and has automated header-boundary tests
- [x] Worker authenticates USDA with `X-Api-Key`, rejects redirects, enforces JSON success + 2 MiB body limits, and times out through body consumption
- [x] Worker enforces a fail-closed global 900/hour Durable Object quota that stores only `{epochHour, count}`
- [ ] Deploy the Worker with its encrypted USDA secret and verify the production route, failure behavior, and rollback
- [ ] Confirm USDA production capacity and rate-limit attribution
- [ ] Audit deployed Cloudflare visitor-IP handling, Managed Transforms, invocation/custom logs, Logpush, and account-level request logging
- [ ] Validate privacy-label answers against deployed behavior
- [ ] Publish privacy policy and support URL
- [ ] Confirm the deployed Durable Object migration/quota behavior under real traffic
- [ ] Accessibility audit on multiple text sizes, VoiceOver, Voice Control, keyboard, contrast, and dark mode; baseline implementation is not acceptance
- [x] Add generation-based cancellation/stale-result guards and deterministic parser/selection regression tests
- [ ] Manually verify cancellation and stale-result behavior with slow real model/network operations
- [x] Add DEBUG-only Foundation Models and USDA duration/signpost instrumentation; build-for-testing passes
- [ ] Establish physical-device cold/warm performance baselines and complete TestFlight crash/performance review
- [x] Parser evaluation corpus/harness and documentation exist; production remains the default prompt
- [ ] Prompt evaluations against the final iOS 27 system model on an eligible device
- [x] Cache reads fail open and Settings provides a confirmed cache-clear action
- [x] Automated corrupted-cache, expiry, and write-failure recovery tests (`DiskCachedFoodDataProviderTests`)
- [ ] Real-device disk-pressure recovery observation (Simulator/device acceptance)
- [x] Configure a non-placeholder AppIcon asset in the application target
- [ ] Complete final icon rendering review, screenshots, attribution, and App Store metadata
- [x] Source secret scan of repository (`Scripts/scan-repository-secrets.sh`; git-tracked files only)
- [ ] Secret scan of archived release binary

The checked items describe repository implementation, not deployment or App Store acceptance. Production Worker/privacy configuration, physical-device behavior, and final visual/accessibility review remain launch gates.
