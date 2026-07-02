import SwiftUI
import SVGConformance

struct ContentView: View {
    @Environment(TestStore.self) private var store
    @State private var mode: Mode = .conformance

    enum Mode: String, CaseIterable, Identifiable {
        case conformance, dropZone
        var id: Self { self }
        var label: String {
            switch self {
            case .conformance: return "Conformance"
            case .dropZone: return "Drop SVG"
            }
        }
    }

    var body: some View {
        @Bindable var bindable = store
        Group {
            switch mode {
            case .conformance:
                NavigationSplitView {
                    SidebarView(selection: $bindable.selectedID)
                } detail: {
                    if let row = store.selectedRow {
                        TestDetailView(row: row)
                            .id(row.id)
                    } else if store.isLoading {
                        ProgressView("Running conformance suite…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = store.loadError {
                        ContentUnavailableView("Failed to load", systemImage: "xmark.octagon", description: Text(error))
                    } else {
                        ContentUnavailableView("Select a test", systemImage: "doc.text.magnifyingglass")
                    }
                }
            case .dropZone:
                DropZoneView()
            }
        }
        .navigationTitle("SVGeeKit Viewer")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                if mode == .conformance {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
