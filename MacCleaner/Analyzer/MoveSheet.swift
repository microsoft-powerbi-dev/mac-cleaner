import AppKit
import SwiftUI

/// Picks where to move items: iCloud Drive, an external drive, a NAS share, or any folder.
struct MoveSheet: View {
    @Bindable var model: AnalyzerModel
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [StorageDestination] = []
    @State private var selected: StorageDestination?
    @State private var folder: URL?

    var body: some View {
        let size = model.pendingMove.reduce(Int64(0)) { total, url in
            total + (model.result?.files.first { $0.url == url }?.size ?? sizeInTree(url))
        }
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(model.pendingMove.count) item(s)").font(.title2.bold())
            Text("About \(Format.bytes(size)). Each item is copied, the copy is checked, and only then is the original moved to the Trash.")
                .foregroundStyle(.secondary)

            List(selection: $selected) {
                if destinations.isEmpty {
                    Text("No external drives, network shares or iCloud Drive found.").foregroundStyle(.secondary)
                }
                ForEach(destinations) { dest in
                    HStack {
                        Image(systemName: dest.kind.symbol).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(dest.name)
                            Text(dest.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let free = dest.available {
                            Text("\(Format.bytes(free)) free")
                                .foregroundStyle(free < size ? .red : .secondary).monospacedDigit()
                        }
                    }
                    .tag(dest)
                }
            }
            .frame(minHeight: 150)

            HStack {
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh") { load() }
                Spacer()
                Text("NAS not listed? Connect it in Finder › Go › Connect to Server (⌘K).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let target = targetURL {
                Label("Destination: \(target.abbreviatedPath)", systemImage: "arrow.right.circle")
                    .lineLimit(1).truncationMode(.middle)
                if target.path.hasPrefix(StorageDestinations.iCloudDrive.path) {
                    Text("Files upload to iCloud in the background. Keep the Mac online until they finish; use 'Remove Download' in Finder later to free the local copy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { model.pendingMove = []; dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") {
                    guard let target = targetURL else { return }
                    dismiss()
                    Task { await model.move(to: target) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targetURL == nil)
            }
        }
        .padding()
        .frame(width: 560, height: 460)
        .onAppear(perform: load)
        .onChange(of: selected) { if selected != nil { folder = nil } }
    }

    private var targetURL: URL? { folder ?? selected?.url }

    private func load() {
        destinations = StorageDestinations.available()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selected?.url ?? URL(fileURLWithPath: "/Volumes")
        panel.prompt = "Move Here"
        if panel.runModal() == .OK, let url = panel.url {
            selected = nil
            folder = url
        }
    }

    private func sizeInTree(_ url: URL) -> Int64 {
        guard let root = model.result?.root, let chain = DiskInsights.chain(to: url, in: root) else { return 0 }
        return chain.last?.size ?? 0
    }
}

struct MoveReportBanner: View {
    let report: MoveReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.failures.isEmpty ? .green : .orange)
                Text("Moved \(report.moved.count) item(s), \(Format.bytes(report.bytesMoved)), to \(report.destinationName). Originals are in the Trash; empty it to free the space.")
                Spacer()
                if !report.moved.isEmpty {
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting(report.moved.map(\.destination)) }
                        .buttonStyle(.borderless)
                }
                Button("Dismiss", action: dismiss).buttonStyle(.borderless)
            }
            if !report.failures.isEmpty {
                DisclosureGroup("\(report.failures.count) item(s) could not be moved") {
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
}
