import Testing
import Foundation
import SVGConformance

@Suite("viewBox / preserveAspectRatio rendering")
@MainActor
struct ViewAttrRenderTests {

    private static let w3cRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1", isDirectory: true)
        .standardizedFileURL

    @Test func coordsViewattr01bMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "coords-viewattr-01-b", w3cResourcesRoot: Self.w3cRoot)
        // Label text uses SVGFreeSans in the W3C reference; system font substitution
        // can produce large per-channel deltas on glyphs while smiley viewports match.
        #expect(diff.mismatchedFraction < 0.12)
    }
}
