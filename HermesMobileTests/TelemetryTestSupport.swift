import XCTest
@testable import HermesMobile

/// A URLProtocol subclass standing in for the ingest server, so delivery
/// behaviour (acks, 5xx, 429, lost responses) is testable without a server.
final class StubURLProtocol: URLProtocol {

    /// A canned reply. `error` wins over `status/body` when set.
    struct Reply {
        var status: Int = 200
        var body: Data? = Data(#"{"ok":true,"received":1,"stored":1}"#.utf8)
        var headers: [String: String] = [:]
        var error: Error?
        var delay: TimeInterval = 0
    }

    /// Queue of replies, consumed in order. When empty, `fallback` is used.
    static var replies: [Reply] = []
    static var fallback = Reply()
    /// Bodies of every request the logger made, in order.
    static var receivedBodies: [Data] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        replies = []
        fallback = Reply()
        receivedBodies = []
    }

    /// Number of events the logger posted, counted from the request bodies.
    static var receivedEventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedBodies.reduce(0) { total, body in
            guard let array = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
                return total
            }
            return total + array.count
        }
    }

    /// `correlationId:seqNo` keys seen by the "server", in order — lets a test
    /// assert that a retry reused the original identifiers.
    static var receivedKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        var keys: [String] = []
        for body in receivedBodies {
            guard let array = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
                continue
            }
            for event in array {
                if let cid = event["correlationId"] as? String,
                   let seq = event["seqNo"] as? Int {
                    keys.append("\(cid):\(seq)")
                }
            }
        }
        return keys
    }

    static func enqueue(_ reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies.append(reply)
    }

    private static func nextReply() -> Reply {
        lock.lock(); defer { lock.unlock() }
        if replies.isEmpty { return fallback }
        return replies.removeFirst()
    }

    private static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        if let body = request.httpBody { receivedBodies.append(body) }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request)
        let reply = Self.nextReply()

        let deliver = { [weak self] in
            guard let self else { return }
            if let error = reply.error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let http = HTTPURLResponse(url: self.request.url!,
                                       statusCode: reply.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            if let body = reply.body { self.client?.urlProtocol(self, didLoad: body) }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

/// A session wired to `StubURLProtocol` only.
func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

/// Minimal JSON ack body the server contract produces.
func ackBody(received: Int, stored: Int) -> Data {
    Data(#"{"ok":true,"received":\#(received),"stored":\#(stored),"batchId":"test"}"#.utf8)
}

/// Wait until `condition` holds, polling the main runloop. Delivery is async
/// (URLSession callback → logger queue), so tests cannot assume completion.
@discardableResult
func waitUntil(timeout: TimeInterval = 5,
               _ condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

/// Per-test temporary directory for the queue file, removed on teardown.
final class TempQueueFile {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("pending-events.jsonl") }

    init(name: String = UUID().uuidString) {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hermex-queue-tests-\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Raw contents, to simulate a torn write or corruption.
    func writeRaw(_ text: String) {
        try? Data(text.utf8).write(to: fileURL)
    }

    func readRaw() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}
