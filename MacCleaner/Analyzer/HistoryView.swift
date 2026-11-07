import Charts
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AnalyzerModel
    @State private var confirmClear = false

    var body: some View {
        let history = model.history
        if history.isEmpty {
            ContentUnavailableView("No history yet", systemImage: "chart.xyaxis.line",
                                   description: Text("MacCleaner records disk usage every day you open it and after every scan."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    diskChart(history)
                    rootSection
                }
                .padding()
            }
            .confirmationDialog("Clear all usage history?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { model.clearHistory() }
            }
        }
    }

    private func diskChart(_ history: [UsageSnapshot]) -> some View {
        let first = history.first!
        let last = history.last!
        let delta = last.volumeUsed - first.volumeUsed
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Startup disk used").font(.headline)
                Spacer()
                Text("\(delta >= 0 ? "+" : "−")\(Format.bytes(abs(delta))) since \(Format.date(first.date))")
                    .foregroundStyle(delta > 0 ? .orange : .green)
                Button("Clear History…") { confirmClear = true }.buttonStyle(.borderless)
            }
            Chart(history) { snap in
                LineMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.volumeUsed) / 1e9))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.volumeUsed) / 1e9))
                    .symbolSize(20)
            }
            .chartYAxisLabel("GB used")
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var rootSection: some View {
        let scans = model.rootHistory
        let rootName = (model.result?.root.url ?? model.rootURL).abbreviatedPath
        VStack(alignment: .leading, spacing: 8) {
            Text("\(rootName) over time").font(.headline)
            if scans.count < 2 {
                Text("Scan this folder again later to compare. Each scan is saved automatically.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(scans) { snap in
                    LineMark(x: .value("Date", snap.date), y: .value("Size", Double(snap.rootSize ?? 0) / 1e9))
                        .foregroundStyle(.purple)
                    PointMark(x: .value("Date", snap.date), y: .value("Size", Double(snap.rootSize ?? 0) / 1e9))
                        .foregroundStyle(.purple).symbolSize(20)
                }
                .chartYAxisLabel("GB")
                .frame(height: 140)
                comparison(scans)
            }
        }
    }

    @ViewBuilder
    private func comparison(_ scans: [UsageSnapshot]) -> some View {
        let latest = scans.last!
        let earlier = scans.dropLast()
        let baseline = earlier.first { $0.date == model.compareDate } ?? earlier.last!
        let changes = UsageHistory.diff(from: baseline, to: latest)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Compare latest scan with", selection: Binding(
                    get: { baseline.date },
                    set: { model.compareDate = $0 }
                )) {
                    ForEach(earlier.reversed()) { snap in
                        Text(snap.date.formatted(date: .abbreviated, time: .shortened)).tag(snap.date)
                    }
                }
                .fixedSize()
                Spacer()
                let delta = (latest.rootSize ?? 0) - (baseline.rootSize ?? 0)
                Text("Total \(delta >= 0 ? "+" : "−")\(Format.bytes(abs(delta)))")
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(delta > 0 ? .orange : .green)
            }
            if changes.isEmpty {
                Text("No changes in the top folders.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Folder").bold()
                        Text("Before").bold()
                        Text("Now").bold()
                        Text("Change").bold()
                    }
                    Divider()
                    ForEach(changes.prefix(20)) { change in
                        GridRow {
                            Text(change.name).lineLimit(1)
                            Text(Format.bytes(change.before)).monospacedDigit().foregroundStyle(.secondary)
                            Text(Format.bytes(change.after)).monospacedDigit()
                            Text("\(change.delta >= 0 ? "+" : "−")\(Format.bytes(abs(change.delta)))")
                                .monospacedDigit()
                                .foregroundStyle(change.delta > 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
    }
}
