// HERMEX-FORK: local telemetry bridge for upstream #920 (ffd49a68).
//
// Upstream #920 emits OSSignpost intervals that only Instruments can read, so the
// phase durations never reach our own log pipeline. This file aggregates the same
// durations in-process and flushes them through HermexLogger, which already writes
// to hermex-logs.jsonl off the main thread.
//
// It is an *additional* measurement channel: the signposts stay Instruments-facing
// and the debug hitch meter is untouched. Nothing here optimises anything, and no
// jank/freeze/stutter event shape changes — this only emits `type: "phase"`.
//
// Cost discipline: a finished interval appends one Double under a lock. Sorting
// happens once per flush window, never in the streaming hot path, and there is no
// per-interval disk I/O.

import Foundation

/// Pure, testable accumulator for instrumented phase durations.
///
/// Durations are kept per phase in milliseconds. Context values are folded into
/// cheap aggregates (a running maximum and a running sum) instead of being stored
/// per sample, so a long stream cannot grow this beyond its bucket capacity.
struct PhaseAggregator {
    /// A phase that carries an `#920` signpost interval.
    enum Phase: String, CaseIterable {
        case streamBatchApply = "Stream Batch Apply"
        case transcriptApply = "Transcript Apply"
        case markdownParse = "Markdown Parse"
        case cacheRead = "Cache Read"
        case cacheWrite = "Cache Write"
        /// HERMEX-FORK: the two session writers used to share the `Cache Write`
        /// phase with the message writer, so a 522 ms reading could not be
        /// attributed to a caller. They get their own phases so the
        /// main-thread cost of session writes is visible on its own.
        case cacheWriteSessions = "Cache Write (sessions)"
        case cacheWriteSession = "Cache Write (session)"
        case sessionOpen = "Session Open"
        // HERMEX-FORK: 3.9.39 — диагностика реального streaming-пути.
        // Мёртвый StreamingMarkdownChunkedView НЕ инструментирован: подтверждено
        // отсутствие call sites (определение + два комментария).
        case renderPolicy = "Render Policy"
        case fallbackRender = "Fallback Render"
        case lightRender = "Light Render"
        case markdownParseSettled = "Markdown Parse (settled)"
        case markdownParseStream = "Markdown Parse (stream)"
        // HERMEX-FORK: 3.9.52 — открытие пикера. Две фазы намеренно разделены:
        // `pickerOpen` меряет только путь «тап → лист показан», а
        // `pickerCatalogRefresh` — сеть плюс применение каталога, которое идёт
        // уже после появления списка. Смешивать их в одну цифру нельзя:
        // сетевое ожидание и задержка отрисовки — разные проблемы.
        case pickerOpen = "Picker Open"
        case pickerCatalogRefresh = "Picker Catalog Refresh"
        // Applying the refreshed catalog is a separate phase: it is pure
        // main-thread work (diff + list rebuild), and folding it into the
        // refresh number hid how much of the 3 355 ms was the network.
        case pickerCatalogApply = "Picker Catalog Apply"
    }

    /// One flush-window summary for a single phase.
    struct Snapshot: Equatable {
        let phase: Phase
        let count: Int
        let p50: Double
        let p90: Double
        let maximum: Double
        /// Samples discarded because the bucket was full; 0 in normal operation.
        let dropped: Int
        /// Largest value seen per context key (for `chars`, `messages`, `rows`).
        let contextMaximum: [String: Int]
        /// Sum of values per context key (for `mutated`, which counts occurrences).
        let contextSum: [String: Int]
    }

    /// Per-phase sample ceiling. A bucket this long already spans far more than one
    /// flush window, so extra samples are dropped and counted rather than growing.
    static let defaultBucketCapacity = 2048

    let bucketCapacity: Int

    private var samples: [Phase: [Double]] = [:]
    private var dropped: [Phase: Int] = [:]
    private var contextMaximum: [Phase: [String: Int]] = [:]
    private var contextSum: [Phase: [String: Int]] = [:]

    init(bucketCapacity: Int = PhaseAggregator.defaultBucketCapacity) {
        self.bucketCapacity = max(1, bucketCapacity)
    }

