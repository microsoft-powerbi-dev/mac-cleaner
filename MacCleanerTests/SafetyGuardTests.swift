import XCTest
@testable import MacCleaner

final class SafetyGuardTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    private let guardian = SafetyGuard.standard

    func testRejectsSystemLocations() {
        for path in ["/System/Library/Caches/x", "/usr/lib/x", "/private/var/db/x", "/Library/Logs/x", "/bin/ls"] {
            XCTAssertThrowsError(try guardian.checkPolicy(path), path)
        }
    }

    func testRejectsProtectedFoldersThemselves() {
        for path in [home, home + "/Library", home + "/Library/Caches", home + "/Documents", "/Applications", home + "/.Trash"] {
            XCTAssertThrowsError(try guardian.checkPolicy(path), path)
        }
    }

    func testRejectsProtectedSubtreesCaseInsensitively() {
        XCTAssertThrowsError(try guardian.checkPolicy(home + "/library/KEYCHAINS/login.keychain-db"))
        XCTAssertThrowsError(try guardian.checkPolicy(home + "/Library/Mobile Documents/com~apple~CloudDocs/file"))
    }

    func testAllowsCacheChildren() {
        XCTAssertNoThrow(try guardian.checkPolicy(home + "/Library/Caches/com.example.app"))
        XCTAssertNoThrow(try guardian.checkPolicy(home + "/Library/Logs/SomeApp"))
        XCTAssertNoThrow(try guardian.checkPolicy("/Applications/Example.app"))
    }

    func testRejectsRelativeAndOutsidePaths() {
        XCTAssertThrowsError(try guardian.checkPolicy("Library/Caches/x"))
        XCTAssertThrowsError(try guardian.checkPolicy("/Users/someone-else/Library/Caches/x"))
    }

    func testDotDotCannotEscape() {
        let sneaky = URL(fileURLWithPath: home + "/Library/Caches/../../../../System/Library/x")
        XCTAssertThrowsError(try guardian.validate(sneaky))
    }

    func testSymlinkInParentIsRejected() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: SafetyGuard.realPath(fm.temporaryDirectory.path)!)
            .appendingPathComponent("SafetyGuardTests-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try fm.createDirectory(at: root.appendingPathComponent("real"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        defer { try? fm.removeItem(at: base) }

        let guardian = SafetyGuard(allowedRoots: [root.path], protectedSubtrees: [], protectedExact: [])
        XCTAssertNoThrow(try guardian.validate(root.appendingPathComponent("real/file")))
        XCTAssertThrowsError(try guardian.validate(root.appendingPathComponent("link/file"))) { error in
            XCTAssertEqual(error as? SafetyGuard.Violation, .symlinkInPath(root.appendingPathComponent("link/file").path))
        }
    }

    func testRejectsKeysAndCrashReportFolder() {
        XCTAssertThrowsError(try guardian.checkPolicy(home + "/.ssh/id_ed25519"))
        XCTAssertThrowsError(try guardian.checkPolicy(home + "/.gnupg/pubring.kbx"))
        XCTAssertThrowsError(try guardian.checkPolicy(home + "/Library/Logs/DiagnosticReports"))
        XCTAssertNoThrow(try guardian.checkPolicy(home + "/Library/Logs/DiagnosticReports/App.ips"))
    }

    /// Normalizing must not depend on the file system: `/private/...` stays as it is whether or not it exists.
    func testLexicalNormalization() {
        XCTAssertEqual(SafetyGuard.lexical("/private/tmp/does-not-exist"), "/private/tmp/does-not-exist")
        XCTAssertEqual(SafetyGuard.lexical("/private/tmp"), "/private/tmp")
        XCTAssertEqual(SafetyGuard.lexical("/a//b/./c/../d/"), "/a/b/d")
        XCTAssertEqual(SafetyGuard.lexical("/../../x"), "/x")
    }

    func testValidateReturnsTheCheckedURL() throws {
        let messy = URL(fileURLWithPath: home + "/Library/Caches/./x/../com.example.app")
        XCTAssertEqual(try guardian.validate(messy).path, home + "/Library/Caches/com.example.app")
    }

    func testTrasherRefusesBlockedPaths() {
        let report = Trasher.removeSync(
            [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")],
            mode: .deletePermanently,
            safety: guardian
        )
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
    }
}
