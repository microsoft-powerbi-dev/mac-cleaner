import AppKit
import Charts
import SwiftUI

@MainActor
@Observable
final class AnalyzerModel {
    enum Tab: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case large = "Large Files"
        case old = "Old Files"
        var id: Self { self }
    }

    var rootURL = FileManager.default.homeDirectoryForCurrentUser
    var result: DiskScanResult?
    /// Drill-down stack. The last element is the folder being shown.
    var path: [DiskNode] = []
    var isScanning = false
    var tab: Tab = .folders
    var removed: Set<URL> = []
    var tableSelection: Set<URL> = []
    var pendingTrash: [URL] = []
    var lastReport: DeletionReport?
    private var cancel = CancelFlag()

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
        let flag = CancelFlag()
        cancel = flag
        isScanning = true
        removed = []
        tableSelection = []
        let root = rootURL
        let scanned = await Task.detached(priority: .userInitiated) {
            DiskScanner(cancel: flag).scan(root)
        }.value
        guard !flag.isSet else { return }   // a newer scan replaced this one, or the user stopped it
        result = scanned
        path = [scanned.root]
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

    func trashPending() async {
        let urls = pendingTrash
        pendingTrash = []
        let report = await Trasher.remove(urls, mode: .moveToTrash)
        removed.formUnion(report.removed)
        tableSelection.subtract(report.removed)
        lastReport = report
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
            if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView("Scanning \(model.rootURL.abbreviatedPath)…")
                    Button("Stop") { model.stop() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.result {
                switch model.tab {
                case .folders: folders
                case .large: fileTable(model.visible(result.largeFiles), empty: "No files over \(Format.bytes(DiskScanner.largeFileThreshold)).")
                case .old: fileTable(model.visible(result.oldFiles), empty: "No large files left unopened for over a year.")
                }
            } else {
                ContentUnavailableView {
                    Label("See what's using your disk", systemImage: "chart.pie")
                } description: {
                    Text("Scan a folder to find the biggest folders, large files and files you haven't opened in a year.")
                } actions: {
                    Button("Scan Home Folder") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
                    Button("Choose Folder…") { model.chooseFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "Move \(model.pendingTrash.count) item(s) to the Trash?",
            isPresented: Binding(get: { !model.pendingTrash.isEmpty }, set: { if !$0 { model.pendingTrash = [] } })
        ) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashPending() } }
        } message: {
            let paths = model.pendingTrash.prefix(5).map(\.abbreviatedPath).joined(separator: "\n")
            if model.pendingTouchesLibrary {
                Text("Files in your Library belong to apps. Removing them can break those apps or delete their data, such as settings, documents or backups.\n\n\(paths)")
            } else {
                Text(paths)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk Analyzer").font(.title2.bold())
                Text(model.rootURL.abbreviatedPath).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $model.tab) {
                ForEach(AnalyzerModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .disabled(model.result == nil)
            Button("Choose Folder…") { model.chooseFolder() }.disabled(model.isScanning)
            Button("Rescan") { Task { await model.scan() } }.disabled(model.isScanning || model.result == nil)
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
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Button("Move to Trash…", role: .destructive) { model.pendingTrash = [node.url] }
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

    // MARK: Large and old files

    @ViewBuilder
    private func fileTable(_ files: [FileEntry], empty: String) -> some View {
        if files.isEmpty {
            ContentUnavailableView(empty, systemImage: "checkmark.circle")
        } else {
            VStack(spacing: 0) {
                Table(files, selection: $model.tableSelection) {
                    TableColumn("Name") { (file: FileEntry) in
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                            .help(file.url.abbreviatedPath)
                    }
                    TableColumn("Size") { (file: FileEntry) in
                        Text(Format.bytes(file.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Last Opened") { (file: FileEntry) in
                        Text(Format.date(file.lastAccess))
                    }
                    .width(110)
                    TableColumn("Location") { (file: FileEntry) in
                        Text(file.url.deletingLastPathComponent().abbreviatedPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: URL.self) { urls in
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
                    Button("Move to Trash…", role: .destructive) { model.pendingTrash = Array(urls) }
                }
                Divider()
                HStack {
                    let selectedSize = files.filter { model.tableSelection.contains($0.url) }.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(model.tableSelection.count) selected · \(Format.bytes(selectedSize))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Move Selected to Trash…") { model.pendingTrash = Array(model.tableSelection) }
                        .disabled(model.tableSelection.isEmpty)
                }
                .padding(10)
            }
        }
    }
}
