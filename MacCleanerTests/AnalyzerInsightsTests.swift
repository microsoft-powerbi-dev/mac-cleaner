import XCTest
@testable import MacCleaner

/// FileKind, FileFilter, space hogs, usage history and the rule-based advisor.
final class AnalyzerInsightsTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    // MARK: FileKind

    func testClassifiesByExtension() {
        XCTAssertEqual(FileKind.classify(fileName: "Holiday.MOV"), .video)
        XCTAssertEqual(FileKind.classify(fileName: "photo.heic"), .image)
        XCTAssertEqual(FileKind.classify(fileName: "song.mp3"), .audio)
        XCTAssertEqual(FileKind.classify(fileName: "backup.zip"), .archive)
        XCTAssertEqual(FileKind.classify(fileName: "Installer.dmg"), .diskImage)
        XCTAssertEqual(FileKind.classify(fileName: "Docker.raw"), .diskImage)
        XCTAssertEqual(FileKind.classify(fileName: "disk.vmdk"), .diskImage)
        XCTAssertEqual(FileKind.classify(fileName: "report.pdf"), .document)
        XCTAssertEqual(FileKind.classify(fileName: "main.swift"), .developer)
        XCTAssertEqual(FileKind.classify(fileName: "system.log"), .cache)
        XCTAssertEqual(FileKind.classify(fileName: "noextension"), .other)
    }

    func testFolderContextWins() {
        XCTAssertEqual(FileKind.directoryContext("DerivedData"), .developer)
        XCTAssertEqual(FileKind.directoryContext("node_modules"), .developer)
        XCTAssertEqual(FileKind.directoryContext("Caches"), .cache)
        XCTAssertEqual(FileKind.directoryContext("Safari.app"), .application)
        XCTAssertEqual(FileKind.directoryContext("Photos Library.photoslibrary"), .image)
        XCTAssertNil(FileKind.directoryContext("Projects"))
        XCTAssertEqual(FileKind.classify(fileName: "clip.mp4", context: .developer), .developer)
    }

    func testAgeBuckets() {
        let now = Date()
        XCTAssertEqual(AgeBucket.bucket(for: now.addingTimeInterval(-86_400), now: now), .lastMonth)
        XCTAssertEqual(AgeBucket.bucket(for: now.addingTimeInterval(-90 * 86_400), now: now), .lastSixMonths)
        XCTAssertEqual(AgeBucket.bucket(for: now.addingTimeInterval(-300 * 86_400), now: now), .lastYear)
        XCTAssertEqual(AgeBucket.bucket(for: now.addingTimeInterval(-800 * 86_400), now: now), .older)
        XCTAssertEqual(AgeBucket.bucket(for: nil, now: now), .older)
    }

    // MARK: FileFilter

    private func file(_ name: String, _ size: Int64, kind: FileKind, accessedDaysAgo: Double? = nil, dir: String = "/Users/x/Movies") -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: dir + "/" + name), size: size,
            lastAccess: accessedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }, modified: nil, kind: kind
        )
    }

    func testFilterBySizeKindNameLocationAndAge() {
        let files = [
            file("big.mov", 5_000_000_000, kind: .video, accessedDaysAgo: 400),
            file("medium.mov", 200_000_000, kind: .video, accessedDaysAgo: 10),
            file("archive.zip", 300_000_000, kind: .archive, accessedDaysAgo: 400, dir: "/Users/x/Downloads"),
            file("small.mov", 5_000_000, kind: .video),
        ]
        var filter = FileFilter()
        XCTAssertEqual(filter.apply(files).map(\.name), ["big.mov", "archive.zip", "medium.mov"])

        filter.kinds = [.video]
        XCTAssertEqual(filter.apply(files).map(\.name), ["big.mov", "medium.mov"])

        filter.age = .year
        XCTAssertEqual(filter.apply(files).map(\.name), ["big.mov"])

        filter = FileFilter()
        filter.minSize = .oneMB
        filter.nameQuery = "MOV"
        filter.limit = 2
        XCTAssertEqual(filter.apply(files).map(\.name), ["big.mov", "medium.mov"])

        filter = FileFilter()
        filter.locationQuery = "downloads"
        XCTAssertEqual(filter.apply(files).map(\.name), ["archive.zip"])
    }

    // MARK: Space hogs

    private func dir(_ path: String, _ children: [DiskNode]) -> DiskNode {
        DiskNode(url: URL(fileURLWithPath: path), isDirectory: true, size: children.reduce(0) { $0 + $1.size }, children: children)
    }

    private func blob(_ path: String, _ size: Int64) -> DiskNode {
        DiskNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size, children: [])
    }

    func testSpaceHogsReportTheFolderThatHoldsTheBytes() {
        let gb: Int64 = 1_000_000_000
        let derived = dir("/h/Library/Developer/DerivedData", [blob("/h/Library/Developer/DerivedData/a", 8 * gb)])
        let developer = dir("/h/Library/Developer", [derived])
        let library = dir("/h/Library", [developer, blob("/h/Library/x", gb / 2)])
        let movies = dir("/h/Movies", [blob("/h/Movies/m1", 2 * gb), blob("/h/Movies/m2", 2 * gb)])
        let root = dir("/h", [library, movies])

        let hogs = DiskInsights.spaceHogs(root: root, minSize: gb)
        XCTAssertEqual(hogs.map(\.node.name), ["DerivedData", "Movies"])
        XCTAssertEqual(hogs.first?.chain.map(\.name), ["h", "Library", "Developer", "DerivedData"])
        XCTAssertEqual(DiskInsights.chain(to: derived.url, in: root)?.count, 4)
        XCTAssertNil(DiskInsights.chain(to: URL(fileURLWithPath: "/elsewhere"), in: root))
    }

    // MARK: Usage history

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UsageHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testHistoryRoundTripAndOneVolumeSnapshotPerDay() throws {
        let store = UsageHistoryStore(directory: try tempDir())
        let now = Date()
        store.recordVolumeSnapshotIfNeeded(now: now, volume: (free: 40, total: 100))
        store.recordVolumeSnapshotIfNeeded(now: now.addingTimeInterval(60), volume: (free: 30, total: 100))
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.volumeUsed, 60)

        store.append(UsageSnapshot(date: now.addingTimeInterval(120), volumeTotal: 100, volumeAvailable: 20,
                                   rootPath: "/h", rootSize: 50, topFolders: ["A": 10]))
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.last?.topFolders["A"], 10)

        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testHistoryIsCapped() throws {
        let store = UsageHistoryStore(directory: try tempDir())
        var snapshots: [UsageSnapshot] = []
        for i in 0..<(UsageHistoryStore.maxSnapshots + 5) {
            snapshots.append(UsageSnapshot(date: Date(timeIntervalSince1970: Double(i) * 1000), volumeTotal: 1, volumeAvailable: 0, rootPath: "/h", rootSize: 1))
        }
        try store.save(snapshots)
        let after = store.append(UsageSnapshot(date: Date(), volumeTotal: 1, volumeAvailable: 0, rootPath: "/h", rootSize: 1))
        XCTAssertEqual(after.count, UsageHistoryStore.maxSnapshots)
    }

    func testHistoryDiff() {
        let old = UsageSnapshot(date: Date(), volumeTotal: 0, volumeAvailable: 0, rootPath: "/h", rootSize: 0,
                                topFolders: ["Movies": 100, "Gone": 50, "Same": 5])
        let new = UsageSnapshot(date: Date(), volumeTotal: 0, volumeAvailable: 0, rootPath: "/h", rootSize: 0,
                                topFolders: ["Movies": 400, "New": 20, "Same": 5])
        let changes = UsageHistory.diff(from: old, to: new)
        XCTAssertEqual(changes.map(\.name), ["Movies", "Gone", "New"])
        XCTAssertEqual(changes.map(\.delta), [300, -50, 20])
    }

    // MARK: Rule-based advisor

    private func advice(_ path: String, dir: Bool = true, kind: FileKind = .other) -> Advice {
        RuleBasedAdvisor.advise(AdvisorItem(url: URL(fileURLWithPath: path), isDirectory: dir, size: 1, kind: kind))
    }

    func testKnownLocations() {
        XCTAssertEqual(advice(home + "/Library/Developer/Xcode/DerivedData/App-abc").safety, .safeToDelete)
        XCTAssertEqual(advice(home + "/Projects/web/node_modules").safety, .safeToDelete)
        XCTAssertEqual(advice(home + "/Library/Caches/com.example.app").safety, .safeToDelete)
        XCTAssertEqual(advice(home + "/Downloads/Setup.dmg", dir: false, kind: .diskImage).safety, .safeToDelete)
        XCTAssertEqual(advice(home + "/Library/Application Support/MobileSync/Backup/123").safety, .reviewFirst)
        XCTAssertEqual(advice(home + "/Movies/Trip.mov", dir: false, kind: .video).safety, .reviewFirst)
        XCTAssertTrue(advice(home + "/Movies/Trip.mov", dir: false, kind: .video).suggestMove)
    }

    func testProtectedLocationsAreAlwaysKeep() {
        // Rules say caches are safe, but the Caches folder itself is protected by SafetyGuard.
        XCTAssertEqual(advice(home + "/Library/Caches").safety, .keep)
        XCTAssertEqual(advice(home + "/Library/Mail/V10").safety, .keep)
        XCTAssertEqual(advice(home + "/Pictures/Photos Library.photoslibrary").safety, .keep)
        XCTAssertEqual(advice("/System/Library/Caches/x").safety, .keep)
    }

    func testSummaryListsFindingsAndDuplicates() {
        let gb: Int64 = 1_000_000_000
        let input = ScanSummaryInput(
            rootPath: home, rootSize: 100 * gb, volumeFree: 5 * gb, volumeTotal: 500 * gb,
            kindTotals: [.developer: 40 * gb, .video: 30 * gb],
            hogs: [AdvisorItem(url: URL(fileURLWithPath: home + "/Library/Developer/Xcode/DerivedData"), isDirectory: true, size: 20 * gb, kind: .developer)],
            largestFiles: [], duplicateWaste: 3 * gb, growthSincePrevious: (bytes: 2 * gb, since: Date())
        )
        let report = RuleBasedAdvisor.summarize(input)
        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.findings.first?.safety, .safeToDelete)
        XCTAssertTrue(report.headline.contains("grew"))
        XCTAssertTrue(report.tips.contains { $0.contains("15%") })
    }
}
