import Testing
import Foundation
import CoreGraphics
import SVGCore
import SVGParser
import SVGRenderer
import SVGRendererSwiftUI
import SVGConformance
@testable import SVGRenderer
@testable import SVGRendererSwiftUI

@Suite("SVG image lowering")
struct SVGImageRenderTests {

    private static let redPixelPNG = """
    data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """

    @Test func decoderProducesCGImage() throws {
        let data = SVGImageDataLoader.dataFromDataURI(Self.redPixelPNG)
        #expect(data != nil)
        let cgImage = SVGImageDecoder.cgImage(from: data!)
        #expect(cgImage?.width == 1)
        #expect(cgImage?.height == 1)
    }

    @Test func rasterizesEmbeddedImage() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20">
          <image x="5" y="5" width="10" height="10" xlink:href="\(Self.redPixelPNG)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 20, height: 20)
        let raster = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 20, height: 20))
        let diff = try SVGSnapshotDiffer.diff(raster, raster, tolerance: .exact)
        #expect(diff.matches)
        #expect(raster.width == 20)
        #expect(raster.height == 20)
        // Offset placement must land inside the image viewport (fit-transform order).
        #expect(sample(raster, x: 10, y: 10).r > 100)
        #expect(sample(raster, x: 1, y: 1).r < 40)
    }

    @Test func lowersImageToDrawCommand() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20">
          <image x="5" y="5" width="10" height="10" xlink:href="\(Self.redPixelPNG)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 20, height: 20)
        guard case .image = doc.root.children.first else {
            Issue.record("expected image element"); return
        }
        let cmds = SVGRenderTree.lower(doc)
        let drawCount = cmds.filter {
            if case .drawImage = $0 { return true }
            return false
        }.count
        #expect(drawCount == 1)
    }

    @Test func lowersSVGImageContentWithoutDrawCommand() throws {
        let w3cRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
            .standardizedFileURL
        let svgURL = w3cRoot.appendingPathComponent("images/happysmiley.svg")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="50" height="50">
          <image x="5" y="5" width="40" height="40" preserveAspectRatio="xMidYMid meet"
                 xlink:href="\(svgURL.lastPathComponent)"/>
        </svg>
        """
        let options = SVGParserOptions.localFiles(at: svgURL.deletingLastPathComponent())
        var doc = try SVGParser(options: options).parse(
            data: Data(svg.utf8),
            options: options,
            sourceURL: nil
        )
        doc.intrinsicSize = CGSize(width: 50, height: 50)
        let cmds = SVGRenderTree.lower(doc)
        let drawCount = cmds.filter {
            if case .drawImage = $0 { return true }
            return false
        }.count
        #expect(drawCount == 0)
        let fillCount = cmds.filter {
            if case .fillPath = $0 { return true }
            return false
        }.count
        #expect(fillCount > 0)
    }

    @Test func cssClipInsetsRasterImageViewport() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="40" height="40">
          <image x="0" y="0" width="40" height="40" overflow="hidden" clip="rect(10,10,10,10)"
                 xlink:href="\(Self.redPixelPNG)" preserveAspectRatio="none"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 40, height: 40)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 40, height: 40), scale: 1)

        let center = sample(image, x: 20, y: 20)
        let margin = sample(image, x: 5, y: 5)
        #expect(center.r > 100, "center=\(center)")
        #expect(margin.r < 40, "margin=\(margin)")
        #expect(sample(image, x: 35, y: 35).r < 40)
    }

    @Test func maskingPath06BClipsImagesInsideRedGuides() throws {
        let w3cRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
            .standardizedFileURL
        let svgURL = w3cRoot.appendingPathComponent("svg/masking-path-06-b.svg")
        var doc = try SVGConformanceFixtureParsing.parse(
            data: Data(contentsOf: svgURL),
            svgURL: svgURL
        )
        doc.intrinsicSize = CGSize(width: 480, height: 360)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        func collectImages(_ elements: [SVGElement]) -> [SVGImage] {
            var out: [SVGImage] = []
            for e in elements {
                switch e {
                case .image(let i): out.append(i)
                case .group(let g): out.append(contentsOf: collectImages(g.children))
                case .svg(let s): out.append(contentsOf: collectImages(s.children))
                default: break
                }
            }
            return out
        }
        let allImages = collectImages(doc.root.children)
        #expect(allImages.count == 2)
        #expect(allImages[0].clip == .rect(top: 10, right: 10, bottom: 10, left: 10))
        #expect(allImages[1].referencedDocument != nil)

        // Raster image: content inside red guide, not in the 10px margin to the blue frame.
        let plantInside = sample(image, x: 135, y: 105)
        #expect(plantInside.r > 20 || plantInside.g > 20 || plantInside.b > 20, "plant=\(plantInside)")
        let plantMargin = sample(image, x: 38, y: 48)
        #expect(plantMargin.r < 40 && plantMargin.g < 40 && plantMargin.b < 40)

        // SVG image: gold quadrant of SVGImageTest maps into the clipped region.
        let svgContent = sample(image, x: 300, y: 210)
        #expect(svgContent.r > 150 || svgContent.b > 150, "svgContent=\(svgContent)")
        let svgMargin = sample(image, x: 248, y: 183)
        #expect(svgMargin.r < 40 && svgMargin.g < 40 && svgMargin.b < 40)
    }

    @Test func appliesNamedICCProfileToRasterImage() throws {
        let w3cRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
            .standardizedFileURL
        let images = w3cRoot.appendingPathComponent("images", isDirectory: true)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             width="190" height="190" viewBox="0 0 190 190">
          <defs>
            <color-profile name="changeColor" xlink:href="changeColor.ICM"/>
          </defs>
          <image color-profile="changeColor" x="0" y="0" width="190" height="190"
                 xlink:href="colorprof.png"/>
        </svg>
        """
        let options = SVGParserOptions.localFiles(at: images)
        var doc = try SVGParser(options: options).parse(
            data: Data(svg.utf8),
            options: options,
            sourceURL: nil
        )
        doc.intrinsicSize = CGSize(width: 190, height: 190)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 190, height: 190), scale: 1)

        // changeColor.ICM maps the muted encoded red cell to pure red.
        let red = sample(image, x: 20, y: 20)
        #expect(red.r > 240 && red.g < 20 && red.b < 20, "red=\(red)")
        let green = sample(image, x: 95, y: 20)
        #expect(green.g > 240 && green.r < 20 && green.b < 20, "green=\(green)")
        let blue = sample(image, x: 160, y: 20)
        #expect(blue.b > 240 && blue.r < 20 && blue.g < 20, "blue=\(blue)")
    }

    @Test @MainActor func colorProf01fMatchesW3CReference() throws {
        let w3cRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
            .standardizedFileURL
        let diff = try W3CReferenceDiff.diff(testId: "color-prof-01-f", w3cResourcesRoot: w3cRoot)
        // Draft watermark + system font for labels; color grids must match.
        #expect(diff.mismatchedFraction < 0.08, "max=\(diff.maxChannelDelta) frac=\(diff.mismatchedFraction)")
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.draw(image, in: CGRect(
            x: -CGFloat(x),
            y: -CGFloat(image.height - 1 - y),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
