#!/usr/bin/env python3
"""Hermex Plus freeze watchdog — no_agent mode.

Reads ~/.hermes/hermex-logs.jsonl and emits a SINGLE compact alert when a NEW
significant freeze arrives. Empty stdout = silence (nothing delivered, no LLM
woken). This replaces the old monitor-script pattern where EVERY new freeze
changed the hash and woke the agent — that spammed the chat and interrupted
ongoing agent work.

Rules (hard-coded, deterministic):
  - threshold:   freezes below 5s are micro-hangs, ignored
  - clustering:  freezes within 30 min of a previous ALERT are one cluster,
                 only the first alerts
  - rate limit:  max 1 alert per 30 minutes
  - errors/crashes alert with the same rate limit
  - processed_upto: never re-alert an old event (advances past every read line)

State file: ~/.hermes/hermex_logs_state.json
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG_FILE = Path.home() / ".hermes" / "hermex-logs.jsonl"
STATE_FILE = Path.home() / ".hermes" / "hermex_logs_state.json"

MIN_FREEZE_MS = 5000          # < 5s = micro-hang, ignore
ALERT_WINDOW_S = 30 * 60      # 30 min cluster / rate-limit window
MAX_CONTEXT_EVENTS = 6        # lastEvents tail to include in the alert


def _load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {"processed_upto": 0.0, "last_alert_ts": 0.0}


def _save_state(state: dict) -> None:
    try:
        STATE_FILE.write_text(json.dumps(state))
    except Exception:
        pass


def _ev_ts(ev: dict) -> float:
    return float(ev.get("receivedAt") or ev.get("ts") or 0)


def _fmt_ts(ts: float) -> str:
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).strftime("%H:%M:%SZ")
    except Exception:
        return "?"


def main() -> int:
    if not LOG_FILE.exists():
        return 0  # silence

    state = _load_state()
    processed_upto = state.get("processed_upto", 0.0)
    last_alert_ts = state.get("last_alert_ts", 0.0)

    new_events = []
    max_ts = processed_upto
    try:
        with open(LOG_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                ts = _ev_ts(ev)
                if ts > processed_upto:
                    new_events.append(ev)
                max_ts = max(max_ts, ts)
    except Exception as e:
        # Log file unreadable — alert once (infra problem), respect rate limit
        now = datetime.now(timezone.utc).timestamp()
        if now - last_alert_ts >= ALERT_WINDOW_S:
            print(f"⚠️ Hermex Plus: log file read error — {e}")
            state["last_alert_ts"] = now
        _save_state(state)
        return 0

    alert = None
    alert_ts = None

    for ev in new_events:
        t = ev.get("type")
        if t not in ("freeze", "stutter", "jank", "error", "crash"):
            continue
        ev_ts = _ev_ts(ev)

        if t == "freeze":
            dur = ev.get("durationMs") or 0
            if dur < MIN_FREEZE_MS:
                continue  # micro-hang, noise
            # foreground=false freezes are suspension artifacts, not hangs: the
            # on-device watchdog counts the app being backgrounded/suspended as
            # a main-thread block (its timer fires on resume and measures the
            # whole pause — real case: 491s/729s "freezes" that were just the
            # phone locked). Only real foreground hangs deserve an alert.
            if ev.get("foreground") is False:
                continue
            dur_s = f"{dur / 1000:.0f}s"
        elif t == "stutter":
            dur = ev.get("durationMs") or 0
            if dur < 1500:  # sub-1.5s stalls are streaming noise
                continue
            dur_s = f"{dur / 1000:.1f}s"
        elif t == "jank":
            # Client already gates: avg frame time > 33ms over a 2s window,
            # rate-limited to 1/30s. Message carries the fps.
            dur_s = ""
        else:
            dur_s = ""

        # Clustering + rate limit: only the first significant event per window
        if ev_ts - last_alert_ts < ALERT_WINDOW_S and ev_ts > last_alert_ts:
            continue

        screen = ev.get("screen") or "-"
        msg = str(ev.get("message") or "").replace("\n", " ")
        context = ev.get("lastEvents") or []
        context_tail = " ← ".join(str(c).replace("\n", " ") for c in context[-MAX_CONTEXT_EVENTS:])

        lines = [f"⚠️ Hermex Plus: {t} {dur_s} [screen: {screen}]"]
        lines.append(f"   {msg}")
        if context_tail:
            lines.append(f"   before: {context_tail}")
        alert = "\n".join(lines)
        alert_ts = ev_ts
        break

    # Always advance past everything read, so old events never re-alert
    state["processed_upto"] = max_ts
    if alert is not None and alert_ts is not None:
        state["last_alert_ts"] = max(last_alert_ts, alert_ts)
    _save_state(state)

    if alert:
        print(alert)
    return 0


if __name__ == "__main__":
    sys.exit(main())
