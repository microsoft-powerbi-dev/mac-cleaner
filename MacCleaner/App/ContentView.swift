import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, cleaner, uninstaller, analyzer

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .cleaner: return "Junk Cleaner"
        case .uninstaller: return "Uninstaller"
        case .analyzer: return "Disk Analyzer"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash.square"
        case .analyzer: return "chart.pie"
        }
    }
}

struct ContentView: View {
    let monitor: SystemMonitor

    @State private var selection: SidebarItem? = .dashboard
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess
    // Models live here so each section keeps its state when you switch tabs.
    @State private var cleaner = CleanerModel()
    @State private var uninstaller = UninstallerModel()
    @State private var analyzer = AnalyzerModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if !hasFullDiskAccess {
                    FullDiskAccessBanner { hasFullDiskAccess = Permissions.hasFullDiskAccess }
                }
                switch selection ?? .dashboard {
                case .dashboard: DashboardView(monitor: monitor) { selection = $0 }
                case .cleaner: CleanerView(model: cleaner)
                case .uninstaller: UninstallerView(model: uninstaller)
                case .analyzer: AnalyzerView(model: analyzer)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess
        }
    }
}

struct FullDiskAccessBanner: View {
    let recheck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is off").font(.headline)
                Text("Without it, MacCleaner can't see some caches, Mail downloads or the Trash. Turn it on in System Settings, then reopen the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
            Button("Check Again", action: recheck)
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}
