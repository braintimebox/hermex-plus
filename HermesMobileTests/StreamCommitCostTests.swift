// HERMEX-FORK: 3.9.66 — reproducible commit-cost baseline (stage 1).
//
// Measures `StreamCommitMeasurement.measure`, the SAME helper the renderer uses
// for `displayedContent`. What it covers: the synchronous String assignment.
// What it does NOT cover: SwiftUI invalidation, layout and paint — those happen
// after the measured closure returns, so numbers here are commit cost on this
// machine, not frame time and not iPhone behaviour.
//
// No telemetry is emitted: `HermexLogger` / `StreamCommitTelemetry` are never
// touched, so nothing is sent to the production receiver.
//
// Each length is reported separately — results from different scenarios are
// never pooled.

import XCTest

@testable import HermesMobile

final class StreamCommitCostTests: XCTestCase {

    /// Text shaped like a real streaming reply: prose lines plus a code fence,
    /// so the assignment copies a realistic String (not one giant literal).
    private static func makeText(_ length: Int) -> String {
        let unit = "Streaming reply line with some words and punctuation. "
        let fence = "```swift\nlet answer = 42\n```\n"
        var text = ""
        while text.count < length {
            text += unit
            if text.count % 900 < unit.count { text += fence }
        }
        return String(text.prefix(length))
    }

    /// Nearest-rank percentile, identical to `StreamCommitTelemetry.percentile`
    /// so the baseline is computed the same way production aggregates are.
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private struct Result {
        let label: String
        let chars: Int
        let samples: Int
        let median: Double
        let p90: Double
        let p95: Double
        let maxMs: Double
        let mean: Double
    }

    /// Runs one streaming-shaped scenario: text grows in equal increments from
    /// empty to `length`, one measured assignment per step.
    @discardableResult
    private func runScenario(label: String, length: Int, steps: Int) -> Result {
        let full = Self.makeText(length)
        let stepSize = max(1, length / steps)
        var sink = ""
        var samples: [Double] = []
        samples.reserveCapacity(steps)

        var position = 0
        for _ in 0..<steps {
            position = min(length, position + stepSize)
            let slice = String(full.prefix(position))
            let ms = StreamCommitMeasurement.measure { sink = slice }
            samples.append(ms)
        }

        // Keep the assignment observable so the optimiser cannot drop it.
        XCTAssertEqual(sink.count, position, "assignment must have taken effect")

        let sorted = samples.sorted()
        let result = Result(
            label: label,
            chars: length,
            samples: samples.count,
            median: Self.percentile(sorted, 0.50),
            p90: Self.percentile(sorted, 0.90),
            p95: Self.percentile(sorted, 0.95),
            maxMs: sorted.last ?? 0,
            mean: samples.reduce(0, +) / Double(max(samples.count, 1))
        )

        // Machine-readable line for the CI log; one line per scenario.
        let json = String(
            format: #"{"scenario":"%@","chars":%d,"samples":%d,"medianMs":%.4f,"p90Ms":%.4f,"p95Ms":%.4f,"maxMs":%.4f,"meanMs":%.4f}"#,
            result.label, result.chars, result.samples,
            result.median, result.p90, result.p95, result.maxMs, result.mean
        )
        // Two channels, because XCTest does not forward `print` to the
        // xcodebuild log on success: stderr (sometimes surfaced) and a file
        // inside the simulator container, which a CI step locates with find.
        Self.persist(json)
        return result
    }

    /// Appends one machine-readable line to `commit-cost.jsonl`.
    private static func persist(_ line: String) {
        let payload = Data((line + "\n").utf8)
        FileHandle.standardError.write(payload)
        // The app container of a cloned simulator is deleted when the test run
        // ends, so the file has to live somewhere the host still sees afterwards.
        // `SIMULATOR_SHARED_RESOURCES_DIRECTORY` is a host path shared by the
        // simulator; the Documents copy stays as a fallback for local runs.
        var targets: [URL] = []
        if let shared = ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"],
           !shared.isEmpty {
            targets.append(URL(fileURLWithPath: shared).appendingPathComponent("commit-cost.jsonl"))
        }
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            targets.append(dir.appendingPathComponent("commit-cost.jsonl"))
        }
        for url in targets {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(payload)
                try? handle.close()
            } else {
                try? payload.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Baseline scenarios

    func testCommitCostAtTwoThousandChars() {
        runScenario(label: "len2000", length: 2_000, steps: 60)
    }

    func testCommitCostAtFiveThousandChars() {
        runScenario(label: "len5000", length: 5_000, steps: 60)
    }

    func testCommitCostAtTwentyThousandChars() {
        runScenario(label: "len20000", length: 20_000, steps: 60)
    }

    func testCommitCostAtFiftyThousandChars() {
        runScenario(label: "len50000", length: 50_000, steps: 60)
    }

    // MARK: - Growth check (same scenario, two lengths)

    /// Guards the actual claim being investigated: cost grows with length.
    func testCommitCostGrowsLessThanLinearly() {
        let small = runScenario(label: "growth2000", length: 2_000, steps: 40)
        let large = runScenario(label: "growth20000", length: 20_000, steps: 40)
        let ratio = large.median / max(small.median, 0.0001)
        print(String(format: "COMMIT_COST_GROWTH {\"ratio\":%.2f,\"smallMedianMs\":%.4f,\"largeMedianMs\":%.4f}",
                     ratio, small.median, large.median))
        // 10x the text must not cost 10x per assignment for a plain String
        // assignment; if it does, the measured path is not what we think.
        XCTAssertLessThan(ratio, 10.0, "per-assignment cost should not scale linearly with length")
    }

    // MARK: - XCTest measure (infrastructure-standard metric)

    /// Standard XCTest measurement over one length, so the baseline is also
    /// comparable with future `measure {}` runs. Percentiles above are the
    /// primary artifact; this is the infrastructure-native cross-check.
    func testCommitCostMeasureFiveThousandChars() {
        let full = Self.makeText(5_000)
        var sink = ""
        measure {
            var position = 0
            for _ in 0..<40 {
                position = min(full.count, position + 125)
                let slice = String(full.prefix(position))
                _ = StreamCommitMeasurement.measure { sink = slice }
            }
        }
        XCTAssertEqual(sink.count, 5_000)
    }
}
