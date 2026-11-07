import Foundation

/// Asks a remote (or local-network) LLM for advice in JSON and maps it onto `Advice` / `ScanReport`.
/// Only metadata is sent: path, size, dates and category — never file contents.
enum RemoteAdvisor {
    static let systemPrompt = """
        You are a macOS storage expert inside a disk cleaning app. You get metadata about files or \
        folders (never their contents) and a hint from the app's built-in rules. Be concrete and brief. \
        Prefer the built-in hint when it names a known location. When unsure, choose a cautious rating. \
        Personal documents, photos, videos, mail, messages, keychains and backups must never be rated \
        safe to delete. Reply with a single JSON object only, no prose and no code fences.
        """

    // MARK: Single item

    static func advise(_ item: AdvisorItem, hint: Advice, client: LLMCompleting, shortenPaths: Bool) async throws -> Advice {
        let user = """
            \(describe(item, shortenPaths: shortenPaths))

            Built-in rule hint: \(hint.fileType) — \(hint.whatItIs) Rated: \(hint.safety.title). \(hint.reasoning)

            Return JSON with exactly these keys:
            {"fileType": short name of what this is,
             "whatItIs": one or two sentences on what it is and which app creates it,
             "safety": "safeToDelete" | "reviewFirst" | "keep",
             "reasoning": one or two sentences explaining the rating,
             "preventGrowth": [2-3 short tips to stop it growing],
             "cleanupSteps": [2-3 short ordered steps to clean it up efficiently],
             "suggestMove": true if it should be kept but could live on external storage, a NAS or iCloud Drive}
            """
        let text = try await client.complete(system: systemPrompt, user: user)
        let reply = try decode(ItemReply.self, from: text)
        return Advice(
            fileType: reply.fileType ?? hint.fileType,
            whatItIs: reply.whatItIs ?? hint.whatItIs,
            safety: rating(reply.safety) ?? hint.safety,
            reasoning: reply.reasoning ?? hint.reasoning,
            preventGrowth: Array((reply.preventGrowth ?? hint.preventGrowth).prefix(4)),
            cleanupSteps: Array((reply.cleanupSteps ?? hint.cleanupSteps).prefix(5)),
            suggestMove: reply.suggestMove ?? hint.suggestMove,
            engine: .remote(client.displayName)
        )
    }

    // MARK: Whole scan

    static func summarize(_ input: ScanSummaryInput, hint: ScanReport, client: LLMCompleting, shortenPaths: Bool) async throws -> ScanReport {
        var lines = [
            "Scanned folder: \(display(input.rootPath, shorten: shortenPaths)), \(Format.bytes(input.rootSize)).",
            "Disk free: \(Format.bytes(input.volumeFree)) of \(Format.bytes(input.volumeTotal)).",
            "By category: " + input.kindTotals.sorted { $0.value > $1.value }.prefix(8)
                .map { "\($0.key.title) \(Format.bytes($0.value))" }.joined(separator: ", "),
        ]
        if let growth = input.growthSincePrevious {
            lines.append("Change since \(Format.date(growth.since)): \(growth.bytes >= 0 ? "+" : "-")\(Format.bytes(abs(growth.bytes))).")
        }
        if let waste = input.duplicateWaste { lines.append("Duplicate files waste: \(Format.bytes(waste)).") }
        lines.append("Biggest items (with the app's rule-based rating):")
        for item in (input.hogs + input.largestFiles).prefix(12) {
            let rule = RuleBasedAdvisor.advise(item)
            lines.append("- \(display(item.url.path, shorten: shortenPaths)), \(Format.bytes(item.size)), \(rule.fileType), \(rule.safety.title)")
        }
        lines.append("""

            Return JSON: {"headline": 2-3 sentences on where the space goes and what to do first, \
            "tips": [3-6 concrete tips to reclaim space and stop the biggest items from growing]}
            """)
        let text = try await client.complete(system: systemPrompt, user: lines.joined(separator: "\n"))
        let reply = try decode(ReportReply.self, from: text)
        var report = hint   // findings and their safety stay rule-based
        if let headline = reply.headline, !headline.isEmpty { report.headline = headline }
        if let tips = reply.tips, !tips.isEmpty { report.tips = Array(tips.prefix(6)) }
        report.engine = .remote(client.displayName)
        return report
    }

    // MARK: Helpers

    private struct ItemReply: Decodable {
        var fileType: String?
        var whatItIs: String?
        var safety: String?
        var reasoning: String?
        var preventGrowth: [String]?
        var cleanupSteps: [String]?
        var suggestMove: Bool?
    }

    private struct ReportReply: Decodable {
        var headline: String?
        var tips: [String]?
    }

    static func rating(_ value: String?) -> SafetyRating? {
        guard let value else { return nil }
        let key = value.lowercased().filter(\.isLetter)
        if key.hasPrefix("safe") { return .safeToDelete }
        if key.hasPrefix("review") || key.contains("caution") { return .reviewFirst }
        if key.hasPrefix("keep") || key.contains("unsafe") || key.contains("donot") { return .keep }
        return nil
    }

    /// Decodes the first JSON object in `text`, tolerating code fences and surrounding prose.
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data) else { throw LLMError.unreadableAnswer }
        return value
    }

    static func display(_ path: String, shorten: Bool) -> String {
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        guard shorten else { return abbreviated }
        let parts = abbreviated.split(separator: "/")
        return parts.count <= 2 ? abbreviated : "…/" + parts.suffix(2).joined(separator: "/")
    }

    private static func describe(_ item: AdvisorItem, shortenPaths: Bool) -> String {
        guard shortenPaths else { return item.promptDescription }
        return item.promptDescription.replacingOccurrences(
            of: "Path: \(item.url.abbreviatedPath)", with: "Path: \(display(item.url.path, shorten: true))")
    }
}
