import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite struct StructUseRenderTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func structUse03ShowsMatchingDiamonds() throws {
        let svgURL = Self.repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-use-03-t.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        // Reference diamond center (~120, 170) and <use> diamond center (~360, 170) both cyan.
        let reference = samplePixel(image, x: 120, y: 170)
        let instanced = samplePixel(image, x: 360, y: 170)
        #expect(reference.g > 200 && reference.b > 200)
        #expect(instanced.g > 200 && instanced.b > 200)
        #expect(abs(reference.g - instanced.g) <= 5)
        #expect(abs(reference.b - instanced.b) <= 5)
    }

    @Test func structUse12ShowsGreenAfterCycles() throws {
        let svgURL = Self.repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-use-12-f.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        let green = samplePixel(image, x: 48, y: 48)
        #expect(green.g > 100)
        #expect(green.g > green.r)
        #expect(green.g > green.b)
    }

    @Test func structUse09ShowsNestedSymbolStrokes() throws {
        let svgURL = Self.repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-use-09-b.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size

        #expect(doc.definitions["rects"] != nil)
        #expect(doc.definitions["rect1"] != nil)

        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        // Five nested stroke rings centered at (240, 180). The outermost black
        // stroke is invisible on the black canvas; visible bands (outside → in)
        // are gold, orange, purple, slateblue at roughly y ≈ 99, 109, 119, 129.
        let outer = samplePixel(image, x: 240, y: 93)   // clear background above gold
        let gold = samplePixel(image, x: 240, y: 99)
        let orange = samplePixel(image, x: 240, y: 109)
        let purple = samplePixel(image, x: 240, y: 119)
        let inner = samplePixel(image, x: 240, y: 129)

        #expect(outer.r < 40 && outer.g < 40 && outer.b < 40)
        #expect(gold.r > 180 && gold.g > 150 && gold.b < 80)
        #expect(orange.r > 200 && orange.g > 100 && orange.b < 80)
        #expect(purple.r > 80 && purple.g < 80 && purple.b > 80)
        #expect(inner.r < 120 && inner.g < 120 && inner.b > 120)
    }

    @Test func useInClipPathAppliesGeometry() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <defs>
            <rect id="shape" x="0" y="0" width="40" height="40"/>
            <clipPath id="clip">
              <use xlink:href="#shape" x="30" y="30"/>
            </clipPath>
          </defs>
          <rect x="0" y="0" width="100" height="100" fill="lime" clip-path="url(#clip)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 100, height: 100)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 100, height: 100), scale: 1)

        let inside = samplePixel(image, x: 50, y: 50)
        let outside = samplePixel(image, x: 10, y: 10)
        #expect(inside.g > 200)
        #expect(outside.g < 20)
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
