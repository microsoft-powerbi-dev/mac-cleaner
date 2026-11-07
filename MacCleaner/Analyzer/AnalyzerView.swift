import AppKit
import Charts
import SwiftUI

@MainActor
@Observable
final class AnalyzerModel {
    enum Tab: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case breakdown = "Breakdown"
        case largest = "Largest"
        case old = "Old Files"
        case duplicates = "Duplicates"
        case history = "History"
        var id: Self { self }

        var symbol: String {
            switch self {
            case .folders: return "folder"
            case .breakdown: return "chart.bar.xaxis"
            case .largest: return "arrow.up.right.square"
            case .old: return "clock"
            case .duplicates: return "doc.on.doc"
            case .history: return "chart.xyaxis.line"
            }
        }
    }

    var rootURL = Prefs.defaultScanURL
    var result: DiskScanResult?
    /// Drill-down stack. The last element is the folder being shown.
    var path: [DiskNode] = []
    var isScanning = false
    var tab: Tab = .folders
    /// Items trashed or moved away since the last scan; hidden from every list.
    var removed: Set<URL> = []
    var tableSelection: Set<URL> = []
    var pendingTrash: [URL] = []
    var lastReport: DeletionReport?
    private var cancel = CancelFlag()

    // Largest
    var filter = AnalyzerModel.defaultFilter
    var showHogs = false
    private(set) var hogs: [SpaceHog] = []

    // Duplicates
    var duplicateGroups: [DuplicateGroup]?
    var isFindingDuplicates = false
    var duplicateProgress = 0.0
    var keepRule: KeepRule = .newest
    /// Group id → the copy to keep.
    var duplicateKeep: [String: URL] = [:]
    /// Extra copies the user unticked (they'll be left alone).
    var duplicateSkip: Set<URL> = []
    private var duplicateCancel = CancelFlag()

    // History
    let historyStore: UsageHistoryStore
    var history: [UsageSnapshot] = []
    var compareDate: Date?

    // AI insights
    var adviceItem: AdvisorItem?
    var advice: Advice?
    var isAdvising = false
    var showInspector = false
    var scanReport: ScanReport?
    var isSummarizing = false
    var showReport = false

    // Moving
    var pendingMove: [URL] = []
    var isMoving = false
    var moveStatus = ""
    var lastMoveReport: MoveReport?

    /// The Largest filter as configured in Settings.
    static var defaultFilter: FileFilter {
        var filter = FileFilter()
        filter.minSize = Prefs.largestMinSizeOption
        return filter
    }

    init(historyStore: UsageHistoryStore = .standard) {
        self.historyStore = historyStore
        history = historyStore.load()
    }

    var current: DiskNode? { path.last }

    /// True when any pending item is inside ~/Library, where files belong to apps.
    var pendingTouchesLibrary: Bool {
        let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path.lowercased() + "/"
        return pendingTrash.contains { $0.standardizedFileURL.path.lowercased().hasPrefix(lib) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        panel.prompt = "Analyze"
        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            Task { await scan() }
        }
    }

    func scan() async {
        cancel.set()
        stopDuplicates()
        let flag = CancelFlag()
        cancel = flag
        isScanning = true
        removed = []
        tableSelection = []
        duplicateGroups = nil
        duplicateKeep = [:]
        duplicateSkip = []
        scanReport = nil
        let root = rootURL
        let scanned = await Task.detached(priority: .userInitiated) {
            DiskScanner(cancel: flag).scan(root)
        }.value
        guard !flag.isSet else { return }   // a newer scan replaced this one, or the user stopped it
        result = scanned
        path = [scanned.root]
        hogs = DiskInsights.spaceHogs(root: scanned.root, minSize: Prefs.hogMinBytes)
        history = historyStore.append(UsageSnapshot(scan: scanned, volume: SystemStats.disk()), limit: Prefs.historySnapshotLimit)
        compareDate = nil
        isScanning = false
    }

    func stop() {
        cancel.set()
        isScanning = false
    }

    func visible(_ nodes: [DiskNode]) -> [DiskNode] {
        nodes.filter { !removed.contains($0.url) }
    }

    func visible(_ files: [FileEntry]) -> [FileEntry] {
        files.filter { !removed.contains($0.url) }
    }

    func open(_ hog: SpaceHog) {
        path = hog.chain
        tab = .folders
    }

    func trashPending() async {
        let urls = pendingTrash
        pendingTrash = []
        let report = await Trasher.remove(urls, mode: .moveToTrash)
        markGone(report.removed)
        lastReport = report
    }

    private func markGone(_ urls: [URL]) {
        removed.formUnion(urls)
        tableSelection.subtract(urls)
        let gone = Set(urls)
        if let groups = duplicateGroups {
            duplicateGroups = groups.map { $0.removing(gone) }.filter { $0.files.count > 1 }
        }
        duplicateSkip.subtract(gone)
    }

    // MARK: Duplicates

    func findDuplicates() async {
        guard let result else { return }
        duplicateCancel.set()
        let flag = CancelFlag()
        duplicateCancel = flag
        isFindingDuplicates = true
        duplicateProgress = 0
        let candidates = visible(result.files)
        let minSize = Prefs.duplicateMinBytes
        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.duplicateProgress = fraction }
        }
        let groups = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.find(candidates, minSize: minSize, cancel: flag, progress: progress)
        }.value
        guard !flag.isSet else { return }
        duplicateGroups = groups
        applyKeepRule()
        isFindingDuplicates = false
    }

    func stopDuplicates() {
        duplicateCancel.set()
        isFindingDuplicates = false
    }

    func applyKeepRule() {
        duplicateKeep = [:]
        duplicateSkip = []
        for group in duplicateGroups ?? [] {
            if let keep = keepRule.pick(from: group.files) { duplicateKeep[group.id] = keep.url }
        }
    }

    func kept(_ group: DuplicateGroup) -> URL? {
        duplicateKeep[group.id] ?? group.files.first?.url
    }

    /// Every copy that will be trashed: all but the kept one, minus the ones the user unticked.
    var duplicateExtras: [FileEntry] {
        (duplicateGroups ?? []).flatMap { group in
            let keep = kept(group)
            return group.files.filter { $0.url != keep && !duplicateSkip.contains($0.url) }
        }
    }

    var duplicateWaste: Int64 { (duplicateGroups ?? []).reduce(0) { $0 + $1.wasted } }

    // MARK: History

    /// Scan snapshots of the folder currently analyzed, oldest first.
    var rootHistory: [UsageSnapshot] {
        let root = (result?.root.url ?? rootURL).path
        return history.filter { $0.rootPath == root }
    }

    /// Picks up history changes and default-folder changes made in Settings.
    func reloadPreferences() {
        history = historyStore.load()
        if result == nil && !isScanning { rootURL = Prefs.defaultScanURL }
    }

    func clearHistory() {
        historyStore.clear()
        history = []
        compareDate = nil
    }

    // MARK: AI insights

    func explain(_ item: AdvisorItem) {
        adviceItem = item
        advice = nil
        isAdvising = true
        showInspector = true
        Task {
            let result = await DiskAdvisor.advise(item)
            guard adviceItem?.id == item.id else { return }
            advice = result
            isAdvising = false
        }
    }

    func summarize() {
        guard let result else { return }
        showReport = true
        isSummarizing = true
        let previous = rootHistory.dropLast().last
        let volume = SystemStats.disk()
        let input = ScanSummaryInput(
            rootPath: result.root.url.path,
            rootSize: result.root.size,
            volumeFree: volume.free,
            volumeTotal: volume.total,
            kindTotals: result.kindTotals,
            hogs: hogs.prefix(8).filter { !removed.contains($0.id) }.map { AdvisorItem(node: $0.node) },
            largestFiles: visible(result.files).prefix(5).map { AdvisorItem(file: $0) },
            duplicateWaste: duplicateGroups == nil ? nil : duplicateWaste,
            growthSincePrevious: previous.flatMap { prev in prev.rootSize.map { (result.root.size - $0, prev.date) } }
        )
        Task {
            scanReport = await DiskAdvisor.summarize(input)
            isSummarizing = false
        }
    }

    // MARK: Moving

    func move(to destination: URL) async {
        let urls = pendingMove
        pendingMove = []
        isMoving = true
        moveStatus = "Preparing…"
        let report = await Mover.move(urls, to: destination) { [weak self] done, total, name in
            Task { @MainActor in
                self?.moveStatus = name.isEmpty ? "Finishing…" : "Copying \(name) (\(done + 1) of \(total))…"
            }
        }
        markGone(report.moved.map(\.source))
        lastMoveReport = report
        isMoving = false
    }
}

