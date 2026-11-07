import XCTest
@testable import MacCleaner

final class AppSortAndPrefsTests: XCTestCase {
    private func app(_ name: String, size: Int64, used: Double?, added: Double?) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: "com.example.\(name)",
            version: nil, size: size,
            lastUsed: used.map { Date(timeIntervalSince1970: $0) },
            dateAdded: added.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private lazy var apps = [
        app("beta", size: 300, used: 100, added: 5),
        app("Alpha", size: 100, used: nil, added: 9),
        app("gamma", size: 200, used: 300, added: nil),
    ]

    private func names(_ sort: AppSort, _ ascending: Bool) -> [String] {
        AppInventory.sorted(apps, by: sort, ascending: ascending).map(\.name)
    }

    func testSortByNameIsCaseInsensitive() {
        XCTAssertEqual(names(.name, true), ["Alpha", "beta", "gamma"])
        XCTAssertEqual(names(.name, false), ["gamma", "beta", "Alpha"])
    }

    func testSortBySize() {
        XCTAssertEqual(names(.size, false), ["beta", "gamma", "Alpha"])
        XCTAssertEqual(names(.size, true), ["Alpha", "gamma", "beta"])
    }

    func testMissingDatesSortLastInBothDirections() {
        XCTAssertEqual(names(.lastUsed, false), ["gamma", "beta", "Alpha"])
        XCTAssertEqual(names(.lastUsed, true), ["beta", "gamma", "Alpha"])
        XCTAssertEqual(names(.dateAdded, false), ["Alpha", "beta", "gamma"])
        XCTAssertEqual(names(.dateAdded, true), ["beta", "Alpha", "gamma"])
    }

    func testDescribeReadsDates() {
        // Any app bundle works; Safari is always installed.
        let safari = AppInventory.describe(URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertNotNil(safari.dateAdded)
    }

    func testPrefsResetRestoresDefaults() throws {
        let store = try XCTUnwrap(UserDefaults(suiteName: "AppSortAndPrefsTests-\(UUID().uuidString)"))
        Prefs.register(store)
        XCTAssertEqual(store.integer(forKey: Prefs.oldFileDays), 365)
        XCTAssertTrue(store.bool(forKey: Prefs.showMenuBarExtra))
        store.set(90, forKey: Prefs.oldFileDays)
        store.set(false, forKey: Prefs.showMenuBarExtra)
        Prefs.resetAll(store)
        XCTAssertEqual(store.integer(forKey: Prefs.oldFileDays), 365)
        XCTAssertTrue(store.bool(forKey: Prefs.showMenuBarExtra))
    }

    func testOldFilesUseConfigurableAge() {
        let now = Date()
        let file = FileEntry(url: URL(fileURLWithPath: "/x/a.mov"), size: 50_000_000,
                             lastAccess: now.addingTimeInterval(-200 * 86_400), modified: nil, kind: .video)
        let root = DiskNode(url: URL(fileURLWithPath: "/x"), isDirectory: true, size: 0, children: [])
        let result = DiskScanResult(root: root, files: [file], kindTotals: [:], ageTotals: [:], fileCount: 1, scannedAt: now)
        XCTAssertTrue(result.oldFiles.isEmpty)
        XCTAssertEqual(result.oldFiles(notOpenedForDays: 182).count, 1)
    }

    func testHistoryLimitIsConfigurable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prefs-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageHistoryStore(directory: dir)
        for i in 0..<5 {
            store.append(UsageSnapshot(date: Date(timeIntervalSince1970: Double(i) * 1000), volumeTotal: 1, volumeAvailable: 0, rootPath: "/h"), limit: 3)
        }
        XCTAssertEqual(store.load().count, 3)
    }
}
