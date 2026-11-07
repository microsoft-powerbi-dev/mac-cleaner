import AppKit
import SwiftUI

/// "Largest" tab: filterable top files, or the folders that hog space.
struct LargestView: View {
    @Bindable var model: AnalyzerModel
    let result: DiskScanResult

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $model.showHogs) {
                    Text("Top Files").tag(false)
                    Text("Space Hogs").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if model.showHogs {
                hogList
            } else {
                filterBar
                Divider()
                AnalyzerFileTable(
                    model: model,
                    files: model.filter.apply(model.visible(result.files)),
                    empty: "No files match these filters."
                )
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All Kinds") { model.filter.kinds = [] }
                Divider()
                ForEach(FileKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { model.filter.kinds.contains(kind) },
                        set: { on in if on { model.filter.kinds.insert(kind) } else { model.filter.kinds.remove(kind) } }
                    )) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Text(kindLabel)
            }
            .fixedSize()

            Picker("Size", selection: $model.filter.minSize) {
                ForEach(FileFilter.MinSize.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()

            Picker("Age", selection: $model.filter.age) {
                ForEach(FileFilter.Age.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            TextField("Name", text: $model.filter.nameQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90)
            TextField("Location", text: $model.filter.locationQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90)

            Picker("Show", selection: $model.filter.limit) {
                ForEach([50, 200, 1000, 5000], id: \.self) { Text("Top \($0)").tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            if model.filter != AnalyzerModel.defaultFilter {
                Button("Reset") { model.filter = AnalyzerModel.defaultFilter }.buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var kindLabel: String {
        switch model.filter.kinds.count {
        case 0: return "All Kinds"
        case 1: return model.filter.kinds.first!.title
        default: return "\(model.filter.kinds.count) Kinds"
        }
    }

    @ViewBuilder
    private var hogList: some View {
        let hogs = model.hogs.filter { !model.removed.contains($0.id) }
        if hogs.isEmpty {
            ContentUnavailableView("No folders over \(Format.bytes(Prefs.hogMinBytes))", systemImage: "checkmark.circle",
                                   description: Text("Nothing in this scan holds that much space on its own."))
        } else {
            let top = hogs.first?.node.size ?? 1
            List(hogs) { hog in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Color.accentColor).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hog.node.name).lineLimit(1)
                        Text(hog.node.url.deletingLastPathComponent().abbreviatedPath)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    ProgressView(value: Double(hog.node.size), total: Double(max(top, 1))).frame(width: 120)
                    Text(Format.bytes(hog.node.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Button {
                        model.explain(AdvisorItem(node: hog.node))
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .help("Explain with AI")
                    Button {
                        model.open(hog)
                    } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Folders")
                }
                .contextMenu {
                    Button("Open in Folders") { model.open(hog) }
                    ItemActions(model: model, urls: [hog.node.url], explainItem: AdvisorItem(node: hog.node))
                }
            }
        }
    }
}

/// The file table used by the Largest and Old tabs.
struct AnalyzerFileTable: View {
    @Bindable var model: AnalyzerModel
    let files: [FileEntry]
    let empty: String

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView(empty, systemImage: "checkmark.circle")
        } else {
            VStack(spacing: 0) {
                Table(files, selection: $model.tableSelection) {
                    TableColumn("Name") { (file: FileEntry) in
                        HStack(spacing: 6) {
                            Image(systemName: file.kind.symbol).foregroundStyle(.secondary).frame(width: 16)
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                        }
                        .help(file.url.abbreviatedPath)
                    }
                    TableColumn("Size") { (file: FileEntry) in
                        Text(Format.bytes(file.size)).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("Kind") { (file: FileEntry) in
                        Text(file.kind.title).foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Modified") { (file: FileEntry) in
                        Text(Format.date(file.modified))
                    }
                    .width(100)
                    TableColumn("Last Opened") { (file: FileEntry) in
                        Text(Format.date(file.lastAccess))
                    }
                    .width(100)
                    TableColumn("Location") { (file: FileEntry) in
                        Text(file.url.deletingLastPathComponent().abbreviatedPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: URL.self) { urls in
                    let item = urls.count == 1 ? files.first { $0.url == urls.first }.map(AdvisorItem.init(file:)) : nil
                    ItemActions(model: model, urls: Array(urls), explainItem: item)
                }
                Divider()
                HStack {
                    let selectedSize = files.filter { model.tableSelection.contains($0.url) }.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(files.count) shown · \(model.tableSelection.count) selected · \(Format.bytes(selectedSize))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Move Selected…") { model.pendingMove = selection }
                        .disabled(model.tableSelection.isEmpty)
                        .help("Move to an external drive, NAS or iCloud Drive")
                    Button("Move Selected to Trash…") { model.pendingTrash = selection }
                        .disabled(model.tableSelection.isEmpty)
                }
                .padding(10)
            }
        }
    }

    /// The selection, limited to rows currently shown.
    private var selection: [URL] {
        files.map(\.url).filter { model.tableSelection.contains($0) }
    }
}
