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
open -a Xcode-beta JustLogIt.xcodeproj
```

The checked-in `.xcodeproj` is generated from `project.yml`. Regenerate it after adding targets or changing build settings.

## Configuration

Debug and Release use separate xcconfigs. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` for local Debug development only. The real file is ignored by Git and is never imported by Release.

In an xcconfig, URLs must escape `//` because it begins a comment. A Debug proxy therefore uses:

```text
PROXY_BASE_URL = https:/$()/api.example.com
PROXY_ALLOWED_HOST = api.example.com
```

For Debug-only direct USDA development, you may instead set:

```text
USDA_API_KEY = your-development-key
```

If neither Debug value is present, the app launches normally and manual nutrition entry remains available.

The Debug build reads `USDA_API_KEY` through its Debug-only Info.plist. The real value remains in ignored `Config/Secrets.xcconfig` and is not committed.

Release accepts only a root HTTPS proxy URL plus an exact host pin. Supply both from a trusted archive or CI environment; Release does not import the local secrets file, define a USDA key setting, include the debug-key plist field, or compile the direct-USDA endpoint.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild \
  -project JustLogIt.xcodeproj \
  -scheme JustLogIt \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  PROXY_BASE_URL="$JUSTLOGIT_RELEASE_PROXY_URL" \
  PROXY_ALLOWED_HOST="$JUSTLOGIT_RELEASE_PROXY_HOST" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The Release pre-build guard rejects missing, non-HTTPS, unpinned, non-root, placeholder, user-info, port, query, fragment, direct-key, and placeholder-bundle configurations without printing their values. The post-build verifier checks the processed app plist and binary for debug USDA credential markers.

## Apple Health

Apple Health sync is optional and off by default. Enabling it in Settings requests write-only access to food and dietary nutrient types. Confirmed entries are always saved locally first; a HealthKit denial or write failure never discards the JustLogIt entry.

A denied or failed entry can expose **Try Apple Health Again**. That explicit tap may request write authorization and returns visible recovery guidance; background entry saving never presents the permission sheet.

JustLogIt writes every USDA nutrient that has a semantically equivalent HealthKit dietary type. Added sugar remains local because HealthKit exposes total dietary sugar but no distinct added-sugar type.

## Tests

The deterministic domain package can be tested without Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swift test --package-path Packages/JustLogItCore
```

With Xcode 27 installed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project JustLogIt.xcodeproj -scheme JustLogIt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Privacy model

- Food-description interpretation runs on device.
- Food logs and nutrition snapshots are stored locally with SwiftData.
- The app includes no advertising or analytics SDK.
- Only deterministic USDA search terms are sent to the configured food-data service.
- The repository includes a stateless Worker scaffold designed not to retain request bodies or user identifiers; deployed Cloudflare behavior must be audited separately.
- Apple Health integration is optional, write-only, and disabled by default.

See [Documentation/Privacy.md](Documentation/Privacy.md) for precise language and limitations.

## External shipping requirements

- Apple Developer signing and physical-device HealthKit permission testing
- Production Cloudflare Worker URL and USDA secret
- Public privacy-policy and support URLs
- Final screenshots and App Store metadata
- Physical-device Foundation Models testing with the final iOS 27 release

See [Documentation/Performance.md](Documentation/Performance.md) for DEBUG measurement markers and the physical-device performance gate.
