import Foundation
import SVGConformance

@main
struct CoverageReport {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("-h") || args.contains("--help") {
            print(helpText)
            return
        }

        let repoRoot = try resolveRepoRoot(args: args)
        let reportURL = repoRoot.appendingPathComponent("docs/conformance/conformance-report.json")
        guard FileManager.default.fileExists(atPath: reportURL.path) else {
            throw UsageError("No conformance report at \(reportURL.path). Run `swift test --filter ConformanceSuite` first.")
        }

        try SVGConformanceMarkdownReport.write(fromReportJSON: reportURL, repoRoot: repoRoot)
        let output = reportURL.deletingLastPathComponent()
        print("Wrote coverage gallery to \(output.path)")
    }

    static func resolveRepoRoot(args: [String], file: String = #filePath) throws -> URL {
        if let flagIndex = args.firstIndex(of: "--repo"), args.indices.contains(flagIndex + 1) {
            let url = URL(fileURLWithPath: args[flagIndex + 1]).standardizedFileURL
            try requirePackageRoot(url)
            return url
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Package.swift").path) {
            return cwd
        }

        let fromSource = URL(fileURLWithPath: file)
            .deletingLastPathComponent() // CoverageReport
            .deletingLastPathComponent() // Apps
            .deletingLastPathComponent() // <repo>
        try requirePackageRoot(fromSource)
        return fromSource
    }

    static func requirePackageRoot(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) else {
            throw UsageError("Not a package root (no Package.swift): \(url.path)")
        }
    }

    static let helpText = """
    CoverageReport — generate GitHub-browseable conformance markdown.

    Usage:
      swift run CoverageReport
      swift run CoverageReport --repo /path/to/SVGeeKit

    Reads docs/conformance/conformance-report.json and writes
    docs/conformance/README.md plus one markdown file per feature tag.
    Image links point at committed snapshots and W3C reference PNGs so
    they load when browsing the files on GitHub.
    """
}

struct UsageError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
