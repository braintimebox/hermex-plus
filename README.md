<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus app icon" width="96" />

# Hermes Plus

**A fork of [Hermex](https://github.com/uzairansaruzi/hermex). Control your self-hosted [Hermes](https://github.com/nesquena/hermes-webui) agent from your iPhone.**

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)](https://apps.apple.com/app/hermex/id6767006319)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)
[![Follow on X](https://img.shields.io/badge/Follow-%40uzairansar-000000?logo=x&logoColor=white)](https://x.com/uzairansar)

[Original Hermex](https://github.com/uzairansaruzi/hermex) · [Download IPA](https://github.com/braintimebox/hermex-plus/actions) · [Report a bug](https://github.com/braintimebox/hermex-plus/issues)

<img src="docs/assets/readme/hero-devices.png" alt="Hermex running on two iPhones: a streaming chat session and the home screen with Tasks, Skills, Memory, Insights, and Sessions" width="720" />

</div>

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex), a native SwiftUI iPhone app for driving a self-hosted [hermes-webui](https://github.com/nesquena/hermes-webui) server — a mobile cockpit for an AI agent that lives on a machine **you** control. Every Hermes Plus release starts as a snapshot of upstream Hermex with surgical changes applied.

- **Free.** No subscriptions, no in-app purchases.
- **Private.** No analytics, no tracking, no third-party relay — the app talks only to your server.
- **Native.** Real SwiftUI, built for iOS 18+, not a web wrapper.
- **Sideload-friendly.** Pre-built unsigned IPA available for [AltStore](https://altstore.io) and [SideStore](https://sidestore.io).

---

### ⚡ This fork changes three things. Nothing else.

|  | Hermex | Hermes Plus |
|--|--------|-------------|
| Swipe gestures | ✅ | ❌ Long-press only |
| App Store | ✅ | ❌ Unsigned IPA via Actions |
| Header logo | Hermex | **Hermes Plus** |
| Features | ✅ All | ✅ All (identical) |
| Server API | ✅ Same | ✅ Same |

## Features

- **Chat with your agent** — send messages with model, reasoning-effort, workspace, and profile options; attach files and images; watch responses stream in real time with thinking and tool-call detail.
- **Steer or stop a run** mid-flight.
- **Sessions** — browse, search, and resume every conversation on your server; cached sessions stay readable offline.
- **Pick your models** — switch between any model or provider your server is configured for, with recents and favorites.
- **Profiles & projects** — switch agent profiles and organize sessions into projects.
- **Tasks** — view and edit your agent's scheduled cron jobs from your phone.
- **Skills** — browse and search the agent's installed skills.
- **Workspace browser** — explore your server's file system from the app.
- **Memory & Insights** — read-only panels for agent memory and usage analytics.

<div align="center">
<table>
  <tr>
    <td align="center"><img src="docs/assets/readme/screenshot-chat.png" alt="Streaming chat with code blocks and markdown tables" width="240" /><br /><sub><b>Stream responses in real time</b></sub></td>
    <td align="center"><img src="docs/assets/readme/screenshot-tasks.png" alt="Tasks screen listing scheduled cron jobs" width="240" /><br /><sub><b>Manage scheduled tasks</b></sub></td>
    <td align="center"><img src="docs/assets/readme/screenshot-skills.png" alt="Skills screen with searchable agent skills" width="240" /><br /><sub><b>Browse agent skills</b></sub></td>
  </tr>
</table>

More screenshots at [hermexapp.com](https://hermexapp.com).
</div>

## Getting started

Hermes Plus is a client only — you bring your own [hermes-webui](https://github.com/nesquena/hermes-webui) server.

1. **Run the server.** Install and start `hermes-webui` on macOS, Linux, or Windows/WSL2 (Python 3.11+). Set `HERMES_WEBUI_PASSWORD`.
2. **Make it reachable.** HTTPS via reverse proxy or tunnel (recommended), or Tailscale (`100.64.0.0/10`).
3. **Connect.** Open Hermes Plus, enter your server URL and password.

## Installation

**SideStore / AltStore:** Download the latest `HermesPlus-unsigned.ipa` from [Actions → Artifacts](https://github.com/braintimebox/hermex-plus/actions).

**App Store:** Not available. Use the [original Hermex](https://apps.apple.com/app/hermex/id6767006319) if you prefer the App Store.

## Building from source

Requires Xcode 26+ (iOS 18 SDK). The CI workflow ([`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)) runs on `macos-26`.

Unsigned build:

```zsh
xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Package IPA:

```zsh
APP=$(find DerivedData -name "*.app" -path "*/Release-iphoneos/*" -type d | head -1)
mkdir Payload && cp -R "$APP" Payload/ && zip -r HermesPlus.ipa Payload
```

## Server compatibility

The app is developed and tested against the `hermes-webui` commit pinned in [`UPSTREAM_TESTED_SHA`](UPSTREAM_TESTED_SHA). Newer or older server versions may break individual features — include your server version in bug reports.

## Contributing

Hermes Plus tracks upstream Hermex. Before contributing:

- Check if the change belongs upstream ([uzairansaruzi/hermex](https://github.com/uzairansaruzi/hermex)) — most features should go there.
- Fork-specific changes (UX tweaks, build pipeline) are welcome here.
- See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md).

## Credits

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex) by [@uzairansar](https://x.com/uzairansar). All credit for the original design, architecture, and App Store presence belongs to Uzair.

## License

MIT — see [LICENSE](LICENSE).

Hermes Plus is an independent fork and is not affiliated with the upstream [hermes-webui](https://github.com/nesquena/hermes-webui) project. Apple, the Apple logo, and App Store are trademarks of Apple Inc.
