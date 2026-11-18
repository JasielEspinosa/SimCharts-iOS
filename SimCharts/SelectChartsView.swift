import SwiftUI

private func chartId(_ apt: AirportResult, _ c: ChartFile) -> String { "\(apt.icao)|\(c.url)" }

private struct ChartGroup: Identifiable {
    let code: String
    let charts: [ChartFile]
    var id: String { code }
}

/// Groups charts by type code, keeping the order in which the codes first appear.
private func grouped(_ charts: [ChartFile]) -> [ChartGroup] {
    var order: [String] = []
    var map: [String: [ChartFile]] = [:]
    for c in charts {
        if map[c.code] == nil { order.append(c.code) }
        map[c.code, default: []].append(c)
    }
    return order.map { ChartGroup(code: $0, charts: map[$0] ?? []) }
}

private enum CheckState { case off, on, mixed }

/// "Select which charts to download": airport > chart type > chart, with tri-state check boxes.
struct SelectChartsView: View {
    let airports: [AirportResult]
    let onConfirm: (Set<String>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<String>
    @State private var open: Set<String>

    init(airports: [AirportResult], onConfirm: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
        self.airports = airports
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        var all = Set<String>()
        var opened = Set<String>()
        for a in airports {
            for c in a.charts { all.insert(chartId(a, c)) }
            for g in grouped(a.charts) where g.charts.count <= 4 { opened.insert("\(a.icao):\(g.code)") }
        }
        _selected = State(initialValue: all)
        _open = State(initialValue: opened)
    }

    private var allIds: [String] {
        airports.flatMap { a in a.charts.map { chartId(a, $0) } }
    }

    private func state(_ ids: [String]) -> CheckState {
        let n = ids.filter { selected.contains($0) }.count
        if n == 0 { return .off }
        return n == ids.count ? .on : .mixed
    }

    private func setIds(_ ids: [String], on: Bool) {
        if on { selected.formUnion(ids) } else { selected.subtract(ids) }
    }

    private func box(_ s: CheckState) -> some View {
        let name: String
        switch s {
        case .off: name = "square"
        case .on: name = "checkmark.square.fill"
        case .mixed: name = "minus.square.fill"
        }
        return Image(systemName: name)
            .font(.title3)
            .foregroundStyle(s == .off ? Color.secondary : Color.accentColor)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select all") { selected = Set(allIds) }
                        Spacer()
                        Button("Select none") { selected = [] }
                    }
                    .buttonStyle(.borderless)
                    Text("\(selected.count) of \(allIds.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(airports, id: \.icao) { apt in
                    Section {
                        ForEach(grouped(apt.charts)) { g in
                            groupRow(apt, g)
                            if open.contains("\(apt.icao):\(g.code)") {
                                ForEach(g.charts) { c in chartRow(apt, c) }
                            }
                        }
                    } header: {
                        airportHeader(apt)
                    }
                }
            }
            .navigationTitle("Select charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Download") { onConfirm(selected) }
                        .disabled(selected.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func airportHeader(_ apt: AirportResult) -> some View {
        let ids = apt.charts.map { chartId(apt, $0) }
        let title: String
        if let n = apt.airportName, !n.trimmed.isEmpty { title = "\(apt.icao) - \(n)" } else { title = apt.icao }
        return Button {
            setIds(ids, on: state(ids) != .on)
        } label: {
            HStack(spacing: 8) {
                box(state(ids))
                Text(title).font(.subheadline.weight(.semibold)).textCase(nil)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func groupRow(_ apt: AirportResult, _ g: ChartGroup) -> some View {
        let ids = g.charts.map { chartId(apt, $0) }
        let key = "\(apt.icao):\(g.code)"
        let isOpen = open.contains(key)
        return HStack(spacing: 8) {
            Button { setIds(ids, on: state(ids) != .on) } label: { box(state(ids)) }
                .buttonStyle(.borderless)
            Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.caption)
            Text("\(FaaChartTypes.describe(g.code)) (\(g.charts.count))")
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen { open.remove(key) } else { open.insert(key) }
        }
    }

    private func chartRow(_ apt: AirportResult, _ c: ChartFile) -> some View {
        let id = chartId(apt, c)
        return Button {
            setIds([id], on: !selected.contains(id))
        } label: {
            HStack(spacing: 8) {
                box(selected.contains(id) ? .on : .off)
                Text(c.name).font(.subheadline).multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
    }
}
