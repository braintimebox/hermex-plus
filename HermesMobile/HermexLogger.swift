import Foundation

/// Sends Hermex Plus diagnostics (freezes, errors, lifecycle events) to the
/// Hermes server's log ingest endpoint (`/webhook/hermex-logs` → proxy → :8912).
///
/// Fire-and-forget, never blocks UI: all work happens on a private utility
/// queue. Events are batched (up to 20 per POST) so a noisy stream doesn't
/// spam the server. The server URL is read from the Keychain at send time —
/// no configuration step needed, live server edits just work.
final class HermexLogger {
    static let shared = HermexLogger()

    private let queue = DispatchQueue(label: "hermex.logger", qos: .utility)
    private var buffer: [[String: Any]] = []
    private let maxBatch = 20

    private init() {}

    /// Enqueue a diagnostic event. Never throws, never crashes.
    func log(
        type: String,
        durationMs: Double? = nil,
        screen: String? = nil,
        message: String
    ) {
        queue.async { [self] in
            var event: [String: Any] = [
                "type": type,
                "ts": Date().timeIntervalSince1970,
                "message": message,
            ]
            if let durationMs { event["durationMs"] = durationMs }
            if let screen { event["screen"] = screen }
            buffer.append(event)
            flushIfNeeded()
        }
    }

    /// Read the configured server URL from the Keychain (same source the app
    /// uses for all API traffic). Synchronous + cheap — fine on a utility queue.
    private var serverBaseURL: URL? {
        guard let urlString = try? KeychainStore().load(.serverURL) else { return nil }
        return URL(string: urlString)
    }

    private func flushIfNeeded() {
        guard !buffer.isEmpty, let baseURL = serverBaseURL else { return }
        let batch = Array(buffer.prefix(maxBatch))
        buffer.removeFirst(batch.count)
        send(batch, to: baseURL)
    }

    private func send(_ events: [[String: Any]], to baseURL: URL) {
        let webhook = baseURL.appendingPathComponent("webhook/hermex-logs")
        var request = URLRequest(url: webhook)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: events)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
