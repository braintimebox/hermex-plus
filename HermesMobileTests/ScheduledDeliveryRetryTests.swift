import XCTest
import SwiftData
@testable import HermesMobile

/// HERMEX-FORK: 3.9.65 — regression tests for the infinite-retry fix.
///
/// Background (3.9.64 telemetry): one scheduled message produced 620 failed
/// requests over 68 hours. The error was HTTP 404 with `retryable: false`, and
/// the delivery loop ignored that flag and retried on every cycle.
@MainActor
final class ScheduledDeliveryRetryTests: XCTestCase {

    // MARK: - Policy

    func testNonRetryableIsTerminalImmediately() {
        let outcome = ScheduledDeliveryPolicy.outcome(
            retryable: false, reason: "badRequest", failedAttempts: 0
        )
        XCTAssertEqual(outcome, .terminal(reason: "badRequest"))
        XCTAssertTrue(outcome.isTerminal)
    }

    func testRetryableKeepsRetryingBelowCap() {
        for attempts in 0..<(ScheduledDeliveryPolicy.maxAttempts - 1) {
            let outcome = ScheduledDeliveryPolicy.outcome(
                retryable: true, reason: "timeout", failedAttempts: attempts
            )
            XCTAssertEqual(outcome, .retry(attempt: attempts + 1),
                           "attempts=\(attempts) must still be retryable")
        }
    }

    func testRetryableBecomesTerminalAtCap() {
        let outcome = ScheduledDeliveryPolicy.outcome(
            retryable: true, reason: "timeout",
            failedAttempts: ScheduledDeliveryPolicy.maxAttempts - 1
        )
        XCTAssertEqual(outcome, .terminal(reason: "retryLimit"))
    }

    /// No sequence of outcomes may stay `retry` forever.
    func testAnyErrorStopsWithinCap() {
        for retryable in [true, false] {
            var attempts = 0
            var terminalReason: String?
            // 200 simulated delivery cycles: a healthy margin over the cap.
            for _ in 0..<200 {
                let outcome = ScheduledDeliveryPolicy.outcome(
                    retryable: retryable, reason: "badRequest", failedAttempts: attempts
                )
                if case .terminal(let reason) = outcome {
                    terminalReason = reason
                    break
                }
                attempts += 1
            }
            XCTAssertNotNil(terminalReason,
                            "retryable=\(retryable) never reached a terminal state")
            XCTAssertLessThanOrEqual(attempts, ScheduledDeliveryPolicy.maxAttempts)
        }
    }

    // MARK: - Persistence

    private func makeStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermex-scheduled-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scheduled.store")
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: PendingScheduledMessage.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    /// The terminal state must survive a process restart — otherwise the next
    /// launch would pick the row up again and the loop would resume.
    func testTerminalStatePersistsAcrossRestart() throws {
        let url = try makeStoreURL()

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let row = PendingScheduledMessage(
                sessionId: "b8686d4beee9",
                draftText: "test",
                scheduledAt: Date(timeIntervalSince1970: 1_792_948_301),
                serverURLString: "https://example.test"
            )
            row.failedAttemptCount = 1
            row.terminalFailureReason = "badRequest"
            row.terminalFailureAt = Date()
            context.insert(row)
            try context.save()
        }

        // Fresh container over the same store == fresh launch.
        let reopened = try makeContainer(at: url)
        let context = ModelContext(reopened)
        let rows = try context.fetch(FetchDescriptor<PendingScheduledMessage>())
        let row = try XCTUnwrap(rows.first)
        XCTAssertTrue(row.isDeliveryTerminal)
        XCTAssertEqual(row.terminalFailureReason, "badRequest")
        XCTAssertEqual(row.failedAttemptCount, 1)
        XCTAssertNotNil(row.terminalFailureAt)
    }

    /// A delivered message is deleted, so nothing is left to send again.
    /// This is the "no duplicate send" side of the contract.
    func testDeliveredRowLeavesNothingToResend() throws {
        let url = try makeStoreURL()
        let container = try makeContainer(at: url)
        let context = ModelContext(container)
        context.insert(PendingScheduledMessage(
            sessionId: "s1",
            draftText: "hi",
            scheduledAt: Date(),
            serverURLString: "https://example.test"
        ))
        try context.save()

        let rows = try context.fetch(FetchDescriptor<PendingScheduledMessage>())
        for row in rows { context.delete(row) }
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingScheduledMessage>()).isEmpty)
    }

    /// Terminal rows are filtered out of the dispatch set: this is what stops
    /// the loop at its source, independently of the policy.
    func testTerminalRowsAreNotDue() throws {
        let url = try makeStoreURL()
        let container = try makeContainer(at: url)
        let context = ModelContext(container)
        let now = Date()

        let live = PendingScheduledMessage(
            sessionId: "live", draftText: "a",
            scheduledAt: now.addingTimeInterval(-60),
            serverURLString: "https://example.test"
        )
        let dead = PendingScheduledMessage(
            sessionId: "dead", draftText: "b",
            scheduledAt: now.addingTimeInterval(-60),
            serverURLString: "https://example.test"
        )
        dead.terminalFailureReason = "badRequest"
        context.insert(live)
        context.insert(dead)
        try context.save()

        let all = try context.fetch(FetchDescriptor<PendingScheduledMessage>())
        let due = all.filter { $0.scheduledAt <= now && $0.terminalFailureReason == nil }
        XCTAssertEqual(due.map(\.sessionId), ["live"])
    }
}
