<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus icon" width="96" />

# Hermes Plus

**iOS client for [Hermes Agent](https://github.com/nesquena/hermes-webui) — a fork of [Hermex](https://github.com/uzairansaruzi/hermex).**

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)]()
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

</div>

## What's different from Hermex

- **Header shows "Hermes Plus"** — logo + "Plus" text
- **No swipe gestures** — pin, archive, and delete via long-press context menu only (no accidental swipe actions)
- **Unsigned IPA builds** — built via GitHub Actions (`macos-26` runner, Xcode 26 beta), install via AltStore/SideStore

Everything else is identical to upstream Hermex: same server API, same features, same codebase.

## Getting the IPA

1. Go to [Actions](https://github.com/braintimebox/hermex-plus/actions)
2. Click the latest successful **Build Hermes Plus** run
3. Download `HermesPlus-unsigned.zip` from Artifacts
4. Extract → install `.ipa` via AltStore or SideStore

## Building from source

Requires Xcode 26+ (iOS 18 SDK). The CI uses `macos-26` runner.

```zsh
xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

For unsigned IPA (no Mac needed):

```zsh
APP=$(find DerivedData -name "*.app" -path "*/Release-iphoneos/*" -type d | head -1)
mkdir Payload && cp -R "$APP" Payload/ && zip -r HermesPlus.ipa Payload
```

## Credits

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex) by [@uzairansar](https://x.com/uzairansar). All credit for the original app goes to Uzair. Hermes Plus adds minor UX tweaks and a no-Mac build pipeline.

## License

MIT — see [LICENSE](LICENSE). Original Hermex is also MIT-licensed.
