import Foundation

/// Measures on-disk (allocated) size. This is synchronous on purpose. Call it from a
/// background task, because directory enumerators can't be iterated in async code.
enum FileSizer {
    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return allocated(values) }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        )
        var total: Int64 = 0
        while let child = enumerator?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            if v.isDirectory != true { total += allocated(v) }
        }
        return total
    }

    private static func allocated(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }
}
