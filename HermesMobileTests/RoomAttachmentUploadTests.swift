import XCTest
@testable import HermesMobile

final class RoomAttachmentUploadTests: XCTestCase {
    func testLimitMatchesTheGatewayConstant() {
        // session_rules/hosted_attachments.py:17 · gateway/session_hosted_attachments.py:53
        XCTAssertEqual(RoomAttachmentLimit.bytes, 15_000_000)
        XCTAssertEqual(RoomAttachmentLimit.encodedCharacters, 20_000_000)
    }

    func testPayloadCarriesTheSixContractFields() throws {
        let upload = try RoomAttachmentUpload(data: Data([1, 2, 3]), name: "a.txt", mime: "text/plain")
        XCTAssertEqual(
            Set(upload.params.keys),
            ["upload_id", "kind", "name", "mime", "data_base64"]
        )
        XCTAssertFalse(upload.uploadID.isEmpty)
        XCTAssertEqual(upload.dataBase64, Data([1, 2, 3]).base64EncodedString())
    }

    func testKindIsDerivedSoTheGatewayNeverHasToRefuseIt() throws {
        // hosted_room_attachments.py:95-106 — an image MIME declared as `file` is refused.
        XCTAssertEqual(RoomAttachmentUpload.kind(forMIME: "image/PNG"), "image")
        XCTAssertEqual(RoomAttachmentUpload.kind(forMIME: "application/pdf"), "pdf")
        XCTAssertEqual(RoomAttachmentUpload.kind(forMIME: "text/plain"), "file")
        XCTAssertEqual(RoomAttachmentUpload.kind(forMIME: "video/quicktime"), "file")

        let photo = try RoomAttachmentUpload(data: Data([0x89]), name: "p.png", mime: "image/png")
        XCTAssertEqual(photo.kind, "image")
        XCTAssertEqual(photo.params["kind"], "image")
    }

    func testAFileAtTheLimitIsAcceptedAndOneByteOverIsRefusedWithItsSize() throws {
        let atLimit = Data(repeating: 7, count: RoomAttachmentLimit.bytes)
        XCTAssertNoThrow(try RoomAttachmentUpload(data: atLimit, name: "edge.mov", mime: "video/quicktime"))

        let overLimit = Data(repeating: 7, count: RoomAttachmentLimit.bytes + 1)
        XCTAssertThrowsError(try RoomAttachmentUpload(data: overLimit, name: "big.mov", mime: "video/quicktime")) { error in
            guard case let RoomAttachmentFailure.tooLarge(name, bytes, limit) = error else {
                return XCTFail("expected a size refusal, got \(error)")
            }
            XCTAssertEqual(name, "big.mov")
            XCTAssertEqual(bytes, RoomAttachmentLimit.bytes + 1)
            XCTAssertEqual(limit, RoomAttachmentLimit.bytes)
            // The message has to name the file and the ceiling, not just "too large".
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(text.contains("big.mov"), text)
            XCTAssertFalse(text.isEmpty)
        }
    }

    func testEmptyFileIsRefusedByName() {
        XCTAssertThrowsError(try RoomAttachmentUpload(data: Data(), name: "nothing.txt", mime: "text/plain")) { error in
            XCTAssertEqual(error as? RoomAttachmentFailure, .empty(name: "nothing.txt"))
        }
    }

    func testReadingAFileStopsAtTheLimitInsteadOfLoadingEverything() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let name = "over.bin"
        let url = directory.appendingPathComponent(name)
        let payload = Data(repeating: 3, count: RoomAttachmentLimit.bytes + 4096)
        try payload.write(to: url)

