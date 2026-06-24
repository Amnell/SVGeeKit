import CoreGraphics
import Foundation
import SVGCore
import SVGParser
import SVGRendererSwiftUI

/// Outcome of a single conformance run for one test case.
public enum SVGConformanceStatus: String, Sendable, Codable {
    case passed
    case failed
    /// A partial (auto-tracked) baseline exists. The render is captured and
    /// tracked for regressions, but has not yet been visually verified against
    /// the W3C reference. Promote to `passed` via the Viewer Approve button or
    /// `APPROVE_SNAPSHOTS=<id>` (comma-separated list of test IDs). Using
    /// `APPROVE_SNAPSHOTS=1` does **not** promote partials — it only re-approves
    /// drifted real baselines.
    case partialBaseline
    case missingBaseline
    case skipped
    case parseError
    case renderError
}

public struct SVGConformanceRecord: Sendable, Codable {
    public let testId: String
    public let tag: String
    public let status: SVGConformanceStatus
    public let detail: String?
    public let baselinePath: String?
    public let actualPath: String?
    public let diffMaxChannel: Int?
    public let mismatchedFraction: Double?
}

/// Runs a `SVGTestCase` end-to-end and returns a structured record.
@MainActor
public struct SVGConformanceRunner {

    public struct Options: Sendable {
        public var outputSize: CGSize
        public var tolerance: SVGSnapshotDiffer.Tolerance
        /// Directory for verified baselines (committed, gate-kept). A mismatch
        /// here fails the test suite unless `APPROVE_SNAPSHOTS=1` is set.
        public var snapshotsDirectory: URL
        /// Directory for auto-tracked partial baselines (committed, not verified).
        /// Mismatches silently update the stored render and are reported as
        /// `partialBaseline`. Promote to a real baseline via `APPROVE_SNAPSHOTS=<id>`.
        public var partialSnapshotsDirectory: URL
        public var resultsDirectory: URL
        /// When `true`, re-approves drifted **real** baselines and creates new real
        /// baselines for tests that currently have no baseline at all.
        /// Does **not** promote partial baselines; use `promotePartialIDs` for that.
        /// Defaults to `true` when `APPROVE_SNAPSHOTS=1`.
        public var approveBaselines: Bool
        /// Explicit set of test IDs whose partial baseline should be promoted to a
        /// real (verified) baseline on the next run. Populated when
        /// `APPROVE_SNAPSHOTS` is a comma-separated list of IDs rather than `"1"`.
        public var promotePartialIDs: Set<String>

        public init(
            outputSize: CGSize = CGSize(width: 480, height: 360),
            tolerance: SVGSnapshotDiffer.Tolerance = .init(perChannel: 4, pixelFraction: 0.001),
            snapshotsDirectory: URL,
            partialSnapshotsDirectory: URL,
            resultsDirectory: URL,
            approveBaselines: Bool = ProcessInfo.processInfo.environment["APPROVE_SNAPSHOTS"] == "1",
            promotePartialIDs: Set<String> = Options.promotePartialIDsFromEnvironment()
        ) {
            self.outputSize = outputSize
            self.tolerance = tolerance
            self.snapshotsDirectory = snapshotsDirectory
            self.partialSnapshotsDirectory = partialSnapshotsDirectory
            self.resultsDirectory = resultsDirectory
            self.approveBaselines = approveBaselines
            self.promotePartialIDs = promotePartialIDs
        }

        /// Parses `APPROVE_SNAPSHOTS` env var.
        /// - Returns a non-empty set when the value is a comma-separated list of IDs.
        /// - Returns an empty set when the value is absent or `"1"` (bulk-approve mode
        ///   does not promote partials; that must be done explicitly per-ID).
        public static func promotePartialIDsFromEnvironment() -> Set<String> {
            let value = ProcessInfo.processInfo.environment["APPROVE_SNAPSHOTS"] ?? ""
            guard value != "1", !value.isEmpty else { return [] }
            return Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
    }

    public let options: Options
    private let parser = SVGParser()

    public init(options: Options) {
        self.options = options
    }

