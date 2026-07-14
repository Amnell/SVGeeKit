import CoreGraphics
import SwiftUI
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite struct CanvasRasterizerParityTests {
    @MainActor
    @Test func emptyClipPathSuppressesFillInCGAndCanvas() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <clipPath id="empty"/>
          <rect x="10" y="10" width="80" height="80" fill="lime" clip-path="url(#empty)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 100, height: 100)
        let size = CGSize(width: 100, height: 100)

        let raster = try SVGRasterizer.rasterize(doc, pixelSize: size, scale: 1)
        let canvas = try rasterizeCanvas(document: doc, size: size)

        let diff = try SVGSnapshotDiffer.diff(raster, canvas, tolerance: .exact)
        #expect(diff.matches)

        let center = samplePixel(canvas, x: 50, y: 50)
        #expect(center.g < 50)
    }

    private static let redPixelPNG = """
    data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """

    @MainActor
    @Test func imageElementRendersIdenticallyInCGAndCanvas() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             width="20" height="20">
          <image x="5" y="5" width="10" height="10" xlink:href="\(Self.redPixelPNG)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 20, height: 20)
        let size = CGSize(width: 20, height: 20)

        let raster = try SVGRasterizer.rasterize(doc, pixelSize: size, scale: 1)
        let canvas = try rasterizeCanvas(document: doc, size: size)

        let diff = try SVGSnapshotDiffer.diff(raster, canvas, tolerance: .exact)
        #expect(diff.matches)
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