struct AnalyzerView: View {
    @Bindable var model: AnalyzerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report = model.lastReport {
                ReportBanner(report: report) { model.lastReport = nil }
            }
            if let report = model.lastMoveReport {
                MoveReportBanner(report: report) { model.lastMoveReport = nil }
            }
            if model.isMoving {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.moveStatus).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(.quaternary.opacity(0.5))
            }
            if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView("Scanning \(model.rootURL.abbreviatedPath)…")
                    Button("Stop") { model.stop() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.result {
                switch model.tab {
                case .folders: folders
                case .breakdown: BreakdownView(model: model, result: result)
                case .largest: LargestView(model: model, result: result)
                case .old:
                    let days = Prefs.oldFileDayCount
                    AnalyzerFileTable(model: model, files: model.visible(result.oldFiles(notOpenedForDays: days)),
                                      empty: "No files of \(Format.bytes(DiskScanner.oldFileThreshold)) or more left unopened for \(days) days.")
                case .duplicates: DuplicatesView(model: model)
                case .history: HistoryView(model: model)
                }
            } else if model.tab == .history && !model.history.isEmpty {
                HistoryView(model: model)
            } else {
                ContentUnavailableView {
                    Label("See what's using your disk", systemImage: "chart.pie")
                } description: {
                    Text("Scan a folder to find the biggest folders and files, duplicates, files you haven't opened in a year, and how your disk usage changes over time.")
                } actions: {
                    Button("Scan Home Folder") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
                    Button("Choose Folder…") { model.chooseFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.reloadPreferences() }
        .inspector(isPresented: $model.showInspector) {
            InsightsPanel(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(isPresented: $model.showReport) {
            ScanReportView(model: model)
        }
        .sheet(isPresented: Binding(get: { !model.pendingMove.isEmpty }, set: { if !$0 { model.pendingMove = [] } })) {
            MoveSheet(model: model)
        }
        .confirmationDialog(
            "Move \(model.pendingTrash.count) item(s) to the Trash?",
            isPresented: Binding(get: { !model.pendingTrash.isEmpty }, set: { if !$0 { model.pendingTrash = [] } })
        ) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashPending() } }
        } message: {
            let paths = model.pendingTrash.prefix(5).map(\.abbreviatedPath).joined(separator: "\n")
            let more = model.pendingTrash.count > 5 ? "\n…and \(model.pendingTrash.count - 5) more" : ""
            if model.pendingTouchesLibrary {
                Text("Files in your Library belong to apps. Removing them can break those apps or delete their data, such as settings, documents or backups.\n\n\(paths)\(more)")
            } else {
                Text(paths + more)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk Analyzer").font(.title2.bold())
                    Text(model.rootURL.abbreviatedPath).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.summarize()
                } label: {
                    Label("Analyze Results", systemImage: "sparkles")
                }
                .disabled(model.result == nil || model.isScanning)
                .help("Explain what's using space and how to clean it up (on-device AI when available)")
                Button("Choose Folder…") { model.chooseFolder() }.disabled(model.isScanning)
                Button("Rescan") { Task { await model.scan() } }.disabled(model.isScanning || model.result == nil)
            }
            Picker("", selection: $model.tab) {
                ForEach(AnalyzerModel.Tab.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.result == nil && model.history.isEmpty)
        }
        .padding()
    }

    // MARK: Folders

    @ViewBuilder
    private var folders: some View {
        if let current = model.current {
            let children = model.visible(current.children)
            let shownTotal = children.reduce(Int64(0)) { $0 + $1.size }
            let other = max(0, current.size - shownTotal)
            VStack(spacing: 0) {
                breadcrumb
                HStack(alignment: .top, spacing: 0) {
                    donut(children: children, total: current.size)
                        .frame(width: 220, height: 220)
                        .padding()
                    List {
                        ForEach(children) { node in
                            nodeRow(node, total: current.size)
                        }
                        if other > 0 {
                            HStack {
                                Image(systemName: "doc.on.doc").frame(width: 20).foregroundStyle(.secondary)
                                Text("Small files & removed items").foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.bytes(other)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    Button(index == 0 ? node.url.abbreviatedPath : node.name) {
                        model.path.removeSubrange((index + 1)...)
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == model.path.count - 1)
                }
                Spacer()
                if let current = model.current {
                    Button {
                        model.explain(AdvisorItem(node: current))
                    } label: {
                        Label("Explain", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .help("Explain this folder with AI")
                }
                Text(Format.bytes(model.current?.size ?? 0)).font(.headline).monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func nodeRow(_ node: DiskNode, total: Int64) -> some View {
        Button {
            if node.isDirectory && !node.children.isEmpty { model.path.append(node) }
        } label: {
            HStack {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                ProgressView(value: Double(node.size), total: Double(max(total, 1)))
                    .frame(width: 120)
                Text(Format.bytes(node.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .opacity(node.isDirectory && !node.children.isEmpty ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ItemActions(model: model, urls: [node.url], explainItem: AdvisorItem(node: node))
        }
    }

    private func donut(children: [DiskNode], total: Int64) -> some View {
        let top = Array(children.prefix(8))
        return Chart(top) { node in
            SectorMark(
                angle: .value("Size", node.size),
                innerRadius: .ratio(0.62),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Item", node.name))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack {
                Text(Format.bytes(total)).font(.headline).monospacedDigit()
                Text("total").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Context-menu actions shared by every list in the analyzer.
struct ItemActions: View {
    let model: AnalyzerModel
    let urls: [URL]
    var explainItem: AdvisorItem?

    var body: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        if let explainItem {
            Button("Explain with AI") { model.explain(explainItem) }
        }
        Divider()
        Button("Move to External / NAS / iCloud…") { model.pendingMove = urls }
        Button("Move to Trash…", role: .destructive) { model.pendingTrash = urls }
    }
}
