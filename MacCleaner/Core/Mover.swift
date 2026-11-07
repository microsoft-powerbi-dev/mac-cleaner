import Foundation

struct MoveReport: Sendable {
    struct Moved: Sendable, Identifiable {
        let source: URL
        let destination: URL
        let bytes: Int64
        var id: URL { source }
    }

    var moved: [Moved] = []
    var failures: [DeletionReport.Failure] = []
    var destinationName = ""

    var bytesMoved: Int64 { moved.reduce(0) { $0 + $1.bytes } }
}

/// Moves items to another disk, a NAS share or iCloud Drive: copy → verify → move the original
/// to the Trash. The original goes through `Trasher` (and so `SafetyGuard`), and it is only
/// touched after the copy has been verified, so a failed move never loses data.
enum Mover {
    enum MoveError: LocalizedError, Equatable {
        case destinationMissing
        case destinationNotWritable
        case destinationInsideSource
        case alreadyThere
        case notEnoughSpace(needed: Int64, available: Int64)
        case verifyFailed

        var errorDescription: String? {
            switch self {
            case .destinationMissing: return "The destination folder isn't available. Is the drive or share connected?"
            case .destinationNotWritable: return "MacCleaner can't write to the destination."
            case .destinationInsideSource: return "The destination is inside the item being moved."
            case .alreadyThere: return "The item is already in the destination folder."
            case .notEnoughSpace(let needed, let available):
                return "Not enough space at the destination: needs \(Format.bytes(needed)), \(Format.bytes(available)) free."
            case .verifyFailed: return "The copy didn't match the original, so the original was kept."
            }
        }
    }

    typealias Progress = @Sendable (_ completed: Int, _ total: Int, _ current: String) -> Void

    static func move(
        _ items: [URL], to destination: URL, safety: SafetyGuard = .standard,
        originalMode: Trasher.Mode = .moveToTrash, progress: Progress? = nil
    ) async -> MoveReport {
        guard !items.isEmpty else { return MoveReport() }
        return await Task.detached(priority: .userInitiated) {
            moveSync(items, to: destination, safety: safety, originalMode: originalMode, progress: progress)
        }.value
    }

    static func moveSync(
        _ items: [URL], to destination: URL, safety: SafetyGuard,
        originalMode: Trasher.Mode = .moveToTrash, progress: Progress? = nil
    ) -> MoveReport {
        let fm = FileManager.default
        var report = MoveReport(destinationName: destination.lastPathComponent)
        for (index, url) in items.enumerated() {
            progress?(index, items.count, url.lastPathComponent)
            var copy: URL?
            do {
                // Moving removes the original, so it must pass the same checks as deleting it.
                let source = try safety.validate(url)
                let content = contentSummary(source)
                try checkDestination(destination, for: source, needed: content.bytes)

                let target = uniqueDestination(for: source.lastPathComponent, in: destination)
                try fm.copyItem(at: source, to: target)
                copy = target
                guard verify(source: source, copy: target, expected: content) else { throw MoveError.verifyFailed }

                let removal = Trasher.removeSync([source], mode: originalMode, safety: safety)
                if let failure = removal.failures.first {
                    // Copy is good but the original couldn't be removed: keep both, report it.
                    report.failures.append(.init(url: url, reason: "Copied to \(target.path), but the original couldn't be removed: \(failure.reason)"))
                    continue
                }
                report.moved.append(.init(source: url, destination: target, bytes: content.bytes))
            } catch {
                if let copy { try? fm.removeItem(at: copy) }
                report.failures.append(.init(url: url, reason: error.localizedDescription))
            }
        }
        progress?(items.count, items.count, "")
        return report
    }

    // MARK: Checks

    static func checkDestination(_ destination: URL, for source: URL, needed: Int64) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue else {
            throw MoveError.destinationMissing
        }
        guard fm.isWritableFile(atPath: destination.path) else { throw MoveError.destinationNotWritable }

        let src = normalized(source.path)
        let dst = normalized(SafetyGuard.realPath(destination.path) ?? destination.path)
        if dst == src || dst.hasPrefix(src + "/") { throw MoveError.destinationInsideSource }
        if normalized(source.deletingLastPathComponent().path) == dst { throw MoveError.alreadyThere }

        if let available = availableSpace(at: destination), available < needed {
            throw MoveError.notEnoughSpace(needed: needed, available: available)
        }
    }

    /// Free bytes at `url`, or nil when the volume doesn't report it (some network shares).
    static func availableSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = values?.volumeAvailableCapacity, plain > 0 { return Int64(plain) }
        return nil
    }

    /// `name`, or `name 2.ext`, `name 3.ext`… — the first that doesn't exist in `directory`.
    static func uniqueDestination(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }

    // MARK: Verification

    struct ContentSummary: Equatable, Sendable {
        var bytes: Int64 = 0
        var files = 0
    }

    /// Logical bytes and file count. Logical (not allocated) size, because block sizes differ
    /// between APFS, exFAT and network shares.
    static func contentSummary(_ url: URL) -> ContentSummary {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return ContentSummary() }
        guard v.isDirectory == true else { return ContentSummary(bytes: Int64(v.fileSize ?? 0), files: 1) }
        var summary = ContentSummary()
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let child = enumerator?.nextObject() as? URL {
            guard let cv = try? child.resourceValues(forKeys: keys), cv.isDirectory != true, cv.isSymbolicLink != true else { continue }
            summary.bytes += Int64(cv.fileSize ?? 0)
            summary.files += 1
        }
        return summary
    }

    static let hashVerifyLimit: Int64 = 2_000_000_000

    static func verify(source: URL, copy: URL, expected: ContentSummary) -> Bool {
        guard contentSummary(copy) == expected else { return false }
        let isFile = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
        if isFile && expected.bytes <= hashVerifyLimit {
            guard let a = FileHasher.sha256(of: source), let b = FileHasher.sha256(of: copy) else { return false }
            return a == b
        }
        return true
    }

    private static func normalized(_ path: String) -> String {
        SafetyGuard.lexical(path).lowercased()
    }
}
