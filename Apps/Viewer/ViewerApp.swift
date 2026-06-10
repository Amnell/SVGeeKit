import AppKit
import SwiftUI

@main
struct ViewerApp: App {
    @State private var store = TestStore()

    init() {
        // SwiftPM-built executables launch as background tools by default.
        // Promote to a regular GUI app and activate so the window comes forward.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("SVGeeKit Viewer") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    await store.reload()
                }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    Task { await store.reload() }
                }
                .keyboardShortcut("r")
            }
        }
    }
}
