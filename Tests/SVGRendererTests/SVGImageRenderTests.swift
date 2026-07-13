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
        var doc = try SVGParser().parse(
            string: svg,
            baseURL: svgURL.deletingLastPathComponent()
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
}
