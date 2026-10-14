import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var monitor = SystemMonitor.shared

    init() {
        SystemMonitor.shared.start()
    }

    var body: some Scene {
        Window("MacCleaner", id: "main") {
            ContentView(monitor: monitor)
                .frame(minWidth: 900, minHeight: 580)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarMonitorView(monitor: monitor)
        } label: {
            Image(systemName: "sparkles")
            Text(Format.percent(monitor.cpu))
        }
        .menuBarExtraStyle(.window)
    }
}
