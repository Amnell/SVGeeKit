import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite("painting rendering")
@MainActor
struct PaintingRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    @Test func paintingControl05fShowsGreenRectsWithoutRed() throws {
        let image = try render(testId: "painting-control-05-f")
        #expect(!imageHasStrongRed(image))

        // Reference lime rects remain visible at the grid centers.
        #expect(samplePixel(image, x: 100, y: 100).g > 200)
        #expect(samplePixel(image, x: 200, y: 100).g > 200)
        #expect(samplePixel(image, x: 300, y: 100).g > 200)
        #expect(samplePixel(image, x: 400, y: 100).g > 200)
        #expect(samplePixel(image, x: 100, y: 250).g > 200)
        #expect(samplePixel(image, x: 200, y: 250).g > 200)
        #expect(samplePixel(image, x: 300, y: 250).g > 200)
        #expect(samplePixel(image, x: 400, y: 250).g > 200)
    }

    @Test func paintingRender01bLinearRGBGradientDiffersFromSRGB() throws {
        let image = try render(testId: "painting-render-01-b")

        // Middle of the default (top) bar vs the linearRGB (bottom) bar at x=150.
        let topMid = samplePixel(image, x: 190, y: 100)
        let bottomMid = samplePixel(image, x: 190, y: 280)
        let topBottomDistance = colorDistance(topMid, bottomMid)
        #expect(topBottomDistance > 12)

        // Default and explicit sRGB bars should match at the same sample point.
        let explicitSRGB = samplePixel(image, x: 190, y: 180)
        #expect(colorDistance(topMid, explicitSRGB) < 4)
    }

    @Test func w3cPaintingRender01BMatchesReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "painting-render-01-b", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.05, "mismatchedFraction=\(diff.mismatchedFraction)")
    }

    private func render(testId: String) throws -> CGImage {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/\(testId).svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        return try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
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

    private func colorDistance(
        _ a: (r: Int, g: Int, b: Int),
        _ b: (r: Int, g: Int, b: Int)
    ) -> Int {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    private func imageHasStrongRed(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else { return false }
        let bytesPerRow = image.bytesPerRow
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = bytes[offset]
                let g = bytes[offset + 1]
                let b = bytes[offset + 2]
                let a = bytes[offset + 3]
                guard a > 16 else { continue }
                if r > 200 && g < 80 && b < 80 { return true }
            }
        }
        return false
    }
}
