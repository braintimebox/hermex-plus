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

    /// Scope id carried by every request of the current test's session.
    ///
    /// The stub state is process-wide, and delivery is asynchronous: the write
    /// closure of a previous test's request can land after `reset()`. Without a
    /// scope its body becomes "the first batch" of the next test and its reply
    /// steals that test's queued ack — measured as `Optional(20) != Optional(3)`
    /// plus an unconfirmed queue of 3 in `testConfirmedCountBelowBatchKeepsTheRemainder`.
    static let scopeKey = "X-Hermex-Stub-Scope"
    private static var currentScope = UUID().uuidString

    /// Starts a fresh scope for a new test session and clears the stub state.
    @discardableResult
    static func beginScope() -> String {
        lock.lock(); defer { lock.unlock() }
        currentScope = UUID().uuidString
        replies = []
        fallback = Reply()
        receivedBodies = []
        return currentScope
    }

    /// False for a late request from an earlier test: it is answered with an
    /// unconfirmed ack and never touches this test's state.
    private static func isCurrentScope(_ request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request.value(forHTTPHeaderField: scopeKey) == currentScope
    }

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
        // Inside a URLProtocol the body is a stream: URLSession moves httpBody
        // into httpBodyStream before handing the request over, so reading
        // httpBody alone records nothing and every delivery assertion fails.
        let body = request.httpBody ?? request.httpBodyStream.flatMap(drain)
        lock.lock(); defer { lock.unlock() }
        if let body { receivedBodies.append(body) }
    }

    private static func drain(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isCurrent = Self.isCurrentScope(request)
        if isCurrent { Self.record(request) }
        // A foreign request still has to finish, or its logger retries forever.
        let reply = isCurrent ? Self.nextReply()
            : Reply(status: 200, body: Data(#"{"ok":true,"received":0,"stored":0}"#.utf8))

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
    // The scope id rides on every request this session makes, so a late callback
    // from an earlier test's session is recognised as foreign and cannot write
    // into this test's bodies or consume its queued replies.
    config.httpAdditionalHeaders = [StubURLProtocol.scopeKey: StubURLProtocol.beginScope()]
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
    while true {
        if condition() { return true }
        if Date() >= deadline {
            XCTFail("timed out after \(timeout)s waiting for the condition")
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
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
