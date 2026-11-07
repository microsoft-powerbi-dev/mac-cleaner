import Foundation

/// How safe it is to remove an item, most permissive first.
enum SafetyRating: Int, Comparable, Sendable, CaseIterable {
    case safeToDelete = 0, reviewFirst = 1, keep = 2

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safeToDelete: return "Safe to delete"
        case .reviewFirst: return "Review before deleting"
        case .keep: return "Keep"
        }
    }

    var symbol: String {
        switch self {
        case .safeToDelete: return "checkmark.shield.fill"
        case .reviewFirst: return "exclamationmark.triangle.fill"
        case .keep: return "lock.shield.fill"
        }
    }
}

enum AdvisorEngine: Sendable, Equatable {
    case onDevice, rules
    /// A cloud or network LLM; the associated value names provider and model.
    case remote(String)

    var title: String {
        switch self {
        case .onDevice: return "Apple Intelligence (on-device)"
        case .rules: return "Built-in rules"
        case .remote(let name): return name
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: return "sparkles"
        case .rules: return "list.bullet.rectangle"
        case .remote: return "network"
        }
    }

    var privacyNote: String {
        switch self {
        case .onDevice, .rules: return "Only names, sizes and dates are analyzed, on this Mac."
        case .remote: return "Paths, names, sizes and dates were sent to this provider. File contents never are."
        }
    }
}

/// What the advisor is told about a file or folder. Metadata only — never file contents.
struct AdvisorItem: Sendable, Identifiable {
    struct Child: Sendable {
        let name: String
        let size: Int64
    }

