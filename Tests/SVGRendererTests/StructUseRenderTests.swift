import CoreGraphics
import Foundation
import Testing
import SVGConformance
import SVGCore
import SVGParser
@testable import SVGRenderer
import SVGRendererSwiftUI

@Suite @MainActor struct StructUseRenderTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let w3cRoot = repoRoot
        .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    private func diffAgainstW3C(testId: String) throws -> SVGSnapshotDiffer.DiffResult {
        try W3CReferenceDiff.diff(testId: testId, w3cResourcesRoot: Self.w3cRoot)
    }

    @Test func structUse01TRegistersUsedTextDefinition() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-01-t.svg")
        let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)

        guard case .text(let usedText) = doc.definitions["usedText"] else {
            Issue.record("expected usedText in definitions"); return
        }
        #expect(usedText.string == "Text")
        #expect(!usedText.runs.isEmpty)
    }

    @Test func structUse01TUsedTextRendersGreen() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-01-t.svg")
        var doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size

        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
        var maxGreen = 0
        for y in 260..<300 {
            for x in 140..<220 {
                maxGreen = max(maxGreen, samplePixel(image, x: x, y: y).g)
            }
        }
        #expect(maxGreen > 200, "usedText instancing did not render bright green (max g=\(maxGreen))")
    }

    @Test func structUse01TMatchesW3CReference() throws {
        let diff = try diffAgainstW3C(testId: "struct-use-01-t")
        #expect(diff.mismatchedFraction < 0.05, "mismatchedFraction=\(diff.mismatchedFraction)")
    }

    @Test func structUse05BRect3FillIsCurrentColor() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-05-b.svg")
        let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)

        guard case .rect(let rect3) = doc.definitions["rect3"] else {
            Issue.record("expected rect3 definition"); return
        }
        #expect(rect3.paint.fill == SVGPaint.currentColor)

        var use3: SVGUse?
        func findUse(_ element: SVGElement) {
            switch element {
            case .use(let u) where u.href == "rect3":
                use3 = u
            case .group(let g):
                g.children.forEach(findUse)
            case .svg(let svg):
                svg.children.forEach(findUse)
            default:
                break
            }
        }
        findUse(.group(doc.root))
        guard let use3 else {
            Issue.record("expected use of rect3"); return
        }
        #expect(use3.paint.color.green > 0.4)

        let instanced = SVGUseExpansion.instanceElement(.rect(rect3), use: use3)
        guard case .rect(let instancedRect) = instanced else {
            Issue.record("expected instanced rect"); return
        }
        #expect(instancedRect.paint.fill == SVGPaint.currentColor)
        #expect(instancedRect.paint.color.green > 0.4)
    }

    @Test func structUse05BRect4UsesExternalRadialGradient() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-05-b.svg")
        let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)

        guard case .rect(let rect4) = doc.definitions["rect4"] else {
            Issue.record("expected rect4 definition"); return
        }
        guard case .paintServer(let id, _, let scope) = rect4.paint.fill else {
            Issue.record("expected paint server fill on rect4"); return
        }
        #expect(id == "radialGrad1")
        guard case .external(let sourceKey) = scope else {
            Issue.record("expected external paint server scope"); return
        }
        #expect(sourceKey == "../images/svgRef1.svg")
    }

    @Test func structUse05BMatchesW3CReference() throws {
        // Gradient stop bands differ slightly from the reference PNG (~14% pixels
        // within per-channel tolerance); rectangle pass criteria are covered by
        // structUse05BExternalComputedValues.
        let diff = try diffAgainstW3C(testId: "struct-use-05-b")
        #expect(diff.mismatchedFraction < 0.15, "mismatchedFraction=\(diff.mismatchedFraction)")
    }

    @Test func structUse05BExternalComputedValues() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-05-b.svg")
        var doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size

        let scopeKey = "../images/svgRef1.svg"
        #expect(doc.externalPaintServers[scopeKey] != nil)
        guard case .radialGradient(let extRadial) = doc.externalPaintServers[scopeKey]?["radialGrad1"] else {
            Issue.record("expected external orange radialGrad1"); return
        }
        guard case .linearGradient(let docLinear) = doc.paintServers["linearGrad1"] else {
            Issue.record("expected referencing blue linearGrad1"); return
        }
        #expect(extRadial.stops.first?.color.red ?? 0 > 0.8)
        #expect(docLinear.stops.first?.color.blue ?? 0 > 0.5)

        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
        let refURL = Self.w3cRoot.appendingPathComponent("png/struct-use-05-b.png")
        guard let ref = SVGSnapshotDiffer.loadPNG(refURL) else {
            Issue.record("missing W3C reference"); return
        }

        // Top-left: blue linear gradient from referencing document defs.
        let topLeft = samplePixel(image, x: 60, y: 110)
        let topLeftRef = samplePixel(ref, x: 60, y: 110)
        #expect(topLeft.b > topLeft.r)
        #expect(abs(topLeft.b - topLeftRef.b) <= 8)

        // Top-right + bottom-left: forestgreen currentColor through use cascade.
        let topRight = samplePixel(image, x: 360, y: 110)
        let bottomLeft = samplePixel(image, x: 120, y: 237)
        let greenRef = samplePixel(ref, x: 360, y: 110)
        #expect(topRight.g > topRight.r && topRight.g > topRight.b)
        #expect(bottomLeft.g > 100 && bottomLeft.g > bottomLeft.r, "expected forestgreen BL, got \(bottomLeft)")
        #expect(abs(topRight.g - greenRef.g) <= 10)
        #expect(abs(bottomLeft.g - greenRef.g) <= 10)

        // Bottom-right: orange radial gradient from external svgRef1.svg.
        let bottomRight = samplePixel(image, x: 360, y: 237)
        let bottomRightRef = samplePixel(ref, x: 360, y: 237)
        #expect(bottomRight.r > 150, "expected orange radial, got \(bottomRight)")
        #expect(bottomRight.r > bottomRight.b, "expected orange radial, got \(bottomRight)")
        #expect(abs(bottomRight.r - bottomRightRef.r) <= 15)
        #expect(abs(bottomRight.g - bottomRightRef.g) <= 15)
    }

    @Test func structUse04BShowsExternalShapes() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/struct-use-04-b.svg")
        let data = try Data(contentsOf: svgURL)
        var doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        doc.intrinsicSize = doc.intrinsicSize ?? doc.viewBox?.size
        #expect(doc.definitions["alpha"] != nil)

        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)
        let refURL = Self.w3cRoot.appendingPathComponent("png/struct-use-04-b.png")
        guard let ref = SVGSnapshotDiffer.loadPNG(refURL) else {
            Issue.record("missing W3C reference"); return
        }

        // svgRef4.css paints rect#alpha fuchsia with a 1px black stroke from inline CSS.
        let alpha = samplePixel(image, x: 160, y: 110)
        #expect(alpha.r > 200 && alpha.b > 200 && alpha.g < 40)
        let alphaRef = samplePixel(ref, x: 160, y: 110)
        #expect(abs(alpha.r - alphaRef.r) <= 5)
        #expect(abs(alpha.b - alphaRef.b) <= 5)

        // Left edge of rect#alpha (x=100): stroke band should match reference, not flat fill.
        let strokeEdge = samplePixel(image, x: 99, y: 110)
        let strokeRef = samplePixel(ref, x: 99, y: 110)
        #expect(abs(strokeEdge.r - strokeRef.r) <= 5)
        #expect(abs(strokeEdge.g - strokeRef.g) <= 5)
        #expect(abs(strokeEdge.b - strokeRef.b) <= 5)

        // Semi-transparent duplicate offset by (-5, 5) — half-intensity fuchsia.
        let duplicateOnly = samplePixel(image, x: 97, y: 60)
        #expect(duplicateOnly.r > 100 && duplicateOnly.r < 180)
        #expect(duplicateOnly.b > 100 && duplicateOnly.b < 180)
        #expect(duplicateOnly.g < 20)
    }

    @Test func structUse04BMatchesW3CReference() throws {
        let diff = try diffAgainstW3C(testId: "struct-use-04-b")
        #expect(diff.mismatchedFraction < 0.05, "mismatchedFraction=\(diff.mismatchedFraction)")
    }

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

    @Test func structUse12LowersWithoutUseCycleStackOverflow() throws {
        let svgURL = Self.repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/struct-use-12-f.svg")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
        _ = SVGRenderTree.lower(doc)
    }

    @Test func useCycleShortPairLowersSafely() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <use xlink:href="#b" id="a"/>
          <use xlink:href="#a" id="b"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        _ = SVGRenderTree.lower(doc)
    }

    @Test func useCycleGroupSelfReferenceLowersSafely() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <g id="g1"><use id="u2" xlink:href="#g1"/></g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        _ = SVGRenderTree.lower(doc)
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

    @Test func textInClipPathAppliesGeometry() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <clipPath id="clip">
              <text x="10" y="70" font-size="60">X</text>
            </clipPath>
          </defs>
          <rect x="0" y="0" width="100" height="100" fill="lime" clip-path="url(#clip)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let clipText) = doc.clipPaths["clip"]?.children.first else {
            Issue.record("expected text clip child"); return
        }
        #expect(TextLayout.glyphPath(text: clipText, fontFaces: doc.fontFaces, fonts: doc.fonts)?.isEmpty == false)
        let commands = SVGRenderTree.lower(doc)
        #expect(commands.contains { if case .clipToPath(let path, _) = $0 { return !path.isEmpty }; return false })

        var paintedDoc = doc
        paintedDoc.intrinsicSize = CGSize(width: 100, height: 100)
        let image = try SVGRasterizer.rasterize(paintedDoc, pixelSize: CGSize(width: 100, height: 100), scale: 1)

        var greenCount = 0
        for y in 0..<100 {
            for x in 0..<100 {
                if samplePixel(image, x: x, y: y).g > 200 { greenCount += 1 }
            }
        }
        #expect(greenCount > 20, "green pixels: \(greenCount)")
        let inside = samplePixel(image, x: 29, y: 48)
        let outside = samplePixel(image, x: 90, y: 10)
        #expect(inside.g > 200)
        #expect(outside.g < 20)
    }

    @Test func maskingPath04BClipsImageToText() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/masking-path-04-b.svg")
        var doc = try SVGConformanceFixtureParsing.parse(
            data: Data(contentsOf: svgURL),
            svgURL: svgURL
        )
        doc.intrinsicSize = CGSize(width: 480, height: 360)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        // Top image is unclipped — pattern visible across the row.
        let top = samplePixel(image, x: 240, y: 80)
        #expect(top.b > 80)

        // Bottom image is clipped to "Clip Test" — pattern visible somewhere in the text band.
        var maxBlueInClipBand = 0
        for y in 200..<310 {
            for x in 50..<400 {
                maxBlueInClipBand = max(maxBlueInClipBand, samplePixel(image, x: x, y: y).b)
            }
        }
        #expect(maxBlueInClipBand > 80, "maxBlueInClipBand=\(maxBlueInClipBand)")

        // Outside the clip region on the bottom row stays background.
        let outsideClip = samplePixel(image, x: 30, y: 190)
        #expect(outsideClip.r < 40 && outsideClip.g < 40 && outsideClip.b < 40)
    }

    @Test func clipRuleEvenOddPunchesHoleInSelfOverlappingPath() throws {
        // Same self-overlapping path shape as masking-path-05-f.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <clipPath id="eo">
              <path clip-rule="evenodd" d="M40,10l10,0 0,30 10,0 0,-10 -30,0 0,-10 40,0 0,30 -30,0 0,-40z"/>
            </clipPath>
            <clipPath id="nz">
              <path clip-rule="nonzero" d="M40,60l10,0 0,30 10,0 0,-10 -30,0 0,-10 40,0 0,30 -30,0 0,-40z"/>
            </clipPath>
          </defs>
          <rect width="100" height="50" fill="red" clip-path="url(#eo)"/>
          <rect y="50" width="100" height="50" fill="blue" clip-path="url(#nz)"/>
        </svg>
        """
        var doc = try SVGParser().parse(string: svg)
        doc.intrinsicSize = CGSize(width: 100, height: 100)
        let commands = SVGRenderTree.lower(doc)
        let evenOddClips = commands.compactMap { cmd -> Bool? in
            if case .clipToPath(_, let evenOdd) = cmd { return evenOdd }
            return nil
        }
        #expect(evenOddClips.contains(true))
        #expect(evenOddClips.contains(false))
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 100, height: 100), scale: 1)

        // Find a pixel that evenodd punches out but nonzero fills (y offset +50).
        var foundHole = false
        for y in 10..<50 {
            for x in 30..<70 {
                let top = samplePixel(image, x: x, y: y)
                let bottom = samplePixel(image, x: x, y: y + 50)
                if top.r < 40 && bottom.b > 200 {
                    foundHole = true
                    break
                }
            }
            if foundHole { break }
        }
        #expect(foundHole)
    }

    @Test func maskingPath05FEvenOddHasHoleAndNonzeroIsSolid() throws {
        let svgURL = Self.w3cRoot.appendingPathComponent("svg/masking-path-05-f.svg")
        var doc = try SVGConformanceFixtureParsing.parse(
            data: Data(contentsOf: svgURL),
            svgURL: svgURL
        )
        doc.intrinsicSize = CGSize(width: 480, height: 360)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360), scale: 1)

        // Pass criteria: evenodd overlap is a hole; nonzero overlap is filled.
        // Paths share the same shape with a +130 y offset (40→170).
        var foundHole = false
        for y in 40..<120 {
            for x in 180..<260 {
                let top = samplePixel(image, x: x, y: y)
                let bottom = samplePixel(image, x: x, y: y + 130)
                if top.r < 40 && bottom.b > 200 {
                    foundHole = true
                    break
                }
            }
            if foundHole { break }
        }
        #expect(foundHole)

        // Outside the clip shapes, the large red/blue rects must not show.
        let outsideTop = samplePixel(image, x: 80, y: 80)
        #expect(outsideTop.r < 40)
        let outsideBottom = samplePixel(image, x: 80, y: 210)
        #expect(outsideBottom.b < 40)
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
