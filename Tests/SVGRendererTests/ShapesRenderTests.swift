import CoreGraphics
import Foundation
import Testing
import SVGConformance
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
        let image = try render(testId: "shapes-intro-01-t")

        // Zero-width stroked rect sits at x=55 inside the first container box.
        #expect(samplePixel(image, x: 55, y: 80) == samplePixel(image, x: 65, y: 80))
        // Zero-height stroked rect sits at y=55 inside the second container box.
        #expect(samplePixel(image, x: 145, y: 55) == samplePixel(image, x: 145, y: 80))
    }

    @Test func shapesIntro01tContainerBoxesUseCrispBlackStrokes() throws {
        let image = try render(testId: "shapes-intro-01-t")

        // First container box top edge: solid black, not gray anti-alias fringe.
        #expect(samplePixel(image, x: 60, y: 50) == (0, 0, 0))
        #expect(samplePixel(image, x: 60, y: 49) == (0, 0, 0))
        // First container box left edge meets the top edge cleanly at the corner.
        #expect(samplePixel(image, x: 50, y: 50) == (0, 0, 0))
        #expect(samplePixel(image, x: 50, y: 60) == (0, 0, 0))
    }

    @Test func typesBasic01fGreyMarkersStayAboveColoredBoxes() throws {
        let image = try render(testId: "types-basic-01-f")

        // Top grey marker should straddle the colored-box top edge (y=75), not sit
        // one pixel lower after hairline snapping shifts open polylines.
        let markerGrey = compositedPixel(image, x: 30, y: 74)
        #expect(markerGrey.r > 150 && markerGrey.g > 150 && markerGrey.b > 150)
        #expect(markerGrey.r < 220)
        #expect(compositedPixel(image, x: 30, y: 75) == markerGrey)
        #expect(compositedPixel(image, x: 50, y: 74) == markerGrey)
        #expect(compositedPixel(image, x: 30, y: 76).r == 255)
    }

    private func render(testId: String) throws -> CGImage {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/\(testId).svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        return try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
    }

    private func compositedPixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
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
        ) else { return (255, 255, 255) }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
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
