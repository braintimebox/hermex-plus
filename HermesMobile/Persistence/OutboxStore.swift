import Foundation
import Network

/// A message the user sent that has not reached the server yet.
///
/// `id` is the same value sent as `clientMessageId`, and it is created once, at
/// the moment the user presses send. Every retry — the three inline attempts and
/// any later resend from this queue — carries it, so the server can recognise a
/// repeat and replay the first turn instead of creating a second message.
struct OutboxMessage: Codable, Identifiable, Equatable {
    let id: String
    let sessionID: String
    /// What the transcript shows for this bubble.
    let displayContent: String
    /// What the API receives (may carry composer directives the display omits).
    let text: String
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let profile: String?
    let explicitModelPick: Bool
    let attachments: [JSONValue]?
    let createdAt: Date
    var attempts: Int
    var nextAttemptAt: Date
    var lastFailureReason: String?

    var isReady: Bool { nextAttemptAt <= Date() }
}

/// Durable queue of sends that did not reach the server.
///
/// One owner for the outgoing message. The contract is: once a send lands here,
/// the app owns it and will deliver it without the user doing anything. The
/// composer keeps no copy — the text left the composer when the user pressed
/// send, and a second copy in two places is exactly what made a failed send
/// reappear as a draft.
///
/// Persistence is a single JSON file written atomically. Losing it costs at most
/// the sends that were still queued, never a delivered message.
actor OutboxStore {
    static let shared = OutboxStore()

    private var messages: [OutboxMessage] = []
    private var didLoad = false
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("HermexOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("outbox.json")
    }

    // MARK: - Queue

    /// Adds a message, replacing any earlier entry with the same id. Replacing
    /// rather than appending matters: a repeated press must not queue twice.
    func enqueue(_ message: OutboxMessage) {
        loadIfNeeded()
        messages.removeAll { $0.id == message.id }
        messages.append(message)
        persist()
    }

    func pending() -> [OutboxMessage] {
        loadIfNeeded()
        return messages
    }

    func ready() -> [OutboxMessage] {
        loadIfNeeded()
        return messages.filter(\.isReady)
    }

    func message(id: String) -> OutboxMessage? {
        loadIfNeeded()
        return messages.first { $0.id == id }
    }

    func remove(id: String) {
        loadIfNeeded()
        let before = messages.count
        messages.removeAll { $0.id == id }
        if messages.count != before { persist() }
    }

    /// Records a failed attempt and schedules the next one with exponential
    /// backoff, capped so a long outage still retries every couple of minutes.
    func markFailed(id: String, reason: String) {
        loadIfNeeded()
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].attempts += 1
        messages[index].lastFailureReason = reason
        let delay = min(120, 5 * pow(2, Double(max(0, messages[index].attempts - 1))))
        messages[index].nextAttemptAt = Date().addingTimeInterval(delay)
        persist()
    }

    func clear() {
        loadIfNeeded()
        guard !messages.isEmpty else { return }
        messages = []
        persist()
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([OutboxMessage].self, from: data) else {
            // A corrupt file must not wedge sending forever: keep no messages
            // rather than crash, and let the next send rewrite the file.
            return
        }
        messages = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Drives the queue: retries on a timer while the app runs, and immediately
/// when the network path becomes usable.
///
/// It owns no per-message state of its own; `OutboxStore` is the single source
/// of truth, so a retry from the timer and a retry triggered by the network
/// monitor cannot disagree about what is still pending.
@MainActor
final class OutboxSender {
    static let shared = OutboxSender()

    /// Called after a message is accepted by the server, so the chat can reload
    /// the transcript and drop the "waiting" bubble.
    var onDelivered: ((String) -> Void)?

    private var send: ((OutboxMessage) async throws -> Void)?
    private var timerTask: Task<Void, Never>?
    private var isDraining = false
    private let monitor = NWPathMonitor()
    private var monitorStarted = false

    private init() {}

    /// `send` performs the actual request. Kept as a closure so this type does
    /// not need to know about `APIClient`, `APIClient+Chat`, or the view model.
    func start(send: @escaping (OutboxMessage) async throws -> Void) {
        self.send = send
        startMonitorIfNeeded()
        startTimerIfNeeded()
        Task { await drain() }
    }

    /// Used when the app knows the situation changed (chat opened, send failed).
    func kick() {
        Task { await drain() }
    }

    private func startMonitorIfNeeded() {
        guard !monitorStarted else { return }
        monitorStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                // The path just became usable: the queued message is likely to
                // go through now, and waiting for the next timer tick would be
                // an avoidable delay.
                await self?.drain()
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.hermex.outbox.path"))
    }

    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.drain()
            }
        }
    }

    /// Sends every message whose backoff has elapsed. Re-entrancy is guarded:
    /// the timer, the path monitor and an explicit kick can all land at once.
    private func drain() async {
        guard !isDraining, let send else { return }
        isDraining = true
        defer { isDraining = false }

        // Oldest first: the transcript should fill in the order the user typed.
        let ready = await OutboxStore.shared.ready().sorted { $0.createdAt < $1.createdAt }
        for message in ready {
            do {
                try await send(message)
                await OutboxStore.shared.remove(id: message.id)
                onDelivered?(message.id)
            } catch {
                let reason = (error as? APIError)?.privacySafeLogCategory
                    ?? String(describing: type(of: error))
                await OutboxStore.shared.markFailed(id: message.id, reason: reason)
                // A failure that is not about connectivity means this message
                // will not deliver by retrying (bad request, auth, refused).
                // Stop the pass instead of hammering the server with the rest.
                if let apiError = error as? APIError, !apiError.isIdempotentRetryCandidate {
                    break
                }
            }
        }
    }
}
