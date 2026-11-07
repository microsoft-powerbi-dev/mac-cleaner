import CoreServices
import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let size: Int64
    /// From Spotlight (`kMDItemLastUsedDate`). nil when the app was never opened or Spotlight is off.
    var lastUsed: Date? = nil
    /// When the app arrived in its folder (`kMDItemDateAdded`, else the bundle's creation date).
    var dateAdded: Date? = nil

    var id: URL { url }
    var isApple: Bool { bundleID?.lowercased().hasPrefix("com.apple.") ?? false }
}

enum AppInventory {
    static var searchFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    static func load() async -> [InstalledApp] {
        let bundles = searchFolders.flatMap { findAppBundles(in: $0) }
        let apps = await withTaskGroup(of: InstalledApp.self) { group in
            for url in bundles {
                group.addTask(priority: .userInitiated) { describe(url) }
            }
            var out: [InstalledApp] = []
            for await app in group { out.append(app) }
            return out
        }
        return sorted(apps, by: .name, ascending: true)
    }

    /// Sorts `apps`. Apps without a date go last in either direction; ties fall back to name.
    static func sorted(_ apps: [InstalledApp], by sort: AppSort, ascending: Bool) -> [InstalledApp] {
        func byName(_ a: InstalledApp, _ b: InstalledApp) -> Bool {
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        func byDate(_ a: Date?, _ b: Date?, _ x: InstalledApp, _ y: InstalledApp) -> Bool {
            switch (a, b) {
            case let (a?, b?): return a == b ? byName(x, y) : (ascending ? a < b : a > b)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return byName(x, y)
            }
        }
        return apps.sorted { x, y in
            switch sort {
            case .name:
                let order = x.name.localizedCaseInsensitiveCompare(y.name)
                if order == .orderedSame { return x.url.path < y.url.path }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            case .size:
                return x.size == y.size ? byName(x, y) : (ascending ? x.size < y.size : x.size > y.size)
            case .lastUsed:
                return byDate(x.lastUsed, y.lastUsed, x, y)
            case .dateAdded:
                return byDate(x.dateAdded, y.dateAdded, x, y)
            }
        }
    }

    /// Finds `.app` bundles in `folder`, plus one level of subfolders (e.g. /Applications/Utilities).
    static func findAppBundles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        var result: [URL] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if child.pathExtension == "app" {
                result.append(child)
            } else if values?.isDirectory == true {
                let nested = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                result += nested.filter { $0.pathExtension == "app" }
            }
        }
        return result
    }

    static func describe(_ url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(
            url: url,
            name: name,
            bundleID: bundle?.bundleIdentifier,
            version: info?["CFBundleShortVersionString"] as? String,
            size: FileSizer.size(of: url),
            lastUsed: spotlightDate(url, kMDItemLastUsedDate),
            dateAdded: spotlightDate(url, kMDItemDateAdded)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
        )
    }

    private static func spotlightDate(_ url: URL, _ attribute: CFString) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, attribute) as? Date
    }
}
