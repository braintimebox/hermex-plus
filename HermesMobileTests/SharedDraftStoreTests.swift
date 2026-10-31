// HERMEX-FORK: `UIPasteboard` is needed to exercise the fallback share
// transport (the App Group path needs no UIKit types in these assertions).
import UIKit
import XCTest
@testable import HermesMobile

final class SharedDraftStoreTests: XCTestCase {
    func testDraftTextCombinesTextAndURLsInOrder() {
        let draft = HermesShareDraft.draftText(
            textSnippets: [
                "  Summarize this page  ",
                "\nSummarize this page\n",
                "Key quote",
                "https://example.com/article"
            ],
            urls: [
                URL(string: "https://example.com/article")!,
                URL(string: "https://example.com/article")!,
                URL(string: "https://example.com/notes")!
            ]
        )

        XCTAssertEqual(
            draft,
            """
            Summarize this page

            Key quote

            https://example.com/article

            https://example.com/notes
            """
        )
    }

    func testDraftTextIgnoresEmptyInput() {
        let draft = HermesShareDraft.draftText(textSnippets: [" \n\t "], urls: [])

        XCTAssertEqual(draft, "")
    }

    func testComposerDraftAddsTrailingNewlineForFollowupInput() {
        XCTAssertEqual(
            HermesShareDraft.composerDraft(from: "  https://example.com/article  "),
            "https://example.com/article\n"
        )
        XCTAssertEqual(HermesShareDraft.composerDraft(from: " \n\t "), "")
    }

    func testShareOpenURLRecognizesOnlyHermesShareLinks() {
        let scheme = HermesShareDraft.urlScheme

        XCTAssertTrue(HermesShareDraft.isShareOpenURL(URL(string: "\(scheme)://share")!))
        XCTAssertFalse(HermesShareDraft.isShareOpenURL(URL(string: "\(scheme)://settings")!))
        XCTAssertFalse(HermesShareDraft.isShareOpenURL(URL(string: "https://example.com/share")!))
    }

