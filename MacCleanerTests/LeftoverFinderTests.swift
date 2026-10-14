import XCTest
@testable import MacCleaner

final class LeftoverFinderTests: XCTestCase {
    private let id = "com.example.CoolApp"

    func testMatchesBundleIdentifierVariants() {
        for name in [
            "com.example.CoolApp",
            "com.example.coolapp.plist",
            "com.example.CoolApp.savedState",
            "com.example.CoolApp.helper",
            "ABCDE12345.com.example.CoolApp",
            "group.com.example.CoolApp.shared",
        ] {
            XCTAssertEqual(LeftoverFinder.match(name, bundleID: id, appName: "Cool App"), .bundleID, name)
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

    func testAppleAppsAreNeverMatched() {
        let found = LeftoverFinder.standard.find(bundleID: "com.apple.Safari", appName: "Safari")
        XCTAssertTrue(found.isEmpty)
    }
}
