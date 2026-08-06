#!/usr/bin/env python3
"""Health data: JSON → MD converter + auto-assessment + log.md append.

Bundled with Hermes Plus Data Channels. Works with any Hermes Agent server.

Usage:
    python3 convert.py < input.json      # JSON → MD + assess
    python3 convert.py --md < input.md   # MD passthrough
    python3 convert.py --assess 2026-07-14  # Re-assess existing day

Configuration (environment variables):
    HERMES_HEALTH_LOG  — accumulative log path (default: ~/.hermes/health/log.md)
    HERMES_HEALTH_RAW  — raw JSON storage dir (default: ~/.hermes/health/)
"""

import sys
import json
import os
import re
from datetime import datetime
from pathlib import Path

# ── Config (env vars with defaults) ────────────────────────────

LOG_PATH = Path(os.environ.get(
    "HERMES_HEALTH_LOG",
    os.path.expanduser("~/.hermes/health/log.md")
))
RAW_DIR = Path(os.environ.get(
    "HERMES_HEALTH_RAW",
    os.path.expanduser("~/.hermes/health")
))

# ── Metric labels ──────────────────────────────────────────────

METRIC_LABELS = {
    "weight_kg": ("Weight", "kg"),
    "bmi": ("BMI", ""),
    "body_fat_pct": ("Body fat", "%"),
    "lean_body_mass_kg": ("Lean mass", "kg"),
    "steps": ("Steps", ""),
    "active_calories": ("Active energy", "kcal"),
    "active_energy": ("Active energy", "kcal"),
    "exercise_minutes": ("Exercise", "min"),
    "stand_minutes": ("Stand", "min"),
    "flights_climbed": ("Flights", ""),
    "distance_walk_run_km": ("Walk+run", "km"),
    "sleep_hours": ("Sleep", "h"),
    "heart_rate_resting": ("HR resting", "bpm"),
    "heart_rate_walking": ("HR walking", "bpm"),
    "heart_rate_avg": ("HR avg", "bpm"),
    "hrv_rmssd": ("HRV RMSSD", "ms"),
    "hrv_sdnn": ("HRV SDNN", "ms"),
    "heart_rate_recovery_1min": ("HR recovery", "bpm"),
    "spo2_pct": ("SpO₂", "%"),
    "respiratory_rate": ("Respiratory", "breaths/min"),
    "vo2max": ("VO₂Max", "mL/kg/min"),
    "blood_pressure_systolic": ("BP systolic", "mmHg"),
    "blood_pressure_diastolic": ("BP diastolic", "mmHg"),
    "body_temperature_c": ("Temperature", "°C"),
    "blood_glucose_mmol": ("Glucose", "mmol/L"),
    "walking_speed_ms": ("Walk speed", "m/s"),
    "walking_step_length_cm": ("Step length", "cm"),
    "walking_asymmetry_pct": ("Walk asymmetry", "%"),
    "walking_double_support_pct": ("Double support", "%"),
    "stair_ascent_speed_ms": ("Stair ascent", "m/s"),
    "stair_descent_speed_ms": ("Stair descent", "m/s"),
    "time_in_daylight_min": ("Daylight", "min"),
    "dietary_energy_kcal": ("Food energy", "kcal"),
    "dietary_protein_g": ("Protein", "g"),
    "dietary_carbs_g": ("Carbs", "g"),
    "dietary_fat_g": ("Fat", "g"),
    "dietary_fiber_g": ("Fiber", "g"),
    "dietary_water_ml": ("Water", "mL"),
    "headphone_audio_db": ("Headphone level", "dB"),
    "env_audio_db": ("Env noise", "dB"),
    "uv_index": ("UV index", ""),
    "wrist_temperature_c": ("Wrist temp", "°C"),
    # Cognitive (manual or auto)
    "focus": ("Focus", "/10"),
    "focus_auto": ("Focus (auto)", "/10"),
    "energy": ("Energy", "/10"),
    "mood": ("Mood", "/10"),
    "stress": ("Stress", "/10"),
    "brain_fog": ("Brain fog", ""),
    "deep_work_h": ("Deep work", "h"),
    # Intake
    "caffeine_mg": ("Caffeine", "mg"),
    "alcohol_units": ("Alcohol", "units"),
}

SUPPLEMENT_LABELS = {
    "vitamin_d3_iu": "D3",
    "vitamin_d3_mcg": "D3",
    "magnesium_mg": "Mg",
    "zinc_mg": "Zn",
    "omega3_mg": "Omega-3",
    "vitamin_c_mg": "Vit C",
    "vitamin_b12_mcg": "B12",
    "iron_mg": "Fe",
    "melatonin_mg": "Melatonin",
}

