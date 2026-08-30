import Foundation
import LDSwiftEventSource

enum KanbanStreamFrame: Equatable, Sendable {
    case hello(cursor: Int, board: String)
    case events(events: [KanbanEvent], cursor: Int, frameID: Int?)
    case ignored
    case malformed
}

enum KanbanStreamFrameDecoder {
    static func decode(eventType: String, data: String, frameID: String?) -> KanbanStreamFrame {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch eventType {
        case "hello":
            guard let payload = try? decoder.decode(Hello.self, from: Data(data.utf8)),
                  let cursor = payload.cursor,
                  cursor >= 0,
                  let board = normalized(payload.board) else {
                return .malformed
            }
            return .hello(cursor: cursor, board: board)
        case "events":
            guard let payload = try? decoder.decode(Events.self, from: Data(data.utf8)),
                  let events = payload.events,
                  let cursor = payload.cursor,
                  cursor >= 0 else {
                return .malformed
            }
            let parsedFrameID = frameID.flatMap(Int.init)
            guard frameID == nil || parsedFrameID != nil else { return .malformed }
            return .events(events: events, cursor: cursor, frameID: parsedFrameID)
        default:
            return .ignored
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct Hello: Decodable {
        let cursor: Int?
        let board: String?
    }

    private struct Events: Decodable {
        let events: [KanbanEvent]?
        let cursor: Int?
    }
}

@MainActor
protocol KanbanEventStreamingClient: AnyObject {
    func start(
        url: URL,
        onFrame: @escaping @MainActor (KanbanStreamFrame) -> Void,
        onFailure: @escaping @MainActor () -> Void
    )
    func stop()
}

@MainActor
final class KanbanEventStreamClient: KanbanEventStreamingClient {
    private let baseConfiguration: URLSessionConfiguration
    private let customHeaderProvider: @MainActor () -> [CustomHeader]
    private var eventSource: EventSource?

    init(
        urlSessionConfiguration: URLSessionConfiguration = .default,
        customHeaderProvider: @escaping @MainActor () -> [CustomHeader] = { CustomHeaderStore.shared.snapshot() }
    ) {
        baseConfiguration = urlSessionConfiguration
        self.customHeaderProvider = customHeaderProvider
    }

    func start(
        url: URL,
        onFrame: @escaping @MainActor (KanbanStreamFrame) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        stop()
        let handler = Handler(onFrame: onFrame, onFailure: onFailure)
        var config = EventSource.Config(handler: handler, url: url)
        // Same reconnect policy as the chat SSE client (F5, v3.2.1): the old
        // `{ _ in .shutdown }` disabled LDSwiftEventSource's built-in exponential
        // backoff — ANY transient TCP/HTTP failure (host sleep, network switch,
        // tunnel blip) killed the Kanban stream for good and the board silently
        // froze (stale data until the section is reopened). `.proceed` reconnects
        // with backoff; permanent client/HTTP errors (4xx) stop reconnecting so
        // the stream surfaces the failure. (3.4.1)
        config.connectionErrorHandler = { error in
            if let http = error as? UnsuccessfulResponseError,
               (400..<500).contains(http.responseCode) {
                return .shutdown
            }
            return .proceed
        }
        config.reconnectTime = 1.0
        config.maxReconnectTime = 30.0
        config.backoffResetThreshold = 60.0
        config.headers = customHeaderProvider().merged(under: [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache, no-transform",
            "Accept-Encoding": "identity"
        ])

        let configuration = baseConfiguration.copy() as? URLSessionConfiguration ?? .default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlSessionConfiguration = configuration

        let source = EventSource(config: config)
        eventSource = source
        source.start()
    }

    func stop() {
        eventSource?.stop()
        eventSource = nil
    }

    private final class Handler: EventHandler {
        private let onFrame: @MainActor (KanbanStreamFrame) -> Void
        private let onFailure: @MainActor () -> Void

        init(
            onFrame: @escaping @MainActor (KanbanStreamFrame) -> Void,
            onFailure: @escaping @MainActor () -> Void
        ) {
            self.onFrame = onFrame
            self.onFailure = onFailure
        }

        func onOpened() {}
        func onClosed() {
            Task { @MainActor in onFailure() }
        }
        func onComment(comment: String) {}

        func onMessage(eventType: String, messageEvent: MessageEvent) {
            let frame = KanbanStreamFrameDecoder.decode(
                eventType: eventType,
                data: messageEvent.data,
                frameID: messageEvent.lastEventId.nilIfEmpty
            )
            Task { @MainActor in onFrame(frame) }
        }

        func onError(error: Error) {
            // Never include the transport error or event payload in logs.
            Task { @MainActor in onFailure() }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
