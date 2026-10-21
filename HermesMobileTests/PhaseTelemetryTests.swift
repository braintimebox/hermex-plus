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
            [.markdownParse, .markdownParseStream, .markdownParseSettled],
            "Markdown is exempt only because its span is wrong; any other phase without a budget must be a deliberate change"
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
}
