import CoreGraphics
import Foundation
import SVGCore
import SVGParser
import SVGRendererSwiftUI

/// Outcome of a single conformance run for one test case.
public enum SVGConformanceStatus: String, Sendable, Codable {
    case passed
    case failed
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
        public var snapshotsDirectory: URL
        public var resultsDirectory: URL
        public var approveBaselines: Bool

        public init(
            outputSize: CGSize = CGSize(width: 480, height: 360),
            tolerance: SVGSnapshotDiffer.Tolerance = .init(perChannel: 4, pixelFraction: 0.001),
            snapshotsDirectory: URL,
            resultsDirectory: URL,
            approveBaselines: Bool = ProcessInfo.processInfo.environment["APPROVE_SNAPSHOTS"] == "1"
        ) {
            self.outputSize = outputSize
            self.tolerance = tolerance
            self.snapshotsDirectory = snapshotsDirectory
            self.resultsDirectory = resultsDirectory
            self.approveBaselines = approveBaselines
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
            document = try parser.parse(data: data)
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

        if let baseline = SVGSnapshotDiffer.loadPNG(baselineURL) {
            do {
                let result = try SVGSnapshotDiffer.diff(baseline, actualImage, tolerance: options.tolerance)
                let exceeds = result.mismatchedFraction > options.tolerance.pixelFraction
                if exceeds && options.approveBaselines {
                    try SVGSnapshotDiffer.writePNG(actualImage, to: baselineURL)
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
        } else {
            if options.approveBaselines {
                do {
                    try SVGSnapshotDiffer.writePNG(actualImage, to: baselineURL)
                    return record(testCase, status: .passed, detail: "baseline created",
                                  baseline: baselineURL, actual: actualURL, result: nil)
                } catch {
                    return record(testCase, status: .renderError, detail: String(describing: error),
                                  baseline: nil, actual: actualURL, result: nil)
                }
            }
            return record(testCase, status: .missingBaseline,
                          detail: "no baseline; run with APPROVE_SNAPSHOTS=1 after visual review",
                          baseline: nil, actual: actualURL, result: nil)
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