        XCTAssertThrowsError(try RoomAttachmentUpload(contentsOf: url)) { error in
            guard case let RoomAttachmentFailure.tooLarge(readName, bytes, _) = error else {
                return XCTFail("expected a size refusal, got \(error)")
            }
            XCTAssertEqual(readName, name)
            // Read is bounded: one byte past the limit is enough to know it is too big.
            XCTAssertEqual(bytes, RoomAttachmentLimit.bytes + 1)
        }
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func file(in directory: URL, named name: String, bytes: Int) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 9, count: bytes).write(to: url)
        return url
    }

    func testReadingAMissingFileSaysSoInsteadOfCrashing() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        XCTAssertThrowsError(try RoomAttachmentUpload(contentsOf: url)) { error in
            guard case RoomAttachmentFailure.unreadable = error else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }
    }

    func testEightThreeMegabyteFilesFitAndTheNinthIsRefusedByName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var budget = RoomAttachmentBudget()
        for index in 1...8 {
            try budget.add(contentsOf: try file(in: directory, named: "f\(index).bin", bytes: 3_000_000))
        }
        XCTAssertEqual(budget.uploads.count, 8)
        XCTAssertEqual(budget.byteCount, 24_000_000)
        XCTAssertEqual(budget.remainingFiles, 0)

        XCTAssertThrowsError(try budget.add(contentsOf: try file(in: directory, named: "f9.bin", bytes: 10))) { error in
            guard case let RoomAttachmentFailure.tooManyFiles(name, limit) = error else {
                return XCTFail("expected a count refusal, got \(error)")
            }
            XCTAssertEqual(name, "f9.bin")
            XCTAssertEqual(limit, RoomAttachmentLimit.filesPerMessage)
        }
        // A refusal leaves the selection exactly as it was.
        XCTAssertEqual(budget.uploads.count, 8)
    }

    func testTwoFifteenMegabyteFilesAreRefusedOnTheSecondWithTheRemainder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var budget = RoomAttachmentBudget()
        try budget.add(contentsOf: try file(in: directory, named: "a.mov", bytes: RoomAttachmentLimit.bytes))
        XCTAssertEqual(budget.remainingBytes, RoomAttachmentLimit.messageBytes - RoomAttachmentLimit.bytes)

        // The second file passes the per-file limit and fails the message budget —
        // the case a per-file check alone would let through to `groups.send`.
        XCTAssertThrowsError(try budget.add(contentsOf: try file(in: directory, named: "b.mov", bytes: RoomAttachmentLimit.bytes))) { error in
            guard case let RoomAttachmentFailure.exceedsMessageBudget(name, bytes, remaining) = error else {
                return XCTFail("expected a message-budget refusal, got \(error)")
            }
            XCTAssertEqual(name, "b.mov")
            XCTAssertEqual(bytes, RoomAttachmentLimit.bytes)
            XCTAssertEqual(remaining, RoomAttachmentLimit.messageBytes - RoomAttachmentLimit.bytes)
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(text.contains("b.mov"), text)
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertEqual(budget.uploads.count, 1, "a refused file must not be queued")
        XCTAssertEqual(budget.byteCount, RoomAttachmentLimit.bytes)
    }

    func testTheBudgetIsCheckedBeforeAnyUploadSoNothingIsOrphaned() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var budget = RoomAttachmentBudget()
        for index in 1...8 {
            try budget.add(contentsOf: try file(in: directory, named: "ok\(index).bin", bytes: 3_000_000))
        }
        let before = budget.uploads

        XCTAssertThrowsError(try budget.add(contentsOf: try file(in: directory, named: "extra.bin", bytes: 1)))
        XCTAssertEqual(budget.uploads, before)
        XCTAssertEqual(Set(budget.uploads.map(\.uploadID)).count, 8)
    }

    func testTheUploadIDMatchesTheGatewaysIdentifierRule() {
        // ^[A-Za-z0-9][A-Za-z0-9._:-]*$ — a hyphen is not allowed, and a dashed UUID would
        // be refused as invalid_params on every upload.
        let id = RoomAttachmentUpload.makeUploadID()
        XCTAssertFalse(id.contains("-"), id)
        XCTAssertTrue(id.allSatisfy { $0.isHexDigit }, id)
        XCTAssertNotNil(id.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]*$", options: .regularExpression), id)
    }

    func testMIMEIsNamedForTheExtensionsAComposerActuallySees() {
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.HEIC")), "image/heic")
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.pdf")), "application/pdf")
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.unknown")), "application/octet-stream")
    }
}
