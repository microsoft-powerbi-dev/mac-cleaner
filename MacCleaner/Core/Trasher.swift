import Foundation

struct DeletionReport: Sendable {
    struct Failure: Sendable, Identifiable {
        let url: URL
        let reason: String
        var id: URL { url }
    }

    var removed: [URL] = []
    var failures: [Failure] = []
    var bytesFreed: Int64 = 0
    var movedToTrash = true

    mutating func merge(_ other: DeletionReport) {
        removed += other.removed
        failures += other.failures
        bytesFreed += other.bytesFreed
        movedToTrash = movedToTrash && other.movedToTrash
    }
}

enum Trasher {
    enum Mode: Sendable {
        case moveToTrash
        case deletePermanently
    }

    /// Removes `items` after every one passes `SafetyGuard`. Runs off the main thread.
    static func remove(_ items: [URL], mode: Mode, safety: SafetyGuard = .standard) async -> DeletionReport {
        guard !items.isEmpty else { return DeletionReport() }
        return await Task.detached(priority: .userInitiated) {
            removeSync(items, mode: mode, safety: safety)
        }.value
    }

    static func removeSync(_ items: [URL], mode: Mode, safety: SafetyGuard) -> DeletionReport {
        let fm = FileManager.default
        var report = DeletionReport(movedToTrash: mode == .moveToTrash)
        for url in items {
            do {
                try safety.validate(url)
                let size = FileSizer.size(of: url)
                switch mode {
                case .moveToTrash: try fm.trashItem(at: url, resultingItemURL: nil)
                case .deletePermanently: try fm.removeItem(at: url)
                }
                report.removed.append(url)
                report.bytesFreed += size
            } catch {
                report.failures.append(.init(url: url, reason: error.localizedDescription))
            }
        }
        return report
    }
}
