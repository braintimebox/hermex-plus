# Telemetry schema (HERMEX-FORK: 3.9.50 — replaces memory)

## Contract
Every telemetry event MUST declare its source version (`appVersion`),
timestamp (`ts` local / `receivedAt` server), `requestId` (UUID),
and category (`type`). Metrics change only when schema changes.

## Channels (10; each stays fixed until stated)

| Channel | Field | Meaning | Norm / threshold |
|---|---|---|---|
| `frames` | `p50` (ms) | Frame time at 60 Hz | 16.67 ms |
| `frames` | `pct>50ms` | % frames >50 ms | < 2 % (
| `frames` | `pct<8.33ms` | % <8.33 ms (ProMotion) | 0.04 % — never expected |
| `jank` | `avg` / `max` | Jank observed (bad windows ONLY) | avg ≤ 18 ms; max ≤ 96 ms; >100 ms = investigate |
| `stutter` | count / `durMs` | Main-thread stall >1 s | 0 in healthy versions; 5 in 3.9.47 |
| `freeze` | count + `lastEvents[]` | Multi-second hang | 0; `freeze` = critical |
| `recovered` | count | Auto-recovered after error | >0 = re-check |
| `error` | category / `message` / `retryable` / `appVersion` | Client error (network, auth, etc.) | `retryable=false` → block |
| `event` | `message` | Lifecycle / policy event (32 types) | Read `event` dictionary for list |
| `phase` | `phase` + `ms` / `context` | Render / stream / persistence phases | `renderPolicy` / `lightRender` / `markdownParse(stream)`; `streamBatchApply` p90 ≤ 56 ms |
| `streamCommit` | `accum` / `delta` / `followActive` / `intervalMs` | Every stream commit | `deltaMax` ≤ 102; `accumMax` ≤ 9992; `intervalMs` should NOT exceed previous stream by >10 000 s |

## Interpreting errors: read order

1. Check `category`: `network.url.-1001` = timedOut, `-1005` = lost, `-1015` = rawData, `-1200` = TLS, `-1001` = retry timeout (20 s in auth.sendCode).
2. Check `retryable`: `false` = no automatic retry; client must retry manually.
3. Check `path`: `send` = telemetry fail, `auth.sendCode` = server unreachable.
4. If `client_ip=?` → mobile/NAT; no server IP correlation possible.
5. Correlate with proxy `cid` by `requestId` (now in event body) — match event `ts` to proxy REQ in ±45 s window.

## Watchdog thresholds (verified):

- `p90` frame > 88 ms (65×1.35) = degradation.
- `pct>50ms` > 22 % (16×1.35) = degradation.
- `intervalMaxMs` > 10 000 s + `streamAgeMs≈0` = `endStream()` not resetting `lastCommitAt` (fixed 3.9.48, must stay fixed).
- Persistence: `Session Open` > 700 ms (base 297 ms at 3.9.42) = investigate.

## Request-ID correlation rule (3.9.50)

- Client sends `X-Hermex-Request-ID: <UUID>` header on each `/webhook/hermex-logs` POST.
- Event JSON includes `requestId`: same UUID.
- Correlator (`proxy-1118-correlate.py`) must read both; if header present, match event by `requestId`; else by `cid` + time window.
- If neither matches: report "REQUEST_ID_MISSING" in correlation log.

## Versioning
Schema updates only when field names, types, or norms change.
Until then: compare new release only to its own baseline, never assume past norms apply.
