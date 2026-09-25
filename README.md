<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermex Plus icon" width="96" />

# Hermex Plus

**Native iPhone client for self-hosted Hermes Agent.** Forked from [Hermex](https://github.com/uzairansaruzi/hermex).

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)]()
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

</div>

## 🔗 Download

**Latest release (direct IPA):** https://github.com/braintimebox/hermex-plus/releases/latest

**All builds:** https://github.com/braintimebox/hermex-plus/actions — pick a green build → Artifacts

Then install with SideStore / AltStore → connect to your Hermes server.

> The link above is stable: every release publishes its IPA as a GitHub Release, so
> `/releases/latest` always points at the newest installable build. Per-run artifact
> links expire after 30 days and are deliberately not used here.

## 🚀 Features (what we added on top of Hermex)

| Feature | Description |
|---------|-------------|
| **Reply** | Long-press → Reply with quote banner |
| **Forward** | Long-press → Forward to any session |
| **Save (сохранённые)** | Bookmark, reorder, jump back to chat |
| **Scheduled Messages** | Long-press Send → pick date/time. Clock badge on Send |
| **Chat long-press** | Hold "Chat" button → Schedule message |
| **Share** | Message context menu → Share (system sheet) |
| **Clarification** | The agent's questions render as an inline card and are answered without leaving the chat |
| **Tasks** | Create, run, schedule and delete tasks against the server's task API |
| **Skills: Personal / Built-in** | The Skills screen splits what you wrote from what ships built in |
| **Skills: Plugins / Hooks** | Plugins and hooks listed with their live data |
| **Skills: breadcrumb** | Origin breadcrumb in the navigation bar |
| **Skills: поиск / фильтр, вкл-выкл** | Search, filter and per-skill enable switch |
| **Skills: `origin`** | The server's `origin` field drives the grouping, not a client-side guess |
| **Fade при печати** | Words fade in as a response streams (Settings → Streamed Text Animation) |
| **Плавная печать (drain)** | Streaming text advances at a readable rate instead of jumping one token at a time |
| **Ссылки-превью** | Links in the transcript resolve to a preview |
| **Медиа в транскрипте** | Images and files render inline in the transcript |
| **Модели** | Saved and scheduled messages persist on device (SwiftData) |
| **Логирование** | Jank, scroll ownership, composer height and network timings go to `~/.hermes/hermex-logs.jsonl` |
| **Детектор зависаний** | Real frame times via `CADisplayLink`; sustained jank is reported rather than felt |
| **Background refresh** | BGTaskScheduler every 4h. ~0.5% battery/day |
| **Config cache** | 24h memory cache — 0 network on repeat visits |
| **Performance** | `async let` parallel loading. No type-check timeouts |
| **No swipes** | Pin/archive/delete via long-press menu only |

> Every row above is checked by `scripts/pipeline-precheck.py` gate 15 against
> `docs/agents/fork-inventory.md`, so a feature cannot quietly disappear from
> this table (or from the app) without failing the pre-push gate.

## 🔧 Key differences from upstream

- App name: "Hermex Plus"
- No swipe actions — contextMenu only
- Reply, Forward, Save, Schedule, Share — all via contextMenu
- Saved messages with drag-to-reorder + chat navigation
- Scheduled messages with count badge + Tasks integration
- Share sheet → choose destination
- BGTaskScheduler background refresh
- Settings → Main Page → Saved toggle
- Unsigned IPA CI

## 🤝 Credits

