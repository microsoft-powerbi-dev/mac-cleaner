import Foundation

struct DiskNode: Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    /// Sub-folders, plus files of at least `DiskScanner.keepFileThreshold`, largest first.
    let children: [DiskNode]

    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

struct FileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let lastAccess: Date?
    var modified: Date? = nil
    var kind: FileKind = .other

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct DiskScanResult: Sendable {
    let root: DiskNode
    /// Every file of at least `DiskScanner.keepFileThreshold`, largest first (capped).
    let files: [FileEntry]
    /// Bytes per kind and per modification age, over every file scanned (not only large ones).
    let kindTotals: [FileKind: Int64]
    let ageTotals: [AgeBucket: Int64]
    let fileCount: Int
    let scannedAt: Date

    var largeFiles: [FileEntry] { files.filter { $0.size >= DiskScanner.largeFileThreshold } }

    var oldFiles: [FileEntry] { oldFiles(notOpenedForDays: 365) }

    func oldFiles(notOpenedForDays days: Int) -> [FileEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: scannedAt) ?? scannedAt
        return files.filter { file in
            guard file.size >= DiskScanner.oldFileThreshold, let accessed = file.lastAccess else { return false }
            return accessed < cutoff
        }
    }
}

/// A thread-safe flag that tells a running scan to stop.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Walks a folder tree once and builds a size tree, a list of big files and per-kind totals.
/// Runs synchronously. Call it from a detached task.
final class DiskScanner {
    static let keepFileThreshold: Int64 = 1_000_000      // files shown in the tree and kept in `files`
    static let largeFileThreshold: Int64 = 100_000_000   // "Large files" default
    static let oldFileThreshold: Int64 = 10_000_000      // "Old files" tab (and not opened for a year)
    static let maxFiles = 50_000

    private let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey, .contentModificationDateKey,
    ]
    private let skip: Set<String>
    private let cancel: CancelFlag
    private let now = Date()
    private var files: [FileEntry] = []
    private var kindTotals: [FileKind: Int64] = [:]
    private var ageTotals: [AgeBucket: Int64] = [:]
    private var fileCount = 0
    private var extensionCache: [String: FileKind] = [:]
    /// (device, inode) of every directory walked, so a folder reachable through
    /// several paths (firmlinks, /.nofollow, bind mounts) is only counted once.
    private var visited: Set<DirID> = []

    private struct DirID: Hashable { let dev: dev_t; let ino: ino_t }

    init(cancel: CancelFlag) {
        self.cancel = cancel
        let lib = FileManager.default.homeDirectoryForCurrentUser.path + "/Library"
        // Cloud folders hold placeholders. /System/Volumes, /.nofollow and /.resolve are
        // alternate views of the same volumes and would count everything again.
        skip = [lib + "/Mobile Documents", lib + "/CloudStorage", "/System/Volumes", "/Volumes", "/dev",
                "/.nofollow", "/.resolve", "/.vol"]
    }

    func scan(_ root: URL) -> DiskScanResult {
        let tree = walk(root, context: nil)
        files.sort { $0.size > $1.size }
        return DiskScanResult(
            root: tree,
            files: Array(files.prefix(Self.maxFiles)),
            kindTotals: kindTotals,
            ageTotals: ageTotals,
            fileCount: fileCount,
            scannedAt: now
        )
    }

    private func walk(_ dir: URL, context: FileKind?) -> DiskNode {
        let fm = FileManager.default
        guard !cancel.isSet, !skip.contains(dir.path), markVisited(dir),
              let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)
        else {
            return DiskNode(url: dir, isDirectory: true, size: 0, children: [])
        }

        let keySet = Set(keys)
        var total: Int64 = 0
        var nodes: [DiskNode] = []
        for entry in entries {
            guard let v = try? entry.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                let child = walk(entry, context: context ?? FileKind.directoryContext(entry.lastPathComponent))
                total += child.size
                if child.size > 0 { nodes.append(child) }
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                total += size
                fileCount += 1
                let kind = FileKind.classify(fileName: entry.lastPathComponent, context: context, cache: &extensionCache)
                kindTotals[kind, default: 0] += size
                ageTotals[AgeBucket.bucket(for: v.contentModificationDate, now: now), default: 0] += size
                if size >= Self.keepFileThreshold {
                    nodes.append(DiskNode(url: entry, isDirectory: false, size: size, children: []))
                    files.append(FileEntry(
                        url: entry, size: size, lastAccess: v.contentAccessDate,
                        modified: v.contentModificationDate, kind: kind
                    ))
                }
            }
        }
        nodes.sort { $0.size > $1.size }
        return DiskNode(url: dir, isDirectory: true, size: total, children: nodes)
    }

    /// Returns false if this directory was already walked via another path.
    private func markVisited(_ dir: URL) -> Bool {
        var st = stat()
        guard lstat(dir.path, &st) == 0 else { return true }
        return visited.insert(DirID(dev: st.st_dev, ino: st.st_ino)).inserted
    }
}
