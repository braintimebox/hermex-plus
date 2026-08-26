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

**Current build (direct IPA):** https://github.com/braintimebox/hermex-plus/actions/runs/33005216650/artifacts/9620437180

**All builds:** https://github.com/braintimebox/hermex-plus/actions — pick a green build → Artifacts → `HermexPlus-unsigned`

Then install with SideStore / AltStore → connect to your Hermes server.

## 🚀 Features (what we added on top of Hermex)

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

## 📄 License

MIT — same as upstream.
