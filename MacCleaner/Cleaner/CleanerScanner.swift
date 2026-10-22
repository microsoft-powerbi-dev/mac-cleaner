import Foundation

struct ScanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    /// For targets that keep child folders: the child folder this item is inside, which is
    /// usually the owning app's bundle identifier (e.g. "com.foo.app" in ~/Library/Caches).
    var owner: String? = nil
    var id: URL { url }

    /// Short label for the preview list, e.g. "com.foo.app/Cache.db".
    var displayName: String {
        owner.map { "\($0)/\(url.lastPathComponent)" } ?? url.lastPathComponent
    }
}

struct CategoryResult: Identifiable, Sendable {
    let category: CleanupCategory
    let items: [ScanItem]
    var id: String { category.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum CleanerScanner {
    static func scan(_ categories: [CleanupCategory]) async -> [CategoryResult] {
        let results = await withTaskGroup(of: CategoryResult.self) { group in
            for category in categories {
                group.addTask(priority: .userInitiated) { scanSync(category) }
            }
            var out: [CategoryResult] = []
            for await result in group { out.append(result) }
            return out
        }
        let order = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1.id, $0) })
        return results.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    static func scanSync(_ category: CleanupCategory) -> CategoryResult {
        let fm = FileManager.default
        var items: [ScanItem] = []
        for target in category.targets {
            let root = URL(fileURLWithPath: target.expandedPath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }

            if target.contentsOnly && isDir.boolValue {
                let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                for child in children where !target.excluding.contains(child.lastPathComponent) {
                    let isChildDir = (try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                        .map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
                    if target.keepChildFolders && isChildDir {
                        let owner = child.lastPathComponent
                        let inner = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                        for item in inner {
                            let size = FileSizer.size(of: item)
                            if size > 0 { items.append(ScanItem(url: item, size: size, owner: owner)) }
                        }
                    } else {
                        let size = FileSizer.size(of: child)
                        if size > 0 { items.append(ScanItem(url: child, size: size)) }
                    }
                }
            } else {
                let size = FileSizer.size(of: root)
                if size > 0 { items.append(ScanItem(url: root, size: size)) }
            }
        }
        return CategoryResult(category: category, items: items.sorted { $0.size > $1.size })
    }
}
