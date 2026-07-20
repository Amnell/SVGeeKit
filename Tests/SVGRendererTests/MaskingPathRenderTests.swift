import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

/// Clip-path / mask construction edge cases from `masking-path-08-b` and
/// `masking-path-10-b` (SVG 1.1 §14.3 / §14.4).
@Suite("masking-path rendering")
@MainActor
struct MaskingPathRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    private static let gridCenters: [(Int, Int)] = [
        (185, 125), (240, 125), (295, 125),
        (185, 180), (240, 180), (295, 180),
        (185, 235), (240, 235), (295, 235),
    ]

    @Test func maskingPath08BHasNoRedAndNineGreenCells() throws {
        let image = try render(testId: "masking-path-08-b")
        #expect(!imageHasStrongRed(image))
        assertNineLimeCells(image)
    }

    @Test func maskingPath10BHasNoRedAndNineGreenCells() throws {
        let image = try render(testId: "masking-path-10-b")
        #expect(!imageHasStrongRed(image))
        assertNineLimeCells(image)
    }

    @Test func emptyClipPathSuppressesElement() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <defs><clipPath id="empty"/></defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" clip-path="url(#empty)"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func hiddenAndDisplayNoneClipChildrenContributeNothing() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="40">
          <defs>
            <clipPath id="hidden"><rect width="40" height="40" visibility="hidden"/></clipPath>
            <clipPath id="display"><rect width="40" height="40" display="none"/></clipPath>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" clip-path="url(#hidden)"/>
          <g transform="translate(40 0)">
            <rect width="40" height="40" fill="lime"/>
            <rect width="40" height="40" fill="red" clip-path="url(#display)"/>
          </g>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(samplePixel(image, x: 60, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func unknownClipPathURLIsIgnored() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <rect width="40" height="40" fill="red"/>
          <rect width="40" height="40" fill="lime" clip-path="url(#unknown)"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func paintAttributesDoNotAffectClipGeometry() throws {
        // opacity / fill-opacity / fill=none / stroke=none still use the shape outline.
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="40">
          <defs>
            <clipPath id="opacity"><rect width="40" height="40" opacity="0"/></clipPath>
            <clipPath id="fillnone"><rect width="40" height="40" fill="none" stroke="none"/></clipPath>
            <clipPath id="fillop"><rect width="40" height="40" fill-opacity="0"/></clipPath>
          </defs>
          <rect width="40" height="40" fill="red"/>
          <rect width="40" height="40" fill="lime" clip-path="url(#opacity)"/>
          <g transform="translate(40 0)">
            <rect width="40" height="40" fill="red"/>
            <rect width="40" height="40" fill="lime" clip-path="url(#fillnone)"/>
          </g>
          <g transform="translate(80 0)">
            <rect width="40" height="40" fill="red"/>
            <rect width="40" height="40" fill="lime" clip-path="url(#fillop)"/>
          </g>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(samplePixel(image, x: 60, y: 20).g > 200)
        #expect(samplePixel(image, x: 100, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func strokeWidthIsExcludedFromClipGeometry() throws {
        // Only the 10×10 fill area clips; a wide stroke must not expand it.
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <defs>
            <clipPath id="stroke">
              <rect x="15" y="15" width="10" height="10" stroke="black" stroke-width="40"/>
            </clipPath>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" clip-path="url(#stroke)"/>
          <rect x="14" y="14" width="12" height="12" fill="lime"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 5, y: 5).g > 200)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func emptyMaskSuppressesElement() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <defs><mask id="empty"/></defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" mask="url(#empty)"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func hiddenAndDisplayNoneMaskChildrenContributeNothing() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="40">
          <defs>
            <mask id="hidden"><rect width="40" height="40" visibility="hidden"/></mask>
            <mask id="display"><rect width="40" height="40" display="none"/></mask>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" mask="url(#hidden)"/>
          <g transform="translate(40 0)">
            <rect width="40" height="40" fill="lime"/>
            <rect width="40" height="40" fill="red" mask="url(#display)"/>
          </g>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(samplePixel(image, x: 60, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func unknownMaskURLIsIgnored() throws {
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <rect width="40" height="40" fill="red"/>
          <rect width="40" height="40" fill="lime" mask="url(#unknown)"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func zeroOpacityMaskContentHidesElement() throws {
        // Unlike clip-path, opacity / fill-opacity / fill=none affect mask coverage.
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="40">
          <defs>
            <mask id="opacity"><rect width="40" height="40" fill="white" opacity="0"/></mask>
            <mask id="fillnone"><rect width="40" height="40" fill="none" stroke="none"/></mask>
            <mask id="fillop"><rect width="40" height="40" fill="white" fill-opacity="0"/></mask>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" mask="url(#opacity)"/>
          <g transform="translate(40 0)">
            <rect width="40" height="40" fill="lime"/>
            <rect width="40" height="40" fill="red" mask="url(#fillnone)"/>
          </g>
          <g transform="translate(80 0)">
            <rect width="40" height="40" fill="lime"/>
            <rect width="40" height="40" fill="red" mask="url(#fillop)"/>
          </g>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(samplePixel(image, x: 60, y: 20).g > 200)
        #expect(samplePixel(image, x: 100, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func blackFillDoesNotContributeLuminanceMaskCoverage() throws {
        // Default black fill has luminance 0 — stroke-opacity 0 leaves an empty mask.
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <defs>
            <mask id="strokeop">
              <rect x="15" y="15" width="10" height="10"
                    stroke="white" stroke-opacity="0" stroke-width="20"/>
            </mask>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" mask="url(#strokeop)"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    @Test func whiteStrokeContributesToMaskCoverage() throws {
        // Black fill (luminance 0) + white stroke should reveal only the stroke ring.
        let image = try rasterize("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
          <defs>
            <mask id="stroke">
              <rect x="15" y="15" width="10" height="10" stroke="white" stroke-width="10"/>
            </mask>
          </defs>
          <rect width="40" height="40" fill="lime"/>
          <rect width="40" height="40" fill="red" mask="url(#stroke)"/>
          <rect x="10" y="10" width="20" height="20" fill="lime"/>
        </svg>
        """)
        #expect(samplePixel(image, x: 5, y: 5).g > 200)
        #expect(samplePixel(image, x: 20, y: 20).g > 200)
        #expect(!imageHasStrongRed(image))
    }

    private func assertNineLimeCells(_ image: CGImage) {
        for (x, y) in Self.gridCenters {
            let p = samplePixel(image, x: x, y: y)
            #expect(p.g > 200 && p.r < 80, "expected lime at (\(x),\(y)), got \(p)")
        }
    }

    private func render(testId: String) throws -> CGImage {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/\(testId).svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        return try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
    }

    private func rasterize(_ svg: String) throws -> CGImage {
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        let size = doc.intrinsicSize ?? CGSize(width: 40, height: 40)
        return try SVGRasterizer.rasterize(doc, pixelSize: size, scale: 1)
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
