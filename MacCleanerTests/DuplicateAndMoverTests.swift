import XCTest
@testable import MacCleaner

final class DuplicateAndMoverTests: XCTestCase {
    private var base: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // Resolve /var → /private/var so SafetyGuard's symlink check sees a real path.
        base = URL(fileURLWithPath: SafetyGuard.realPath(fm.temporaryDirectory.path)!)
            .appendingPathComponent("DuplicateAndMoverTests-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: base)
    }

    @discardableResult
    private func write(_ relative: String, _ data: Data) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func entry(_ url: URL) -> FileEntry {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return FileEntry(url: url, size: size, lastAccess: nil, modified: Date(), kind: .other)
    }

    private func payload(_ seed: UInt8, count: Int = 200_000) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31) ^ seed })
    }

    // MARK: Duplicates

    func testFindsIdenticalFilesOnly() throws {
        let a = try write("a/one.bin", payload(1))
        let b = try write("b/copy.bin", payload(1))
        let c = try write("c/copy2.bin", payload(1))
        var differentTail = payload(1)
        differentTail[differentTail.count - 1] ^= 0xFF
        let d = try write("d/almost.bin", differentTail)          // same size, same head, different tail
        var differentMiddle = payload(1)
        differentMiddle[100_000] ^= 0xFF
        let e = try write("e/middle.bin", differentMiddle)        // same head and tail, different middle
        let f = try write("f/other.bin", payload(2, count: 1000))

        let groups = DuplicateFinder.find([a, b, c, d, e, f].map(entry), minSize: 1, cancel: CancelFlag())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), [a, b, c])
        XCTAssertEqual(groups[0].wasted, 2 * 200_000)
    }

    func testHardLinksAreNotDuplicates() throws {
        let a = try write("a.bin", payload(3))
        let link = base.appendingPathComponent("link.bin")
        try fm.linkItem(at: a, to: link)
        XCTAssertTrue(DuplicateFinder.find([entry(a), entry(link)], minSize: 1, cancel: CancelFlag()).isEmpty)
    }

    func testCancelledSearchReturnsNothing() throws {
        let a = try write("a.bin", payload(4))
        let b = try write("b.bin", payload(4))
        let flag = CancelFlag()
        flag.set()
        XCTAssertTrue(DuplicateFinder.find([entry(a), entry(b)], minSize: 1, cancel: flag).isEmpty)
    }

    func testKeepRules() {
        let old = FileEntry(url: URL(fileURLWithPath: "/x/a/very/long/path.bin"), size: 1, lastAccess: nil, modified: Date(timeIntervalSince1970: 0))
        let new = FileEntry(url: URL(fileURLWithPath: "/x/b.bin"), size: 1, lastAccess: nil, modified: Date())
        XCTAssertEqual(KeepRule.newest.pick(from: [old, new])?.url, new.url)
        XCTAssertEqual(KeepRule.oldest.pick(from: [old, new])?.url, old.url)
        XCTAssertEqual(KeepRule.shortestPath.pick(from: [old, new])?.url, new.url)
    }

    // MARK: Mover

    private var guardian: SafetyGuard {
        SafetyGuard(allowedRoots: [base.appendingPathComponent("src").path], protectedSubtrees: [], protectedExact: [])
    }

    func testMoveCopiesVerifiesAndRemovesOriginal() throws {
        let file = try write("src/movie.mov", payload(5))
        let folder = try write("src/Project/inner/data.bin", payload(6)).deletingLastPathComponent().deletingLastPathComponent()
        let dest = base.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try write("dest/movie.mov", Data([1]))   // name collision

        let report = Mover.moveSync([file, folder], to: dest, safety: guardian, originalMode: .deletePermanently)
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures.map(\.reason))")
        XCTAssertEqual(report.moved.count, 2)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("movie 2.mov")), payload(5))
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("Project/inner/data.bin")), payload(6))
        XCTAssertEqual(report.bytesMoved, 400_000)
    }

    func testMoveRefusesDestinationInsideSource() throws {
        let folder = base.appendingPathComponent("src/Folder")
        try write("src/Folder/a.bin", payload(7))
        let inner = folder.appendingPathComponent("Sub")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)

        let report = Mover.moveSync([folder], to: inner, safety: guardian, originalMode: .deletePermanently)
        XCTAssertEqual(report.moved.count, 0)
        XCTAssertEqual(report.failures.first?.reason, Mover.MoveError.destinationInsideSource.errorDescription)
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("a.bin").path))
    }

    func testMoveRefusesSourcesSafetyGuardRejects() throws {
        let outside = try write("elsewhere/a.bin", payload(8))
        let dest = base.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let report = Mover.moveSync([outside], to: dest, safety: guardian, originalMode: .deletePermanently)
        XCTAssertEqual(report.moved.count, 0)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("a.bin").path))
    }

    func testMoveFailsWhenDestinationMissing() throws {
        let file = try write("src/a.bin", payload(9))
        let report = Mover.moveSync([file], to: base.appendingPathComponent("unplugged"), safety: guardian, originalMode: .deletePermanently)
        XCTAssertEqual(report.failures.first?.reason, Mover.MoveError.destinationMissing.errorDescription)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    func testDestinationSpaceCheck() throws {
        let file = try write("src/a.bin", payload(10))
        let dest = base.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Mover.checkDestination(dest, for: file, needed: Int64.max / 2)) { error in
            guard case Mover.MoveError.notEnoughSpace = error else { return XCTFail("\(error)") }
        }
        XCTAssertNoThrow(try Mover.checkDestination(dest, for: file, needed: 1))
    }

    func testVerifyDetectsMismatch() throws {
        let a = try write("src/a.bin", payload(11))
        var tampered = payload(11)
        tampered[5] ^= 0xFF
        let b = try write("dest/a.bin", tampered)
        XCTAssertFalse(Mover.verify(source: a, copy: b, expected: Mover.contentSummary(a)))
        let c = try write("dest/c.bin", payload(11))
        XCTAssertTrue(Mover.verify(source: a, copy: c, expected: Mover.contentSummary(a)))
    }
}
