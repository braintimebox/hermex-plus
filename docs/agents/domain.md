# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

This is a single-context repo: Hermex is one native iOS app with related app extension targets, tests, release docs, and one shared product vocabulary.

When present, use:

- `CONTEXT.md` at the repo root for domain vocabulary and project concepts.
- `docs/adr/` for architectural decision records.
- `docs/agents/testing.md` before writing or fixing a test — it records the
  failure modes this suite has actually produced (asserting `async let` order,
  reading a cache right after an async write, a wait helper that times out
  silently). Each entry names the commit that fixed it.
- `docs/agents/upstream-sync-plan.md` before starting an upstream sync — the
  conflict set, the resolution rule for each class of file, and the known traps.
  Run `python3 scripts/upstream-rehearse.py` first; the plan is written against
  its output.

There is currently no required `CONTEXT.md` or `docs/adr/` directory. If these files do not exist, proceed silently. Do not suggest creating them upfront; producer skills such as `grill-with-docs` can create them lazily when domain terms or decisions are clarified.

## Consumer Rules

Before making architecture, diagnosis, TDD, or issue-writing decisions, read the relevant domain docs if they exist.

When output names a domain concept in an issue title, refactor proposal, hypothesis, or test name, use the term as defined in `CONTEXT.md`. Do not drift to synonyms the glossary explicitly avoids.

If the concept you need is not in the glossary yet, either reconsider whether the repo already uses a different term or note the gap for a later documentation pass.

If your output contradicts an existing ADR, surface that conflict explicitly instead of silently overriding the decision.
