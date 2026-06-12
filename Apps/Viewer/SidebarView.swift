import SwiftUI
import SVGConformance

struct SidebarView: View {
    @Environment(TestStore.self) private var store
    @Binding var selection: String?

    var body: some View {
        @Bindable var bindable = store
        VStack(spacing: 0) {
            FilterBar()
                .padding(.horizontal)
                .padding(.top, 8)

            List(selection: $selection) {
                ForEach(store.rowsByTag, id: \.tag) { group in
                    Section(header: Text(group.tag.capitalized).font(.headline)) {
                        ForEach(group.rows) { row in
                            TestRowItem(row: row).tag(row.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            CountsBar()
                .padding(8)
        }
        .searchable(text: $bindable.searchText, placement: .sidebar, prompt: "Search tests")
        .frame(minWidth: 280)
    }
}

private struct TestRowItem: View {
    let row: TestRow
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.id)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if let detail = row.record.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct StatusDot: View {
    let status: SVGConformanceStatus
    var body: some View {
        Circle()
            .fill(StatusStyle.color(for: status))
            .frame(width: 10, height: 10)
            .help(StatusStyle.label(for: status))
    }
}

enum StatusStyle {
    static func color(for status: SVGConformanceStatus) -> Color {
        switch status {
        case .passed: return .green
        case .failed: return .red
        case .partialBaseline: return .yellow
        case .missingBaseline: return .orange
        case .skipped: return .gray
        case .parseError, .renderError: return .purple
        }
    }
    static func label(for status: SVGConformanceStatus) -> String {
        switch status {
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .partialBaseline: return "Partial baseline (unverified)"
        case .missingBaseline: return "Missing baseline"
        case .skipped: return "Skipped"
        case .parseError: return "Parse error"
        case .renderError: return "Render error"
        }
    }
}

private struct FilterBar: View {
    @Environment(TestStore.self) private var store

    private let allStatuses: [SVGConformanceStatus] = [
        .passed, .failed, .partialBaseline, .missingBaseline, .skipped, .parseError, .renderError
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(allStatuses, id: \.self) { status in
                let active = store.statusFilter.contains(status)
                Button {
                    if active { store.statusFilter.remove(status) }
                    else { store.statusFilter.insert(status) }
                } label: {
                    HStack(spacing: 4) {
                        StatusDot(status: status)
                        Text(StatusStyle.label(for: status))
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(active ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CountsBar: View {
    @Environment(TestStore.self) private var store
    var body: some View {
        HStack(spacing: 12) {
            ForEach(store.counts, id: \.0) { item in
                HStack(spacing: 4) {
                    StatusDot(status: item.0)
                    Text("\(item.1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(store.rows.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
