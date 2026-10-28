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

    func testMainThreadLabelIsReadable() {
        HeavyOperationTracker.begin("main-op")
        XCTAssertEqual(HeavyOperationTracker.currentLabelForTesting, "main-op")
        HeavyOperationTracker.end()
        XCTAssertNil(HeavyOperationTracker.currentLabelForTesting)
    }

    func testBackgroundOperationDoesNotOverwriteMainLabel() {
        HeavyOperationTracker.begin("main-op")

        DispatchQueue.global(qos: .utility).sync {
            HeavyOperationTracker.begin("bg-op")
            HeavyOperationTracker.end()
        }

        XCTAssertEqual(
            HeavyOperationTracker.currentLabelForTesting, "main-op",
            "a background operation must not take over the main-thread label"
        )
    }

    func testBackgroundBeginAloneIsIgnored() {
        HeavyOperationTracker.end()
        DispatchQueue.global(qos: .utility).sync {
            HeavyOperationTracker.begin("bg-only")
        }
        XCTAssertNil(
            HeavyOperationTracker.currentLabelForTesting,
            "a label set off-main is not evidence about freezes"
        )
    }

    func testBackgroundEndDoesNotClearMainLabel() {
        HeavyOperationTracker.begin("main-op")

        DispatchQueue.global(qos: .utility).sync {
            HeavyOperationTracker.end()
        }

        XCTAssertEqual(
            HeavyOperationTracker.currentLabelForTesting, "main-op",
            "a background end must not clear the main-thread operation"
        )
    }
}
