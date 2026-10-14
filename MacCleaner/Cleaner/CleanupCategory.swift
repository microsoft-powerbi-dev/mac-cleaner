import Foundation

struct CleanupCategory: Identifiable, Hashable, Sendable {
    enum Mode: Sendable {
        /// Move to the Trash. This is the safe default and can be undone.
        case trash
        /// Delete for good. Only used for the Trash itself.
        case permanent
        /// Show the size only. Cleaning these needs admin rights (planned for v2).
        case listOnly
    }

    struct Target: Hashable, Sendable {
        /// May start with `~`.
        let path: String
        /// true: remove the folder's children and keep the folder. false: remove the folder itself.
        let contentsOnly: Bool
        /// Child names to skip, either covered by another category or too risky.
        let excluding: Set<String>

        init(_ path: String, contentsOnly: Bool = true, excluding: Set<String> = []) {
            self.path = path
            self.contentsOnly = contentsOnly
            self.excluding = excluding
        }

        var expandedPath: String { (path as NSString).expandingTildeInPath }
    }

    let id: String
    let name: String
    let detail: String
    let symbol: String
    let targets: [Target]
    let defaultSelected: Bool
    let mode: Mode
}
