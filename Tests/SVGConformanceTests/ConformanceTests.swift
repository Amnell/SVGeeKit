import Testing
import Foundation
import CoreGraphics
@testable import SVGConformance

/// Runs every vendored W3C-shaped test through the conformance harness.
/// Baselines live alongside the source tree under `Tests/__Snapshots__/`.
/// New / changed baselines require `APPROVE_SNAPSHOTS=1` after visual review.
@Suite("W3C SVG 1.1 conformance")
@MainActor
struct ConformanceSuite {

    @Test(arguments: try testCases())
    func render(_ testCase: SVGTestCase) throws {
        let runner = SVGConformanceRunner(options: .init(
            snapshotsDirectory: Paths.snapshotsDirectory,
            partialSnapshotsDirectory: Paths.partialSnapshotsDirectory,
            resultsDirectory: Paths.resultsDirectory
        ))
        let record = runner.run(testCase)
        try Reporter.shared.record(record)

        switch record.status {
        case .passed, .skipped, .missingBaseline, .partialBaseline:
            // missingBaseline is kept for parse/render errors with no output.
            // partialBaseline tracks auto-captured renders pending visual review.
            return
        case .failed:
            Issue.record(.init(rawValue: "Snapshot mismatch for \(record.testId): \(record.detail ?? "")"))
        case .parseError:
            Issue.record(.init(rawValue: "Parse error for \(record.testId): \(record.detail ?? "")"))
        case .renderError:
            Issue.record(.init(rawValue: "Render error for \(record.testId): \(record.detail ?? "")"))
        }
    }

    static nonisolated func testCases() throws -> [SVGTestCase] {
        let root = try Paths.suiteRoot()
        let index = try SVGTestSuiteIndex(rootDirectory: root)
        return index.cases
    }
}

/// Computes repo-rooted paths so committed baselines + the JSON report sit
/// in the source tree, not in the test bundle's temp copy.
enum Paths {
    static func suiteRoot() throws -> URL {
        let bundleURL = Bundle.module.url(forResource: "W3C-SVG-1.1", withExtension: nil)
        if let bundleURL { return bundleURL }
        // Fallback: source-tree path relative to this file.
        return repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
    }

    static let repoRoot: URL = {
        // This file lives at <repo>/Tests/SVGConformanceTests/ConformanceTests.swift.
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // SVGConformanceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // <repo>
    }()

    static let snapshotsDirectory: URL = repoRoot.appendingPathComponent("Tests/__Snapshots__", isDirectory: true)
    static let partialSnapshotsDirectory: URL = repoRoot.appendingPathComponent("Tests/__PartialSnapshots__", isDirectory: true)
    static let resultsDirectory: URL = repoRoot.appendingPathComponent("Tests/__SnapshotResults__", isDirectory: true)
    static let reportURL: URL = repoRoot.appendingPathComponent("docs/conformance/conformance-report.json")
}

/// Aggregates per-test records and emits a single JSON report at process exit.
final class Reporter: @unchecked Sendable {
    static let shared = Reporter()

    private let lock = NSLock()
    private var records: [SVGConformanceRecord] = []

    private init() {
        atexit_b { [weak self] in
            guard let self else { return }
            self.flush()
        }
    }

    func record(_ record: SVGConformanceRecord) throws {
        lock.lock(); defer { lock.unlock() }
        records.append(record)
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        let sorted = records.sorted { $0.testId < $1.testId }
        try? SVGConformanceReportEmitter.write(sorted, to: Paths.reportURL)
    }
}
