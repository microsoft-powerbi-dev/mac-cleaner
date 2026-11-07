import Foundation

/// One point in the disk-usage history: the startup volume, plus the scanned folder when a scan produced it.
struct UsageSnapshot: Codable, Identifiable, Sendable, Equatable {
    var date: Date
    var volumeTotal: Int64
    var volumeAvailable: Int64
    /// nil for a volume-only snapshot recorded at launch.
    var rootPath: String?
    var rootSize: Int64?
    /// Size of each direct child of the scanned folder (the 20 largest).
    var topFolders: [String: Int64] = [:]
    /// `FileKind.rawValue` → bytes.
    var kindTotals: [String: Int64] = [:]

    var id: Date { date }
    var volumeUsed: Int64 { max(0, volumeTotal - volumeAvailable) }
    var isScan: Bool { rootPath != nil }

    init(date: Date, volumeTotal: Int64, volumeAvailable: Int64, rootPath: String? = nil, rootSize: Int64? = nil,
         topFolders: [String: Int64] = [:], kindTotals: [String: Int64] = [:]) {
        self.date = date
        self.volumeTotal = volumeTotal
        self.volumeAvailable = volumeAvailable
        self.rootPath = rootPath
        self.rootSize = rootSize
        self.topFolders = topFolders
        self.kindTotals = kindTotals
    }

    init(scan: DiskScanResult, volume: (free: Int64, total: Int64)) {
        let top = scan.root.children.filter(\.isDirectory).prefix(20)
        self.init(
            date: scan.scannedAt,
            volumeTotal: volume.total,
            volumeAvailable: volume.free,
            rootPath: scan.root.url.path,
            rootSize: scan.root.size,
            topFolders: Dictionary(top.map { ($0.name, $0.size) }, uniquingKeysWith: max),
            kindTotals: Dictionary(uniqueKeysWithValues: scan.kindTotals.map { ($0.key.rawValue, $0.value) })
        )
    }
}

/// How one folder changed between two snapshots.
struct FolderChange: Identifiable, Sendable, Equatable {
    let name: String
    let before: Int64
    let after: Int64

    var id: String { name }
    var delta: Int64 { after - before }
}

enum UsageHistory {
    /// Folder-by-folder changes, biggest absolute change first. Folders that are missing on one
    /// side count as 0 there.
    static func diff(from old: UsageSnapshot, to new: UsageSnapshot) -> [FolderChange] {
        let names = Set(old.topFolders.keys).union(new.topFolders.keys)
        return names
            .map { FolderChange(name: $0, before: old.topFolders[$0] ?? 0, after: new.topFolders[$0] ?? 0) }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
    }
}

/// Stores snapshots as JSON in Application Support. Small file; reads and writes are synchronous.
struct UsageHistoryStore: Sendable {
    static let maxSnapshots = 365

    let fileURL: URL

    static let standard: UsageHistoryStore = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return UsageHistoryStore(directory: support.appendingPathComponent("MacCleaner", isDirectory: true))
    }()

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("usage-history.json")
    }

    func load() -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([UsageSnapshot].self, from: data)) ?? []).sorted { $0.date < $1.date }
    }

    func save(_ snapshots: [UsageSnapshot]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshots).write(to: fileURL, options: .atomic)
    }

    /// Adds `snapshot`, keeping at most one volume-only snapshot per day and the newest `maxSnapshots`.
    @discardableResult
    func append(_ snapshot: UsageSnapshot, limit: Int = UsageHistoryStore.maxSnapshots) -> [UsageSnapshot] {
        var all = load()
        if !snapshot.isScan {
            all.removeAll { !$0.isScan && Calendar.current.isDate($0.date, inSameDayAs: snapshot.date) }
        }
        all.append(snapshot)
        all.sort { $0.date < $1.date }
        if all.count > limit { all.removeFirst(all.count - limit) }
        try? save(all)
        return all
    }

    /// Records the startup volume's usage once per day.
    func recordVolumeSnapshotIfNeeded(now: Date = Date(), volume: (free: Int64, total: Int64), limit: Int = UsageHistoryStore.maxSnapshots) {
        guard volume.total > 0 else { return }
        if load().contains(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }) { return }
        append(UsageSnapshot(date: now, volumeTotal: volume.total, volumeAvailable: volume.free), limit: limit)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
