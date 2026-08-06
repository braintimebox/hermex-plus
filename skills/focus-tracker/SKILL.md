---
name: focus-tracker
description: >
  Health data pipeline for Hermes Agent. Ingest Apple Health data from Hermes Plus
  (JSON via [TRACKER] prefix), auto-assess Focus/Energy score, append to log.md.
  Also accepts manual MD and A4 tracker photos.
  Bundled with Hermes Plus — copy this directory to your Hermes Agent's skills/ folder.
---

# Focus Tracker — Health Data Pipeline

## Quick Setup

```bash
# 1. Copy this skill to your Hermes Agent
cp -r skills/focus-tracker ~/.hermes/skills/

# 2. Set your vault path (or accept default)
export HERMES_HEALTH_LOG=~/.hermes/_projects/Obsidian/raw/health/log.md
export HERMES_HEALTH_RAW=~/.hermes/_projects/Obsidian/raw/health

# 3. That's it. Hermes Plus will auto-sync.
```

## Architecture

```
Hermes Plus (iPhone)
  └─ Apple Health → [TRACKER] + JSON
         │
         ▼
Hermes Agent receives message
  └─ focus-tracker skill triggered by [TRACKER]
         │
         ▼
convert.py
  ├─ Save raw JSON (audit trail)
  ├─ Format metrics → MD
  ├─ Auto-assess Focus/Energy (from steps/sleep/HR/HRV)
  └─ Append to log.md (dedup by date)
```

## Ingestion Paths

### Path 0: Data Channels — Hermes Plus Apple Health (automatic)

Agent receives a message starting with `[TRACKER]` containing JSON:

```json
{
  "date": "2026-08-06",
  "source": "Apple Health (Hermes Plus)",
  "metrics": {
    "steps": 8432,
    "sleep_hours": 7.2,
    "heart_rate_resting": 58,
    "hrv_rmssd": 77.9,
    ...
  }
}
```

Agent MUST:
1. Extract JSON after `[TRACKER]`
2. Save as `raw/health/YYYY-MM-DD.json`
3. Pipe to convert.py: `echo '<json>' | python3 convert.py`
4. Report: "Health data ingested. Focus: X/10 (confidence: high/medium/low)"

### Path 1: Manual JSON / Health.md webhook

```bash
python3 convert.py < input.json
```

### Path 2: Markdown passthrough

```bash
python3 convert.py --md < input.md
```

Appends as-is. No auto-assessment (MD is assumed human-curated).

### Path 3: Photo of A4 tracker (vision)

Send photo + keyword «трекер». Agent reads focus/energy/sleep/supplements from the image.

## Auto-Assessment

convert.py derives Focus/10 from available biometrics:

| Metric | Range | Effect |
|--------|-------|--------|
| Sleep | 5 levels | −2.5 to +2.0 |
| HR resting | 6 levels | −1.5 to +1.5 |
| HRV RMSSD | 5 levels | −2.0 to +2.0 |
| Steps | 3 levels | −0.5 to +1.0 |
| D3 taken | boolean | +0.5 |
| Mg taken | boolean | +0.5 |

Baseline: 5.0. Clamped to [1.0, 10.0].

### Missing data

- Missing supplement ≠ missed dose. Don't subtract.
- Missing biometric → doesn't participate. Confidence drops, not score.
- Empty day → skip entirely. Never interpolate.

### Confidence

| Metrics present | Confidence | Margin |
|-----------------|-----------|--------|
| 4+ | high | ±1 |
| 2–3 | medium | ±2 |
| 0–1 | low | ±3 |

## Configuration

All paths are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_HEALTH_LOG` | `~/.hermes/health/log.md` | Accumulative log file |
| `HERMES_HEALTH_RAW` | `~/.hermes/health/` | Raw JSON storage |

## Scoring override

If `focus` is present in the JSON payload, auto-assessment is skipped.
Human > algorithm.
