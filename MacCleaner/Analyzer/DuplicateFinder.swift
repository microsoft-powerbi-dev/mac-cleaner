import Foundation

/// Files with byte-identical contents.
struct DuplicateGroup: Identifiable, Sendable {
    let hash: String
    let size: Int64
    /// Sorted newest-modified first.
    let files: [FileEntry]

    var id: String { hash }
    /// Space freed by keeping only one copy.
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }

    func removing(_ urls: Set<URL>) -> DuplicateGroup {
        DuplicateGroup(hash: hash, size: size, files: files.filter { !urls.contains($0.url) })
    }
}

/// Which copy of a duplicate group to keep by default.
enum KeepRule: String, CaseIterable, Identifiable, Sendable {
    case newest = "Keep newest"
    case oldest = "Keep oldest"
    case shortestPath = "Keep shortest path"

    var id: Self { self }

    func pick(from files: [FileEntry]) -> FileEntry? {
        switch self {
        case .newest: return files.max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .oldest: return files.min { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        case .shortestPath: return files.min { ($0.url.path.count, $0.url.path) < ($1.url.path.count, $1.url.path) }
        }
    }
}

/// Finds duplicates in three passes: same size → same head/tail hash → same full SHA-256.
/// Hard links to one file are counted once. Synchronous: call from a detached task.
enum DuplicateFinder {
    static func find(
        _ candidates: [FileEntry],
        minSize: Int64 = DiskScanner.keepFileThreshold,
        cancel: CancelFlag,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> [DuplicateGroup] {
        // 1. Same size, distinct inodes.
        var bySize: [Int64: [(FileEntry, Int64)]] = [:]
        var seenInodes = Set<FileID>()
        for file in candidates {
            guard let info = statInfo(file.url), info.size >= minSize, seenInodes.insert(info.id).inserted else { continue }
            bySize[info.size, default: []].append((file, info.size))
        }
        let sizeGroups = bySize.values.filter { $0.count > 1 }

        // 2. Same head + tail.
        var partialGroups: [[(FileEntry, Int64)]] = []
        for group in sizeGroups {
            if cancel.isSet { return [] }
            var byPartial: [String: [(FileEntry, Int64)]] = [:]
            for item in group {
                if let key = FileHasher.partialHash(of: item.0.url, length: item.1) {
                    byPartial[key, default: []].append(item)
                }
            }
            partialGroups += byPartial.values.filter { $0.count > 1 }
        }

        // 3. Full hash.
        let totalBytes = max(1, partialGroups.reduce(Int64(0)) { $0 + $1.reduce(Int64(0)) { $0 + $1.1 } })
        var hashed: Int64 = 0
        var lastReported = 0.0
        var result: [DuplicateGroup] = []
        for group in partialGroups {
            var byHash: [String: [FileEntry]] = [:]
            for (file, _) in group {
                let hash = FileHasher.sha256(of: file.url, cancel: cancel) { bytes in
                    hashed += Int64(bytes)
                    let fraction = Double(hashed) / Double(totalBytes)
                    if fraction - lastReported > 0.01 {
                        lastReported = fraction
                        progress?(min(fraction, 1))
                    }
                }
                if cancel.isSet { return [] }
                if let hash { byHash[hash, default: []].append(file) }
            }
            for (hash, files) in byHash where files.count > 1 {
                let sorted = files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
                result.append(DuplicateGroup(hash: hash, size: files[0].size, files: sorted))
            }
        }
        progress?(1)
        return result.sorted { $0.wasted > $1.wasted }
    }

    private struct FileID: Hashable {
        let device: Int32
        let inode: UInt64
    }

    /// Logical size and inode from `lstat`. Skips anything that isn't a regular file.
    private static func statInfo(_ url: URL) -> (id: FileID, size: Int64)? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return (FileID(device: st.st_dev, inode: st.st_ino), Int64(st.st_size))
    }
}