    func testPendingDraftStorageLoadsAndClearsDraft() throws {
        let directory = try temporaryDirectory()

        try HermesShareDraft.savePendingDraft(
            "  Draft from Safari  ",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let draft = try HermesShareDraft.loadPendingDraft(from: directory)
        XCTAssertEqual(draft, "Draft from Safari")
        XCTAssertNil(try HermesShareDraft.loadPendingDraft(from: directory))
    }

    func testPendingImportStorageLoadsAttachmentAndClearsStagedFiles() throws {
        let directory = try temporaryDirectory()
        let attachmentData = Data("pdf bytes".utf8)

        try HermesShareDraft.savePendingImport(
            draft: "  Review this  ",
            attachments: [
                SharedAttachmentImport(
                    filename: "/private/tmp/report.pdf",
                    typeIdentifier: "com.adobe.pdf",
                    data: attachmentData
                )
            ],
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_001)
        )

        let sharedImport = try XCTUnwrap(try HermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "Review this")
        XCTAssertEqual(sharedImport.attachments.count, 1)
        XCTAssertEqual(sharedImport.attachments.first?.filename, "report.pdf")
        XCTAssertEqual(sharedImport.attachments.first?.typeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(sharedImport.attachments.first?.data, attachmentData)
        XCTAssertNil(try HermesShareDraft.loadPendingImport(from: directory))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(HermesShareDraft.pendingAttachmentsDirectoryName).path
            )
        )
    }

    func testPendingImportSupportsAttachmentOnlyShare() throws {
        let directory = try temporaryDirectory()

        try HermesShareDraft.savePendingImport(
            draft: " \n ",
            attachments: [
                SharedAttachmentImport(
                    filename: "photo.jpg",
                    typeIdentifier: "public.jpeg",
                    data: Data([0x01, 0x02, 0x03])
                )
            ],
            in: directory
        )

        let sharedImport = try XCTUnwrap(try HermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "")
        XCTAssertEqual(sharedImport.attachments.first?.filename, "photo.jpg")
        XCTAssertEqual(sharedImport.attachments.first?.data, Data([0x01, 0x02, 0x03]))
    }

    func testPendingImportKeepsMultipleUploadableAttachments() throws {
        let directory = try temporaryDirectory()

        try HermesShareDraft.savePendingImport(
            draft: "",
            attachments: [
                SharedAttachmentImport(
                    filename: "first.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("first".utf8)
                ),
                SharedAttachmentImport(
                    filename: "second.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("second".utf8)
                )
            ],
            in: directory
        )

        let sharedImport = try XCTUnwrap(try HermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.attachments.map(\.filename), ["first.txt", "second.txt"])
        XCTAssertEqual(sharedImport.attachments.map(\.data), [Data("first".utf8), Data("second".utf8)])
    }

    func testPendingImportCapsAttachmentsAtSharedLimit() throws {
        let directory = try temporaryDirectory()
        let attachments = (0..<(HermesShareDraft.maximumSharedAttachmentCount + 1)).map { index in
            SharedAttachmentImport(
                filename: "file-\(index).txt",
                typeIdentifier: "public.plain-text",
                data: Data("file-\(index)".utf8)
            )
        }

        try HermesShareDraft.savePendingImport(
            draft: "",
            attachments: attachments,
            in: directory
        )

        let sharedImport = try XCTUnwrap(try HermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.attachments.count, HermesShareDraft.maximumSharedAttachmentCount)
        XCTAssertEqual(sharedImport.attachments.first?.filename, "file-0.txt")
        XCTAssertEqual(sharedImport.attachments.last?.filename, "file-9.txt")
    }

    func testInboxKeepsTwoSharesAndReservesThemOldestFirst() throws {
        let directory = try temporaryDirectory()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_010)
        let secondDate = Date(timeIntervalSince1970: 1_800_000_020)

        try HermesShareDraft.savePendingDraft("First share", in: directory, now: firstDate)
        try HermesShareDraft.savePendingDraft("Second share", in: directory, now: secondDate)
        XCTAssertTrue(try HermesShareDraft.hasPendingImport(in: directory, now: secondDate))

        let first = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate)
        )
        XCTAssertEqual(first.sharedImport.draft, "First share")
        XCTAssertEqual(first.createdAt, firstDate)
        XCTAssertTrue(try HermesShareDraft.hasPendingImport(in: directory, now: secondDate))
        try HermesShareDraft.consume(first, from: directory)

        let second = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate)
        )
        XCTAssertEqual(second.sharedImport.draft, "Second share")
        XCTAssertEqual(second.createdAt, secondDate)
        try HermesShareDraft.consume(second, from: directory)

        XCTAssertFalse(try HermesShareDraft.hasPendingImport(in: directory, now: secondDate))
        XCTAssertNil(try HermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate))
    }

    func testInboxDeduplicatesRepeatedPendingContent() throws {
        let directory = try temporaryDirectory()

        try HermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_030)
        )
        try HermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_040)
        )

        let reservation = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )
        try HermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_050)
        )
        try HermesShareDraft.consume(reservation, from: directory)

        XCTAssertNil(try HermesShareDraft.reserveNextPendingImport(from: directory))
    }

    func testReleasedReservationCanBeReservedAgain() throws {
        let directory = try temporaryDirectory()
        try HermesShareDraft.savePendingDraft("Route me later", in: directory)

        let first = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )
        try HermesShareDraft.release(first, in: directory)

        let second = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(second.itemID, first.itemID)
        XCTAssertNotEqual(second.reservationID, first.reservationID)
        XCTAssertEqual(second.sharedImport, first.sharedImport)
    }

    func testExpiredReservationReturnsToInboxWithNewOwnership() throws {
        let directory = try temporaryDirectory()
        let reservationDate = Date(timeIntervalSince1970: 1_800_000_050)
        try HermesShareDraft.savePendingDraft("Recover me", in: directory, now: reservationDate)

        let expired = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory, now: reservationDate)
        )
        let recovered = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(
                from: directory,
                now: reservationDate.addingTimeInterval(HermesShareDraft.reservationLifetime + 1)
            )
        )

        XCTAssertEqual(recovered.itemID, expired.itemID)
        XCTAssertNotEqual(recovered.reservationID, expired.reservationID)
        XCTAssertThrowsError(try HermesShareDraft.consume(expired, from: directory))
        try HermesShareDraft.consume(recovered, from: directory)
    }

    func testMissingAttachmentOnlyItemDoesNotBlockLaterShare() throws {
        let directory = try temporaryDirectory()
        let attachmentDate = Date(timeIntervalSince1970: 1_800_000_060)
        try HermesShareDraft.savePendingImport(
            draft: "",
            attachments: [
                SharedAttachmentImport(
                    filename: "missing.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("gone".utf8)
                )
            ],
            in: directory,
            now: attachmentDate
        )
        try HermesShareDraft.savePendingDraft(
            "Still valid",
            in: directory,
            now: attachmentDate.addingTimeInterval(1)
        )

        for fileURL in try attachmentFileURLs(in: directory) {
            try FileManager.default.removeItem(at: fileURL)
        }

        let reservation = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(reservation.sharedImport.draft, "Still valid")
        try HermesShareDraft.consume(reservation, from: directory)
        XCTAssertNil(try HermesShareDraft.reserveNextPendingImport(from: directory))
    }

    func testMissingAttachmentDoesNotDiscardRemainingSharedContent() throws {
        let directory = try temporaryDirectory()
        try HermesShareDraft.savePendingImport(
            draft: "Review what remains",
            attachments: [
                SharedAttachmentImport(
                    filename: "first.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("first".utf8)
                ),
                SharedAttachmentImport(
                    filename: "second.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("second".utf8)
                )
            ],
            in: directory
        )

        let attachmentFiles = try attachmentFileURLs(in: directory)
        XCTAssertEqual(attachmentFiles.count, 2)
        try FileManager.default.removeItem(at: attachmentFiles[0])

        let reservation = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(reservation.sharedImport.draft, "Review what remains")
        XCTAssertEqual(reservation.sharedImport.attachments.count, 1)
        try HermesShareDraft.consume(reservation, from: directory)
    }

    func testFailedInboxPreparationDoesNotOverwriteExistingFile() throws {
        let parent = try temporaryDirectory()
        let fileURL = parent.appendingPathComponent("not-a-directory")
        let originalData = Data("keep me".utf8)
        try originalData.write(to: fileURL)

        XCTAssertThrowsError(
            try HermesShareDraft.savePendingDraft("Unsaved share", in: fileURL)
        )
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testPendingImportDecodesLegacyDraftOnlyPayload() throws {
        let directory = try temporaryDirectory()
        let payloadURL = directory.appendingPathComponent(HermesShareDraft.pendingDraftFileName)
        let legacyPayload = """
        {
          "draft": "Legacy note",
          "createdAt": 1800000002
        }
        """
        try Data(legacyPayload.utf8).write(to: payloadURL)

        let sharedImport = try XCTUnwrap(try HermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "Legacy note")
        XCTAssertTrue(sharedImport.attachments.isEmpty)
    }

    func testMalformedLegacyPayloadDoesNotBlockTransactionalInbox() throws {
        let directory = try temporaryDirectory()
        try HermesShareDraft.savePendingDraft("Valid new share", in: directory)

        let legacyPayloadURL = directory.appendingPathComponent(HermesShareDraft.pendingDraftFileName)
        try Data("not json".utf8).write(to: legacyPayloadURL)
        let legacyAttachmentsURL = directory.appendingPathComponent(
            HermesShareDraft.pendingAttachmentsDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyAttachmentsURL, withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: legacyAttachmentsURL.appendingPathComponent("orphan.txt"))

        let reservation = try XCTUnwrap(
            try HermesShareDraft.reserveNextPendingImport(from: directory)
        )

        XCTAssertEqual(reservation.sharedImport.draft, "Valid new share")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPayloadURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAttachmentsURL.path))
    }

    func testEmptyPendingDraftIsNotWritten() throws {
        let directory = try temporaryDirectory()

        try HermesShareDraft.savePendingDraft(" \n ", in: directory)

        XCTAssertNil(try HermesShareDraft.loadPendingDraft(from: directory))
    }

    // HERMEX-FORK: fallback pasteboard transport (sideloaded builds)

    /// The fallback name must be derived from the app group identifier: the App
    /// Store Hermex is installed beside this fork, so a shared literal would let
    /// one app claim the other app's share.
    func testPasteboardNameIsNamespacedToTheAppGroup() {
        XCTAssertEqual(
            HermesShareDraft.sharePasteboardName,
            "\(HermesShareDraft.appGroupIdentifier).share.inbox"
        )
        XCTAssertTrue(HermesShareDraft.sharePasteboardName.hasPrefix("group."))
    }

    /// The share round-trip has to wake THIS app. iOS resolves a URL scheme to
    /// exactly one app, and upstream declares `hermes-agent`: with the App Store
    /// Hermex installed beside Hermex Plus both apps claim it, so the extension's
    /// request to open `hermes-agent://share` could be handed to the App Store
    /// app and the share sheet opened the wrong window. The fork therefore opens
    /// its links under a scheme of its own; this test fails if a merge ever
    /// restores upstream's value (the bundle identifier has the same guard in
    /// gate 14).
    func testShareSchemeIsForkOwned() {
        XCTAssertFalse(HermesShareDraft.urlScheme.isEmpty)
        XCTAssertNotEqual(
            HermesShareDraft.urlScheme,
            "hermes-agent",
            "the share scheme must not be the one upstream's App Store build claims"
        )
        XCTAssertTrue(
            HermesShareDraft.urlScheme.hasPrefix("hermesplus"),
            "expected a fork-owned share scheme, got \(HermesShareDraft.urlScheme)"
        )
    }

    func testPasteboardTransportCarriesDraftAndAttachmentOnce() throws {
        try skipUnlessPasteboardIsAvailable()
        defer { HermesShareDraft.clearPasteboard() }

        let saved = HermesShareDraft.saveToPasteboard(
            draft: "  Summarize this page  ",
            attachments: [
                SharedAttachmentImport(
                    filename: "notes.pdf",
                    typeIdentifier: "com.adobe.pdf",
                    data: Data("pages".utf8)
                )
            ]
        )
        XCTAssertTrue(saved, "an available pasteboard with content must accept the payload")

        let loaded = try XCTUnwrap(HermesShareDraft.loadFromPasteboard())
        XCTAssertEqual(loaded.draft, "Summarize this page")
        XCTAssertEqual(loaded.attachments.map(\.filename), ["notes.pdf"])
        XCTAssertEqual(loaded.attachments.first?.data, Data("pages".utf8))
        // The type travels with the name: without it the attachment loses what it
        // is, which is how it gets attached as an anonymous blob downstream.
        XCTAssertEqual(loaded.attachments.first?.typeIdentifier, "com.adobe.pdf")

        // Reading alone must not consume the payload — a share that is read but
        // never claimed (app backgrounded mid-routing) has to survive.
        XCTAssertNotNil(HermesShareDraft.loadFromPasteboard())

        let reservation = try XCTUnwrap(HermesShareDraft.reserveNextPasteboardImport())
        XCTAssertEqual(reservation.source, .pasteboard)
        XCTAssertEqual(reservation.sharedImport.draft, "Summarize this page")
        XCTAssertNil(
            HermesShareDraft.loadFromPasteboard(),
            "claiming a pasteboard share must clear it, or a relaunch re-imports it"
        )
    }

    /// A payload written by the first build of this fallback carried the bytes
    /// without an envelope. Such a share must still deliver its content: the name
    /// is allowed to fall back, the bytes are not. Deliberately does NOT assert
    /// that a foreign `public.filename` key survives the pasteboard — that is a
    /// platform conversion this code no longer depends on.
    func testPasteboardReaderStillDeliversBytesWithoutAnEnvelope() throws {
        try skipUnlessPasteboardIsAvailable()
        defer { HermesShareDraft.clearPasteboard() }

        let pasteboard = try XCTUnwrap(
            UIPasteboard(name: .init(HermesShareDraft.sharePasteboardName), create: true)
        )
        pasteboard.setItems([["public.data": Data("legacy pages".utf8)]], options: [:])

        let loaded = try XCTUnwrap(HermesShareDraft.loadFromPasteboard())
        XCTAssertEqual(loaded.attachments.count, 1, "a bare-data item must still arrive")
        XCTAssertEqual(loaded.attachments.first?.data, Data("legacy pages".utf8))
        XCTAssertFalse(
            (loaded.attachments.first?.filename ?? "").isEmpty,
            "an attachment without a name must get a usable placeholder"
        )
    }

    /// A pasteboard share has no inbox state, so acknowledging it must be a
    /// no-op rather than a validation failure on a payload that was delivered.
    func testAcknowledgingPasteboardReservationDoesNotTouchTheInbox() throws {
        let directory = try temporaryDirectory()
        let reservation = SharedImportReservation(
            itemID: "pasteboard-1",
            reservationID: "reservation-1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sharedImport: SharedImport(draft: "from pasteboard", attachments: []),
            source: .pasteboard
        )

        XCTAssertNoThrow(try HermesShareDraft.consume(reservation, from: directory))
        XCTAssertNoThrow(try HermesShareDraft.release(reservation, in: directory))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("share-inbox-v1").path
            ),
            "acknowledging a pasteboard share must not create or touch inbox state"
        )
    }

    /// The App Group stays the default source, so call sites and tests written
    /// before the fallback existed keep their meaning.
    func testReservationDefaultsToAppGroupTransport() {
        let reservation = SharedImportReservation(
            itemID: "item",
            reservationID: "reservation",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sharedImport: SharedImport(draft: "inbox", attachments: [])
        )

        XCTAssertEqual(reservation.source, .appGroup)
    }

    // MARK: - 3.9.68 regression: URL draft byte limit

    func testURLDraftAtLimitIsCarriedInline() {
        let draft = String(repeating: "a", count: HermesShareDraft.maximumURLDraftBytes)
        XCTAssertEqual(draft.utf8.count, HermesShareDraft.maximumURLDraftBytes)

        let url = HermesShareDraft.openURL(withDraft: draft)
        XCTAssertEqual(
            HermesShareDraft.draftFromURL(url), draft,
            "a draft exactly at the limit must ride in the URL"
        )
    }

    func testURLDraftOverLimitIsNotInlined() {
        let draft = String(repeating: "a", count: HermesShareDraft.maximumURLDraftBytes + 1)

        let url = HermesShareDraft.openURL(withDraft: draft)
        XCTAssertNil(
            HermesShareDraft.draftFromURL(url),
            "one byte over the limit must not be inlined; it goes through the container"
        )
    }

    /// The cap is in BYTES, not characters: a multibyte draft that fits the
    /// character count can still exceed the byte budget.
    func testURLDraftLimitMeasuresBytesNotCharacters() {
        let atLimit = String(repeating: "я", count: HermesShareDraft.maximumURLDraftBytes / 2)
        XCTAssertEqual(atLimit.utf8.count, HermesShareDraft.maximumURLDraftBytes)
        XCTAssertEqual(
            HermesShareDraft.draftFromURL(HermesShareDraft.openURL(withDraft: atLimit)),
            atLimit
        )

        let overLimit = String(repeating: "я", count: HermesShareDraft.maximumURLDraftBytes / 2 + 1)
        XCTAssertGreaterThan(overLimit.utf8.count, HermesShareDraft.maximumURLDraftBytes)
        XCTAssertNil(
            HermesShareDraft.draftFromURL(HermesShareDraft.openURL(withDraft: overLimit)),
            "3001 two-byte characters are 6002 bytes and must not be inlined"
        )
    }

    func testEmptyDraftIsNotInlined() {
        XCTAssertNil(HermesShareDraft.draftFromURL(HermesShareDraft.openURL(withDraft: "")))
    }

    /// The payload must be URL-safe base64: `+`, `/` and `=` inside a query
    /// value can be re-encoded or truncated by a host before the app sees them,
    /// and the receiver would then decode a different string. This is the
    /// invariant that keeps extension and app agreeing on one format.
    func testURLDraftPayloadIsURLSafeBase64() {
        // Two-byte characters produce `+` and `/` in plain base64.
        let draft = String(repeating: "ÿ", count: 300)
        XCTAssertLessThanOrEqual(draft.utf8.count, HermesShareDraft.maximumURLDraftBytes)

        let url = HermesShareDraft.openURL(withDraft: draft)
        let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value ?? ""

        XCTAssertFalse(encoded.isEmpty, "a draft under the limit must be inlined")
        XCTAssertFalse(encoded.contains("+"), "base64 `+` must be rewritten to `-`")
        XCTAssertFalse(encoded.contains("/"), "base64 `/` must be rewritten to `_`")
        XCTAssertFalse(encoded.contains("="), "padding must be stripped and rebuilt on decode")
        XCTAssertEqual(HermesShareDraft.draftFromURL(url), draft,
                       "sender and receiver must agree on the payload format")
    }

    // MARK: - 3.9.68 regression: delivery and open outcomes

    func testDeliveryOutcomePrefersContainerThenPasteboardThenGeneral() {
        XCTAssertEqual(
            HermesShareDraft.deliveryOutcome(
                containerDelivered: true, namedPasteboardDelivered: true,
                generalPasteboardDelivered: true
            ),
            .container
        )
        XCTAssertEqual(
            HermesShareDraft.deliveryOutcome(
                containerDelivered: false, namedPasteboardDelivered: true,
                generalPasteboardDelivered: true
            ),
            .namedPasteboard
        )
        XCTAssertEqual(
            HermesShareDraft.deliveryOutcome(
                containerDelivered: false, namedPasteboardDelivered: false,
                generalPasteboardDelivered: true
            ),
            .textOnlyGeneralPasteboard
        )
        XCTAssertEqual(
            HermesShareDraft.deliveryOutcome(
                containerDelivered: false, namedPasteboardDelivered: false,
                generalPasteboardDelivered: false
            ),
            .unavailable
        )
    }

    func testOnlyFullPayloadOutcomesCountAsCarried() {
        XCTAssertTrue(HermesShareDraft.ShareDeliveryOutcome.container.carriedFullPayload)
        XCTAssertTrue(HermesShareDraft.ShareDeliveryOutcome.namedPasteboard.carriedFullPayload)
        XCTAssertFalse(HermesShareDraft.ShareDeliveryOutcome.textOnlyGeneralPasteboard.carriedFullPayload)
        XCTAssertFalse(HermesShareDraft.ShareDeliveryOutcome.unavailable.carriedFullPayload)
    }

    func testUnavailableDeliveryNeverReportsSuccess() {
        let outcome = HermesShareDraft.deliveryOutcome(
            containerDelivered: false,
            namedPasteboardDelivered: false,
            generalPasteboardDelivered: false
        )
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertNotNil(
            HermesShareDraft.statusMessage(forDelivery: outcome),
            "an undelivered share must say so instead of finishing silently"
        )
    }

    func testConfirmedDeliveryAndOpenStaySilent() {
        XCTAssertNil(HermesShareDraft.statusMessage(forDelivery: .container))
        XCTAssertNil(HermesShareDraft.statusMessage(forDelivery: .namedPasteboard))
        XCTAssertNil(HermesShareDraft.statusMessage(forOpen: .confirmed))
    }

    /// A dispatched request is not an opened app: the user must be told to open
    /// Hermex themselves instead of the extension silently claiming success.
    func testUnconfirmedOpenIsNotReportedAsSuccess() {
        XCTAssertNotNil(HermesShareDraft.statusMessage(forOpen: .dispatchedOnly))
        XCTAssertNotNil(HermesShareDraft.statusMessage(forOpen: .failed))
    }

    func testTextOnlyFallbackWarnsAboutAttachments() {
        let message = HermesShareDraft.statusMessage(forDelivery: .textOnlyGeneralPasteboard)
        XCTAssertNotNil(message)
        XCTAssertTrue(
            message?.lowercased().contains("copied") == true,
            "the text-only path must tell the user the text was copied for manual pasting"
        )
    }

    func testGeneralPasteboardRejectsEmptyText() {
        XCTAssertFalse(HermesShareDraft.saveTextToGeneralPasteboard("   \n\t "))
    }

    // MARK: - 3.9.68 regression: stranded reservation recovery

    /// A share left in `reserved/` without reservation metadata — exactly what a
    /// failed rollback leaves behind — must return to `pending/`, not vanish.
    func testStrandedReservedItemIsRecoveredToPending() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try HermesShareDraft.savePendingImport(draft: "stranded", attachments: [], in: directory)

        let inbox = directory.appendingPathComponent("share-inbox-v1", isDirectory: true)
        let pendingDirectory = inbox.appendingPathComponent("pending", isDirectory: true)
        let reservedDirectory = inbox.appendingPathComponent("reserved", isDirectory: true)
        try FileManager.default.createDirectory(at: reservedDirectory, withIntermediateDirectories: true)

        let itemName = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(atPath: pendingDirectory.path).first
        )
        let pendingItem = pendingDirectory.appendingPathComponent(itemName)
        let reservedItem = reservedDirectory.appendingPathComponent(itemName)

        // Move it into reserved/ with NO metadata, then age it past the
        // reservation lifetime so the recovery pass considers it abandoned.
        try FileManager.default.moveItem(at: pendingItem, to: reservedItem)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: reservedItem.path
        )

        XCTAssertTrue(
            try HermesShareDraft.hasPendingImport(in: directory),
            "the recovery pass must bring the stranded item back to pending/"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: reservedItem.path),
            "the item must not stay stuck in reserved/"
        )
    }

    private func skipUnlessPasteboardIsAvailable() throws {
        guard UIPasteboard(name: .init(HermesShareDraft.sharePasteboardName), create: true) == nil else {
            return
        }
        throw XCTSkip("no named pasteboard in this environment")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func attachmentFileURLs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard
                let url = element as? URL,
                url.pathExtension != "json",
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }
}
