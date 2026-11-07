import AppKit
import SwiftUI

/// Inspector that explains one item: what it is, whether it's safe to delete, how to stop it growing.
struct InsightsPanel: View {
    @Bindable var model: AnalyzerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let item = model.adviceItem {
                    header(item)
                    Divider()
                    if model.isAdvising {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Analyzing…").foregroundStyle(.secondary)
                        }
                    } else if let advice = model.advice {
                        adviceBody(advice, item: item)
                    }
                } else {
                    ContentUnavailableView("Nothing selected", systemImage: "sparkles",
                                           description: Text("Right-click a file or folder and choose Explain with AI."))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ item: AdvisorItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.name, systemImage: item.isDirectory ? "folder.fill" : item.kind.symbol)
                .font(.headline).lineLimit(2)
            Text(item.url.deletingLastPathComponent().abbreviatedPath)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(Format.bytes(item.size)).font(.title3.bold()).monospacedDigit()
        }
    }

    @ViewBuilder
    private func adviceBody(_ advice: Advice, item: AdvisorItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(advice.fileType).font(.headline)
            Text(advice.whatItIs)
        }
        SafetyBadge(rating: advice.safety)
        Text(advice.reasoning).foregroundStyle(.secondary)

        if !advice.cleanupSteps.isEmpty {
            section("How to clean up", advice.cleanupSteps, numbered: true)
        }
        if !advice.preventGrowth.isEmpty {
            section("Keep it from growing", advice.preventGrowth, numbered: false)
        }

        VStack(alignment: .leading, spacing: 8) {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            if advice.suggestMove || advice.safety != .safeToDelete {
                Button("Move to External / NAS / iCloud…") { model.pendingMove = [item.url] }
            }
            if advice.safety != .keep {
                Button("Move to Trash…", role: .destructive) { model.pendingTrash = [item.url] }
            }
        }
        .padding(.top, 4)

        Divider()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(advice.engine.title, systemImage: advice.engine.symbol).font(.caption)
                Spacer()
                SettingsLink { Text("AI Settings…") }.buttonStyle(.borderless).font(.caption)
            }
            if let notice = advice.notice {
                Text(notice).font(.caption2).foregroundStyle(.orange)
            }
            Text("Advice can be wrong. Review before deleting. \(advice.engine.privacyNote)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, _ lines: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(numbered ? "\(index + 1)." : "•").foregroundStyle(.secondary)
                    Text(line).textSelection(.enabled)
                }
            }
        }
    }
}

struct SafetyBadge: View {
    let rating: SafetyRating

    var body: some View {
        Label(rating.title, systemImage: rating.symbol)
            .font(.callout.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch rating {
        case .safeToDelete: return .green
        case .reviewFirst: return .orange
        case .keep: return .red
        }
    }
}

/// Whole-scan report sheet.
struct ScanReportView: View {
    @Bindable var model: AnalyzerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Disk Analysis", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if model.isSummarizing || model.scanReport == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing scan results…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = model.scanReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(report.headline).font(.body)
                        if !report.findings.isEmpty {
                            Text("Biggest items").font(.headline)
                            ForEach(report.findings) { finding in
                                findingRow(finding)
                            }
                        }
                        if !report.tips.isEmpty {
                            Text("Recommendations").font(.headline)
                            ForEach(Array(report.tips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "lightbulb").foregroundStyle(.yellow)
                                    Text(tip).textSelection(.enabled)
                                }
                            }
                        }
                        Divider()
                        if let notice = report.notice {
                            Text(notice).font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Text("\(report.engine.title). Safety ratings come from MacCleaner's built-in rules. Review before deleting.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            SettingsLink { Text("AI Settings…") }.font(.caption)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 620, height: 560)
    }

    private func findingRow(_ finding: ScanReport.Finding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.safety.symbol)
                .foregroundStyle(finding.safety == .safeToDelete ? .green : finding.safety == .reviewFirst ? .orange : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).bold().lineLimit(2)
                Text(finding.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.bytes(finding.size)).monospacedDigit()
            if let url = finding.url {
                Menu {
                    Button("Explain") {
                        dismiss()
                        model.explain(item(for: url, size: finding.size))
                    }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func item(for url: URL, size: Int64) -> AdvisorItem {
        if let hog = model.hogs.first(where: { $0.id == url }) { return AdvisorItem(node: hog.node) }
        if let file = model.result?.files.first(where: { $0.url == url }) { return AdvisorItem(file: file) }
        return AdvisorItem(url: url, isDirectory: false, size: size, kind: FileKind.classify(fileName: url.lastPathComponent))
    }
}