# ── Auto-assessment ─────────────────────────────────────────────

def assess_focus(metrics: dict, supplements: dict) -> dict:
    """Derive Focus/10 from available biometrics."""
    score = 5.0
    reasons = []
    present = 0

    # Sleep
    sleep = metrics.get("sleep_hours")
    if sleep is not None:
        present += 1
        if sleep >= 8:
            score += 2
            reasons.append(f"Sleep {sleep}h → +2")
        elif sleep >= 7:
            score += 1.5
            reasons.append(f"Sleep {sleep}h → +1.5")
        elif sleep >= 6:
            reasons.append(f"Sleep {sleep}h → 0 (baseline)")
        elif sleep >= 5:
            score -= 1.5
            reasons.append(f"Sleep {sleep}h → −1.5")
        else:
            score -= 2.5
            reasons.append(f"Sleep {sleep}h → −2.5")

    # HR resting
    hr = metrics.get("heart_rate_resting")
    if hr is not None:
        present += 1
        if hr < 55:
            score += 1.5
            reasons.append(f"HR {hr} bpm → +1.5")
        elif hr < 60:
            score += 1
            reasons.append(f"HR {hr} bpm → +1")
        elif hr < 65:
            score += 0.5
            reasons.append(f"HR {hr} bpm → +0.5")
        elif hr < 75:
            reasons.append(f"HR {hr} bpm → 0 (normal)")
        else:
            score -= 1.5
            reasons.append(f"HR {hr} bpm → −1.5")

    # HRV
    hrv = metrics.get("hrv_rmssd")
    if hrv is not None:
        present += 1
        if hrv >= 50:
            score += 2
            reasons.append(f"HRV {hrv}ms → +2")
        elif hrv >= 35:
            score += 1
            reasons.append(f"HRV {hrv}ms → +1")
        elif hrv >= 25:
            reasons.append(f"HRV {hrv}ms → 0 (normal)")
        elif hrv >= 15:
            score -= 1
            reasons.append(f"HRV {hrv}ms → −1")
        else:
            score -= 2
            reasons.append(f"HRV {hrv}ms → −2")

    # Steps
    steps = metrics.get("steps")
    if steps is not None:
        present += 1
        if steps >= 12000:
            score += 1
            reasons.append(f"Steps {steps} → +1")
        elif steps >= 5000:
            score += 0.5
            reasons.append(f"Steps {steps} → +0.5")
        else:
            score -= 0.5
            reasons.append(f"Steps {steps} → −0.5")

    # Supplements (no penalty if missing)
    if supplements:
        if any(k in supplements for k in ("vitamin_d3_iu", "vitamin_d3_mcg")):
            score += 0.5
            reasons.append("D3 → +0.5")
        if "magnesium_mg" in supplements:
            score += 0.5
            reasons.append("Mg → +0.5")

    score = max(1.0, min(10.0, round(score, 1)))

    if present >= 3:
        confidence, margin = "high", 1
    elif present >= 2:
        confidence, margin = "medium", 2
    else:
        confidence, margin = "low", 3

    all_keys = ["sleep_hours", "heart_rate_resting", "hrv_rmssd", "steps"]
    missing = [k for k in all_keys if k not in metrics or metrics.get(k) is None]

    return {
        "score": score,
        "confidence": confidence,
        "margin": margin,
        "reasons": reasons,
        "missing": missing,
        "present_count": present,
    }


def format_assessment(assess: dict) -> list[str]:
    lines = [
        f"- Focus (auto): {assess['score']}/10 ±{assess['margin']}",
        f"- Confidence: {assess['confidence']} ({assess['present_count']} metrics)",
    ]
    if assess["reasons"]:
        lines.append(f"- Breakdown: {' | '.join(assess['reasons'])}")
    if assess["missing"]:
        friendly = {
            "sleep_hours": "Sleep", "heart_rate_resting": "HR resting",
            "hrv_rmssd": "HRV", "steps": "Steps",
        }
        missing_str = ", ".join(str(friendly.get(m, m)) for m in assess["missing"])
        lines.append(f"- Missing: {missing_str}")
    return lines


# ── Conversion ──────────────────────────────────────────────────

