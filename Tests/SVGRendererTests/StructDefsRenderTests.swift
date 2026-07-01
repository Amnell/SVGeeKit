import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite struct StructDefsRenderTests {
    @Test func structDefs01MatchesPassCriteria() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-defs-01-t.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let size = CGSize(width: 480, height: 360)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: size, scale: 1)

        let center = samplePixel(image, x: 240, y: 180)
        #expect(center.g > 200)
        #expect(center.r < 50)
        #expect(center.b < 50)

        let corner = samplePixel(image, x: 10, y: 10)
        #expect(corner.r < 50)
    }

    @MainActor
    @Test func canvasMatchesRasterizerForStructDefs01() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-defs-01-t.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let size = CGSize(width: 480, height: 360)

        let raster = try SVGRasterizer.rasterize(doc, pixelSize: size, scale: 1)
        let canvas = try rasterizeCanvas(document: doc, size: size)

        let diff = try SVGSnapshotDiffer.diff(
            raster,
            canvas,
            tolerance: .init(perChannel: 2, pixelFraction: 0.01)
        )
        #expect(diff.mismatchedFraction <= 0.01)
    }

    @MainActor
    private func rasterizeCanvas(document: SVGDocument, size: CGSize) throws -> CGImage {
        let view = SVGImageView(document: document)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else {
            throw CanvasRasterizeError.noImage
        }
        return image
    }

    private enum CanvasRasterizeError: Error {
        case noImage
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
