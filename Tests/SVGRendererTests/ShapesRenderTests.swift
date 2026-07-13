import CoreGraphics
import Foundation
import Testing
import SVGParser
import SVGRendererSwiftUI

@Suite("degenerate shape rendering")
@MainActor
struct ShapesRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    @Test func shapesIntro01tDegenerateRectsRenderNothing() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/shapes-intro-01-t.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        // Zero-width stroked rect sits at x=55 inside the first container box.
        #expect(samplePixel(image, x: 55, y: 80) == samplePixel(image, x: 65, y: 80))
        // Zero-height stroked rect sits at y=55 inside the second container box.
        #expect(samplePixel(image, x: 145, y: 55) == samplePixel(image, x: 145, y: 80))
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
        ctx.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
