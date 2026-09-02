## 3.5.4 — UX: hide FAB and scroll-to-bottom during clarification prompts

### Fixed — compose FAB and clarification card overlapping in the bottom-right corner

- **Problem:** when a clarification prompt (A/B/C/D) appeared, the compose FAB button (48×48 circle) and the clarification card overlapped in the bottom-right corner. The scroll-to-bottom button also competed for the same space. Both buttons were positioned at `.bottomTrailing` without accounting for the clarification card's presence.
- **Fix:** (1) FAB now hides when `clarificationPrompt != nil` — no more button-on-card overlap. (2) `onChange(of: clarificationPrompt?.id)` auto-hides the composer when clarification appears, preventing the text input from occupying space below the card. (3) Scroll-to-bottom button already lifted via `clarificationCardHeight` padding — no additional change needed.
- **Effect:** clarification prompts render cleanly without button overlap. Composer returns after clarification is dismissed.

## 3.5.3 — Silent Streaming: 90% fewer per-token UI updates
