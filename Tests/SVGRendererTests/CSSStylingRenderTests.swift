import Testing
import Foundation
import SVGConformance

@Suite("CSS styling rendering")
@MainActor
struct CSSStylingRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    @Test func stylingCss01bMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-01-b", w3cResourcesRoot: Self.w3cRoot)
        // Label text uses SVGFreeSans in the W3C reference; system font substitution
        // can produce large per-channel deltas on glyphs while shape fills still match.
        #expect(diff.mismatchedFraction < 0.12)
    }
}
