import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let size: Int64

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
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            size: FileSizer.size(of: url)
        )
    }
}
