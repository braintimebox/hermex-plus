<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus icon" width="96" />

# Hermes Plus v1.4.4 (on Hermex v1.5)

**Native iPhone client for self-hosted Hermes Agent.** Forked from [Hermex](https://github.com/uzairansaruzi/hermex) v1.5.

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)]()
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

</div>

## 🔗 Download

**Latest IPA (direct):** https://github.com/braintimebox/hermex-plus/actions — click the latest green build → scroll to Artifacts → download `HermesPlus-unsigned`

**Current build (v1.4.3, 2026-08-12):** https://github.com/braintimebox/hermex-plus/actions/runs/31632087255/artifacts/9155629650

Then install with SideStore / AltStore → connect to your Hermes server.

## 🚀 Features (what we added on top of Hermex v1.5)

| Feature | Description |
|---------|-------------|
| **Reply** | Long-press → Reply with quote banner |
| **Forward** | Long-press → Forward to any session |
| **Saved Messages** | Bookmark, reorder, jump back to chat |
| **Scheduled Messages** | Long-press Send → pick date/time. Clock badge on Send |
| **Chat long-press** | Hold "Chat" button → Schedule message |
| **Share** | Message context menu → Share (system sheet) |
| **Background refresh** | BGTaskScheduler every 4h. ~0.5% battery/day |
| **Config cache** | 24h memory cache — 0 network on repeat visits |
| **Performance** | `async let` parallel loading. No type-check timeouts |
| **No swipes** | Pin/archive/delete via long-press menu only |

## 🔧 Key differences from upstream

- App name: "Hermes Plus"
- No swipe actions — contextMenu only
- Reply, Forward, Save, Schedule, Share — all via contextMenu
- Saved messages with drag-to-reorder + chat navigation
- Scheduled messages with count badge + Tasks integration
- Share sheet → choose destination
- BGTaskScheduler background refresh
- Settings → Main Page → Saved toggle
- Unsigned IPA CI

## 🤝 Credits

- [Hermex](https://github.com/uzairansaruzi/hermex) v1.5 by Uzair Ansar — the base
- [Hermes Agent](https://github.com/nesquena/hermes-webui) — the server

## 📄 License

MIT — same as upstream.
