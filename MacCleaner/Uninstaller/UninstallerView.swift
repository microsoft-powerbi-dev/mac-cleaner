import AppKit
import SwiftUI

@MainActor
@Observable
final class UninstallerModel {
    var apps: [InstalledApp] = []
    var isLoading = false
    var search = ""
    var selectedID: URL?
    var leftovers: [Leftover] = []
    var isFindingLeftovers = false
    /// Another copy of the selected app (same bundle identifier) is installed, so its
    /// support files are still in use and are not offered for removal.
    var otherCopyInstalled = false
    var deselected: Set<URL> = []
    var showConfirm = false
    var runningApp: NSRunningApplication?
    var lastReport: DeletionReport?

    var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedID } }

    var totalSize: Int64 {
        (selectedApp?.size ?? 0)
            + leftovers.filter { !deselected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        apps = await AppInventory.load()
        isLoading = false
    }

    func selectionChanged() async {
        leftovers = []
        deselected = []
        otherCopyInstalled = false
        isFindingLeftovers = false
        guard let app = selectedApp, !app.isApple else { return }
        isFindingLeftovers = true
        let id = app.bundleID
        let name = app.name
        let others = Set(apps.filter { $0.id != app.id }.compactMap(\.bundleID))
        let found = await Task.detached(priority: .userInitiated) {
            LeftoverFinder.standard.find(bundleID: id, appName: name, otherBundleIDs: others)
        }.value
        guard selectedApp?.id == app.id else { return }
        isFindingLeftovers = false
        otherCopyInstalled = id.map { id in others.contains { $0.caseInsensitiveCompare(id) == .orderedSame } } ?? false
        leftovers = found
        deselected = Set(found.filter { $0.match != .bundleID }.map(\.url))
    }

    func requestUninstall() {
        guard let app = selectedApp else { return }
        if let id = app.bundleID,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            runningApp = running
        } else {
            showConfirm = true
        }
    }

    func uninstall() async {
        guard let app = selectedApp else { return }
        let urls = [app.url] + leftovers.map(\.url).filter { !deselected.contains($0) }
        let report = await Trasher.remove(urls, mode: .moveToTrash)
        lastReport = report
        if report.removed.contains(app.url) {
            apps.removeAll { $0.id == app.id }
            selectedID = nil
            leftovers = []
        }
    }

    func leftoverBinding(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { !self.deselected.contains(url) },
            set: { on in
                if on { self.deselected.remove(url) } else { self.deselected.insert(url) }
            }
        )
    }
}

struct UninstallerView: View {
    @Bindable var model: UninstallerModel

    var body: some View {
        VStack(spacing: 0) {
            if let report = model.lastReport {
                ReportBanner(report: report) { model.lastReport = nil }
            }
            // A fixed-width list instead of HSplitView: HSplitView asks for its columns' combined
            // minimum widths and pushed the window wider than the screen area it had.
            HStack(spacing: 0) {
                appList.frame(width: 270)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if model.apps.isEmpty { await model.load() } }
        .onChange(of: model.selectedID) { Task { await model.selectionChanged() } }
        .confirmationDialog(
            "Uninstall \(model.selectedApp?.name ?? "app")?",
            isPresented: $model.showConfirm
        ) {
            Button("Move to Trash", role: .destructive) { Task { await model.uninstall() } }
        } message: {
            Text("The app and the selected files (\(Format.bytes(model.totalSize))) will be moved to the Trash.")
        }
        .alert(
            "\(model.runningApp?.localizedName ?? "The app") is running",
            isPresented: Binding(get: { model.runningApp != nil }, set: { if !$0 { model.runningApp = nil } })
        ) {
            Button("Quit App") {
                model.runningApp?.terminate()
                model.runningApp = nil
            }
            Button("Cancel", role: .cancel) { model.runningApp = nil }
        } message: {
            Text("Quit it before uninstalling, then click Uninstall again.")
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $model.search).textFieldStyle(.plain)
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload app list")
            }
            .padding(8)
            Divider()
            List(model.filteredApps, selection: $model.selectedID) { app in
                HStack {
                    AppIcon(url: app.url, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).lineLimit(1)
                        if app.isApple {
                            Text("Apple app").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Format.bytes(app.size)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(app.id)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    AppIcon(url: app.url, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold()).lineLimit(2)
                        Text(app.bundleID ?? "No bundle identifier").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if let version = app.version {
                            Text("Version \(version)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .help(app.bundleID ?? "")
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing) {
                        Text(Format.bytes(model.totalSize)).font(.title3.bold()).monospacedDigit()
                        Button("Uninstall") { model.requestUninstall() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(app.isApple || model.isFindingLeftovers)
                    }
                }
                .padding()
                Divider()

                if app.isApple {
                    ContentUnavailableView(
                        "System app",
                        systemImage: "lock.shield",
                        description: Text("Apple apps are part of macOS and can't be removed.")
                    )
                } else {
                    List {
                        Section("Application") {
                            fileRow(url: app.url, size: app.size)
                        }
                        Section {
                            if model.isFindingLeftovers {
                                ProgressView().frame(maxWidth: .infinity)
                            } else if model.otherCopyInstalled {
                                Text("Another copy of this app is installed, so its support files are kept.")
                                    .foregroundStyle(.secondary)
                            } else if model.leftovers.isEmpty {
                                Text("No leftover files found.").foregroundStyle(.secondary)
                            }
                            ForEach(model.leftovers) { leftover in
                                HStack {
                                    Toggle("", isOn: model.leftoverBinding(leftover.url)).labelsHidden()
                                    fileRow(url: leftover.url, size: leftover.size, badge: Self.badge(for: leftover.match))
                                }
                            }
                        } header: {
                            Text("Support files & leftovers")
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select an app",
                systemImage: "app.dashed",
                description: Text("Choose an app to see its size and the files it leaves in your Library.")
            )
        }
    }

    private static func badge(for match: Leftover.Match) -> (label: String, help: String)? {
        switch match {
        case .bundleID: return nil
        case .related: return ("related", "Its name starts with this app's identifier. It may be a helper, or belong to another edition of the app.")
        case .sharedGroup: return ("shared", "A group container. Other apps from the same developer may use it too.")
        case .appName: return ("name match", "Matched by folder name only. Check that it belongs to this app.")
        }
    }

    private func fileRow(url: URL, size: Int64, badge: (label: String, help: String)? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let badge {
                Text(badge.label).font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .help(badge.help)
            }
            Spacer()
            Text(Format.bytes(size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}
