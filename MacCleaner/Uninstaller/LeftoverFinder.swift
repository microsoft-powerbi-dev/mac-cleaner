import Foundation

struct Leftover: Identifiable, Hashable, Sendable {
    enum Match: Sendable {
        /// Matched by bundle identifier. High confidence.
        case bundleID
        /// Matched by folder name only. Lower confidence, so it starts unchecked.
        case appName
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

    func find(bundleID: String?, appName: String) -> [Leftover] {
        if bundleID?.lowercased().hasPrefix("com.apple.") == true { return [] }
        let fm = FileManager.default
        var found: [Leftover] = []
        for sub in Self.subfolders {
            let dir = libraryRoot.appendingPathComponent(sub)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                guard let match = Self.match(name, bundleID: bundleID, appName: appName) else { continue }
                let url = dir.appendingPathComponent(name)
                found.append(Leftover(url: url, size: FileSizer.size(of: url), match: match))
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    static func match(_ fileName: String, bundleID: String?, appName: String) -> Leftover.Match? {
        let name = fileName.lowercased()
        if let id = bundleID?.lowercased(), !id.isEmpty {
            // com.foo.app, com.foo.app.plist, com.foo.app.savedState, com.foo.app.helper
            if name == id || name.hasPrefix(id + ".") { return .bundleID }
            // Group containers: TEAMID.com.foo.app, group.com.foo.app.shared
            if name.hasSuffix("." + id) || name.contains("." + id + ".") { return .bundleID }
        }
        let app = appName.lowercased()
        // Short names such as "Mail" or "Zoom" would match too much, so require a few characters.
        if app.count >= 4, name == app { return .appName }
        return nil
    }
}
