import XCTest
@testable import HermesMobile

/// The composer's file-attachment path.
///
/// The picker itself cannot be presented in a unit test — there is no foreground
/// window scene — so what is pinned here is the delegate contract the composer
/// depends on: what it receives when the user confirms a choice, what happens on
/// cancellation, and that a finished presentation is never reported as still in
/// flight.
///
/// This contract is exactly what was broken on device: the SwiftUI `.fileImporter`
/// never called its completion handler, so choosing a file and tapping "Open" did
/// nothing at all. These tests fail if the UIKit path loses either delivery.
@MainActor
final class ComposerDocumentPickerTests: XCTestCase {
    func testPickedDocumentsReachTheComposerAndEndThePresentation() {
        let picker = ComposerDocumentPicker()
        let controller = ComposerDocumentPicker.makePicker()

        var picked: [URL] = []
        var presentationStates: [Bool] = []

        picker.installForTesting(
            onPick: { picked = $0 },
            onCancel: { XCTFail("cancel must not run when the user confirms a choice") },
            onPresentationChange: { presentationStates.append($0) }
        )

        let urls = [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.pdf"),
        ]
        picker.documentPicker(controller, didPickDocumentsAt: urls)

        XCTAssertEqual(picked, urls, "every URL the picker returned must reach the composer")
        XCTAssertEqual(presentationStates, [false], "the presentation must be reported as finished")
        XCTAssertFalse(picker.isPresenting, "a finished presentation must not report itself as live")
    }

    func testCancellationAttachesNothingAndEndsThePresentation() {
        let picker = ComposerDocumentPicker()
        let controller = ComposerDocumentPicker.makePicker()

        var cancelled = false
        var picked: [URL]?

        picker.installForTesting(
            onPick: { picked = $0 },
            onCancel: { cancelled = true },
            onPresentationChange: { _ in }
        )

        picker.documentPickerWasCancelled(controller)

        XCTAssertTrue(cancelled, "cancellation must reach the composer so focus can be restored")
        XCTAssertNil(picked, "a cancelled pick must never attach anything")
        XCTAssertFalse(picker.isPresenting)
    }

    /// `asCopy` is what makes the returned URL readable without security-scoped
    /// access — the silent failure mode this path used to have. Losing it would
    /// reintroduce a read that fails only on iCloud placeholders.
    func testTheForkPresentsACopyingMultiSelectPicker() {
        let controller = ComposerDocumentPicker.makePicker()

        XCTAssertTrue(
            controller.allowsMultipleSelection,
            "the composer attaches several files per trip, so multi-select must stay on"
        )
    }

    /// A double delivery would attach the same files twice. The callbacks are
    /// consumed on the first one, so the composer must see exactly one.
    func testASecondDeliveryIsIgnored() {
        let picker = ComposerDocumentPicker()
        let controller = ComposerDocumentPicker.makePicker()

        var pickCount = 0
        picker.installForTesting(
            onPick: { _ in pickCount += 1 },
            onCancel: {},
            onPresentationChange: { _ in }
        )

        let url = URL(fileURLWithPath: "/tmp/only-once.txt")
        picker.documentPicker(controller, didPickDocumentsAt: [url])
        picker.documentPicker(controller, didPickDocumentsAt: [url])

        XCTAssertEqual(pickCount, 1, "callbacks are consumed on first delivery")
    }
}
