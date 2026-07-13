# JustLogIt

JustLogIt is a low-friction, privacy-first iPhone food logger. It interprets a natural-language food description with Apple's on-device Foundation Models framework, lets the person choose an authoritative USDA FoodData Central result, resolves the consumed quantity deterministically, and stores a durable nutrition snapshot locally.

## Current milestone

The repository is implementing the MVP described in [Backlog/MVP.md](Backlog/MVP.md). Deferred capabilities and their activation criteria live in [Backlog/README.md](Backlog/README.md).

## Requirements

- Xcode 27 beta with the iOS 27 SDK
- An iOS 27 device with Apple Intelligence enabled for on-device parsing
- XcodeGen 2.45 or newer (`brew install xcodegen`)
- Node.js 22 or newer for the optional Cloudflare Worker tests

The app remains usable through manual search and manual nutrition entry when Foundation Models is unavailable.

## Generate and open the project

```sh
xcodegen generate
open JustLogIt.xcodeproj
```

The checked-in `.xcodeproj` is generated from `project.yml`. Regenerate it after adding targets or changing build settings.

## Configuration

Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`. The real file is ignored by Git.

For the normal configuration, set:

```text
PROXY_BASE_URL = https://api.example.com
```

For debug-only direct USDA development, you may instead set:

```text
USDA_API_KEY = your-development-key
```

No release configuration embeds a USDA key. If neither value is present, the app launches normally and manual nutrition entry remains available.

## Tests

The deterministic domain package can be tested without Xcode:

```sh
swift test --package-path Packages/JustLogItCore
```

With Xcode 27 installed:

```sh
xcodebuild test -project JustLogIt.xcodeproj -scheme JustLogIt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Privacy model

- Food-description interpretation runs on device.
- Food logs and nutrition snapshots are stored locally with SwiftData.
- The app includes no advertising or analytics SDK.
- Only deterministic USDA search terms are sent to the configured food-data service.
- The minimal Worker is designed not to retain request bodies or user identifiers.

See [Documentation/Privacy.md](Documentation/Privacy.md) for precise language and limitations.

## External shipping requirements

- Apple Developer signing and HealthKit entitlement when that backlog item is implemented
- Production Cloudflare Worker URL and USDA secret
- Public privacy-policy and support URLs
- Final app icon, screenshots, and App Store metadata
- Physical-device Foundation Models testing with the final iOS 27 release
