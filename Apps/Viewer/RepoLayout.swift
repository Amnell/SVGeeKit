import Foundation

/// Discovers the repo root so the Viewer can read the test suite, snapshots,
/// and conformance report from the source tree (not the executable's bundle).
///
/// Strategy: use the source-file path of this file at compile time. That keeps
/// the binary self-locating when launched via `swift run Viewer`. If the binary
/// is moved, fall back to the current working directory if it contains a
/// `Package.swift`.
enum RepoLayout {
    static let repoRoot: URL = {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Package.swift").path) {
            return cwd
        }
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // Viewer
            .deletingLastPathComponent() // Apps
            .deletingLastPathComponent() // <repo>
    }()

    static let suiteRoot = repoRoot
        .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)

    static let snapshotsDirectory = repoRoot
        .appendingPathComponent("Tests/__Snapshots__", isDirectory: true)

    static let resultsDirectory = repoRoot
        .appendingPathComponent("Tests/__SnapshotResults__", isDirectory: true)

    static let reportURL = repoRoot
        .appendingPathComponent("docs/conformance/conformance-report.json")
}
