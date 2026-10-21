// HERMEX-FORK: tests for the local telemetry bridge (PhaseTelemetry.swift).
//
// These pin the arithmetic and the flush contract: what a window summary reports,
// when it is emitted, and that a finished interval never writes on its own.

import XCTest
@testable import HermesMobile

final class PhaseTelemetryTests: XCTestCase {

    // MARK: - Aggregation

    func testSummaryReportsCountPercentilesAndMaximum() {
        var aggregator = PhaseAggregator()
        for value in 1...10 {
            aggregator.record(.markdownParse, milliseconds: Double(value))
        }

        let snapshots = aggregator.takeSnapshots()
        XCTAssertEqual(snapshots.count, 1)

        let snapshot = try? XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot?.phase, .markdownParse)
        XCTAssertEqual(snapshot?.count, 10)
        // Nearest rank: p50 -> ceil(0.5 * 10) = 5, p90 -> ceil(0.9 * 10) = 9.
        XCTAssertEqual(snapshot?.p50, 5)
        XCTAssertEqual(snapshot?.p90, 9)
        XCTAssertEqual(snapshot?.maximum, 10)
        XCTAssertEqual(snapshot?.dropped, 0)
    }

    func testUnsortedInputIsRankedAfterSorting() {
        var aggregator = PhaseAggregator()
        for value in [40.0, 10, 30, 20] {
            aggregator.record(.transcriptApply, milliseconds: value)
        }

        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.count, 4)
        // ceil(0.5 * 4) = 2 -> 20; ceil(0.9 * 4) = 4 -> 40.
        XCTAssertEqual(snapshot?.p50, 20)
        XCTAssertEqual(snapshot?.p90, 40)
        XCTAssertEqual(snapshot?.maximum, 40)
    }

    func testSingleSampleIsItsOwnP50P90AndMaximum() {
        var aggregator = PhaseAggregator()
        aggregator.record(.streamBatchApply, milliseconds: 12.5)

        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.count, 1)
        XCTAssertEqual(snapshot?.p50, 12.5)
        XCTAssertEqual(snapshot?.p90, 12.5)
        XCTAssertEqual(snapshot?.maximum, 12.5)
    }

    func testEmptyBucketProducesNoSnapshot() {
        var aggregator = PhaseAggregator()
        aggregator.record(.cacheRead, milliseconds: 3)

        let snapshots = aggregator.takeSnapshots()
        XCTAssertEqual(snapshots.map(\.phase), [.cacheRead])
        XCTAssertNil(snapshots.first { $0.phase == .sessionOpen })
        XCTAssertNil(snapshots.first { $0.phase == .markdownParse })
    }

    func testPhasesAccumulateIndependently() {
        var aggregator = PhaseAggregator()
        aggregator.record(.cacheRead, milliseconds: 1)
        aggregator.record(.cacheWrite, milliseconds: 9)
        aggregator.record(.cacheRead, milliseconds: 5)

        let snapshots = aggregator.takeSnapshots()
        XCTAssertEqual(snapshots.count, 2)

        let read = snapshots.first { $0.phase == .cacheRead }
        let write = snapshots.first { $0.phase == .cacheWrite }
        XCTAssertEqual(read?.count, 2)
        XCTAssertEqual(read?.maximum, 5)
        XCTAssertEqual(write?.count, 1)
        XCTAssertEqual(write?.maximum, 9)
    }

    func testSnapshotsAreResetByTakeSnapshots() {
        var aggregator = PhaseAggregator()
        aggregator.record(.sessionOpen, milliseconds: 120)
        XCTAssertEqual(aggregator.takeSnapshots().count, 1)

        // Nothing accumulated in the new window yet.
        XCTAssertTrue(aggregator.takeSnapshots().isEmpty)

        aggregator.record(.sessionOpen, milliseconds: 30)
        let second = aggregator.takeSnapshots()
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.count, 1)
        XCTAssertEqual(second.first?.maximum, 30)
    }

    // MARK: - Context

    func testContextKeepsMaximumAndSum() {
        var aggregator = PhaseAggregator()
        aggregator.record(.streamBatchApply, milliseconds: 4, context: ["mutated": 1, "chars": 200])
        aggregator.record(.streamBatchApply, milliseconds: 6, context: ["mutated": 0, "chars": 900])

        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.contextMaximum["chars"], 900)
        XCTAssertEqual(snapshot?.contextMaximum["mutated"], 1)
        XCTAssertEqual(snapshot?.contextSum["mutated"], 1)
        XCTAssertEqual(snapshot?.contextSum["chars"], 1100)
    }

    func testContextIsResetWithTheWindow() {
        var aggregator = PhaseAggregator()
        aggregator.record(.markdownParse, milliseconds: 1, context: ["chars": 50])
        _ = aggregator.takeSnapshots()

        aggregator.record(.markdownParse, milliseconds: 2, context: ["chars": 10])
        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.contextMaximum["chars"], 10)
        XCTAssertNil(snapshot?.contextMaximum["rows"])
    }

    // MARK: - Capacity

    func testBucketCapacityDropsAndCountsOverflow() {
        var aggregator = PhaseAggregator(bucketCapacity: 4)
        for value in 1...6 {
            aggregator.record(.transcriptApply, milliseconds: Double(value))
        }

        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.count, 4)
        XCTAssertEqual(snapshot?.dropped, 2)
        XCTAssertEqual(snapshot?.maximum, 4)
    }

    func testCapacityIsAtLeastOne() {
        var aggregator = PhaseAggregator(bucketCapacity: 0)
        aggregator.record(.cacheWrite, milliseconds: 7)
        XCTAssertEqual(aggregator.takeSnapshots().first?.count, 1)
    }

    // MARK: - Window

    func testNothingIsEmittedBeforeTheFlushInterval() {
        var clock: TimeInterval = 1_000
        var emitted: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 15,
            now: { clock },
            sink: { emitted.append($0) }
        )

        telemetry.record(.streamBatchApply, milliseconds: 3)
        telemetry.record(.streamBatchApply, milliseconds: 4)
        telemetry.record(.markdownParse, milliseconds: 9)

        XCTAssertTrue(emitted.isEmpty, "a finished interval must not log on its own")

        clock += 15
        telemetry.record(.streamBatchApply, milliseconds: 5)

        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(Set(emitted.map(\.phase)), [.streamBatchApply, .markdownParse])
        XCTAssertEqual(emitted.first { $0.phase == .streamBatchApply }?.count, 3)
    }

    func testFlushEmitsAccumulatedAndStartsANewWindow() {
        var clock: TimeInterval = 500
        var emitted: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(flushInterval: 60, now: { clock }, sink: { emitted.append($0) })

        telemetry.record(.sessionOpen, milliseconds: 250)
        telemetry.flush()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.count, 1)

        telemetry.flush()
        XCTAssertEqual(emitted.count, 1, "flushing an empty window emits nothing")

        clock += 1
        telemetry.record(.sessionOpen, milliseconds: 90)
        telemetry.flush()
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted.last?.count, 1)
    }

    func testResetDropsSamplesWithoutEmitting() {
        var emitted: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(flushInterval: 60, now: { 100 }, sink: { emitted.append($0) })

        telemetry.record(.cacheRead, milliseconds: 2)
        telemetry.reset()
        telemetry.flush()

        XCTAssertTrue(emitted.isEmpty)
    }

    func testSnapshotLoggingShapeIsStable() {
        var aggregator = PhaseAggregator()
        aggregator.record(.streamBatchApply, milliseconds: 16, context: ["mutated": 1, "chars": 320])
        let snapshot = try? XCTUnwrap(aggregator.takeSnapshots().first)

        // The sink reads only these fields; guard the shape with a direct call so a
        // rename cannot silently stop phase events from reaching HermexLogger.
        XCTAssertNotNil(snapshot)
        PhaseTelemetry.logToHermex(snapshot!)
    }

    // MARK: - Escalation (budgets → detailed context → silence again)

    /// Every phase must have a deliberate budget decision. A phase that quietly
    /// returns nil is a phase nobody can regress: adding one without a budget is
    /// how the picker shipped without telemetry in the first place.
    func testEveryPhaseHasADeliberateBudgetDecision() {
        let withoutBudget = PhaseAggregator.Phase.allCases
            .filter { PhaseBudget.p90Milliseconds(for: $0) == nil }

        XCTAssertEqual(
            Set(withoutBudget),
            [
                .markdownParse, .markdownParseStream, .markdownParseSettled,
                // Added in the Model Picker diagnostic stage: no baseline exists yet,
                // so a budget would be a guess dressed as a norm. They get budgets
                // once the device run produces one.
                .pickerNetwork, .pickerCatalogPrepare, .pickerFirstFrame, .pickerSearch,
            ],
            "A phase without a budget must be a deliberate change, not an oversight"
        )
    }

    /// Three consecutive samples over budget switch the phase to detailed mode:
    /// the next samples carry `escalated` and `isMainThread`, so a later reading
    /// can tell main-thread work from background work without a rebuild.
    func testRepeatedBreachesEscalateTheFollowingSamples() throws {
        var clock = 0.0
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { clock },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        // Budget for Cache Write is 50 ms; each sample takes 200 ms.
        for _ in 0..<5 {
            telemetry.begin(.cacheWrite)
            clock += 0.2
            telemetry.end(.cacheWrite)
        }
        telemetry.flush()

        let snapshot = try XCTUnwrap(snapshots.first { $0.phase == .cacheWrite })
        XCTAssertEqual(snapshot.count, 5)
        // The sample that reaches the threshold is already detailed: 3rd, 4th, 5th.
        XCTAssertEqual(snapshot.contextSum["escalated"], 3)
        XCTAssertNotNil(snapshot.contextSum["isMainThread"])
    }

    /// A sample inside its budget keeps the phase quiet and resets the streak —
    /// otherwise one bad minute would leave every later report verbose forever.
    func testSampleInsideBudgetResetsTheStreak() throws {
        var clock = 0.0
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { clock },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        func sample(_ milliseconds: Double) {
            telemetry.begin(.cacheWrite)
            clock += milliseconds / 1000
            telemetry.end(.cacheWrite)
        }

        sample(200)   // breach 1
        sample(200)   // breach 2
        sample(10)    // inside budget → streak reset
        sample(200)   // breach 1 again, not 3
        sample(200)   // breach 2
        telemetry.flush()

        let snapshot = try XCTUnwrap(snapshots.first { $0.phase == .cacheWrite })
        XCTAssertEqual(snapshot.count, 5)
        XCTAssertNil(snapshot.contextSum["escalated"], "two breaches with a reset between them must not escalate")
    }

    /// A single second-long sample is reported as a hang with a stack, once.
    func testHangIsReportedOncePerCooldown() throws {
        // A real timestamp is a Unix epoch, and the cooldown gate compares absolute
        // instants: starting at 0 would make the first hang look like it happened
        // seconds ago, so it would be swallowed before any report.
        var clock = 1_000_000.0
        var hangs: [(PhaseAggregator.Phase, Double)] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { clock },
            sink: { _ in },
            hangReporter: { hangs.append(($0, $1)) }
        )

        telemetry.begin(.cacheWrite)
        clock += 1.5
        telemetry.end(.cacheWrite)

        telemetry.begin(.cacheWrite)
        clock += 1.5          // still inside the 60 s cooldown
        telemetry.end(.cacheWrite)

        XCTAssertEqual(hangs.count, 1, "one stack per cooldown, not one per hang")
        let firstHang = try XCTUnwrap(hangs.first)
        XCTAssertEqual(firstHang.1, 1500, accuracy: 1)
    }

    // MARK: - Correlation (one trace per user action)

    /// Samples from two picker opens must never share a bucket: mixing them let a
    /// fast warm open hide the tail of a slow cold one.
    func testSnapshotsAreSeparatedByTrace() {
        var aggregator = PhaseAggregator()
        aggregator.record(.pickerCatalogPrepare, milliseconds: 40, traceId: "open-A")
        aggregator.record(.pickerCatalogPrepare, milliseconds: 20, traceId: "open-A")
        aggregator.record(.pickerCatalogPrepare, milliseconds: 200, traceId: "open-B")

        let snapshots = aggregator.takeSnapshots()
        XCTAssertEqual(snapshots.count, 2)

        let byTrace = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.traceId ?? "-", $0) })
        XCTAssertEqual(byTrace["open-A"]?.count, 2)
        XCTAssertEqual(byTrace["open-A"]?.maximum, 40)
        XCTAssertEqual(byTrace["open-B"]?.count, 1)
        XCTAssertEqual(byTrace["open-B"]?.maximum, 200)
    }

    /// Untraced samples keep the historical behaviour: one bucket per phase.
    func testUntracedSamplesStayInOneBucket() {
        var aggregator = PhaseAggregator()
        aggregator.record(.sessionOpen, milliseconds: 10)
        aggregator.record(.sessionOpen, milliseconds: 20)

        let snapshots = aggregator.takeSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertNil(snapshots.first?.traceId)
        XCTAssertEqual(snapshots.first?.count, 2)
    }

    /// Tail percentiles use the same nearest-rank rule as p50/p90.
    func testTailPercentilesAreReported() {
        var aggregator = PhaseAggregator()
        for value in 1...100 {
            aggregator.record(.pickerFirstFrame, milliseconds: Double(value))
        }
        let snapshot = aggregator.takeSnapshots().first
        XCTAssertEqual(snapshot?.p90, 90)
        XCTAssertEqual(snapshot?.p95, 95)
        XCTAssertEqual(snapshot?.p99, 99)
        XCTAssertEqual(snapshot?.maximum, 100)
    }

    // MARK: - Overlapping phases

    /// Two overlapping spans of the same phase each keep their own start: the
    /// second `begin` used to overwrite the first, so one span measured the other
    /// and the other disappeared.
    func testOverlappingPhaseSpansAreBothRecorded() {
        var clock = 1_000_000.0
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { clock },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        telemetry.begin(.pickerNetwork)
        clock += 0.100
        telemetry.begin(.pickerNetwork)
        clock += 0.050
        telemetry.end(.pickerNetwork)      // closes the inner span: 50 ms
        clock += 0.100
        telemetry.end(.pickerNetwork)      // closes the outer span: 250 ms
        telemetry.flush()

        let snapshot = snapshots.first { $0.phase == .pickerNetwork }
        XCTAssertEqual(snapshot?.count, 2, "both spans must survive")
        XCTAssertEqual(snapshot?.p50, 50, "LIFO pairs each end with its own start")
        XCTAssertEqual(snapshot?.maximum, 250)
    }

    /// An `end` without a matching `begin` records nothing instead of inventing a
    /// span from an unrelated start time.
    func testEndWithoutBeginRecordsNothing() {
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { 1_000_000 },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        telemetry.end(.pickerSearch)
        telemetry.flush()
        XCTAssertTrue(snapshots.isEmpty)
    }

    /// The scenario tag must survive a child screen finishing after its parent:
    /// a late `leave` for a screen that is no longer on top must not clear the
    /// context the frame histogram is reading.
    func testScenarioIsOnlyClearedByTheScreenThatOwnsIt() {
        TelemetryScenario.shared.enter(screen: "ModelPicker", traceId: "trace-1")
        TelemetryScenario.shared.leave(screen: "Chat")
        XCTAssertEqual(TelemetryScenario.shared.current.screen, "ModelPicker")
        XCTAssertEqual(TelemetryScenario.shared.current.traceId, "trace-1")

        TelemetryScenario.shared.leave(screen: "ModelPicker")
        XCTAssertNil(TelemetryScenario.shared.current.screen)
        XCTAssertNil(TelemetryScenario.shared.current.traceId)
    }

    // MARK: - Prepare measurement must not change the catalog

    /// Timing is a wrapper, not a second implementation: whatever `prepare`
    /// returns, the measured variant returns byte for byte.
    func testMeasuredPrepareReturnsTheSameCatalog() {
        let groups = [
            ModelCatalogGroup(
                id: "opencode",
                name: "OpenCode",
                providerID: "opencode-go",
                models: [
                    ModelCatalogOption(id: "kept", displayName: "Kept", providerID: "opencode-go"),
                    ModelCatalogOption(id: "kept", displayName: "Kept", providerID: "opencode-go"),
                ]
            ),
            ModelCatalogGroup(
                id: "stealth",
                name: "Stealth",
                providerID: "stealth",
                models: [
                    ModelCatalogOption(id: "stealth/hidden", displayName: "Hidden", providerID: "stealth"),
                ]
            ),
        ]

        XCTAssertEqual(ModelPickerSheet.measuredPrepare(groups), ModelPickerSheet.prepare(groups))
    }

    /// Spans that finish in START order cannot be paired by a stack at all: the
    /// first `end` would pop the second span's start. Tokens pair each end with its
    /// own span, so both durations stay true.
    func testTokenSpansPairEachEndWithItsOwnStart() {
        var clock = 1_000_000.0
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { clock },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        let first = telemetry.begin(.cacheRead)
        clock += 0.100
        let second = telemetry.begin(.cacheRead)
        clock += 0.200
        telemetry.end(first)          // first span: 300 ms, closed while the second is live
        clock += 0.100
        telemetry.end(second)         // second span: 300 ms
        telemetry.flush()

        let snapshot = snapshots.first { $0.phase == .cacheRead }
        XCTAssertEqual(snapshot?.count, 2)
        XCTAssertEqual(snapshot?.p50, 300)
        XCTAssertEqual(snapshot?.maximum, 300)
    }

    /// A token that was never opened, or already closed, records nothing.
    func testEndingAnUnknownTokenRecordsNothing() {
        var snapshots: [PhaseAggregator.Snapshot] = []
        let telemetry = PhaseTelemetry(
            flushInterval: 3_600,
            now: { 1_000_000 },
            sink: { snapshots.append($0) },
            hangReporter: { _, _ in }
        )

        let span = telemetry.begin(.pickerSearch)
        telemetry.end(span)
        telemetry.end(span)   // second close must not invent a sample
        telemetry.flush()

        let snapshot = snapshots.first { $0.phase == .pickerSearch }
        XCTAssertEqual(snapshot?.count, 1)
    }
}
