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

    @Test func stylingCss02bMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-02-b", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.12)
    }

    @Test func stylingCss03bMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-03-b", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.12)
    }

    @Test func stylingCss04fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-04-f", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.12)
    }

    @Test func stylingPres03fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-pres-03-f", w3cResourcesRoot: Self.w3cRoot)
        // Draft watermark bar + revision text; main rect is green per passCriteria.
        #expect(diff.mismatchedFraction < 0.12)
    }

    @Test func stylingPres04fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-pres-04-f", w3cResourcesRoot: Self.w3cRoot)
        // Draft watermark + revision text; shape fills match passCriteria (no red).
        #expect(diff.mismatchedFraction < 0.25)
    }

    @Test func stylingCss08fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-08-f", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.05)
    }

    @Test func stylingCss09fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-09-f", w3cResourcesRoot: Self.w3cRoot)
        // W3C PNG is draft-bar only; parser verifies selector + @import behavior.
        #expect(diff.mismatchedFraction < 0.25)
    }

    @Test func stylingCss10fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-css-10-f", w3cResourcesRoot: Self.w3cRoot)
        // W3C PNG uses green circles; passCriteria expects orange from case-insensitive CSS.
        #expect(diff.mismatchedFraction < 0.25)
    }

    @Test func stylingPres05fMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-pres-05-f", w3cResourcesRoot: Self.w3cRoot)
        // Draft watermark + revision text; @import stylesheet paints shapes green.
        #expect(diff.mismatchedFraction < 0.25)
    }

    @Test func stylingElem01bMatchesW3CReference() throws {
        let diff = try W3CReferenceDiff.diff(testId: "styling-elem-01-b", w3cResourcesRoot: Self.w3cRoot)
        #expect(diff.mismatchedFraction < 0.12)
    }
}
