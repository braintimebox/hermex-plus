<div align="center">

<img src="docs/assets/readme/hermex-icon.png" alt="Hermes Plus icon" width="96" />

# Hermes Plus v2.0

**Native iPhone client for self-hosted Hermes Agent.** Forked from [Hermex](https://github.com/uzairansaruzi/hermex) v1.5.

Your server. Your iPhone. No middleman.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)]()
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

</div>

## 🚀 Why Hermes Plus v2.0

Upstream Hermex is excellent. Hermes Plus adds the power-user features that matter:

| Feature | Description |
|---------|-------------|
| **Reply** | Long-press any message → Reply with quote banner |
| **Forward** | Long-press → Forward to any session |
| **Saved Messages** | Bookmark messages, reorder them, jump back to chat |
| **Scheduled Messages** | Long-press Send → pick date/time. Clock badge on Send button |
| **Performance** | Parallel async loading — 33% faster composer load |
| **No swipes** | Pin/archive/delete via long-press menu only |

## 📦 Install

1. Download the latest IPA from [Actions](https://github.com/braintimebox/hermex-plus/actions)
2. Install via SideStore / AltStore
3. Connect to your Hermes server — done

## 🔧 Key differences from upstream (Hermex v1.5)

- App name: "Hermes Plus" — `APP_DISPLAY_NAME` in project settings
- No swipe actions — contextMenu only (Pin/Archive/Delete)
- Reply, Forward, Save, Schedule — all via contextMenu
- Saved messages with drag-to-reorder + chat navigation
- Scheduled messages with count badge + Tasks integration
- Share sheet → choose destination chat
- Unsigned IPA CI (`CODE_SIGNING_ALLOWED=NO`)
- Settings → Main Page → Saved toggle

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## 🤝 Credits

- [Hermex](https://github.com/uzairansaruzi/hermex) v1.5 by Uzair Ansar — the base
- [Hermes Agent](https://github.com/nesquena/hermes-webui) — the server

## 📄 License

MIT — same as upstream.
