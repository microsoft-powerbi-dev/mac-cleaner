import Charts
import SwiftUI

/// Detailed breakdown of a scan: by kind, by age, by top-level folder.
struct BreakdownView: View {
    @Bindable var model: AnalyzerModel
    let result: DiskScanResult

    private struct Slice: Identifiable {
        let id: String
        let title: String
        let bytes: Int64
    }

    var body: some View {
        let volume = SystemStats.disk()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    tile("Scanned", Format.bytes(result.root.size), "externaldrive")
                    tile("Files", result.fileCount.formatted(), "doc")
                    tile("Disk free", Format.bytes(volume.free), "internaldrive")
                    tile("Caches & logs", Format.bytes(result.kindTotals[.cache] ?? 0), "clock.arrow.circlepath")
                    if model.duplicateGroups != nil {
                        tile("Duplicates", Format.bytes(model.duplicateWaste), "doc.on.doc")
                    }
                }
                kindChart
                HStack(alignment: .top, spacing: 24) {
                    ageChart
                    folderChart
                }
            }
            .padding()
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var kindChart: some View {
        let total = max(1, result.kindTotals.values.reduce(0, +))
        let kinds = FileKind.allCases
            .map { ($0, result.kindTotals[$0] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("By file type").font(.headline)
            Text("Click a type to see its largest files.").font(.caption).foregroundStyle(.secondary)
            ForEach(kinds, id: \.0) { kind, bytes in
                Button {
                    model.filter = FileFilter()
                    model.filter.kinds = [kind]
                    model.filter.minSize = .oneMB
                    model.showHogs = false
                    model.tab = .largest
                } label: {
                    HStack {
                        Label(kind.title, systemImage: kind.symbol).frame(width: 170, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.gradient)
                                .frame(width: max(2, geo.size.width * CGFloat(bytes) / CGFloat(total)))
                        }
                        .frame(height: 14)
                        Text(Format.bytes(bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Text(Format.percent(Double(bytes) / Double(total))).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ageChart: some View {
        let slices = AgeBucket.allCases.map { Slice(id: $0.rawValue, title: $0.title, bytes: result.ageTotals[$0] ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("By last modified").font(.headline)
            Chart(slices) { slice in
                BarMark(x: .value("Age", slice.title), y: .value("GB", Double(slice.bytes) / 1e9))
                    .foregroundStyle(.teal)
                    .annotation(position: .top) {
                        if slice.bytes > 0 {
                            Text(Format.bytes(slice.bytes)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
            }
            .chartYAxisLabel("GB")
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity)
    }

    private var folderChart: some View {
        let folders = model.visible(result.root.children).prefix(8)
            .map { Slice(id: $0.url.path, title: $0.name, bytes: $0.size) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Largest items in \(result.root.name)").font(.headline)
            let top = max(1, folders.first?.bytes ?? 1)
            ForEach(folders) { slice in
                HStack {
                    Text(slice.title).lineLimit(1).truncationMode(.middle).frame(width: 130, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.indigo.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(slice.bytes) / CGFloat(top)))
                    }
                    .frame(height: 12)
                    Text(Format.bytes(slice.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