    mutating func record(_ phase: Phase, milliseconds: Double, context: [String: Int] = [:]) {
        var bucket = samples[phase] ?? []
        if bucket.count >= bucketCapacity {
            dropped[phase, default: 0] += 1
        } else {
            bucket.append(max(0, milliseconds))
            samples[phase] = bucket
        }

        guard !context.isEmpty else { return }
        for (key, value) in context {
            contextMaximum[phase, default: [:]][key] = max(contextMaximum[phase]?[key] ?? value, value)
            contextSum[phase, default: [:]][key, default: 0] += value
        }
    }

    /// Summaries for every phase that has samples, in `Phase.allCases` order, with
    /// the accumulated data reset. Phases with no samples produce nothing.
    mutating func takeSnapshots() -> [Snapshot] {
        var snapshots: [Snapshot] = []
        for phase in Phase.allCases {
            guard let bucket = samples[phase], !bucket.isEmpty else {
                samples[phase] = nil
                continue
            }
            let sorted = bucket.sorted()
            snapshots.append(
                Snapshot(
                    phase: phase,
                    count: sorted.count,
                    p50: Self.percentile(sorted, 0.50),
                    p90: Self.percentile(sorted, 0.90),
                    maximum: sorted[sorted.count - 1],
                    dropped: dropped[phase] ?? 0,
                    contextMaximum: contextMaximum[phase] ?? [:],
                    contextSum: contextSum[phase] ?? [:]
                )
            )
            samples[phase] = nil
            dropped[phase] = nil
            contextMaximum[phase] = nil
            contextSum[phase] = nil
        }
        return snapshots
    }

    /// Nearest-rank percentile over an ascending array: rank = ceil(p * n), clamped
    /// into `1...n`. Deterministic, with no interpolation, so tests can pin it.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        let index = min(max(rank, 1), sorted.count) - 1
        return sorted[index]
    }
}

/// Windowed owner of `PhaseAggregator`: records without doing work on the hot path
/// and flushes the aggregate through `HermexLogger` once per interval.
final class PhaseTelemetry {
    static let shared = PhaseTelemetry()

    /// One flush window. Long enough that a flush is rare, short enough that a
    /// session's numbers are visible while it is still in use.
    static let defaultFlushInterval: TimeInterval = 15

    private let lock = NSLock()
    private var aggregator: PhaseAggregator
    private let flushInterval: TimeInterval
    private let now: () -> TimeInterval
    private let sink: (PhaseAggregator.Snapshot) -> Void
    private let hangReporter: (PhaseAggregator.Phase, Double) -> Void
    private var windowStartedAt: TimeInterval
    private var startedAt: [PhaseAggregator.Phase: TimeInterval] = [:]
    /// Consecutive samples over budget, per phase. Reset by any sample that fits.
    private var breachStreak: [PhaseAggregator.Phase: Int] = [:]
    /// Remaining samples in which this phase records its context (escalated mode).
    private var detailedRemaining: [PhaseAggregator.Phase: Int] = [:]
    private var lastHangReportAt: TimeInterval = 0

    init(
        flushInterval: TimeInterval = PhaseTelemetry.defaultFlushInterval,
        bucketCapacity: Int = PhaseAggregator.defaultBucketCapacity,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        sink: @escaping (PhaseAggregator.Snapshot) -> Void = PhaseTelemetry.logToHermex,
        hangReporter: @escaping (PhaseAggregator.Phase, Double) -> Void = PhaseTelemetry.reportHang
    ) {
        self.aggregator = PhaseAggregator(bucketCapacity: bucketCapacity)
        self.flushInterval = flushInterval
        self.now = now
        self.sink = sink
        self.hangReporter = hangReporter
        self.windowStartedAt = now()
    }

    /// Marks the start of an instrumented phase. Paired with `end(_:context:)`, which
    /// computes the elapsed time locally — the signpost interval keeps its own timing
    /// for Instruments, so neither channel depends on the other.
    func begin(_ phase: PhaseAggregator.Phase) {
        lock.lock()
        startedAt[phase] = now()
        lock.unlock()
    }

