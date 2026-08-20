import Testing
import Foundation
@testable import SVGConformance

@Suite("Conformance markdown gallery")
struct MarkdownReportSuite {

    @Test func writesIndexAndChapterWithRelativeImagePaths() throws {
        let repo = try FixtureRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.root) }

        let records = [
            record(id: "shapes-rect-01-t", tag: "shapes", status: .passed),
            record(id: "shapes-circle-01-t", tag: "shapes", status: .partialBaseline),
            record(
                id: "filters-blend-01-b",
                tag: "filters",
                status: .skipped,
                detail: "feBlend not implemented yet"
            )
        ]
        try SVGConformanceMarkdownReport.write(
            records,
            repoRoot: repo.root,
            outputDirectory: repo.output,
            generatedOn: "2026-08-20"
        )

        let index = try String(contentsOf: repo.output.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(index.contains(SVGConformanceMarkdownReport.generatedMarker))
        #expect(index.contains("Generated from [`conformance-report.json`](conformance-report.json) on 2026-08-20."))
        #expect(index.contains("| [shapes](shapes.md) | 2 | 1 | 1 | 0 | 0 |"))
        #expect(index.contains("| [filters](filters.md) | 1 | 0 | 0 | 1 | 0 |"))
        #expect(index.contains("`partialBaseline`"))

        let shapes = try String(contentsOf: repo.output.appendingPathComponent("shapes.md"), encoding: .utf8)
        #expect(shapes.contains("[coverage index](README.md)"))
        #expect(shapes.contains("[`shapes-rect-01-t`](../../Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/shapes-rect-01-t.svg)"))
        #expect(shapes.contains("src=\"../../Tests/__Snapshots__/shapes-rect-01-t/baseline.png\""))
        #expect(shapes.contains("src=\"../../Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/shapes-rect-01-t.png\""))
        #expect(shapes.contains("src=\"../../Tests/__PartialSnapshots__/shapes-circle-01-t/baseline.png\""))
        #expect(shapes.contains("`partialBaseline`"))
        #expect(shapes.contains("**not** visually verified"))
        #expect(!shapes.contains("filters-blend-01-b"))

        let filters = try String(contentsOf: repo.output.appendingPathComponent("filters.md"), encoding: .utf8)
        #expect(filters.contains("## Renders"))
        #expect(filters.contains("`skipped`<br>feBlend not implemented yet"))
        #expect(filters.contains("src=\"../../Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/filters-blend-01-b.png\""))
        #expect(!filters.contains("__Snapshots__/"))
        #expect(!filters.contains("## No snapshot"))
    }

    @Test func omitsMissingPngsAndEscapesTablePipes() throws {
        let repo = try FixtureRepo.make(createW3CReference: false)
        defer { try? FileManager.default.removeItem(at: repo.root) }

        try SVGConformanceMarkdownReport.write(
            [
                record(id: "shapes-rect-01-t", tag: "shapes", status: .passed),
                record(id: "shapes-ghost-01-t", tag: "shapes", status: .skipped, detail: "a | b")
            ],
            repoRoot: repo.root,
            outputDirectory: repo.output,
            generatedOn: "2026-08-20"
        )

        let shapes = try String(contentsOf: repo.output.appendingPathComponent("shapes.md"), encoding: .utf8)
        #expect(shapes.contains("src=\"../../Tests/__Snapshots__/shapes-rect-01-t/baseline.png\""))
        #expect(!shapes.contains("W3C-SVG-1.1/png/shapes-rect-01-t.png"))
        #expect(shapes.contains("a \\| b"))
    }

    @Test func prefersPartialSnapshotForPartialStatus() throws {
        let repo = try FixtureRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.root) }

        // A verified snapshot also exists; partial status must still link the partial file.
        try FixtureRepo.touch(
            repo.root
                .appendingPathComponent("Tests/__Snapshots__/shapes-circle-01-t/baseline.png")
        )

        try SVGConformanceMarkdownReport.write(
            [record(id: "shapes-circle-01-t", tag: "shapes", status: .partialBaseline)],
            repoRoot: repo.root,
            outputDirectory: repo.output,
            generatedOn: "2026-08-20"
        )

        let shapes = try String(contentsOf: repo.output.appendingPathComponent("shapes.md"), encoding: .utf8)
        #expect(shapes.contains("__PartialSnapshots__/shapes-circle-01-t/baseline.png"))
        #expect(!shapes.contains("__Snapshots__/shapes-circle-01-t/baseline.png"))
    }

    @Test func removesStaleGeneratedChaptersAndKeepsHandWrittenFiles() throws {
        let repo = try FixtureRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.root) }

        let stale = repo.output.appendingPathComponent("obsolete.md")
        try """
        \(SVGConformanceMarkdownReport.generatedMarker)

        leftover
        """.write(to: stale, atomically: true, encoding: .utf8)

        let notes = repo.output.appendingPathComponent("notes.md")
        try "hand-written notes\n".write(to: notes, atomically: true, encoding: .utf8)

        try SVGConformanceMarkdownReport.write(
            [record(id: "shapes-rect-01-t", tag: "shapes", status: .passed)],
            repoRoot: repo.root,
            outputDirectory: repo.output,
            generatedOn: "2026-08-20"
        )

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: notes.path))
        #expect(FileManager.default.fileExists(atPath: repo.output.appendingPathComponent("shapes.md").path))
        #expect(!FileManager.default.fileExists(atPath: repo.output.appendingPathComponent("filters.md").path))
    }

    @Test func writeFromJSONRoundTrips() throws {
        let repo = try FixtureRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.root) }

        let jsonURL = repo.output.appendingPathComponent("conformance-report.json")
        try SVGConformanceReportEmitter.write(
            [record(id: "shapes-rect-01-t", tag: "shapes", status: .passed)],
            to: jsonURL
        )

        try SVGConformanceMarkdownReport.write(
            fromReportJSON: jsonURL,
            repoRoot: repo.root,
            generatedOn: "2026-08-20"
        )

        let index = try String(contentsOf: repo.output.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(index.contains("| [shapes](shapes.md) | 1 | 1 | 0 | 0 | 0 |"))
    }

    private func record(
        id: String,
        tag: String,
        status: SVGConformanceStatus,
        detail: String? = nil
    ) -> SVGConformanceRecord {
        SVGConformanceRecord(
            testId: id,
            tag: tag,
            status: status,
            detail: detail,
            baselinePath: nil,
            actualPath: nil,
            diffMaxChannel: nil,
            mismatchedFraction: nil
        )
    }
}

private enum FixtureRepo {
    struct Layout {
        let root: URL
        var output: URL { root.appendingPathComponent("docs/conformance") }
    }

    static func make(createW3CReference: Bool = true) throws -> Layout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svgeekit-md-\(UUID().uuidString)", isDirectory: true)
        let layout = Layout(root: root)
        try FileManager.default.createDirectory(at: layout.output, withIntermediateDirectories: true)

        try touch(root.appendingPathComponent("Tests/__Snapshots__/shapes-rect-01-t/baseline.png"))
        try touch(root.appendingPathComponent("Tests/__PartialSnapshots__/shapes-circle-01-t/baseline.png"))
        try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/shapes-rect-01-t.svg"))
        try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/shapes-circle-01-t.svg"))
        try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/filters-blend-01-b.svg"))
        try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/shapes-ghost-01-t.svg"))
        if createW3CReference {
            try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/shapes-rect-01-t.png"))
            try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/shapes-circle-01-t.png"))
            try touch(root.appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/filters-blend-01-b.png"))
        }
        return layout
    }

    static func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
    }
}
