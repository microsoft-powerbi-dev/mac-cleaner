import AppKit
import SwiftUI

@MainActor
@Observable
final class CleanerModel {
    var results: [CategoryResult] = []
    var selectedCategories: Set<String> = Set(CleanupCatalog.all.filter(\.defaultSelected).map(\.id))
    var deselectedItems: Set<URL> = []
    var isScanning = false
    var isCleaning = false
    var showConfirm = false
    var lastReport: DeletionReport?

    var isBusy: Bool { isScanning || isCleaning }

    private var cleanableResults: [CategoryResult] {
        results.filter { $0.category.mode != .listOnly && selectedCategories.contains($0.id) }
    }

    var selectedSize: Int64 {
        cleanableResults.flatMap(\.items).filter { !deselectedItems.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var totalFound: Int64 {
        results.filter { $0.category.mode != .listOnly }.reduce(0) { $0 + $1.totalSize }
    }

    func scan() async {
        isScanning = true
        results = await CleanerScanner.scan(CleanupCatalog.all)
        deselectedItems = []
        isScanning = false
    }

    func clean() async {
        isCleaning = true
        var toTrash: [URL] = []
        var toDelete: [URL] = []
        for result in cleanableResults {
            let urls = result.items.map(\.url).filter { !deselectedItems.contains($0) }
            if result.category.mode == .permanent { toDelete += urls } else { toTrash += urls }
        }
        var report = await Trasher.remove(toTrash, mode: .moveToTrash)
        if !toDelete.isEmpty {
            report.merge(await Trasher.remove(toDelete, mode: .deletePermanently))
        }
        lastReport = report
        isCleaning = false
        await scan()
    }

    func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.selectedCategories.contains(id) },
            set: { on in
                if on { self.selectedCategories.insert(id) } else { self.selectedCategories.remove(id) }
            }
        )
    }

    func itemBinding(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { !self.deselectedItems.contains(url) },
            set: { on in
                if on { self.deselectedItems.remove(url) } else { self.deselectedItems.insert(url) }
            }
        )
    }
}

struct CleanerView: View {
    @Bindable var model: CleanerModel
    private let previewLimit = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report = model.lastReport {
                ReportBanner(report: report) { model.lastReport = nil }
            }
            if model.results.isEmpty {
                if model.isScanning {
                    ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Find junk files", systemImage: "sparkles")
                    } description: {
                        Text("Scan caches, logs and developer leftovers. You choose what to remove, and files move to the Trash.")
                    } actions: {
                        Button("Scan Now") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                resultsList
            }
        }
        .confirmationDialog(
            "Clean \(Format.bytes(model.selectedSize))?",
            isPresented: $model.showConfirm
        ) {
            Button("Clean", role: .destructive) { Task { await model.clean() } }
        } message: {
            Text("Selected files will be moved to the Trash. Items in “Empty Trash” are deleted permanently.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Junk Cleaner").font(.title2.bold())
                Text(model.results.isEmpty ? "Not scanned yet" : "\(Format.bytes(model.totalFound)) found")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button(model.results.isEmpty ? "Scan" : "Rescan") { Task { await model.scan() } }
                .disabled(model.isBusy)
            Button("Clean \(Format.bytes(model.selectedSize))") { model.showConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.selectedSize == 0)
        }
        .padding()
    }

    private var resultsList: some View {
        List {
            ForEach(model.results) { result in
                let listOnly = result.category.mode == .listOnly
                DisclosureGroup {
                    ForEach(result.items.prefix(previewLimit)) { item in
                        HStack {
                            if !listOnly {
                                Toggle("", isOn: model.itemBinding(item.url))
                                    .labelsHidden()
                                    .disabled(!model.selectedCategories.contains(result.id))
                            }
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .help(item.url.abbreviatedPath)
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        }
                    }
                    if result.items.count > previewLimit {
                        Text("…and \(result.items.count - previewLimit) more").foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 10) {
                        if listOnly {
                            Image(systemName: "eye").foregroundStyle(.secondary).frame(width: 16)
                        } else {
                            Toggle("", isOn: model.categoryBinding(result.id)).labelsHidden()
                        }
                        Image(systemName: result.category.symbol)
                            .frame(width: 22)
                            .foregroundStyle(result.category.mode == .permanent ? Color.red : Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.category.name).font(.headline)
                            Text(result.category.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(result.totalSize)).monospacedDigit().font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct ReportBanner: View {
    let report: DeletionReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.failures.isEmpty ? .green : .orange)
                Text(summary)
                Spacer()
                Button("Dismiss", action: dismiss).buttonStyle(.borderless)
            }
            if !report.failures.isEmpty {
                DisclosureGroup("\(report.failures.count) item(s) could not be removed") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.failures) { failure in
                                Text("\(failure.url.abbreviatedPath): \(failure.reason)")
                                    .font(.caption).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
    }

    private var summary: String {
        let size = Format.bytes(report.bytesFreed)
        let count = report.removed.count
        return report.movedToTrash
            ? "Moved \(count) item(s), \(size), to the Trash. Empty the Trash to free the space."
            : "Removed \(count) item(s) and freed \(size)."
    }
}
