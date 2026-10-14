import AppKit

enum Permissions {
    /// macOS has no API for this check. We try to read folders that TCC only
    /// opens to apps with Full Disk Access.
    static var hasFullDiskAccess: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [
            home + "/Library/Safari",
            home + "/Library/Containers/com.apple.stocks",
            home + "/Library/Application Support/com.apple.TCC",
        ]
        let fm = FileManager.default
        for probe in probes where fm.fileExists(atPath: probe) {
            return (try? fm.contentsOfDirectory(atPath: probe)) != nil
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
