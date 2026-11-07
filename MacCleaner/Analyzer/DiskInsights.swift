import Foundation

/// A folder that is itself responsible for a lot of space, with the path from the scan root to it.
struct SpaceHog: Identifiable, Sendable {
    let node: DiskNode
    /// Scan root first, `node` last. Assigning it to `AnalyzerModel.path` opens the folder.
    let chain: [DiskNode]
    /// Bytes held directly by this folder, not by a sub-folder that is itself listed.
    let ownBytes: Int64

    var id: URL { node.url }
}

enum DiskInsights {
    static let defaultHogSize: Int64 = 1_000_000_000

    /// The folders that actually hold the space. A folder is listed when at least `minSize`
    /// of its bytes are *not* inside a sub-folder that is itself at least `minSize`, so
    /// `~/Library` isn't listed just because `~/Library/Developer/Xcode/DerivedData` is big.
    static func spaceHogs(root: DiskNode, minSize: Int64 = defaultHogSize, limit: Int = 25) -> [SpaceHog] {
        var out: [SpaceHog] = []
        collect(root, chain: [root], minSize: minSize, isRoot: true, into: &out)
        return Array(out.sorted { $0.node.size > $1.node.size }.prefix(limit))
    }

    private static func collect(_ node: DiskNode, chain: [DiskNode], minSize: Int64, isRoot: Bool, into out: inout [SpaceHog]) {
        guard node.isDirectory, node.size >= minSize else { return }
        let bigKids = node.children.filter { $0.isDirectory && $0.size >= minSize }
        let leftover = node.size - bigKids.reduce(Int64(0)) { $0 + $1.size }
        if !isRoot && leftover >= minSize {
            out.append(SpaceHog(node: node, chain: chain, ownBytes: leftover))
        }
        for kid in bigKids {
            collect(kid, chain: chain + [kid], minSize: minSize, isRoot: false, into: &out)
        }
    }

    /// The chain of nodes from `root` to the node at `url`, or nil when it isn't in the tree.
    static func chain(to url: URL, in root: DiskNode) -> [DiskNode]? {
        if root.url == url { return [root] }
        let target = url.path
        for child in root.children where child.isDirectory {
            let prefix = child.url.path.hasSuffix("/") ? child.url.path : child.url.path + "/"
            if child.url == url || target.hasPrefix(prefix), let rest = chain(to: url, in: child) {
                return [root] + rest
            }
        }
        return nil
    }
}

/// Filters for the "Largest" tab. Pure, so it can be unit tested.
struct FileFilter: Equatable, Sendable {
    enum MinSize: Int64, CaseIterable, Identifiable, Sendable {
        case oneMB = 1_000_000, tenMB = 10_000_000, hundredMB = 100_000_000, oneGB = 1_000_000_000, fiveGB = 5_000_000_000
        var id: Self { self }
        var title: String { "≥ " + Format.bytes(rawValue) }
    }

    enum Age: Int, CaseIterable, Identifiable, Sendable {
        case any = 0, month = 30, sixMonths = 182, year = 365, twoYears = 730
        var id: Self { self }
        var title: String {
            switch self {
            case .any: return "Any time"
            case .month: return "Not opened in 1 month"
            case .sixMonths: return "Not opened in 6 months"
            case .year: return "Not opened in 1 year"
            case .twoYears: return "Not opened in 2 years"
            }
        }
    }

    var kinds: Set<FileKind> = []          // empty = every kind
    var minSize: MinSize = .hundredMB
    var age: Age = .any
    var nameQuery = ""
    var locationQuery = ""
    var limit = 200

    func apply(_ files: [FileEntry], now: Date = Date()) -> [FileEntry] {
        let name = nameQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let location = locationQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let cutoff = now.addingTimeInterval(-Double(age.rawValue) * 86_400)
        var out: [FileEntry] = []
        for file in files where file.size >= minSize.rawValue {
            if !kinds.isEmpty && !kinds.contains(file.kind) { continue }
            if age != .any {
                guard let used = file.lastAccess ?? file.modified, used < cutoff else { continue }
            }
            if !name.isEmpty && !file.name.lowercased().contains(name) { continue }
            if !location.isEmpty && !file.url.deletingLastPathComponent().abbreviatedPath.lowercased().contains(location) { continue }
            out.append(file)
        }
        out.sort { $0.size > $1.size }
        return Array(out.prefix(limit))
    }
}
