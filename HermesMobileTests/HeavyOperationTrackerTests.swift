import XCTest
@testable import HermesMobile

/// HERMEX-FORK: 3.9.65 — freeze attribution must belong to the main thread.
///
/// 3.9.64 attributed a 3 262 ms freeze to `CacheStore.cacheMessages`, which runs
/// on `CacheStore.writeQueue`. The tracker was a single global slot: a
/// background label overwrote the main-thread one and its `end()` cleared it, so
/// the freeze report could name work that was never on the main thread.
@MainActor
final class HeavyOperationTrackerTests: XCTestCase {

    override func tearDown() {
        HeavyOperationTracker.end()
        super.tearDown()
    }

    /// Runs `work` on a non-main thread and waits for it.
    ///
    /// Two constraints shaped this:
    ///  * `sync` is wrong — libdispatch may run a `sync` block on the CALLING
    ///    thread, i.e. main, so `Thread.isMainThread` stayed true and the first
    ///    version of these tests failed because of the test, not the tracker;
    ///  * `DispatchQueue.async` needs a `@Sendable` closure, and
    ///    `XCTestExpectation` is not `Sendable`, so an expectation-based wait
    ///    would not compile under Swift 6. `Task.detached` runs off-main and
    ///    needs no expectation at all.
    private func onBackgroundThread(_ work: @escaping @Sendable () -> Void) async {
        await Task.detached(priority: .utility) { work() }.value
    }

    func testMainThreadLabelIsReadable() {
        HeavyOperationTracker.begin("main-op")
        XCTAssertEqual(HeavyOperationTracker.currentLabelForTesting, "main-op")
        HeavyOperationTracker.end()
        XCTAssertNil(HeavyOperationTracker.currentLabelForTesting)
    }

    func testBackgroundOperationDoesNotOverwriteMainLabel() async {
        HeavyOperationTracker.begin("main-op")

        await onBackgroundThread {
            HeavyOperationTracker.begin("bg-op")
            HeavyOperationTracker.end()
        }

        XCTAssertEqual(
            HeavyOperationTracker.currentLabelForTesting, "main-op",
            "a background operation must not take over the main-thread label"
        )
    }

    func testBackgroundBeginAloneIsIgnored() async {
        HeavyOperationTracker.end()
        await onBackgroundThread {
            HeavyOperationTracker.begin("bg-only")
        }
        XCTAssertNil(
            HeavyOperationTracker.currentLabelForTesting,
            "a label set off-main is not evidence about freezes"
        )
    }

    func testBackgroundEndDoesNotClearMainLabel() async {
        HeavyOperationTracker.begin("main-op")

        await onBackgroundThread {
            HeavyOperationTracker.end()
        }

        XCTAssertEqual(
            HeavyOperationTracker.currentLabelForTesting, "main-op",
            "a background end must not clear the main-thread operation"
        )
    }
}
