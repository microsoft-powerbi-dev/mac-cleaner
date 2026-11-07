#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Uses Apple's on-device language model (macOS 26+, Apple Intelligence). Runs entirely on
/// the Mac: nothing is sent over the network. Only metadata (path, size, dates, category) is
/// given to the model, never file contents.
@available(macOS 26, *)
enum FoundationModelsAdvisor {
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to use on-device AI."
            case .modelNotReady: return "The on-device model is still downloading. Try again later."
            @unknown default: return "The on-device model isn't available."
            }
        }
    }

    private static let instructions = """
        You are a macOS storage expert inside a disk cleaning app. You are given metadata about one \
        file or folder (never its contents) and a hint from the app's built-in rules. Explain what it \
        most likely is, whether deleting it is safe, how to stop it from growing, and how to clean it \
        up efficiently. Be concrete and brief. Prefer the app's built-in hint when it names a known \
        location. When unsure, choose a cautious safety rating. Personal documents, photos, videos, \
        mail, messages, keychains and backups must never be rated safe to delete.
        """

    @Generable
    enum GeneratedSafety {
        case safeToDelete, reviewFirst, keep
    }

    @Generable
    struct GeneratedAdvice {
        @Guide(description: "Short name of what this is, e.g. 'Xcode build cache'")
        var fileType: String
        @Guide(description: "One or two sentences explaining what the item is and which app creates it")
        var whatItIs: String
        @Guide(description: "How safe it is to delete")
        var safety: GeneratedSafety
        @Guide(description: "One or two sentences explaining the safety rating")
        var reasoning: String
        @Guide(description: "Two or three short tips to stop this from growing again")
        var preventGrowth: [String]
        @Guide(description: "Two or three short, ordered steps to clean it up efficiently")
        var cleanupSteps: [String]
        @Guide(description: "True if it should be kept but could live on external storage, a NAS or iCloud Drive instead of the internal disk")
        var suggestMove: Bool
    }

    static func advise(_ item: AdvisorItem, hint: Advice) async throws -> Advice {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
            \(item.promptDescription)

            Built-in rule hint: \(hint.fileType) — \(hint.whatItIs) Rated: \(hint.safety.title). \(hint.reasoning)
            """
        let out = try await session.respond(to: prompt, generating: GeneratedAdvice.self).content
        let safety: SafetyRating
        switch out.safety {
        case .safeToDelete: safety = .safeToDelete
        case .reviewFirst: safety = .reviewFirst
        case .keep: safety = .keep
        }
        return Advice(
            fileType: out.fileType, whatItIs: out.whatItIs, safety: safety, reasoning: out.reasoning,
            preventGrowth: Array(out.preventGrowth.prefix(4)), cleanupSteps: Array(out.cleanupSteps.prefix(5)),
            suggestMove: out.suggestMove, engine: .onDevice
        )
    }

    @Generable
    struct GeneratedReport {
        @Guide(description: "Two or three sentences summarizing where the disk space goes and what to do first")
        var headline: String
        @Guide(description: "Three to five concrete tips to reclaim space and to stop the biggest items from growing")
        var tips: [String]
    }

    /// Writes the headline and tips. Findings (with their safety ratings) stay rule-based so the
    /// model can't mark something as safe that the rules don't.
    static func summarize(_ input: ScanSummaryInput, hint: ScanReport) async throws -> ScanReport {
        let session = LanguageModelSession(instructions: instructions)
        var lines = [
            "Scanned folder: \((input.rootPath as NSString).abbreviatingWithTildeInPath), \(Format.bytes(input.rootSize)).",
            "Disk free: \(Format.bytes(input.volumeFree)) of \(Format.bytes(input.volumeTotal)).",
            "By category: " + input.kindTotals.sorted { $0.value > $1.value }.prefix(6)
                .map { "\($0.key.title) \(Format.bytes($0.value))" }.joined(separator: ", "),
        ]
        if let growth = input.growthSincePrevious {
            lines.append("Change since \(Format.date(growth.since)): \(growth.bytes >= 0 ? "+" : "-")\(Format.bytes(abs(growth.bytes))).")
        }
        if let waste = input.duplicateWaste { lines.append("Duplicate files waste: \(Format.bytes(waste)).") }
        lines.append("Biggest findings (rule-based rating):")
        for finding in hint.findings.prefix(10) {
            lines.append("- \(finding.title), \(Format.bytes(finding.size)), \(finding.safety.title)")
        }
        let out = try await session.respond(to: lines.joined(separator: "\n"), generating: GeneratedReport.self).content
        var report = hint
        report.headline = out.headline
        report.tips = Array(out.tips.prefix(6))
        report.engine = .onDevice
        return report
    }
}
#endif
