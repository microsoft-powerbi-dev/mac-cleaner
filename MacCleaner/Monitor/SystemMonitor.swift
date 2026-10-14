import Foundation
import Observation

@MainActor
@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()

    private(set) var cpu: Double = 0
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryUsed: UInt64 = 0
    private(set) var memoryTotal: UInt64 = 1
    private(set) var diskFree: Int64 = 0
    private(set) var diskTotal: Int64 = 1
    private(set) var battery: BatteryInfo?
    private(set) var thermal: ProcessInfo.ThermalState = .nominal

    var memoryFraction: Double { Double(memoryUsed) / Double(max(memoryTotal, 1)) }
    var diskUsedFraction: Double { 1 - Double(diskFree) / Double(max(diskTotal, 1)) }

    private var lastTicks: SystemStats.CPUTicks?
    private var timer: Timer?
    private let historyLength = 60

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        if let ticks = SystemStats.cpuTicks() {
            if let last = lastTicks {
                cpu = SystemStats.cpuUsage(from: last, to: ticks)
                cpuHistory.append(cpu)
                if cpuHistory.count > historyLength { cpuHistory.removeFirst(cpuHistory.count - historyLength) }
            }
            lastTicks = ticks
        }
        let memory = SystemStats.memory()
        memoryUsed = memory.used
        memoryTotal = memory.total
        let disk = SystemStats.disk()
        diskFree = disk.free
        diskTotal = disk.total
        battery = SystemStats.battery()
        thermal = ProcessInfo.processInfo.thermalState
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot (throttling)"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