    /// Finishes a phase started with `begin(_:)`. Records one sample and the context
    /// counters; a phase that was never started records nothing.
    func end(_ phase: PhaseAggregator.Phase, context: [String: Int] = [:]) {
        lock.lock()
        let start = startedAt[phase]
        startedAt[phase] = nil
        guard let start else {
            lock.unlock()
            return
        }
        let elapsed = (now() - start) * 1000
        let timestamp = now()

        // ESCALATION. A phase that keeps missing its budget starts recording WHY,
        // for a bounded number of samples, then falls silent again. Without this
        // every investigation began with a patch, a rebuild and a reinstall just
        // to learn whether the work ran on the main thread.
        var effective = context
        if let budget = PhaseBudget.p90Milliseconds(for: phase) {
            if elapsed > budget {
                breachStreak[phase, default: 0] += 1
            } else {
                breachStreak[phase] = 0
            }
            if breachStreak[phase, default: 0] >= PhaseBudget.breachStreakThreshold,
               detailedRemaining[phase, default: 0] == 0 {
                detailedRemaining[phase] = PhaseBudget.detailedSampleBudget
                breachStreak[phase] = 0
            }
        }
        if detailedRemaining[phase, default: 0] > 0 {
            detailedRemaining[phase, default: 0] -= 1
            effective["escalated"] = 1
            effective["isMainThread"] = Thread.isMainThread ? 1 : 0
        }

        aggregator.record(phase, milliseconds: elapsed, context: effective)
        var due: [PhaseAggregator.Snapshot] = []
        if timestamp - windowStartedAt >= flushInterval {
            windowStartedAt = timestamp
            due = aggregator.takeSnapshots()
        }
        // Hangs are reported regardless of escalation: one stack is worth more
        // than a hundred counters, and the cooldown keeps the log readable.
        var reportHang = false
        if elapsed >= PhaseBudget.hangMilliseconds,
           timestamp - lastHangReportAt >= PhaseBudget.hangCooldown {
            lastHangReportAt = timestamp
            reportHang = true
        }
        lock.unlock()

        for snapshot in due { sink(snapshot) }
        if reportHang { hangReporter(phase, elapsed) }
    }

    /// Records one finished interval. O(1): an append under a lock, plus a window
    /// check. The flush happens on the thread that crosses the boundary, and the
    /// sink itself hands off to `HermexLogger`'s own serial queue.
    func record(_ phase: PhaseAggregator.Phase, milliseconds: Double, context: [String: Int] = [:]) {
        var due: [PhaseAggregator.Snapshot] = []
        lock.lock()
        aggregator.record(phase, milliseconds: milliseconds, context: context)
        let timestamp = now()
        if timestamp - windowStartedAt >= flushInterval {
            windowStartedAt = timestamp
            due = aggregator.takeSnapshots()
        }
        lock.unlock()

        // Outside the lock: never hold it across a sink.
        for snapshot in due { sink(snapshot) }
    }

    /// Emits whatever has accumulated and starts a new window.
    func flush() {
        lock.lock()
        windowStartedAt = now()
        let due = aggregator.takeSnapshots()
        lock.unlock()
        for snapshot in due { sink(snapshot) }
    }

    /// Drops accumulated samples without emitting them.
    func reset() {
        lock.lock()
        aggregator = PhaseAggregator(bucketCapacity: aggregator.bucketCapacity)
        startedAt = [:]
        breachStreak = [:]
        detailedRemaining = [:]
        windowStartedAt = now()
        lock.unlock()
    }

