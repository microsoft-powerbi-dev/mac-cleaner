import CryptoKit
import Foundation

/// Streaming SHA-256 of file contents. Synchronous: call from a background task.
enum FileHasher {
    static let chunkSize = 1 << 20

    /// Hash of the whole file, or nil if it can't be read or `cancel` was set.
    static func sha256(of url: URL, cancel: CancelFlag? = nil, onBytes: ((Int) -> Void)? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if cancel?.isSet == true { return nil }
            let chunk: Data?
            do { chunk = try handle.read(upToCount: chunkSize) } catch { return nil }
            guard let data = chunk, !data.isEmpty else { break }   // nil or empty means end of file
            hasher.update(data: data)
            onBytes?(data.count)
        }
        return hex(hasher.finalize())
    }

    /// Hash of the first and last `window` bytes plus the length. A cheap pre-filter: files whose
    /// partial hashes differ can't be identical.
    static func partialHash(of url: URL, length: Int64, window: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        withUnsafeBytes(of: length.littleEndian) { hasher.update(bufferPointer: $0) }
        do {
            hasher.update(data: try handle.read(upToCount: window) ?? Data())
            if length > Int64(window * 2) {
                try handle.seek(toOffset: UInt64(length) - UInt64(window))
                hasher.update(data: try handle.read(upToCount: window) ?? Data())
            }
        } catch {
            return nil
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
