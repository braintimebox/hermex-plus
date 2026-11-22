import XCTest
@testable import HermesMobile

@MainActor
final class ConnectionLogTests: XCTestCase {
    func testTheNewestEntryComesFirst() {
        let log = ConnectionLog()
        log.record(.attempt, address: "https://a:8443", detail: "username one", at: Date(timeIntervalSince1970: 1))
        log.record(.refused, address: "https://a:8443", detail: "invalid credentials", at: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.first?.kind, .refused)
        XCTAssertEqual(log.entries.last?.kind, .attempt)
    }

    func testTheBufferIsBoundedSoTheScreenStaysInstant() {
        let log = ConnectionLog()
        for index in 0..<(ConnectionLog.limit + 20) {
            log.record(.attempt, address: "https://a:8443", detail: "attempt \(index)")
        }
        XCTAssertEqual(log.entries.count, ConnectionLog.limit)
        XCTAssertEqual(log.entries.first?.detail, "attempt \(ConnectionLog.limit + 19)")
    }

    func testTheTranscriptCarriesTheReasonNotJustTheAddress() {
        let log = ConnectionLog()
        log.record(.refused, address: "https://hermes00.duckdns.org:8443", detail: "invalid credentials")
        let transcript = log.transcript
        XCTAssertTrue(transcript.contains("hermes00.duckdns.org"))
        XCTAssertTrue(transcript.contains("invalid credentials"))
        XCTAssertTrue(transcript.contains("Refused"))
    }

    func testClearingLeavesNothingToCopy() {
        let log = ConnectionLog()
        log.record(.connected, address: "https://a:8443", detail: "connected")
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertEqual(log.transcript, "")
    }
}
