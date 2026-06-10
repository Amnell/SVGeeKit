import Foundation
import Observation
import SVGConformance

/// One row in the Viewer UI, combining the discovered test case with its latest
/// run record so the UI can render everything without reloading from disk.
struct TestRow: Identifiable {
    let id: String
    let testCase: SVGTestCase
    let record: SVGConformanceRecord
    let baselineURL: URL?
    let actualURL: URL?
    let referenceURL: URL?
    let svgSource: String

    var status: SVGConformanceStatus { record.status }
    var tag: String { record.tag }
}

/// Centralized state for the Viewer. Re-runs the conformance harness on demand,
/// owns filters/selection, and offers an `approveBaseline` action.
@Observable
@MainActor
final class TestStore {

    var rows: [TestRow] = []
    var selectedID: String?
    var statusFilter: Set<SVGConformanceStatus> = []
    var searchText: String = ""
    var isLoading: Bool = false
    var loadError: String?

    var visibleRows: [TestRow] {
        rows.filter { row in
            if !statusFilter.isEmpty && !statusFilter.contains(row.status) { return false }
            if !searchText.isEmpty,
               !row.id.localizedCaseInsensitiveContains(searchText),
               !row.tag.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    var counts: [(SVGConformanceStatus, Int)] {
        let order: [SVGConformanceStatus] = [
            .passed, .failed, .missingBaseline, .skipped, .parseError, .renderError
        ]
        return order.map { status in
            (status, rows.filter { $0.status == status }.count)
        }
    }

    var rowsByTag: [(tag: String, rows: [TestRow])] {
        let groups = Dictionary(grouping: visibleRows, by: { $0.tag })
        return groups
            .map { (tag: $0.key, rows: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.tag < $1.tag }
    }

    var selectedRow: TestRow? {
        guard let id = selectedID else { return nil }
        return rows.first { $0.id == id }
    }

    func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let index = try SVGTestSuiteIndex(rootDirectory: RepoLayout.suiteRoot)
            let runner = SVGConformanceRunner(options: .init(
                snapshotsDirectory: RepoLayout.snapshotsDirectory,
                resultsDirectory: RepoLayout.resultsDirectory,
                approveBaselines: false
            ))
            var rows: [TestRow] = []
            rows.reserveCapacity(index.cases.count)
            for testCase in index.cases {
                let record = runner.run(testCase)
                let row = makeRow(testCase: testCase, record: record)
                rows.append(row)
            }
            self.rows = rows.sorted { $0.id < $1.id }
            try? SVGConformanceReportEmitter.write(rows.map(\.record), to: RepoLayout.reportURL)
            if selectedID == nil {
                selectedID = self.rows.first?.id
            }
        } catch {
            loadError = "Failed to load: \(error)"
        }
    }

    func approveSelected() async {
        guard let row = selectedRow else { return }
        await approve(testCaseID: row.id)
    }

    /// Re-runs a single test with `APPROVE_SNAPSHOTS=1` semantics, then refreshes its row.
    func approve(testCaseID: String) async {
        guard let index = rows.firstIndex(where: { $0.id == testCaseID }) else { return }
        let row = rows[index]

        let runner = SVGConformanceRunner(options: .init(
            snapshotsDirectory: RepoLayout.snapshotsDirectory,
            resultsDirectory: RepoLayout.resultsDirectory,
            approveBaselines: true
        ))
        let updated = runner.run(row.testCase)
        let newRow = makeRow(testCase: row.testCase, record: updated)
        rows[index] = newRow
        try? SVGConformanceReportEmitter.write(rows.map(\.record), to: RepoLayout.reportURL)
    }

    private func makeRow(testCase: SVGTestCase, record: SVGConformanceRecord) -> TestRow {
        let baselineURL = RepoLayout.snapshotsDirectory
            .appendingPathComponent(testCase.id, isDirectory: true)
            .appendingPathComponent("baseline.png")
        let actualURL = RepoLayout.resultsDirectory
            .appendingPathComponent(testCase.id, isDirectory: true)
            .appendingPathComponent("actual.png")
        let baselineExists = FileManager.default.fileExists(atPath: baselineURL.path)
        let actualExists = FileManager.default.fileExists(atPath: actualURL.path)
        let svgSource = (try? String(contentsOf: testCase.svgURL, encoding: .utf8)) ?? ""

        return TestRow(
            id: testCase.id,
            testCase: testCase,
            record: record,
            baselineURL: baselineExists ? baselineURL : nil,
            actualURL: actualExists ? actualURL : nil,
            referenceURL: testCase.referencePNGURL,
            svgSource: svgSource
        )
    }
}
