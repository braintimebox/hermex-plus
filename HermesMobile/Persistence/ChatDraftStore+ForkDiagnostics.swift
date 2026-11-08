import Foundation

// HERMEX-FORK: the draft-lifecycle probe this fork added while chasing the
// composer oscillation. Upstream's ChatDraftStore does not carry it, so it lives
// in its own extension: replacing the store with the newer version keeps the
// diagnostic instead of dropping it on the floor.
extension ChatDraftStore {
        /// HERMEX-FORK: (diagnostic, temporary — remove once the draft lifecycle is proven):
        /// follows one draft text across the lifecycle. Logs the key shape and the text
        /// length so a single string can be tracked from share → composer → send → clear,
        /// and so the suspected resurrection chain (session key → `.newChat(server:)`) is
        /// visible in hermex-logs.jsonl rather than inferred from static reading.
        /// Session identifiers are truncated to 8 characters: enough to correlate events,
        /// not enough to reconstruct the id.
        func logDraftProbe(
            _ point: String,
            key: ChatDraftKey,
            textLength: Int,
            detail: String = "",
            durationMs: Double? = nil
        ) {
            var extras: [String: Any] = [
                "point": point,
                "key": ChatDraftStore.probeLabel(key),
                "len": textLength,
            ]
            if !detail.isEmpty { extras["detail"] = detail }
            // HERMEX-FORK: 3.9.65 — the probe recorded the fact of a write but never
            // its cost: 3 437 `draft setContent` events in 3.9.64 all carried
            // durationMs = 0, so a slow composer write was invisible. The duration is
            // now measured around the write itself and emitted in the same field the
            // rest of the telemetry uses.
            HermexLogger.shared.log(
                type: "draft",
                durationMs: durationMs,
                screen: "ChatDraftStore",
                message: "draft \(point)",
                extras: extras
            )
        }

    /// A short, log-safe label for a draft key: host plus an 8-character id, so a
    /// probe line identifies the draft it followed without reconstructing the id.
    static func probeLabel(_ key: ChatDraftKey) -> String {
        let server = URL(string: key.serverID)?.host ?? "?"
        switch key.context {
        case .session(let sessionID):
            return "session/\(server)/\(sessionID.prefix(8))"
        case .bot(let connectionID, let profile):
            return "bot/\(server)/\(connectionID.uuidString.prefix(8))/\(profile)"
        case .newChat:
            return "newChat/\(server)"
        }
    }
}
