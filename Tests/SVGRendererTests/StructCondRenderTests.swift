import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite struct StructCondRenderTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func parse(_ testId: String, context: SVGConditionalProcessingContext? = nil) throws -> SVGDocument {
        let svgURL = repoRoot()
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/\(testId).svg")
        let data = try Data(contentsOf: svgURL)
        let options = SVGConformanceFixtureParsing.localFilesOptions(for: svgURL)
        let parser = context.map { SVGParser(conditionalContext: $0, options: options) }
            ?? SVGParser(options: options)
        return try parser.parse(
            data: data,
            options: options,
            sourceURL: svgURL.standardizedFileURL
        )
    }

    private func render(_ testId: String, context: SVGConditionalProcessingContext? = nil) throws -> CGImage {
        var doc = try parse(testId, context: context)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        return try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
    }

    private func joinedText(in document: SVGDocument) -> String {
        var texts: [SVGText] = []
        func walk(_ elements: [SVGElement]) {
            for element in elements {
                switch element {
                case .group(let group):
                    walk(group.children)
                case .text(let text):
                    texts.append(text)
                default:
                    break
                }
            }
        }
        walk(document.root.children)
        return texts.map { $0.runs.map(\.string).joined() }.joined(separator: "|")
    }

    @Test func structCond01ParsesSingleGreenRect() throws {
        let doc = try parse("struct-cond-01-t")
        var rects: [SVGRect] = []
        func walk(_ elements: [SVGElement]) {
            for element in elements {
                switch element {
                case .group(let group):
                    walk(group.children)
                case .rect(let rect):
                    rects.append(rect)
                default:
                    break
                }
            }
        }
        walk(doc.root.children)
        let paintedRects = rects.filter {
            if case .none = $0.paint.fill { return false }
            if case .color(let c) = $0.paint.fill { return c.alpha > 0.01 }
            return true
        }
        #expect(paintedRects.count == 1)
        guard case .color(let fill) = paintedRects[0].paint.fill else {
            Issue.record("expected color fill"); return
        }
        #expect(fill.green > 0.4 && fill.red < 0.2)
    }

    @Test func structCond01ShowsGreenLowerLeftRect() throws {
        let image = try render("struct-cond-01-t")
        let green = samplePixel(image, x: 110, y: 225)
        let redCorner = samplePixel(image, x: 110, y: 50)
        let blueCorner = samplePixel(image, x: 350, y: 50)
        #expect(green.g > 100 && green.r < 80 && green.b < 80)
        #expect(redCorner.r < 80)
        #expect(blueCorner.b < 80)
    }

    @Test func structCond02ParsesEnglishBranch() throws {
        let doc = try parse(
            "struct-cond-02-t",
            context: SVGConditionalProcessingContext(preferredLanguages: ["en-US"])
        )
        let joined = joinedText(in: doc)
        #expect(joined.contains("English"))
        #expect(joined.contains("Why can't they just speak English"))
        #expect(joined.contains("You have no (matching) language preference set") == false)
    }

    @Test func structCond02ParsesDefaultBranchWhenNoLanguageMatches() throws {
        let doc = try parse(
            "struct-cond-02-t",
            context: SVGConditionalProcessingContext(preferredLanguages: ["xx"])
        )
        let joined = joinedText(in: doc)
        #expect(joined.contains("You have no (matching) language preference set"))
        #expect(joined.contains("Why can't they just speak English"))
        #expect(joined.contains("Pourquoi, tout simplement, ne parlent-ils pas en Français"))
        #expect(joined.contains("なぜ、みんな日本語を話してくれないのか"))
        #expect(joined.contains("English (US)") == false)
    }

    @Test func structCondOverview04SuppressesChildWhenParentFails() throws {
        let image = try render("struct-cond-overview-04-f")
        // Pass criteria: no red (except draft watermark). Green rect remains.
        let body = samplePixel(image, x: 50, y: 50)
        #expect(body.g > 100 && body.r < 80, "expected green, got \(body)")
        var redBody = 0
        for y in 25..<120 {
            for x in 0..<120 {
                let p = samplePixel(image, x: x, y: y)
                if p.r > 200 && p.g < 80 && p.b < 80 { redBody += 1 }
            }
        }
        #expect(redBody == 0, "red body pixels=\(redBody)")
    }

    @Test func structCondOverview03EmptyAttributesDoNotCoverBlueRects() throws {
        let image = try render("struct-cond-overview-03-f")
        // Pass criteria: three blue boxes visible (empty required* / systemLanguage = false).
        for y in [50, 170, 290] {
            let p = samplePixel(image, x: 50, y: y)
            #expect(p.b > 150 && p.r < 80 && p.g < 80, "expected blue at y=\(y), got \(p)")
        }
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
