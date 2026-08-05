<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus app icon" width="96" />

# Hermes Plus

**A fork of [Hermex](https://github.com/uzairansaruzi/hermex) — native iOS client for [Hermes Agent](https://github.com/nesquena/hermes-webui).**

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)](https://apps.apple.com/app/hermex/id6767006319)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

[Website](https://hermexapp.com) · [Original Hermex](https://github.com/uzairansaruzi/hermex) · [Report a bug](https://github.com/braintimebox/hermex-plus/issues)

<img src="docs/assets/readme/hero-devices.png" alt="Hermex running on two iPhones: a streaming chat session and the home screen with Tasks, Skills, Memory, Insights, and Sessions" width="720" />

</div>

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex), a native SwiftUI iPhone app for driving a self-hosted [hermes-webui](https://github.com/nesquena/hermes-webui) server — a mobile cockpit for an AI agent that lives on a machine **you** control. The phone is the control plane, not the compute plane: the agent, its tools, and your data stay on your own hardware.

- **Free.** No subscriptions, no in-app purchases.
- **Private.** No analytics, no tracking, no third-party relay — the app talks only to your server.
- **Native.** Real SwiftUI, built for iOS 18+, not a web wrapper.

---

## 🔀 What's different from upstream Hermex

> Every Hermes Plus release starts as a snapshot of `uzairansaruzi/hermex:master` with these surgical changes applied:

| # | Change | File(s) | Why |
|---|--------|---------|-----|
| 1 | **App name** — "Hermes Plus" on home screen and header | `project.pbxproj` (`APP_DISPLAY_NAME`), `SessionListView.swift` (`HermesHeaderLogo`) | Branding |
| 2 | **No swipe actions** — pin/archive/delete via long-press context menu only | `SessionListComponents.swift` | Prevents accidental swipe triggers |
| 3 | **Unsigned IPA build pipeline** — GitHub Actions workflow producing downloadable `.ipa` | `.github/workflows/build-ipa.yml` | Allows installation via AltStore/SideStore without a Mac |

**Everything else** — server API, features, settings, onboarding, model selection, profiles, tasks, skills, workspace browser, memory, insights — is identical to upstream Hermex.

---

## Getting the IPA (no Mac required)

1. Go to [Actions](https://github.com/braintimebox/hermex-plus/actions)
2. Click the latest **Build Hermes Plus** run with ✅
3. Download `HermesPlus-unsigned.zip` from Artifacts
4. Extract → install `.ipa` via [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)

---

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

---

## Getting started

Hermes Plus is a client only — it does not ship with, host, or provision a backend. You bring your own [hermes-webui](https://github.com/nesquena/hermes-webui) server (a third-party, MIT-licensed open-source project) running on a machine you control.

1. **Run the server.** Install and start `hermes-webui` on macOS, Linux, or Windows/WSL2 (Python 3.11+). Set `HERMES_WEBUI_PASSWORD`.
2. **Make it reachable from your phone.** HTTPS via Cloudflare Tunnel or reverse proxy (recommended), or Tailscale (`100.64.0.0/10`).
3. **Connect.** Open Hermes Plus, enter your server URL (e.g. `https://hermes.yourdomain.com`) and password.

---

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

---

## Credits

Hermes Plus is a fork of [Hermex](https://github.com/uzairansaruzi/hermex) by [@uzairansar](https://x.com/uzairansar). All credit for the original app — design, architecture, and App Store presence — belongs to Uzair.

---

## License

MIT — see [LICENSE](LICENSE).

Hermex and Hermes Plus are independent clients and are not affiliated with the upstream [hermes-webui](https://github.com/nesquena/hermes-webui) project. Apple, the Apple logo, and App Store are trademarks of Apple Inc.
