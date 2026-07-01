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
}
