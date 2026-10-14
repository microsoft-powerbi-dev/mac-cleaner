import Foundation

/// The last line of defence before anything is removed from disk.
///
/// Every deletion goes through `validate(_:)`. A path is only allowed when it is
/// strictly inside an allowed root, not inside a protected subtree, not itself a
/// protected folder, and reached without passing through a symlink.
/// Comparisons are case-insensitive because APFS volumes usually are.
struct SafetyGuard: Sendable {
    enum Violation: LocalizedError, Equatable {
        case notAbsolute(String)
        case outsideAllowedRoots(String)
        case protected(String)
        case symlinkInPath(String)
        case missingParent(String)

        var errorDescription: String? {
            switch self {
            case .notAbsolute(let p): return "Not an absolute path: \(p)"
            case .outsideAllowedRoots(let p): return "Outside the folders MacCleaner may touch: \(p)"
            case .protected(let p): return "Protected location: \(p)"
            case .symlinkInPath(let p): return "Path goes through a symbolic link: \(p)"
            case .missingParent(let p): return "Parent folder not found: \(p)"
            }
        }
    }

    private let allowedRoots: [String]
    private let protectedSubtrees: [String]
    private let protectedExact: Set<String>

    init(allowedRoots: [String], protectedSubtrees: [String], protectedExact: [String]) {
        self.allowedRoots = allowedRoots.map(Self.normalize)
        self.protectedSubtrees = protectedSubtrees.map(Self.normalize)
        self.protectedExact = Set(protectedExact.map(Self.normalize))
    }

    static let standard: SafetyGuard = {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let lib = home + "/Library"
        return SafetyGuard(
            allowedRoots: [home, "/Applications"],
            protectedSubtrees: [
                "/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/opt", "/cores", "/Volumes",
                lib + "/Mobile Documents",   // iCloud Drive
                lib + "/CloudStorage",       // Dropbox, OneDrive, Google Drive
                lib + "/Keychains",
                lib + "/Accounts",
                lib + "/Messages",
                lib + "/Mail",
                lib + "/Calendars",
                lib + "/Safari",
                home + "/Pictures/Photos Library.photoslibrary",
            ],
            protectedExact: [
                home, "/Applications", home + "/Applications",
                home + "/Desktop", home + "/Documents", home + "/Downloads",
                home + "/Movies", home + "/Music", home + "/Pictures", home + "/Public",
                home + "/.Trash", home + "/.npm", home + "/.cache", home + "/.gradle",
                lib,
                lib + "/Caches", lib + "/Logs", lib + "/Preferences",
                lib + "/Application Support", lib + "/Containers", lib + "/Group Containers",
                lib + "/Saved Application State", lib + "/HTTPStorages", lib + "/WebKit",
                lib + "/LaunchAgents", lib + "/Cookies", lib + "/Application Scripts",
                lib + "/Developer", lib + "/Developer/Xcode", lib + "/Developer/CoreSimulator",
            ]
        )
    }()

    /// Pure string check, with no file system access.
    func checkPolicy(_ rawPath: String) throws {
        guard rawPath.hasPrefix("/") else { throw Violation.notAbsolute(rawPath) }
        let path = Self.normalize(rawPath)
        if protectedExact.contains(path)
            || protectedSubtrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            throw Violation.protected(rawPath)
        }
        guard allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) else {
            throw Violation.outsideAllowedRoots(rawPath)
        }
    }

    /// Full check before deleting `url`: policy, symlinks in the parent chain, own bundle.
    func validate(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        try checkPolicy(path)

        let parent = (path as NSString).deletingLastPathComponent
        guard let resolved = Self.realPath(parent) else { throw Violation.missingParent(path) }
        guard Self.normalize(resolved) == Self.normalize(parent) else { throw Violation.symlinkInPath(path) }

        let ownBundle = Self.normalize(Bundle.main.bundlePath)
        let normalized = Self.normalize(path)
        if normalized == ownBundle || normalized.hasPrefix(ownBundle + "/") {
            throw Violation.protected(path)
        }
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath.lowercased()
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
