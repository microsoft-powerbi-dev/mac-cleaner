import Foundation

/// A place files can be moved to that frees space on the internal disk.
struct StorageDestination: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case iCloud, external, network, folder

        var symbol: String {
            switch self {
            case .iCloud: return "icloud"
            case .external: return "externaldrive"
            case .network: return "server.rack"
            case .folder: return "folder"
            }
        }

        var title: String {
            switch self {
            case .iCloud: return "iCloud Drive"
            case .external: return "External drive"
            case .network: return "Network / NAS"
            case .folder: return "Folder"
            }
        }
    }

    let url: URL
    let name: String
    let kind: Kind
    let available: Int64?

    var id: URL { url }
}

enum StorageDestinations {
    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// iCloud Drive (when signed in) plus every mounted, writable, non-internal volume.
    static func available() -> [StorageDestination] {
        var out: [StorageDestination] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: iCloudDrive.path) {
            out.append(.init(url: iCloudDrive, name: "iCloud Drive", kind: .iCloud, available: nil))
        }

        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey,
        ]
        for volume in fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard let v = try? volume.resourceValues(forKeys: Set(keys)),
                  v.volumeIsRootFileSystem != true, v.volumeIsReadOnly != true else { continue }
            let kind: StorageDestination.Kind
            if v.volumeIsLocal == false {
                kind = .network
            } else if v.volumeIsInternal != true || v.volumeIsRemovable == true || v.volumeIsEjectable == true {
                kind = .external
            } else {
                continue   // another internal volume: moving there frees nothing
            }
            out.append(.init(
                url: volume, name: v.volumeLocalizedName ?? volume.lastPathComponent,
                kind: kind, available: Mover.availableSpace(at: volume)
            ))
        }
        return out
    }
}
