import AppKit
import Charts
import SwiftUI

/// Small menu-bar popover.
struct MenuBarMonitorView: View {
    let monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacCleaner").font(.headline)
            StatsGrid(monitor: monitor, compact: true)
            CPUChart(history: monitor.cpuHistory).frame(height: 50)
            Divider()
            HStack {
                Button("Open MacCleaner") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

/// The dashboard shown in the main window.
struct DashboardView: View {
    let monitor: SystemMonitor
    var go: (SidebarItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview").font(.title2.bold())
                StatsGrid(monitor: monitor, compact: false)
                GroupBox("CPU, last 2 minutes") {
                    CPUChart(history: monitor.cpuHistory).frame(height: 120).padding(.top, 4)
                }
                Text("Quick actions").font(.headline)
                HStack(spacing: 12) {
                    QuickAction(title: "Clean Junk", symbol: "sparkles") { go(.cleaner) }
                    QuickAction(title: "Uninstall Apps", symbol: "trash.square") { go(.uninstaller) }
                    QuickAction(title: "Analyze Disk", symbol: "chart.pie") { go(.analyzer) }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatsGrid: View {
    let monitor: SystemMonitor
    let compact: Bool

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(
                title: "CPU", symbol: "cpu", fraction: monitor.cpu,
                value: Format.percent(monitor.cpu),
                caption: "Thermal: \(monitor.thermal.label)", compact: compact
            )
            StatTile(
                title: "Memory", symbol: "memorychip", fraction: monitor.memoryFraction,
                value: Format.percent(monitor.memoryFraction),
                caption: "\(Format.bytes(monitor.memoryUsed)) of \(Format.bytes(monitor.memoryTotal))",
                compact: compact
            )
            StatTile(
                title: "Disk", symbol: "internaldrive", fraction: monitor.diskUsedFraction,
                value: Format.percent(monitor.diskUsedFraction),
                caption: "\(Format.bytes(monitor.diskFree)) free", compact: compact
            )
            if let battery = monitor.battery {
                StatTile(
                    title: "Battery",
                    symbol: battery.isCharging ? "battery.100.bolt" : "battery.75",
                    fraction: battery.percent,
                    value: Format.percent(battery.percent),
                    caption: battery.isCharging ? "Charging" : (battery.onACPower ? "Plugged in" : "On battery"),
                    compact: compact,
                    highIsGood: true
                )
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let symbol: String
    let fraction: Double
    let value: String
    let caption: String
    let compact: Bool
    var highIsGood = false

    private var tint: Color {
        let level = highIsGood ? 1 - fraction : fraction
        switch level {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(compact ? .caption.bold() : .headline)
            Text(value).font(compact ? .title3.bold() : .largeTitle.bold()).monospacedDigit()
            ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(compact ? 8 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CPUChart: View {
    let history: [Double]

    var body: some View {
        Chart(Array(history.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("Time", index), y: .value("CPU", value * 100))
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            LineMark(x: .value("Time", index), y: .value("CPU", value * 100))
                .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
    }
}

struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title)
                Text(title)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}
