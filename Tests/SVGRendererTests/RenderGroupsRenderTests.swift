import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGRenderer
import SVGRendererSwiftUI

@Suite("render groups")
@MainActor
struct RenderGroupsRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    @Test func renderGroups01bUsesGroupLayerForOpacity() throws {
        let doc = try parse(testId: "render-groups-01-b")
        let groupOpacities = groupOpacityValues(in: .group(doc.root))
        #expect(groupOpacities.contains(0.5))

        let hasGroupLayer = containsGroupLayer(opacity: 0.5, in: SVGRenderTree.lower(doc))
        #expect(hasGroupLayer)
    }

    @Test func renderGroups01bCompositesGroupOpacityAsUnit() throws {
        let image = try render(testId: "render-groups-01-b")

        // Maroon rect center — opaque within the group, 0.5 over the striped backdrop.
        let rectCenter = samplePixel(image, x: 243, y: 162)
        #expect(rectCenter.r > rectCenter.g + 20, "rect should stay maroon, not text gray")
        #expect(rectCenter.r > 170)
        #expect(rectCenter.g < 140)
        #expect(rectCenter.b > 100 && rectCenter.b < 170)
    }

    private func parse(testId: String) throws -> SVGDocument {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/\(testId).svg")
        let data = try Data(contentsOf: svgURL)
        return try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
    }

    private func groupOpacityValues(in element: SVGElement) -> [CGFloat] {
        switch element {
        case .group(let g):
            return [g.opacity] + g.children.flatMap { groupOpacityValues(in: $0) }
        default:
            return []
        }
    }

    private func containsGroupLayer(opacity: CGFloat, in commands: [SVGRenderCommand]) -> Bool {
        for command in commands {
            if case .groupLayer(let value, let content) = command {
                if abs(value - opacity) < 0.001 { return true }
                if containsGroupLayer(opacity: opacity, in: content) { return true }
            }
            if case .maskedContent(_, _, let content) = command {
                if containsGroupLayer(opacity: opacity, in: content) { return true }
            }
        }
        return false
    }

    private func render(testId: String) throws -> CGImage {
        var doc = try parse(testId: testId)
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
}
