import XCTest
@testable import HermesMobile

/// HERMEX-FORK: 3.9.65 — regression tests for `intervalAvgMs`.
///
/// 3.9.64: 193 of 708 intervals (27%) exceeded 5 s, p95 was 163 570 ms and the
/// maximum 19.5M ms — the distance across hours of background was being added
/// to the new stream's per-commit average.
final class StreamCommitIntervalTests: XCTestCase {

    private let gap: TimeInterval = 3.0

    func testNormalIntervalIsRecorded() {
        let now = Date()
        let result = StreamCommitInterval.classify(
            now: now,
            last: now.addingTimeInterval(-0.2),
            gap: gap
        )
        XCTAssertEqual(result.intervalMs ?? -1, 200, accuracy: 1)
        XCTAssertNil(result.gapMs)
    }

    /// The background case: the phone was asleep, the app came back.
    func testBackgroundGapIsNotARecordedInterval() {
        let now = Date()
        let result = StreamCommitInterval.classify(
            now: now,
            last: now.addingTimeInterval(-6 * 3600),   // 6 hours
            gap: gap
        )
        XCTAssertNil(result.intervalMs, "a pause across background must not enter intervalAvgMs")
        XCTAssertEqual((result.gapMs ?? 0) / 1000, 21_600, accuracy: 1)
    }

    /// Exactly at the boundary the gap has NOT opened yet: real delays up to the
    /// threshold are kept as measurements.
    func testIntervalAtGapBoundaryIsStillRecorded() {
        let now = Date()
        let result = StreamCommitInterval.classify(
            now: now,
            last: now.addingTimeInterval(-gap),
            gap: gap
        )
        XCTAssertNotNil(result.intervalMs)
        XCTAssertNil(result.gapMs)
    }

    /// A long-but-real stall inside one stream is preserved: dropping it would
    /// hide exactly the degradation this metric exists to show.
    func testRealStallBelowGapIsPreserved() {
        let now = Date()
        let result = StreamCommitInterval.classify(
            now: now,
            last: now.addingTimeInterval(-(gap - 0.05)),
            gap: gap
        )
        XCTAssertEqual(result.intervalMs ?? -1, 2_950, accuracy: 5)
        XCTAssertNil(result.gapMs)
    }

    func testFirstCommitHasNoInterval() {
        let result = StreamCommitInterval.classify(now: Date(), last: nil, gap: gap)
        XCTAssertNil(result.intervalMs)
        XCTAssertNil(result.gapMs)
    }
}
