import Testing
import Foundation
import CoreGraphics
import SVGParser
import SVGRenderer
import SVGRendererSwiftUI
import SVGConformance

@Suite("Pattern rendering")
@MainActor
struct PatternRenderTests {

  private static let w3cRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
    .standardizedFileURL

  private func diffAgainstW3C(testId: String) throws -> SVGSnapshotDiffer.DiffResult {
    try W3CReferenceDiff.diff(testId: testId, w3cResourcesRoot: Self.w3cRoot)
  }

  @Test func rendersPatternFillRect() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
      <pattern id="p" patternUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">
        <rect x="0" y="0" width="10" height="10" fill="red"/>
        <rect x="10" y="10" width="10" height="10" fill="blue"/>
      </pattern>
      <rect width="100" height="100" fill="url(#p)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 100, height: 100))
    #expect(image.width == 100)
    #expect(image.height == 100)
  }

  @Test func patternFallbackOnInvalidSize() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="50" height="50">
      <pattern id="bad">
        <rect width="10" height="10" fill="red"/>
      </pattern>
      <rect width="50" height="50" fill="url(#bad) lime"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    guard case .rect(let r) = doc.root.children.first else {
      Issue.record("expected rect"); return
    }
    if case .paintServer(let id, let fallback) = r.paint.fill {
      #expect(id == "bad")
      #expect(fallback?.green == 1)
    } else {
      Issue.record("expected paintServer with fallback")
    }
  }

  @Test func w3cPattern01BMatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-01-b")
    // Remaining delta is mostly Arial vs SVGFreeSans label text and antialiasing.
    #expect(diff.mismatchedFraction < 0.12)
  }

  @Test func w3cPattern06MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-06-f")
    // Test file includes an uncommented DRAFT watermark not in the W3C PNG.
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cPattern03MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-03-f")
    #expect(diff.mismatchedFraction < 0.08)
  }

  @Test func w3cPattern05MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-05-f")
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cPattern04MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-04-f")
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cPattern07MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-07-f")
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cPattern08MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-08-f")
    // DRAFT watermark at top; body is four lime circles over red reference pattern.
    #expect(diff.mismatchedFraction < 0.05)
  }

  /// A zero-size pattern with a `viewBox` paints nothing; ICC fallback is
  /// not applied (pservers-pattern-09-f `pattern3`).
  @Test func zeroSizePatternWithViewBoxDoesNotUseFallback() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">
      <pattern id="p" patternUnits="userSpaceOnUse" width="0" height="0" viewBox="0 0 10 10">
        <circle cx="5" cy="5" r="4" fill="red"/>
      </pattern>
      <rect x="0" y="0" width="20" height="20" fill="url(#p) lime"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 20, height: 20))
    let center = Self.pixel(in: image, x: 10, y: 10)
    #expect(center.red < 80)
    #expect(center.green < 80)
  }

  /// Zero-size patterns without a `viewBox` use ICC fallback
  /// (pservers-pattern-03-f, pservers-pattern-09-f `pattern2`).
  @Test func zeroSizePatternWithoutViewBoxUsesFallback() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">
      <pattern id="p" patternUnits="userSpaceOnUse" width="0" height="0">
        <circle cx="10" cy="10" r="4" fill="red"/>
      </pattern>
      <rect x="0" y="0" width="20" height="20" fill="url(#p) lime"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 20, height: 20))
    let center = Self.pixel(in: image, x: 10, y: 10)
    #expect(center.green > 200)
    #expect(center.red < 80)
  }

  /// Invalid `xlink:href` with default zero dimensions also uses fallback when
  /// there is no `viewBox` (pservers-pattern-09-f `pattern2`).
  @Test func invalidHrefZeroSizePatternUsesFallback() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20">
      <pattern id="p" xlink:href="#invalidlink">
        <circle cx="10" cy="10" r="4" fill="red"/>
      </pattern>
      <rect x="0" y="0" width="20" height="20" fill="url(#p) lime"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 20, height: 20))
    let center = Self.pixel(in: image, x: 10, y: 10)
    #expect(center.green > 200)
    #expect(center.red < 80)
  }

  @Test func w3cPattern09MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-pattern-09-f")
    // DRAFT watermark; left rect is lime fallback, right rect is unfilled.
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cGrad03PatternHrefMatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-03-b")
    // Label text uses SVGFreeSans vs reference font; pattern tiles must match.
    #expect(diff.mismatchedFraction < 0.12)
  }

  @Test func w3cGrad04MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-04-b")
    // Two 30px labels + a revision line render in SVGFreeSans vs. the reference
    // font, so the text drives most of the mismatch. Gradient geometry is
    // asserted precisely in objectBoundingBoxDiagonalLinearGradientSkewsStopLines;
    // this is only a coarse regression guard on the overall render.
    #expect(diff.mismatchedFraction < 0.4)
  }

  @Test func w3cGrad05MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-05-b")
    // Large "Background" labels dominate the W3C diff; stop-opacity bands are
    // covered by gradientStopOpacity* tests.
    #expect(diff.mismatchedFraction < 0.45)
  }

  @Test func w3cGrad10MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-10-b")
    #expect(diff.mismatchedFraction < 0.08)
  }

  @Test func w3cGrad14MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-14-b")
    #expect(diff.mismatchedFraction < 0.2)
  }

  @Test func w3cGrad16MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-16-b")
    // Revision line at bottom uses SVGFreeSans vs reference font.
    #expect(diff.mismatchedFraction < 0.07)
  }

  @Test func w3cGrad18MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-18-b")
    #expect(diff.mismatchedFraction < 0.05)
  }

  @Test func w3cGrad21MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-21-b")
    // "Reference" label and revision line differ in font from W3C PNG.
    #expect(diff.mismatchedFraction < 0.09)
  }

  @Test func w3cGrad13MatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "pservers-grad-13-b")
    // Radial focal tiles + inherited 0.5px stroke outlines on each rect (~28% W3C diff).
    #expect(diff.mismatchedFraction < 0.29)
  }

  @Test func grad13FirstTileCenterMatchesBlueDominant() throws {
    let svgURL = Self.w3cRoot.appendingPathComponent("svg/pservers-grad-13-b.svg")
    let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))
    let p = Self.pixel(in: image, x: 67, y: 60)
    #expect(p.blue > p.red, "first focal tile should read blue, not stripe yellow")
    #expect(p.blue > 60)
  }

  /// Yellow base rect must stay under stripes; only the no-fill overlay gets the gradient.
  @Test func grad13TilesShowYellowBehindStripes() throws {
    let svgURL = Self.w3cRoot.appendingPathComponent("svg/pservers-grad-13-b.svg")
    let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))
    // Bottom-right of first tile: gradient is transparent; yellow base should dominate.
    let p = Self.pixel(in: image, x: 105, y: 98)
    #expect(p.red > 200, "expected yellow background behind stripes, got \(p)")
    #expect(p.green > 200)
    #expect(p.blue < 80)
  }

  /// group1 stroke="black" stroke-width="0.5" must outline each instanced tile rect.
  @Test func grad13TilesHaveInheritedStrokeOutlines() throws {
    let svgURL = Self.w3cRoot.appendingPathComponent("svg/pservers-grad-13-b.svg")
    let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))
    // Bottom edge of first tile row (y=105): black stroke between stripe rects.
    let p = Self.pixel(in: image, x: 67, y: 105)
    #expect(p.red < 40 && p.green < 40 && p.blue < 40, "expected inherited black stroke, got \(p)")
  }

  @Test func w3cCoordsUnits01BMatchesReference() throws {
    let diff = try diffAgainstW3C(testId: "coords-units-01-b")
    // Label text may differ (Arial vs SVGFreeSans); gradient/pattern tiles must match.
    #expect(diff.mismatchedFraction < 0.12)
  }

  @Test func coordsUnits01BPatternFillsShowFuchsiaAtCenter() throws {
    let w3cRoot = Self.w3cRoot
    let svgURL = w3cRoot.appendingPathComponent("svg/coords-units-01-b.svg")
    let data = try Data(contentsOf: svgURL)
    let doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: svgURL)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))

    // Bottom row: percentage (≈30–80), fraction (≈180–230), user space (≈330–380).
    // Each should show a 2×2 grid of fuchsia quarter-circles in the upper half of the rect.
    for (name, xRange) in [("pct", 30..<80), ("frac", 180..<230), ("user", 330..<380)] {
      var found = false
      for y in 248..<272 {
        for x in xRange {
          let p = Self.pixel(in: image, x: x, y: y)
          if p.red > 150 && p.blue > 100 { found = true; break }
        }
        if found { break }
      }
      #expect(found, "expected fuchsia pattern in \(name) band")
    }
  }

  /// pservers-grad-10-b reflect row: blue-lime-blue-lime across the bar.
  @Test func linearGradientReflectSpreadTiles() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="460" height="55" viewBox="0 0 460 55">
      <linearGradient id="g" gradientUnits="objectBoundingBox" x1=".4" y1="0" x2=".6" y2="0" spreadMethod="reflect">
        <stop stop-color="blue" offset="0"/>
        <stop stop-color="lime" offset="1"/>
      </linearGradient>
      <rect width="460" height="55" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 460, height: 55))
    let left = Self.pixel(in: image, x: 20, y: 27)
    let mid = Self.pixel(in: image, x: 230, y: 27)
    let right = Self.pixel(in: image, x: 440, y: 27)
    #expect(left.blue > left.green)
    #expect(mid.green > mid.blue)
    #expect(right.green > right.blue)
  }

  /// pservers-grad-10-b repeat row: abrupt blue discontinuities between tiles.
  @Test func linearGradientRepeatSpreadTiles() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="460" height="55" viewBox="0 0 460 55">
      <linearGradient id="g" gradientUnits="objectBoundingBox" x1=".4" y1="0" x2=".6" y2="0" spreadMethod="repeat">
        <stop stop-color="blue" offset="0"/>
        <stop stop-color="lime" offset="1"/>
      </linearGradient>
      <rect width="460" height="55" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 460, height: 55))
    // Tile boundary near 20%: blue end meets blue start.
    let boundary = Self.pixel(in: image, x: Int(460 * 0.2), y: 27)
    #expect(boundary.blue > 200)
    #expect(boundary.green < 80)
    let mid = Self.pixel(in: image, x: 230, y: 27)
    #expect(mid.green > 50)
    #expect(mid.blue > 50)
  }

  @Test func userSpaceLinearRepeatSpread() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="225" height="40" viewBox="0 0 225 40">
      <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="50" y1="0" x2="100" y2="0" spreadMethod="repeat">
        <stop offset="0" stop-color="black"/>
        <stop offset="1" stop-color="gold"/>
      </linearGradient>
      <rect width="225" height="40" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 225, height: 40))
    let mid = Self.pixel(in: image, x: 112, y: 20)
    #expect(mid.red > 40)
    #expect(mid.green > 30)
  }

  @Test func grad10RepeatRowShowsTiledGradient() throws {
    let svgURL = Self.w3cRoot.appendingPathComponent("svg/pservers-grad-10-b.svg")
    let doc = try SVGConformanceFixtureParsing.parse(data: Data(contentsOf: svgURL), svgURL: svgURL)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))
    let mid = Self.pixel(in: image, x: 230, y: 232)
    #expect(mid.green > 50)
    #expect(mid.blue > 50)
  }

  /// pservers-grad-05-b: blue at offset 0.2 with stop-opacity 0 reveals the aqua fill behind.
  @Test func gradientStopOpacityZeroBandShowsBackground() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="480" height="100" viewBox="0 0 480 100">
      <rect width="480" height="100" fill="aqua"/>
      <linearGradient id="Grad1" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="rgb(238,130,238)" stop-opacity="1" offset="0"/>
        <stop stop-color="blue" stop-opacity="0" offset="0.2"/>
        <stop stop-color="lime" stop-opacity="0.5" offset="0.4"/>
        <stop stop-color="yellow" stop-opacity="0.2" offset="0.6"/>
        <stop stop-color="rgb(255,165,0)" stop-opacity="0.8" offset="0.8"/>
        <stop stop-color="black" stop-opacity="1" offset="1"/>
      </linearGradient>
      <rect x="20" y="20" width="440" height="80" fill="url(#Grad1)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 100))
    // On the u+v ≈ 0.4 iso-line (offset 0.2 along the diagonal), blue is fully transparent.
    let p = Self.pixel(in: image, x: 108, y: 36)
    #expect(p.green > 200)
    #expect(p.blue > 200)
    #expect(p.red < 120)
  }

  /// stop-color and stop-opacity interpolate independently: between violet and
  /// transparent blue the ramp stays blue-violet, not gray (pservers-grad-05-b).
  @Test func gradientStopOpacityInterpolatesColorAndAlphaIndependently() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="480" height="100" viewBox="0 0 480 100">
      <rect width="480" height="100" fill="aqua"/>
      <linearGradient id="Grad1" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="rgb(238,130,238)" stop-opacity="1" offset="0"/>
        <stop stop-color="blue" stop-opacity="0" offset="0.2"/>
        <stop stop-color="lime" stop-opacity="0.5" offset="0.4"/>
        <stop stop-color="yellow" stop-opacity="0.2" offset="0.6"/>
        <stop stop-color="rgb(255,165,0)" stop-opacity="0.8" offset="0.8"/>
        <stop stop-color="black" stop-opacity="1" offset="1"/>
      </linearGradient>
      <rect x="20" y="20" width="440" height="80" fill="url(#Grad1)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 100))
    // Midway between violet (offset 0) and transparent blue (offset 0.2) on the diagonal.
    let p = Self.pixel(in: image, x: 64, y: 28)
    #expect(p.blue > p.red + 40, "blue stop-color must participate when stop-opacity is 0")
    #expect(p.blue > 200)
  }

  /// Semi-transparent stops must not double-darken (straight alpha, not premul RGB).
  @Test func semiTransparentGradientStopPreservesBrightness() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
      <rect width="100" height="100" fill="black"/>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="0" gradientUnits="objectBoundingBox">
        <stop offset="0" stop-color="lime" stop-opacity="1"/>
        <stop offset="1" stop-color="lime" stop-opacity="0.5"/>
      </linearGradient>
      <rect width="100" height="100" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 100, height: 100))
    let p = Self.pixel(in: image, x: 75, y: 50)
    #expect(p.green > 140)
    #expect(p.green > p.red + 40)
  }

  /// A stop with stop-opacity="0" is fully transparent at the gradient endpoint.
  @Test func gradientStopOpacityShowsBackground() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
      <rect width="100" height="100" fill="aqua"/>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="0" gradientUnits="objectBoundingBox">
        <stop offset="0" stop-color="red" stop-opacity="1"/>
        <stop offset="1" stop-color="blue" stop-opacity="0"/>
      </linearGradient>
      <rect width="100" height="100" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 100, height: 100))
    let left = Self.pixel(in: image, x: 5, y: 50)
    let right = Self.pixel(in: image, x: 95, y: 50)
    #expect(left.red > 200)
    #expect(left.green < 80)
    #expect(right.green > 200)
    #expect(right.blue > 200)
    #expect(right.red < 80)
  }

  /// objectBoundingBox diagonal linear gradients map stop lines through the
  /// bounding-box affine transform (not just remapped endpoints).
  @Test func objectBoundingBoxDiagonalLinearGradientSkewsStopLines() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="400" height="40" viewBox="0 0 400 40">
      <linearGradient id="g" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="red"/>
        <stop offset="1" stop-color="blue"/>
      </linearGradient>
      <rect width="400" height="40" fill="url(#g)"/>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let commands = SVGRenderTree.lower(doc)
    guard let fill = commands.first(where: {
      if case .fillPath = $0 { return true }
      return false
    }), case .fillPath(_, let paint, _, _) = fill,
      case .linearGradient(let g) = paint else {
      Issue.record("expected fillPath with linearGradient"); return
    }
    #expect(g.transform.matrix.a == 400)
    #expect(g.transform.matrix.d == 40)
    #expect(g.x1 == 0 && g.y1 == 0 && g.x2 == 1 && g.y2 == 1)

    let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 400, height: 40))
    // Endpoint baking would project (200,10) to ~52% along the user-space
    // diagonal; the OBB affine maps the same point to ~37.5% in sRGB space.
    let p = Self.pixel(in: image, x: 200, y: 10)
    #expect(p.red > p.blue)
    #expect(p.red > 140)
    #expect(p.blue > 80 && p.blue < 110)
  }

  private static func pixel(in image: CGImage, x: Int, y: Int)
    -> (red: Int, green: Int, blue: Int, alpha: Int) {
    var data = [UInt8](repeating: 0, count: 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
                   | CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = data.withUnsafeMutableBytes { buffer -> CGContext? in
      guard let base = buffer.baseAddress else { return nil }
      return CGContext(
        data: base, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo
      )
    }
    ctx?.translateBy(x: CGFloat(-x), y: CGFloat(-(image.height - 1 - y)))
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
  }
}