    /// Default sink: one `type: "phase"` event per phase per window.
    static func logToHermex(_ snapshot: PhaseAggregator.Snapshot) {
        var extras: [String: Any] = [
            "phase": snapshot.phase.rawValue,
            "count": snapshot.count,
            "p50": rounded(snapshot.p50),
            "p90": rounded(snapshot.p90),
            "max": rounded(snapshot.maximum),
        ]
        if snapshot.dropped > 0 { extras["dropped"] = snapshot.dropped }
        for (key, value) in snapshot.contextMaximum { extras["\(key)_max"] = value }
        for (key, value) in snapshot.contextSum {
            if key == "mutated" { extras["\(key)_sum"] = value }
        }
        var phaseExtras = extras
        phaseExtras["durationMs"] = snapshot.maximum
        HermexLogger.shared.log(
            type: "phase",
            screen: "Performance",
            message: "phase aggregate",
            extras: phaseExtras
        )
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

// HERMEX-FORK: 3.9.41 — streaming-commit diagnostics (instrumentation only).
//
// WHY: the 3.9.40 frame histogram proved that only streaming contexts degrade
// (`stream` 34.3% of frames miss 16.67 ms, `app_update` only 3.4%), but it
// cannot say WHY. This channel records, per commit of the streaming renderer,
// enough to discriminate the four remaining hypotheses from §7 of the baseline:
//
//   G1  follow-scroll competes for the frame      → cost high only when followActive
//   G2  the whole accumulated text is re-laid out → cost grows with accumulatedChars
//   G3  the initial heavy layout dominates        → bad frames cluster at small streamAgeMs
//   G4  the degradation merely coincides with
//       background operations (cache/session)     → no dependence on length/follow
//
// Nothing here changes behaviour: values are only written to the log.
// Aggregation is per 2 s window so the channel stays comparable to `frames`.
final class StreamCommitTelemetry {
    static let shared = StreamCommitTelemetry()

    private let queue = DispatchQueue(label: "hermex.streamCommit.telemetry")
    private let windowDuration: TimeInterval = 2.0
    /// A gap longer than this between commits means a new answer started.
    private let streamGap: TimeInterval = 3.0

    private var windowStart = Date()
    private var lastCommitAt: Date?
    private var streamStart = Date()
    private var streamID = 0

    private var commits = 0
    private var accumulatedMin = Int.max
    private var accumulatedMax = 0
    private var deltaSum = 0
    private var deltaMax = 0
    private var intervalSumMs = 0.0
    private var intervalMaxMs = 0.0
    private var intervals = 0
    private var followActiveCommits = 0
    private var followScrolls = 0
    private var frameSumMs = 0.0
    private var frameMaxMs = 0.0
    private var frameSamples = 0

    private init() {}

    /// One renderer commit of the streaming text.
    /// Called on the main actor, so the frame duration is read on main too.
    func recordCommit(accumulatedChars: Int, deltaChars: Int, followActive: Bool) {
        let now = Date()
        let frameMs = FrameTimeMonitor.shared.lastFrameMs
        queue.sync {
            if let last = lastCommitAt, now.timeIntervalSince(last) > streamGap {
                flushLocked(at: last)
                streamID += 1
                streamStart = now
            }
            if let last = lastCommitAt {
                let ms = now.timeIntervalSince(last) * 1000
                intervalSumMs += ms
                intervalMaxMs = max(intervalMaxMs, ms)
                intervals += 1
            }
            lastCommitAt = now

            commits += 1
            accumulatedMin = min(accumulatedMin, accumulatedChars)
            accumulatedMax = max(accumulatedMax, accumulatedChars)
            deltaSum += deltaChars
            deltaMax = max(deltaMax, deltaChars)
            if followActive { followActiveCommits += 1 }
            if frameMs > 0 {
                frameSumMs += frameMs
                frameMaxMs = max(frameMaxMs, frameMs)
                frameSamples += 1
            }

            if now.timeIntervalSince(windowStart) >= windowDuration { flushLocked(at: now) }
        }
    }

    /// A programmatic auto-follow scroll fired while streaming (G1).
    func recordFollowScroll() {
        queue.sync { followScrolls += 1 }
    }

    /// Stream ended (or the app is going away): emit whatever is still pending.
    ///
    /// WHY THIS EXISTS: on 3.9.41 this channel produced zero events while six
    /// `Stream Batch Apply` phases proved streaming was happening. The window
    /// only flushed on a commit that crossed the 2 s boundary; a stream that
    /// ended first kept its last window in memory forever — no flush, no event.
    /// The short streams in that session (1-7 batches) never crossed it.
    func endStream() {
        let now = Date()
        queue.sync {
            flushLocked(at: now)
            // HERMEX-FORK: clearing the last-commit stamp on stream end, not just
            // on a gap flush. Without this, the first commit of the NEXT stream
            // measured its interval from the previous stream's last commit —
            // across minutes of app background, that produced intervalMaxMs of
            // thousands of seconds in windows whose own frameAvg was a healthy
            // 16.7 ms (verified 125/125 anomalous windows in the 3.9.47
            // telemetry). The gap flush inside recordCommit handles its own
            // interval; endStream only needs to stop the clock between streams.
            lastCommitAt = nil
        }
    }

    private func flushLocked(at now: Date) {
        guard commits > 0 else {
            windowStart = now
            return
        }
        let avgFrame = frameSamples > 0 ? frameSumMs / Double(frameSamples) : 0
        let ageMs = now.timeIntervalSince(streamStart) * 1000
        HermexLogger.shared.log(
            type: "streamCommit",
            durationMs: avgFrame,
            screen: "Performance",
            message: String(
                format: "stream commits n=%d accum<=%d avgFrame=%.1f maxFrame=%.1f follow=%d/%d",
                commits, accumulatedMax, avgFrame, frameMaxMs, followActiveCommits, commits
            ),
            extras: [
                "streamId": streamID,
                "commits": commits,
                "accumulatedMin": accumulatedMin == Int.max ? 0 : accumulatedMin,
                "accumulatedMax": accumulatedMax,
                "deltaSum": deltaSum,
                "deltaMax": deltaMax,
                "intervalAvgMs": intervals > 0 ? intervalSumMs / Double(intervals) : 0,
                "intervalMaxMs": intervalMaxMs,
                "followActiveCommits": followActiveCommits,
                "followScrolls": followScrolls,
                "streamAgeMs": ageMs,
                "frameAvgMs": avgFrame,
                "frameMaxMs": frameMaxMs,
                "frameSamples": frameSamples,
            ]
        )

        commits = 0
        accumulatedMin = Int.max
        accumulatedMax = 0
        deltaSum = 0
        deltaMax = 0
        intervalSumMs = 0
        intervalMaxMs = 0
        intervals = 0
        followActiveCommits = 0
        followScrolls = 0
        frameSumMs = 0
        frameMaxMs = 0
        frameSamples = 0
        windowStart = now
    }
}

/// p90 budgets: the line between "normal" and "worth investigating".
///
/// A phase without a budget cannot regress visibly — nobody knows what bad is,
/// so every report restarts the argument. Markdown deliberately has none: it
/// reports 0.2 ms p90 across tens of thousands of samples while the app visibly
/// janks, which means its span is wrong and a budget would only lend authority
/// to a number that measures the wrong thing.
enum PhaseBudget {
    static func p90Milliseconds(for phase: PhaseAggregator.Phase) -> Double? {
        switch phase {
        case .cacheWrite, .cacheWriteSessions, .cacheWriteSession: return 50
        case .cacheRead: return 20
        case .sessionOpen: return 150
        case .transcriptApply, .streamBatchApply, .pickerCatalogApply,
             .renderPolicy, .lightRender, .fallbackRender: return 16
        case .pickerOpen: return 100
        case .pickerCatalogRefresh: return 2000
        case .markdownParse, .markdownParseStream, .markdownParseSettled: return nil
        }
    }

    /// Samples over budget, in a row, before the phase starts recording context.
    static let breachStreakThreshold = 3
    /// How many samples the escalated phase stays detailed before falling silent.
    static let detailedSampleBudget = 50
    /// A single sample this long is a hang, not a slow phase.
    static let hangMilliseconds: Double = 1000
    /// One stack per minute is enough to identify the call site.
    static let hangCooldown: TimeInterval = 60
}

extension PhaseTelemetry {
    /// Reports a single sample that took a second or more, with a stack.
    ///
    /// This is the link the log was missing: `Cache Write 6 920 ms` says how bad
    /// it was, never where. Fifteen frames and the thread name are enough to
    /// name the function without shipping a profiler.
    static func reportHang(_ phase: PhaseAggregator.Phase, _ milliseconds: Double) {
        HermexLogger.shared.log(
            type: "freeze",
            durationMs: milliseconds,
            screen: "Performance",
            message: "phase \(phase.rawValue) \(Int(milliseconds)) ms",
            extras: [
                "phase": phase.rawValue,
                "thread": Thread.isMainThread ? "main" : "background",
                "stack": Thread.callStackSymbols.prefix(15).joined(separator: "\n"),
            ]
        )
    }
}
