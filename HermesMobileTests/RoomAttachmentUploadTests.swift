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

    func testReadingAMissingFileSaysSoInsteadOfCrashing() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        XCTAssertThrowsError(try RoomAttachmentUpload(contentsOf: url)) { error in
            guard case RoomAttachmentFailure.unreadable = error else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }
    }

    func testMIMEIsNamedForTheExtensionsAComposerActuallySees() {
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.HEIC")), "image/heic")
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.pdf")), "application/pdf")
        XCTAssertEqual(RoomAttachmentUpload.mime(for: URL(fileURLWithPath: "a.unknown")), "application/octet-stream")
    }
}
