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

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct DiskScanResult: Sendable {
    let root: DiskNode
    let largeFiles: [FileEntry]
    let oldFiles: [FileEntry]
}

/// A thread-safe flag that tells a running scan to stop.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Walks a folder tree once and builds a size tree plus "large" and "old" file lists.
/// Runs synchronously. Call it from a detached task.
final class DiskScanner {
    static let keepFileThreshold: Int64 = 1_000_000      // files shown in the tree
    static let largeFileThreshold: Int64 = 100_000_000   // "Large files" tab
    static let oldFileThreshold: Int64 = 10_000_000      // "Old files" tab (and not opened for a year)

    private let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey,
    ]
    private let skip: Set<String>
    private let cancel: CancelFlag
    private let oldCutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    private var large: [FileEntry] = []
    private var old: [FileEntry] = []

    init(cancel: CancelFlag) {
        self.cancel = cancel
        let lib = FileManager.default.homeDirectoryForCurrentUser.path + "/Library"
        // Cloud folders hold placeholders. /System/Volumes would count the data volume twice.
        skip = [lib + "/Mobile Documents", lib + "/CloudStorage", "/System/Volumes", "/Volumes", "/dev"]
    }

    func scan(_ root: URL) -> DiskScanResult {
        let tree = walk(root)
        return DiskScanResult(
            root: tree,
            largeFiles: Array(large.sorted { $0.size > $1.size }.prefix(500)),
            oldFiles: Array(old.sorted { $0.size > $1.size }.prefix(500))
        )
    }

    private func walk(_ dir: URL) -> DiskNode {
        let fm = FileManager.default
        guard !cancel.isSet, !skip.contains(dir.path),
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
                let child = walk(entry)
                total += child.size
                if child.size > 0 { nodes.append(child) }
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                total += size
                if size >= Self.keepFileThreshold {
                    nodes.append(DiskNode(url: entry, isDirectory: false, size: size, children: []))
                }
                if size >= Self.largeFileThreshold {
                    large.append(FileEntry(url: entry, size: size, lastAccess: v.contentAccessDate))
                }
                if size >= Self.oldFileThreshold, let accessed = v.contentAccessDate, accessed < oldCutoff {
                    old.append(FileEntry(url: entry, size: size, lastAccess: accessed))
                }
            }
        }
        nodes.sort { $0.size > $1.size }
        return DiskNode(url: dir, isDirectory: true, size: total, children: nodes)
    }
}
