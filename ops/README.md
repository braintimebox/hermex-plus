# ops/ — services this project runs on the host

Code here is **not part of the iOS app**. It is the local infrastructure the app
talks to, kept in this repository because the alternative already failed once.

## Why this directory exists

The logs endpoint (`server.py` + its systemd unit) used to live only in
`~/.hermes/_projects/hermex-logs/` and `~/.config/systemd/user/` — outside git,
in one copy, on one machine. Nothing tracked it and nothing noticed when it broke:
it sat dead for two weeks because a client disconnect raised `BrokenPipeError`
inside an HTTP handler and killed the process. The service was `inactive (dead)`
and `Restart=on-failure` did not bring it back, because an unhandled exception
exits via SIGTERM, which systemd reads as a clean stop.

Keeping the source here makes the service reproducible: a fresh machine restores
it with one command instead of archaeological reconstruction.

## hermex-logs — diagnostics ingest from the iOS app

The app (`HermexLogger.swift`, `MainThreadWatchdog.swift`) POSTs diagnostic events
to this endpoint; it appends them to a JSON-lines file that the freeze watchdog
reads. This is the telemetry behind freeze reports.

| | |
|---|---|
| Port | `8912` |
| Endpoint | `POST /webhook/hermex-logs` (object or array) |
| Health | `GET /health` → `{"status":"ok","events":N}` |
| Store | `~/.hermes/hermex-logs.jsonl` (append-only, rotates at 20 MB) |
| Server log | `~/.hermes/hermex-logs-server.log` |
| Unit | `~/.config/systemd/user/hermex-logs.service` |

### Install / update

```bash
python3 scripts/pipelines/release_hermesplus.py install-server
```

That command copies `server.py` to `~/.hermes/_projects/hermex-logs/`, renders the
unit template with the real path into `~/.config/systemd/user/`, reloads systemd,
restarts the service and prints the health check. Re-running it is the update path.

Options: `--dir <path>` to install elsewhere (then also pass the same `--dir` on
later runs so the unit keeps pointing at it).

### Verify

```bash
systemctl --user status hermex-logs        # active (running)
curl -s localhost:8912/health              # {"status":"ok","events":N}
curl -s -X POST localhost:8912/webhook/hermex-logs \
     -H 'Content-Type: application/json' -d '{"type":"test"}'
```

### Two failures this code already fixed — do not undo them

1. **A client disconnect must not kill the process.** `handle_one_request` and
   `_json` catch `BrokenPipeError` / `ConnectionResetError`. An unhandled one
   propagated out of the handler and killed the server.
2. **`Restart=always`, not `on-failure`.** An unhandled exception exits with
   SIGTERM, which `on-failure` treats as a deliberate stop, so the service stayed
   down silently. `StartLimitBurst` caps a pathological restart loop.

Also: the log file rotates (`MAX_LOG_BYTES`, `KEEP_LINES`). Without it the file
grows without bound — it is append-only and the app pushes continuously.
