import Foundation

/// HERMEX-FORK: 3.9.65 — decides whether a failed scheduled send is retried.
///
/// WHY THIS IS A SEPARATE TYPE: the decision is the whole fix for the infinite
/// retry loop, and it must be testable without SwiftData, a network client or a
/// 68-hour wait. 3.9.64 computed `retryable` in `DeliveryFailure.classify` and
/// then ignored it: one message produced 620 requests over 68 hours because
/// every failure took the same `continue` path.
///
/// Rules:
///   * non-retryable → terminal immediately (repeating it cannot help and may
///     duplicate a side effect);
///   * retryable → retry, but only up to `maxAttempts`, so no error class can
///     keep a message in flight forever;
///   * terminal reasons stay distinguishable (`retryLimit` vs the actual reason).
enum ScheduledDeliveryPolicy {

    /// Attempts allowed for a retryable error before the message is closed.
    static let maxAttempts = 5

    enum Outcome: Equatable {
        case retry(attempt: Int)
        case terminal(reason: String)

        var isTerminal: Bool {
            if case .terminal = self { return true }
            return false
        }
    }

    /// - Parameters:
    ///   - retryable: from `DeliveryFailure.classify` — whether repeating the
    ///     request can plausibly succeed without duplicating a side effect.
    ///   - reason: `DeliveryReason.rawValue` of this attempt.
    ///   - failedAttempts: attempts recorded BEFORE this one.
    static func outcome(retryable: Bool, reason: String, failedAttempts: Int) -> Outcome {
        let attempt = failedAttempts + 1
        if !retryable { return .terminal(reason: reason) }
        if attempt >= maxAttempts { return .terminal(reason: "retryLimit") }
        return .retry(attempt: attempt)
    }
}
