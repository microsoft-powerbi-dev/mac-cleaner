import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var monitor = SystemMonitor.shared
    @State private var menuBar = MenuBarSetting.shared

    init() {
        Prefs.register()
        SystemMonitor.shared.start()
        if Prefs.recordsDailyHistory {
            UsageHistoryStore.standard.recordVolumeSnapshotIfNeeded(volume: SystemStats.disk(), limit: Prefs.historySnapshotLimit)
        }
    }

    var body: some Scene {
        Window("MacCleaner", id: "main") {
            ContentView(monitor: monitor)
                .frame(minWidth: 900, minHeight: 580)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $menuBar.isShown) {
            MenuBarMonitorView(monitor: monitor)
        } label: {
            Image(systemName: "sparkles")
            Text(Format.percent(monitor.cpu))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Whether the menu-bar monitor is shown. Not `@AppStorage`: binding `MenuBarExtra(isInserted:)`
/// to `@AppStorage` at the App level makes SwiftUI re-evaluate the scene graph endlessly.
@MainActor
@Observable
final class MenuBarSetting {
    static let shared = MenuBarSetting()

    var isShown: Bool {
        didSet { UserDefaults.standard.set(isShown, forKey: Prefs.showMenuBarExtra) }
    }

    private init() {
        Prefs.register()
        isShown = UserDefaults.standard.bool(forKey: Prefs.showMenuBarExtra)
    }

    /// Re-reads the stored value (after "Reset All Settings").
    func reload() {
        let stored = UserDefaults.standard.bool(forKey: Prefs.showMenuBarExtra)
        if stored != isShown { isShown = stored }
    }
}
