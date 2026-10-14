import XCTest
@testable import MacCleaner

final class CleanupCatalogTests: XCTestCase {
    func testIDsAreUnique() {
        let ids = CleanupCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAllTargetsExpandToAbsolutePaths() {
        for category in CleanupCatalog.all {
            for target in category.targets {
                XCTAssertTrue(target.expandedPath.hasPrefix("/"), target.path)
            }
        }
    }

    /// Every item a cleanable category could produce must pass the safety policy.
    func testCleanableTargetsAreAllowedBySafetyGuard() {
        for category in CleanupCatalog.all where category.mode != .listOnly {
            for target in category.targets {
                let sample = target.contentsOnly ? target.expandedPath + "/sample-item" : target.expandedPath
                XCTAssertNoThrow(try SafetyGuard.standard.checkPolicy(sample), "\(category.id): \(sample)")
            }
        }
    }

    func testOnlyTrashIsPermanent() {
        let permanent = CleanupCatalog.all.filter { $0.mode == .permanent }.map(\.id)
        XCTAssertEqual(permanent, ["trash"])
    }
}
