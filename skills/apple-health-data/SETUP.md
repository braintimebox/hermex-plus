# Setting up Focus Tracker

## For any Hermes Plus user

### 1. Copy the skill to your Hermes Agent server

```bash
cp -r skills/apple-health-data ~/.hermes/skills/
```

### 2. (Optional) Set your vault path

By default, health data is stored in `~/.hermes/health/log.md`.
To use a different location:

```bash
echo 'export HERMES_HEALTH_LOG=~/vault/health/log.md' >> ~/.bashrc
echo 'export HERMES_HEALTH_RAW=~/vault/health/' >> ~/.bashrc
```

### 3. Enable in Hermes Plus

Settings → Data Channels → Apple Health [ON] → grant permission → done.

Auto-sync runs every 1-4 hours when Hermes Plus is backgrounded.
First sync: tap "Sync Now".

### 4. Verify

Check your vault — data should appear in `log.md` with Focus/Energy scoring.

## How it works

```
Hermes Plus → Apple Health → BGTaskScheduler
  → POST /api/background → [TRACKER] + JSON
  → focus-tracker skill activated
  → convert.py: JSON → MD + scoring → log.md
```

## Customisation

Edit `convert.py` to:
- Change scoring weights (the `assess_focus` function)
- Add new metric labels (the `METRIC_LABELS` dict)
- Change supplement tracking (the `SUPPLEMENT_LABELS` dict)

## No Hermes Plus? Use directly

If you use Health.md or Health Auto Export to POST data, pipe JSON to convert.py:

```bash
python3 convert.py < health-data.json
```