- [Hermex](https://github.com/uzairansaruzi/hermex) by Uzair Ansar — the base
- [Hermes Agent](https://github.com/nesquena/hermes-webui) — the server

- **HTTPS via a tunnel or reverse proxy (recommended).** Expose the server through Cloudflare Tunnel or any reverse proxy that terminates real TLS at a hostname you own. Real HTTPS keeps iOS App Transport Security happy with no exceptions. On a publicly reachable hostname the password is your only app-level defense — set a strong one.
- **Private HTTPS with Tailscale Serve.** Keep the server password-protected and bound to `127.0.0.1:8787`, inspect existing Serve/Funnel routes, then add `tailscale serve --bg 8787` only when HTTPS port 443 at the root path is free. Install Tailscale on the iPhone and connect with the exact `https://…ts.net` URL reported by `tailscale serve status`. Direct binding to `0.0.0.0` over plain HTTP remains a manual fallback, not the default.
- **Simulator-only local testing** can use `http://localhost:8787` when the server runs on the same Mac.

### Troubleshooting the connection

If connection testing fails, check these first:

1. The machine hosting `hermes-webui` is awake.
2. `hermes-webui` is running and serving `/health` (`curl https://<your-server>/health`).
3. The tunnel, reverse proxy, or Tailscale route is connected.
4. The server URL and password are correct.

## Building from source

Prefer the [App Store build](https://apps.apple.com/app/hermex/id6767006319) unless you're developing. To build yourself you need Xcode 26 or newer (iOS 18 SDK) and an iPhone or simulator on iOS 18+.

Clone the repo, open `HermesMobile.xcodeproj`, and run the `HermesMobile` scheme on an iPhone simulator (the Xcode target is `HermesMobile`; the app's display name is `Hermex`). Dependencies are resolved automatically via Swift Package Manager.

From the command line:

```zsh
xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```zsh
xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17'
```

If that simulator is not installed, list available devices and choose a nearby iPhone simulator:

```zsh
xcrun simctl list devices available
```

Local validation defaults for XcodeBuildMCP users live in `.xcodebuildmcp/config.yaml`; the standard post-change flow is in [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Server compatibility

The app is developed and tested against the `hermes-webui` commit pinned in [`UPSTREAM_TESTED_SHA`](UPSTREAM_TESTED_SHA). Upstream does not yet guarantee API stability (its README declares version skew unsupported pending their stable-API work), so newer or older server versions may break individual features — please include your server version in bug reports. The app decodes tolerantly (unknown fields never crash it) and endpoint shapes are verified against upstream source, never invented.

Bot Mode's direct-Hermes connection has its own pin, [`HERMES_AGENT_TESTED_SHA`](HERMES_AGENT_TESTED_SHA): line 1 is the tested `hermes-agent` commit and line 2 the release string its `/api/status` reports. When a host reports a different release, the Bot connection screen shows a one-line "Untested Hermes version" note. It never blocks signing in.

## Documentation map

- [`AGENTS.md`](AGENTS.md): the working agreement — product boundaries, server-contract rules, locked dependencies, verification, and PR flow.
- [`DEVELOPMENT.md`](DEVELOPMENT.md): local development workflow, server setup notes, and the maintainer release runbook.
- [`TESTFLIGHT.md`](TESTFLIGHT.md): maintainer-only TestFlight/App Store Connect operations.
- [`SECURITY.md`](SECURITY.md): how to report a vulnerability.
- [`docs/agents/`](docs/agents): repo-local agent workflow conventions (issues, triage labels, domain notes).
- [GitHub Issues](https://github.com/uzairansaruzi/hermex/issues): source of truth for active bugs, polish notes, and feature requests.

## Contributing

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to pick up work and open a PR, [`AGENTS.md`](AGENTS.md) for the working agreement coding agents follow in this repo, and the [Code of Conduct](CODE_OF_CONDUCT.md). The short version:

- Do not invent API endpoints or JSON shapes; verify against the upstream server source or a running server.
- Every `Codable` model decodes tolerantly — never crash on unknown fields.
- Add no third-party dependencies beyond the locked list in `AGENTS.md` without explicit approval.
- Do not modify the upstream `hermes-webui` server from this repo.

## Support the project

Hermex is free and built in the open. If it's useful to you:

- ⭐ **Star this repo** — it helps others find the project.
- 🐦 **Follow [@uzairansar on X](https://x.com/uzairansar)** for updates and dev logs.
- ☕ **[Buy me a coffee](https://buymeacoffee.com/callmeuzi)** to support development.

<a href="https://buymeacoffee.com/callmeuzi"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-callmeuzi-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee" height="40" /></a>

## License

MIT — see [LICENSE](LICENSE).

The file-type icons in the workspace tree are [Pierre](https://pierre.co)'s `@pierre/trees` icons (Apache-2.0) with six additions from [T3 Code](https://github.com/pingdotgg/t3code) (MIT).

Hermex is an independent client and is not affiliated with the upstream [hermes-webui](https://github.com/nesquena/hermes-webui) project. Apple, the Apple logo, and App Store are trademarks of Apple Inc.

## This fork

`braintimebox/hermex-plus` is a personal fork of Hermex that tracks it as **upstream**
for future updates. Licensing is unchanged (MIT, same as upstream). Releases here carry
`HermesPlus-<version>.ipa` builds produced by this fork's CI; the App Store build belongs
to upstream.
