<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus icon" width="96" />

# Hermes Plus

**Fork of [Hermex](https://github.com/uzairansaruzi/hermex) — iOS client for [Hermes Agent](https://github.com/nesquena/hermes-webui).**

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)](https://apps.apple.com/app/hermex/id6767006319)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

[Website](https://hermexapp.com) · [Original Hermex](https://github.com/uzairansaruzi/hermex) · [Report a bug](https://github.com/braintimebox/hermex-plus/issues)

<img src="docs/assets/readme/hero-devices.png" alt="Hermes Plus running on iPhones" width="720" />

</div>

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex), a native SwiftUI iPhone app for driving a self-hosted [hermes-webui](https://github.com/nesquena/hermes-webui) server — a mobile cockpit for an AI agent that lives on a machine **you** control.

- **Free.** No subscriptions, no in-app purchases.
- **Private.** No analytics, no tracking, no third-party relay — the app talks only to your server.
- **Native.** Real SwiftUI, built for iOS 18+, not a web wrapper.

## Differences from original Hermex

1. **App name** — "Hermes Plus" on the home screen and in the header
2. **No swipe gestures** — pin, archive, and delete via long-press context menu only
3. **Unsigned IPA** — pre-built artifact available in [Actions](https://github.com/braintimebox/hermex-plus/actions) for AltStore/SideStore

## Features

- **Chat with your agent** — send messages with model, reasoning-effort, workspace, and profile options; attach files and images; watch responses stream in real time.
- **Sessions** — browse, search, and resume every conversation.
- **Pick your models** — switch between any model or provider, with recents and favorites.
- **Profiles & projects** — switch agent profiles and organize sessions into projects.
- **Tasks** — view and edit scheduled cron jobs.
- **Skills** — browse the agent's installed skills.
- **Workspace browser** — explore your server's file system.
- **Memory & Insights** — read-only panels for agent memory and analytics.

## Getting started

1. **Run the server.** Install `hermes-webui` on macOS, Linux, or Windows/WSL2. Set `HERMES_WEBUI_PASSWORD`.
2. **Make it reachable.** HTTPS via reverse proxy or tunnel (recommended), or Tailscale (`100.64.0.0/10`).
3. **Connect.** Enter server URL and password.

## Installation

**Pre-built IPA:** Download from [Actions → Artifacts](https://github.com/braintimebox/hermex-plus/actions) → install via AltStore or SideStore.

**App Store:** Use the [original Hermex](https://apps.apple.com/app/hermex/id6767006319) — Hermes Plus is not on the App Store.

## Building from source

Requires Xcode 26+ (iOS 18 SDK). The CI uses `macos-26`.

Unsigned build:
```zsh
xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Package unsigned IPA:
```zsh
APP=$(find DerivedData -name "*.app" -path "*/Release-iphoneos/*" -type d | head -1)
mkdir Payload && cp -R "$APP" Payload/ && zip -r HermesPlus.ipa Payload
```

## Credits

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex) by [@uzairansar](https://x.com/uzairansar). All credit for the original app goes to Uzair.

## License

MIT — see [LICENSE](LICENSE).
