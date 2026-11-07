import AppKit
import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: AnalyzerModel

    var body: some View {
        if model.isFindingDuplicates {
            VStack(spacing: 12) {
                ProgressView(value: model.duplicateProgress) {
                    Text("Comparing file contents…")
                }
                .frame(width: 320)
                Button("Stop") { model.stopDuplicates() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let groups = model.duplicateGroups {
            if groups.isEmpty {
                ContentUnavailableView("No duplicates found", systemImage: "checkmark.circle",
                                       description: Text("No files of \(Format.bytes(Prefs.duplicateMinBytes)) or more have identical contents in this scan."))
            } else {
                results(groups)
            }
        } else {
            ContentUnavailableView {
                Label("Find duplicate files", systemImage: "doc.on.doc")
            } description: {
                Text("Compares the contents of every file of \(Format.bytes(max(Prefs.duplicateMinBytes, DiskScanner.keepFileThreshold))) or more in this scan. Hard links are counted once.")
            } actions: {
                Button("Find Duplicates") { Task { await model.findDuplicates() } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func results(_ groups: [DuplicateGroup]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(groups.count) groups · \(Format.bytes(model.duplicateWaste)) in extra copies")
                    .font(.headline)
                Spacer()
                Picker("Default", selection: $model.keepRule) {
                    ForEach(KeepRule.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                .onChange(of: model.keepRule) { model.applyKeepRule() }
                Button("Search Again") { Task { await model.findDuplicates() } }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            row(file, in: group)
                        }
                    } header: {
                        HStack {
                            Text("\(group.files.count) copies of \(group.files.first?.name ?? "")")
                            Spacer()
                            Text("\(Format.bytes(group.size)) each · \(Format.bytes(group.wasted)) extra").monospacedDigit()
                        }
                    }
                }
            }
            Divider()
            HStack {
                let extras = model.duplicateExtras
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("One copy per group is always kept. Copies made with APFS cloning may already share space.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(extras.count) to remove · \(Format.bytes(extras.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary)
                Button("Move Extras to Trash…") { model.pendingTrash = extras.map(\.url) }
                    .disabled(extras.isEmpty)
            }
            .padding(10)
        }
    }

    private func row(_ file: FileEntry, in group: DuplicateGroup) -> some View {
        let isKept = model.kept(group) == file.url
        return HStack {
            Button {
                model.duplicateKeep[group.id] = file.url
                model.duplicateSkip.remove(file.url)
            } label: {
                Image(systemName: isKept ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.borderless)
            .help("Keep this copy")
            Text(isKept ? "Keep" : "Remove")
                .font(.caption.bold())
                .foregroundStyle(isKept ? Color.green : (model.duplicateSkip.contains(file.url) ? Color.secondary : Color.red))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Format.date(file.modified)).foregroundStyle(.secondary)
            if !isKept {
                Toggle("", isOn: Binding(
                    get: { !model.duplicateSkip.contains(file.url) },
                    set: { on in if on { model.duplicateSkip.remove(file.url) } else { model.duplicateSkip.insert(file.url) } }
                ))
                .labelsHidden()
                .help("Remove this copy")
            }
        }
        .contextMenu {
            ItemActions(model: model, urls: [file.url], explainItem: AdvisorItem(file: file))
        }
    }
}