    let url: URL
    let isDirectory: Bool
    let size: Int64
    let kind: FileKind
    var modified: Date? = nil
    var lastAccess: Date? = nil
    var topChildren: [Child] = []

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, size: Int64, kind: FileKind, modified: Date? = nil, lastAccess: Date? = nil, topChildren: [Child] = []) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.kind = kind
        self.modified = modified
        self.lastAccess = lastAccess
        self.topChildren = topChildren
    }

    init(node: DiskNode) {
        self.init(
            url: node.url, isDirectory: node.isDirectory, size: node.size,
            kind: node.isDirectory ? (FileKind.directoryContext(node.name) ?? .other) : FileKind.classify(fileName: node.name),
            topChildren: node.children.prefix(10).map { Child(name: $0.name, size: $0.size) }
        )
    }

    init(file: FileEntry) {
        self.init(url: file.url, isDirectory: false, size: file.size, kind: file.kind, modified: file.modified, lastAccess: file.lastAccess)
    }

    /// A plain-text description for the language model.
    var promptDescription: String {
        var lines = [
            "Path: \(url.abbreviatedPath)",
            "Type: \(isDirectory ? "folder" : "file"), category \(kind.title)",
            "Size: \(Format.bytes(size))",
        ]
        if let modified { lines.append("Last modified: \(Format.date(modified))") }
        if let lastAccess { lines.append("Last opened: \(Format.date(lastAccess))") }
        if !topChildren.isEmpty {
            lines.append("Largest items inside: " + topChildren.map { "\($0.name) (\(Format.bytes($0.size)))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

struct Advice: Sendable {
    var fileType: String
    var whatItIs: String
    var safety: SafetyRating
    var reasoning: String
    var preventGrowth: [String]
    var cleanupSteps: [String]
    /// True when the item is worth keeping but doesn't need to live on the internal disk.
    var suggestMove: Bool
    var engine: AdvisorEngine = .rules
    /// Set when the chosen AI failed and these are the built-in rules instead.
    var notice: String? = nil
}

/// Input for a whole-scan report.
struct ScanSummaryInput: Sendable {
    let rootPath: String
    let rootSize: Int64
    let volumeFree: Int64
    let volumeTotal: Int64
    let kindTotals: [FileKind: Int64]
    let hogs: [AdvisorItem]
    let largestFiles: [AdvisorItem]
    let duplicateWaste: Int64?
    /// Change in scanned-folder size since the previous scan of the same folder.
    let growthSincePrevious: (bytes: Int64, since: Date)?
}

struct ScanReport: Sendable {
    struct Finding: Sendable, Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let safety: SafetyRating
        let url: URL?
        let size: Int64
    }

    var headline: String
    var findings: [Finding]
    var tips: [String]
    var engine: AdvisorEngine = .rules
    var notice: String? = nil
}

/// Front door for analysis: uses the provider chosen in Settings (on-device by default) and
/// falls back to the built-in rules. The rule result is always computed: it grounds the model,
/// and the final safety rating can never be more permissive than it.
enum DiskAdvisor {
    /// Why on-device AI is unavailable, or nil when it can be used.
    static var onDeviceUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return FoundationModelsAdvisor.unavailableReason }
        #endif
        return "On-device AI needs macOS 26 or later with Apple Intelligence turned on."
    }

    /// Why the selected provider can't be used right now, or nil when it's ready.
    static func providerProblem(_ settings: AISettings = .load()) -> String? {
        if settings.provider == .onDevice { return onDeviceUnavailableReason }
        let client = RemoteLLMClient(kind: settings.provider, config: settings.config(for: settings.provider),
                                     apiKey: AISettings.apiKey(for: settings.provider))
        return client.configurationProblem.map { "\(settings.provider.title) isn't set up: \($0). Open Settings › AI." }
    }

    static func advise(_ item: AdvisorItem, settings: AISettings = .load(), client: LLMCompleting? = nil) async -> Advice {
        let rules = RuleBasedAdvisor.advise(item)
        var advice: Advice
        do {
            if let remote = client ?? settings.remoteClient() {
                advice = try await RemoteAdvisor.advise(item, hint: rules, client: remote, shortenPaths: settings.shortenPaths)
            } else if settings.provider == .onDevice, let local = try await onDeviceAdvice(item, hint: rules) {
                advice = local
            } else {
                return withNotice(rules, providerProblem(settings))
            }
        } catch {
            return withNotice(rules, "\(settings.provider.title) failed: \(error.localizedDescription) Showing built-in rules.")
        }
        // Never let a model be more permissive than the rules or SafetyGuard.
        advice.safety = max(advice.safety, rules.safety)
        if rules.safety == .keep { advice.suggestMove = advice.suggestMove || rules.suggestMove }
        return advice
    }

    static func summarize(_ input: ScanSummaryInput, settings: AISettings = .load(), client: LLMCompleting? = nil) async -> ScanReport {
        var rules = RuleBasedAdvisor.summarize(input)
        do {
            if let remote = client ?? settings.remoteClient() {
                return try await RemoteAdvisor.summarize(input, hint: rules, client: remote, shortenPaths: settings.shortenPaths)
            }
            if settings.provider == .onDevice, let local = try await onDeviceSummary(input, hint: rules) {
                return local
            }
            rules.notice = providerProblem(settings)
        } catch {
            rules.notice = "\(settings.provider.title) failed: \(error.localizedDescription) Showing built-in rules."
        }
        return rules
    }

    private static func withNotice(_ advice: Advice, _ notice: String?) -> Advice {
        var advice = advice
        advice.notice = notice
        return advice
    }

    private static func onDeviceAdvice(_ item: AdvisorItem, hint: Advice) async throws -> Advice? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), FoundationModelsAdvisor.unavailableReason == nil {
            return try await FoundationModelsAdvisor.advise(item, hint: hint)
        }
        #endif
        return nil
    }

    private static func onDeviceSummary(_ input: ScanSummaryInput, hint: ScanReport) async throws -> ScanReport? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), FoundationModelsAdvisor.unavailableReason == nil {
            return try await FoundationModelsAdvisor.summarize(input, hint: hint)
        }
        #endif
        return nil
    }
}