    public func run(_ testCase: SVGTestCase) -> SVGConformanceRecord {
        if testCase.isSkipped {
            return SVGConformanceRecord(
                testId: testCase.id, tag: testCase.tag.rawValue,
                status: .skipped, detail: testCase.skipReason,
                baselinePath: nil, actualPath: nil,
                diffMaxChannel: nil, mismatchedFraction: nil
            )
        }

        let document: SVGDocument
        do {
            let data = try Data(contentsOf: testCase.svgURL)
            document = try parser.parse(
                data: data,
                baseURL: testCase.svgURL.deletingLastPathComponent()
            )
        } catch {
            return SVGConformanceRecord(
                testId: testCase.id, tag: testCase.tag.rawValue,
                status: .parseError, detail: String(describing: error),
                baselinePath: nil, actualPath: nil,
                diffMaxChannel: nil, mismatchedFraction: nil
            )
        }

        let actualImage: CGImage
        let actualURL = options.resultsDirectory
            .appendingPathComponent(testCase.id, isDirectory: true)
            .appendingPathComponent("actual.png")
        do {
            actualImage = try SVGRasterizer.rasterize(document, pixelSize: options.outputSize)
            try SVGSnapshotDiffer.writePNG(actualImage, to: actualURL)
        } catch {
            return SVGConformanceRecord(
                testId: testCase.id, tag: testCase.tag.rawValue,
                status: .renderError, detail: String(describing: error),
                baselinePath: nil, actualPath: nil,
                diffMaxChannel: nil, mismatchedFraction: nil
            )
        }

        let baselineURL = options.snapshotsDirectory
            .appendingPathComponent(testCase.id, isDirectory: true)
            .appendingPathComponent("baseline.png")
        let partialURL = options.partialSnapshotsDirectory
            .appendingPathComponent(testCase.id, isDirectory: true)
            .appendingPathComponent("baseline.png")

        if let baseline = SVGSnapshotDiffer.loadPNG(baselineURL) {
            // ── Real (verified) baseline ────────────────────────────────────
            do {
                let result = try SVGSnapshotDiffer.diff(baseline, actualImage, tolerance: options.tolerance)
                let exceeds = result.mismatchedFraction > options.tolerance.pixelFraction
                if exceeds && options.approveBaselines {
                    try SVGSnapshotDiffer.writePNG(actualImage, to: baselineURL)
                    try? FileManager.default.removeItem(at: partialURL)
                    return record(testCase, status: .passed,
                                  detail: "baseline re-approved",
                                  baseline: baselineURL, actual: actualURL,
                                  result: result)
                }
                return record(testCase,
                              status: exceeds ? .failed : .passed,
                              detail: exceeds ? "\(result.mismatchedPixels) px exceed tolerance" : nil,
                              baseline: baselineURL, actual: actualURL,
                              result: result)
            } catch {
                return record(testCase, status: .failed, detail: String(describing: error),
                              baseline: baselineURL, actual: actualURL, result: nil)
            }

        } else if let partial = SVGSnapshotDiffer.loadPNG(partialURL) {
            // ── Partial (auto-tracked) baseline ─────────────────────────────
            let shouldPromote = options.promotePartialIDs.contains(testCase.id)
            if shouldPromote {
                // Promote partial → real baseline.
                do {
                    try SVGSnapshotDiffer.writePNG(actualImage, to: baselineURL)
                    try? FileManager.default.removeItem(at: partialURL)
                    return record(testCase, status: .passed,
                                  detail: "promoted from partial baseline",
                                  baseline: baselineURL, actual: actualURL, result: nil)
                } catch {
                    return record(testCase, status: .renderError, detail: String(describing: error),
                                  baseline: nil, actual: actualURL, result: nil)
                }
            }
            // Compare and silently update on change — never fail.
            let result = try? SVGSnapshotDiffer.diff(partial, actualImage, tolerance: options.tolerance)
            let changed = (result?.mismatchedFraction ?? 1) > options.tolerance.pixelFraction
            if changed {
                try? SVGSnapshotDiffer.writePNG(actualImage, to: partialURL)
            }
            let detail = changed
                ? "partial baseline updated (\(result?.mismatchedPixels ?? 0) px changed)"
                : nil
            return record(testCase, status: .partialBaseline, detail: detail,
                          baseline: partialURL, actual: actualURL, result: result)

        } else {
            // ── No baseline at all ───────────────────────────────────────────
            let shouldPromote = options.promotePartialIDs.contains(testCase.id)
            if options.approveBaselines || shouldPromote {
                // Create real baseline when explicitly approving or promoting.
                do {
                    try SVGSnapshotDiffer.writePNG(actualImage, to: baselineURL)
                    return record(testCase, status: .passed, detail: "baseline created",
                                  baseline: baselineURL, actual: actualURL, result: nil)
                } catch {
                    return record(testCase, status: .renderError, detail: String(describing: error),
                                  baseline: nil, actual: actualURL, result: nil)
                }
            }
            // Auto-write partial baseline — tracked but not yet verified.
            try? SVGSnapshotDiffer.writePNG(actualImage, to: partialURL)
            return record(testCase, status: .partialBaseline,
                          detail: "partial baseline created",
                          baseline: partialURL, actual: actualURL, result: nil)
        }
    }

    private func record(
        _ testCase: SVGTestCase,
        status: SVGConformanceStatus,
        detail: String?,
        baseline: URL?,
        actual: URL?,
        result: SVGSnapshotDiffer.DiffResult?
    ) -> SVGConformanceRecord {
        SVGConformanceRecord(
            testId: testCase.id,
            tag: testCase.tag.rawValue,
            status: status,
            detail: detail,
            baselinePath: baseline?.path,
            actualPath: actual?.path,
            diffMaxChannel: result.map { Int($0.maxChannelDelta) },
            mismatchedFraction: result?.mismatchedFraction
        )
    }
}

public enum SVGConformanceReportEmitter {
    public static func write(_ records: [SVGConformanceRecord], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: url, options: .atomic)
    }
}
