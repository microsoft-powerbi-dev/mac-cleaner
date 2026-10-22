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

    func testSignInAndSyncCachesAreNeverScanned() {
        let caches = CleanupCatalog.all.first { $0.id == "userCaches" }!.targets[0]
        for name in ["CloudKit", "com.apple.bird", "com.apple.akd", "com.apple.nsurlsessiond"] {
            XCTAssertTrue(caches.excluding.contains(name), name)
        }
    }

    /// Caches and logs must keep each app's folder (e.g. Logs/DiagnosticReports) and remove only what is inside.
    func testCachesAndLogsKeepChildFolders() throws {
        for id in ["userCaches", "userLogs"] {
            XCTAssertTrue(CleanupCatalog.all.first { $0.id == id }!.targets.allSatisfy(\.keepChildFolders), id)
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ScannerTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("com.example.app"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: root.appendingPathComponent("com.example.app/Cache.db"))
        try Data(count: 10_000).write(to: root.appendingPathComponent("loose.log"))

        let category = CleanupCategory(
            id: "t", name: "t", detail: "", symbol: "",
            targets: [.init(root.path, keepChildFolders: true)], defaultSelected: true, mode: .trash
        )
        let items = CleanerScanner.scanSync(category).items
        XCTAssertEqual(Set(items.map(\.displayName)), ["com.example.app/Cache.db", "loose.log"])
        XCTAssertEqual(items.first { $0.url.lastPathComponent == "Cache.db" }?.owner, "com.example.app")
    }

    func testOnlyTrashIsPermanent() {
        let permanent = CleanupCatalog.all.filter { $0.mode == .permanent }.map(\.id)
        XCTAssertEqual(permanent, ["trash"])
    }
}
