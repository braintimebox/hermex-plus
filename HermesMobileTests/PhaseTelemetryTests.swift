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
}
