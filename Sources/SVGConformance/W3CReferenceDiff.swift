import CoreGraphics
import Foundation
import SVGParser
import SVGRendererSwiftUI

/// Renders a W3C SVG test case and diffs against the bundled reference PNG.
/// Use during development to sanity-check a render before promoting a baseline.
@MainActor
public enum W3CReferenceDiff {
    public static func diff(
        testId: String,
        w3cResourcesRoot: URL,
        pixelSize: CGSize = CGSize(width: 480, height: 360),
        tolerance: SVGSnapshotDiffer.Tolerance = .init(perChannel: 4, pixelFraction: 0.05)
    ) throws -> SVGSnapshotDiffer.DiffResult {
        let svgURL = w3cResourcesRoot.appendingPathComponent("svg/\(testId).svg")
        let refURL = w3cResourcesRoot.appendingPathComponent("png/\(testId).png")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())
        let actual = try SVGRasterizer.rasterize(doc, pixelSize: pixelSize)
        guard let ref = SVGSnapshotDiffer.loadPNG(refURL) else {
            throw Error.unableToLoadReference(testId: testId, path: refURL.path)
        }
        return try SVGSnapshotDiffer.diff(actual, ref, tolerance: tolerance)
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case unableToLoadReference(testId: String, path: String)

        public var description: String {
            switch self {
            case .unableToLoadReference(let testId, let path):
                "Could not load W3C reference PNG for \(testId) at \(path)"
            }
        }
    }
}
