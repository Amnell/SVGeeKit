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
    let svgURL = Self.w3cRoot.appendingPathComponent("svg/\(testId).svg")
    let refURL = Self.w3cRoot.appendingPathComponent("png/\(testId).png")
    let data = try Data(contentsOf: svgURL)
    let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())
    let actual = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 480, height: 360))
    guard let ref = SVGSnapshotDiffer.loadPNG(refURL) else {
      throw PatternTestError.unableToLoadReference
    }
    return try SVGSnapshotDiffer.diff(
      actual, ref,
      tolerance: SVGSnapshotDiffer.Tolerance(perChannel: 4, pixelFraction: 0.05)
    )
  }

  enum PatternTestError: Error { case unableToLoadReference }

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
    #expect(diff.mismatchedFraction < 0.2)
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
    // diagonal; the OBB affine maps the same point to ~38% in gradient space.
    let p = Self.pixel(in: image, x: 200, y: 10)
    #expect(p.red > 140)
    #expect(p.blue < 110)
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
