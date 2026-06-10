import SwiftUI
import SVGConformance

struct ContentView: View {
    @Environment(TestStore.self) private var store

    var body: some View {
        @Bindable var bindable = store
        NavigationSplitView {
            SidebarView(selection: $bindable.selectedID)
        } detail: {
            if let row = store.selectedRow {
                TestDetailView(row: row)
            } else if store.isLoading {
                ProgressView("Running conformance suite…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.loadError {
                ContentUnavailableView("Failed to load", systemImage: "xmark.octagon", description: Text(error))
            } else {
                ContentUnavailableView("Select a test", systemImage: "doc.text.magnifyingglass")
            }
        }
        .navigationTitle("SVGeeKit Viewer")
        .toolbar {
            ToolbarItemGroup {
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
