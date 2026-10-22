import XCTest
@testable import MacCleaner

final class LeftoverFinderTests: XCTestCase {
    private let id = "com.example.CoolApp"

    func testMatchesBundleIdentifierVariants() {
        for name in [
            "com.example.CoolApp",
            "com.example.coolapp.plist",
            "com.example.CoolApp.savedState",
            "com.example.CoolApp.binarycookies",
            "ABCDE12345.com.example.CoolApp",
        ] {
            XCTAssertEqual(LeftoverFinder.match(name, bundleID: id, appName: "Cool App"), .bundleID, name)
        }
    }

    /// Longer identifiers may be a helper or a different edition (e.g. Chrome vs. Chrome for
    /// Testing), so they match only as `.related` and start unchecked.
    func testLongerIdentifiersAreOnlyRelated() {
        for name in [
            "com.example.CoolApp.helper",
            "com.example.CoolApp.beta.plist",
            "group.com.example.CoolApp.shared",
        ] {
            XCTAssertEqual(LeftoverFinder.match(name, bundleID: id, appName: "Cool App"), .related, name)
        }
    }

    func testDoesNotMatchSimilarIdentifiers() {
        for name in ["com.example.CoolAppPro", "com.example", "com.example.Other.plist", "xcom.example.CoolApp"] {
            XCTAssertNil(LeftoverFinder.match(name, bundleID: id, appName: "Cool App"), name)
        }
    }

    func testNameMatchIsExactAndNeedsFourCharacters() {
        XCTAssertEqual(LeftoverFinder.match("Cool App", bundleID: id, appName: "Cool App"), .appName)
        XCTAssertNil(LeftoverFinder.match("Cool App Backups", bundleID: id, appName: "Cool App"))
        XCTAssertNil(LeftoverFinder.match("Zed", bundleID: nil, appName: "Zed"))
    }

    func testFindSearchesLibrarySubfolders() throws {
        let fm = FileManager.default
        let lib = fm.temporaryDirectory.appendingPathComponent("LeftoverTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: lib) }
        for sub in ["Application Support/Cool App", "Caches/com.example.CoolApp", "Caches/com.other.App"] {
            try fm.createDirectory(at: lib.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: lib.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: lib.appendingPathComponent("Preferences/com.example.CoolApp.plist"))

        let found = LeftoverFinder(libraryRoot: lib).find(bundleID: id, appName: "Cool App")
        let names = Set(found.map(\.url.lastPathComponent))
        XCTAssertEqual(names, ["Cool App", "com.example.CoolApp", "com.example.CoolApp.plist"])
    }

    func testSkipsFilesOfOtherInstalledApps() throws {
        let lib = try makeLibrary([
            "Caches/com.example.CoolApp",
            "Caches/com.example.CoolApp.beta",
            "Caches/com.example.CoolApp.helper",
        ])
        defer { try? FileManager.default.removeItem(at: lib) }

        let found = LeftoverFinder(libraryRoot: lib)
            .find(bundleID: id, appName: "Cool App", otherBundleIDs: ["com.example.CoolApp.beta"])
        XCTAssertEqual(Set(found.map(\.url.lastPathComponent)), ["com.example.CoolApp", "com.example.CoolApp.helper"])
    }

    func testAnotherCopyOfTheSameAppKeepsEverything() throws {
        let lib = try makeLibrary(["Caches/com.example.CoolApp"])
        defer { try? FileManager.default.removeItem(at: lib) }

        let found = LeftoverFinder(libraryRoot: lib)
            .find(bundleID: id, appName: "Cool App", otherBundleIDs: ["com.example.coolapp"])
        XCTAssertTrue(found.isEmpty)
    }

    func testGroupContainersAreMarkedShared() throws {
        let lib = try makeLibrary(["Group Containers/ABCDE12345.com.example.CoolApp"])
        defer { try? FileManager.default.removeItem(at: lib) }

        let found = LeftoverFinder(libraryRoot: lib).find(bundleID: id, appName: "Cool App")
        XCTAssertEqual(found.map(\.match), [.sharedGroup])
    }

    private func makeLibrary(_ folders: [String]) throws -> URL {
        let fm = FileManager.default
        let lib = fm.temporaryDirectory.appendingPathComponent("LeftoverTests-\(UUID().uuidString)")
        for sub in folders {
            let dir = lib.appendingPathComponent(sub)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent("data"))
        }
        return lib
    }

    func testAppleAppsAreNeverMatched() {
        let found = LeftoverFinder.standard.find(bundleID: "com.apple.Safari", appName: "Safari")
        XCTAssertTrue(found.isEmpty)
    }
}