def json_to_md(data: dict) -> tuple[str, str]:
    date_str = data.get("date", datetime.now().strftime("%Y-%m-%d"))
    source = data.get("source", "")
    metrics = data.get("metrics", {})

    lines = [f"## {date_str}"]
    if source:
        lines.append(f"- Source: {source}")

    # Known metrics in order
    for key, (label, unit) in METRIC_LABELS.items():
        if key == "focus_auto":
            continue
        if key in metrics and metrics[key] is not None:
            val = metrics[key]
            if isinstance(val, float):
                val = f"{val:.1f}"
            unit_str = f" {unit}" if unit else ""
            lines.append(f"- {label}: {val}{unit_str}")

    # Supplements
    supplements = metrics.get("supplements", {})
    if supplements:
        parts = []
        for key, short in SUPPLEMENT_LABELS.items():
            if key in supplements and supplements[key] is not None:
                parts.append(f"{short} {supplements[key]}")
        if parts:
            lines.append(f"- Supplements: {', '.join(parts)}")

    # Unknown metrics (pass through)
    known = set(METRIC_LABELS) | {"supplements"}
    for key, val in metrics.items():
        if key not in known and val is not None:
            lines.append(f"- {key}: {val}")

    # Auto-assess if user didn't manually set focus
    if "focus" not in metrics:
        assess = assess_focus(metrics, supplements)
        lines.append("")
        lines.extend(format_assessment(assess))

    lines.append("")
    return date_str, "\n".join(lines)


def md_passthrough(text: str) -> tuple[str, str]:
    m = re.search(r"##\s*(\d{4}-\d{2}-\d{2})", text)
    date_str = m.group(1) if m else datetime.now().strftime("%Y-%m-%d")
    return date_str, text.strip() + "\n\n"


# ── Log management ──────────────────────────────────────────────

def append_to_log(date_str: str, entry: str):
    if not LOG_PATH.exists():
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOG_PATH.write_text("# Health Log\n\n> Auto-generated by focus-tracker.\n\n")

    content = LOG_PATH.read_text()
    pattern = rf"(## {re.escape(date_str)}.*?)(?=\n## |\Z)"

    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern, entry.strip(), content, flags=re.DOTALL)
    else:
        content = content.rstrip() + "\n\n" + entry

    LOG_PATH.write_text(content)


def re_assess(date_str: str):
    content = LOG_PATH.read_text()
    pattern = rf"## {re.escape(date_str)}\n(.*?)(?=\n## |\Z)"
    m = re.search(pattern, content, re.DOTALL)
    if not m:
        print(f"Date {date_str} not found in log.md", file=sys.stderr)
        return

    section = m.group(1)
    metrics = {}
    supplements = {}

    for line in section.split("\n"):
        if any(line.startswith(p) for p in (
            "- Focus (auto):", "- Confidence:", "- Breakdown:", "- Missing:", "- Focus:"
        )):
            continue

        if line.startswith("- Supplements:"):
            supp_str = line.replace("- Supplements:", "").strip()
            for part in supp_str.split(","):
                part = part.strip()
                for key, short in SUPPLEMENT_LABELS.items():
                    if part.startswith(short + " "):
                        try:
                            supplements[key] = float(part.split()[-1])
                        except ValueError:
                            supplements[key] = part.split()[-1]
            continue

        for key, (label, _) in METRIC_LABELS.items():
            if key == "focus_auto":
                continue
            if line.strip().startswith(f"- {label}:"):
                val_str = line.split(":", 1)[1].strip()
                num_match = re.match(r"([\d.]+)", val_str)
                if num_match:
                    try:
                        metrics[key] = float(num_match.group(1))
                    except ValueError:
                        metrics[key] = val_str
                else:
                    metrics[key] = val_str
                break

    assess = assess_focus(metrics, supplements)

    original_lines = []
    for line in section.split("\n"):
        if any(line.startswith(p) for p in (
            "- Focus (auto):", "- Confidence:", "- Breakdown:", "- Missing:"
        )):
            continue
        original_lines.append(line)
    while original_lines and not original_lines[-1].strip():
        original_lines.pop()

    new_section = "\n".join(original_lines) + "\n\n" + "\n".join(format_assessment(assess)) + "\n"
    content = content.replace(m.group(0), f"## {date_str}\n{new_section}")
    LOG_PATH.write_text(content)

    print(f"Re-assessed {date_str}: Focus {assess['score']}/10 ({assess['confidence']})", file=sys.stderr)
    print(f"## {date_str}\n{new_section}")


# ── Main ────────────────────────────────────────────────────────

def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    if len(sys.argv) > 1 and sys.argv[1] == "--assess":
        re_assess(sys.argv[2])
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--md":
        text = sys.stdin.read()
        date_str, entry = md_passthrough(text)
    else:
        text = sys.stdin.read()
        data = json.loads(text)
        date_str, entry = json_to_md(data)

        json_path = RAW_DIR / f"{date_str}.json"
        json_path.write_text(text)
        print(f"Saved: {json_path}", file=sys.stderr)

    append_to_log(date_str, entry)
    print(f"Log updated: {date_str}", file=sys.stderr)
    print(entry)


if __name__ == "__main__":
    main()
