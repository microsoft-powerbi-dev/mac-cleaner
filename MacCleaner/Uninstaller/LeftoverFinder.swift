import Foundation

struct Leftover: Identifiable, Hashable, Sendable {
    enum Match: Sendable {
        /// Matched by bundle identifier. High confidence.
        case bundleID
        /// Starts with the bundle identifier but is longer, e.g. `com.foo.app.helper` or
        /// `com.foo.app.beta`. Could be a helper or a different edition, so it starts unchecked.
        case related
        /// Matched by folder name only. Lower confidence, so it starts unchecked.
        case appName
        /// A Group Container. Apps from the same developer often share these, so it starts unchecked.
        case sharedGroup
    }

    let url: URL
    let size: Int64
    let match: Match
    var id: URL { url }
}

/// Finds an app's support files in ~/Library, the same approach AppCleaner, PureMac and Mole use.
struct LeftoverFinder: Sendable {
    let libraryRoot: URL

    static let standard = LeftoverFinder(
        libraryRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    )

    static let subfolders = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs", "LaunchAgents",
        "Cookies", "Application Scripts",
    ]

    /// `otherBundleIDs` are the bundle identifiers of the other installed apps. Files that
    /// belong to one of them are never returned, e.g. `com.foo.app.beta.plist` when uninstalling
    /// `com.foo.app` while `com.foo.app.beta` is still installed.
    func find(bundleID: String?, appName: String, otherBundleIDs: Set<String> = []) -> [Leftover] {
        if bundleID?.lowercased().hasPrefix("com.apple.") == true { return [] }
        let others = Set(otherBundleIDs.map { $0.lowercased() })
        let ownID = bundleID?.lowercased() ?? ""
        // Another copy of the same app is still installed, so its files are still in use.
        if !ownID.isEmpty && others.contains(ownID) { return [] }
        let moreSpecific = others.filter { $0.hasPrefix(ownID + ".") }

        let fm = FileManager.default
        var found: [Leftover] = []
        for sub in Self.subfolders {
            let dir = libraryRoot.appendingPathComponent(sub)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                guard var match = Self.match(name, bundleID: bundleID, appName: appName) else { continue }
                if moreSpecific.contains(where: { Self.match(name, bundleID: $0, appName: "") != nil }) { continue }
                if sub == "Group Containers" && match == .bundleID { match = .sharedGroup }
                let url = dir.appendingPathComponent(name)
                found.append(Leftover(url: url, size: FileSizer.size(of: url), match: match))
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    /// File extensions the app itself adds to its bundle identifier.
    private static let ownSuffixes: Set<String> = ["plist", "savedstate", "binarycookies"]

    static func match(_ fileName: String, bundleID: String?, appName: String) -> Leftover.Match? {
        let name = fileName.lowercased()
        if let id = bundleID?.lowercased(), !id.isEmpty {
            // com.foo.app, com.foo.app.plist, com.foo.app.savedState, TEAMID.com.foo.app
            if name == id || name.hasSuffix("." + id) { return .bundleID }
            if name.hasPrefix(id + "."),
               ownSuffixes.contains(String(name.dropFirst(id.count + 1))) { return .bundleID }
            // com.foo.app.helper, com.foo.app.beta, group.com.foo.app.shared
            if name.hasPrefix(id + ".") || name.contains("." + id + ".") { return .related }
        }
        let app = appName.lowercased()
        // Short names such as "Mail" or "Zoom" would match too much, so require a few characters.
        if app.count >= 4, name == app { return .appName }
        return nil
    }
}
