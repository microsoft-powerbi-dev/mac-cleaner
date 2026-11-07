import Foundation

/// UserDefaults keys and defaults for app preferences. Views bind with `@AppStorage(Prefs.key)`;
/// model code reads the static accessors. `register()` runs at launch so both agree on defaults.
enum Prefs {
    // General
    static let showMenuBarExtra = "general.showMenuBarExtra"

    // Disk Analyzer
    static let defaultScanPath = "analyzer.defaultScanPath"
    static let hogMinSize = "analyzer.hogMinSize"
    static let oldFileDays = "analyzer.oldFileDays"
    static let largestMinSize = "analyzer.largestMinSize"
    static let duplicateMinSize = "analyzer.duplicateMinSize"

    // History
    static let recordDailyHistory = "history.recordDaily"
    static let historyLimit = "history.limit"

    // Uninstaller
    static let uninstallerSort = "uninstaller.sort"
    static let uninstallerAscending = "uninstaller.ascending"
    static let showAppleApps = "uninstaller.showAppleApps"

    static let defaults: [String: Any] = [
        showMenuBarExtra: true,
        defaultScanPath: "",
        hogMinSize: 1_000_000_000,
        oldFileDays: 365,
        largestMinSize: Int(FileFilter.MinSize.hundredMB.rawValue),
        duplicateMinSize: 1_000_000,
        recordDailyHistory: true,
        historyLimit: 365,
        uninstallerSort: AppSort.name.rawValue,
        uninstallerAscending: true,
        showAppleApps: true,
    ]

    static func register(_ store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }

    /// Removes every stored preference, so the registered defaults apply again.
    static func resetAll(_ store: UserDefaults = .standard) {
        for key in defaults.keys { store.removeObject(forKey: key) }
    }

    private static var store: UserDefaults { .standard }

    static var defaultScanURL: URL {
        let path = store.string(forKey: defaultScanPath) ?? ""
        var isDir: ObjCBool = false
        if !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var hogMinBytes: Int64 { Int64(max(100_000_000, store.integer(forKey: hogMinSize))) }
    static var oldFileDayCount: Int { max(30, store.integer(forKey: oldFileDays)) }
    static var duplicateMinBytes: Int64 { Int64(max(1, store.integer(forKey: duplicateMinSize))) }
    static var recordsDailyHistory: Bool { store.bool(forKey: recordDailyHistory) }
    static var historySnapshotLimit: Int { min(max(30, store.integer(forKey: historyLimit)), 3650) }

    static var largestMinSizeOption: FileFilter.MinSize {
        FileFilter.MinSize(rawValue: Int64(store.integer(forKey: largestMinSize))) ?? .hundredMB
    }
}

/// Sort orders for the Uninstaller's app list.
enum AppSort: String, CaseIterable, Identifiable, Sendable {
    case name, size, lastUsed, dateAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .lastUsed: return "Last Used"
        case .dateAdded: return "Date Added"
        }
    }

    /// The direction most people want when they first pick this order.
    var naturalAscending: Bool { self == .name }
}
