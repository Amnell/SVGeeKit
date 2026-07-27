import Testing
import CoreGraphics
@testable import SVGCore

@Suite("SVGCore model")
struct SVGCoreTests {

    @Test func defaultDocumentIsEmpty() {
        let doc = SVGDocument()
        #expect(doc.root.children.isEmpty)
        #expect(doc.viewBox == nil)
    }

    @Test func rectStoresGeometryAndPaint() {
        let r = SVGRect(
            origin: CGPoint(x: 1, y: 2),
            size: CGSize(width: 10, height: 20),
            paint: SVGPaintProperties(fill: .color(.white))
        )
        #expect(r.origin == CGPoint(x: 1, y: 2))
        #expect(r.size == CGSize(width: 10, height: 20))
        if case .color(let c) = r.paint.fill {
            #expect(c == .white)
        } else {
            Issue.record("expected fill color")
        }
    }

    @Test func transformConcatenation() {
        let a = SVGTransform(CGAffineTransform(translationX: 10, y: 0))
        let b = SVGTransform(CGAffineTransform(scaleX: 2, y: 2))
        let c = a.concatenating(b)
        let p = CGPoint(x: 1, y: 1).applying(c.matrix)
        #expect(p == CGPoint(x: 22, y: 2))
    }

    @Test func systemLanguageMatchesPrimarySubtag() {
        #expect(
            SVGConditionalProcessing.evaluateSystemLanguage("en", preferredLanguages: ["en-US"])
        )
        #expect(
            SVGConditionalProcessing.evaluateSystemLanguage("en,fr", preferredLanguages: ["sv-SE"]) == false
        )
        #expect(
            SVGConditionalProcessing.evaluateSystemLanguage("he", preferredLanguages: ["iw-IL"])
        )
    }

    @Test func emptyConditionalAttributesEvaluateFalse() {
        let context = SVGConditionalProcessingContext(preferredLanguages: ["en-US"])
        #expect(
            SVGConditionalProcessing.evaluate(
                attributes: ["requiredFeatures": ""],
                context: context
            ) == false
        )
        #expect(
            SVGConditionalProcessing.evaluate(
                attributes: ["requiredExtensions": ""],
                context: context
            ) == false
        )
        #expect(
            SVGConditionalProcessing.evaluate(
                attributes: ["requiredFormats": "   "],
                context: context
            ) == false
        )
        #expect(
            SVGConditionalProcessing.evaluateSystemLanguage("", preferredLanguages: ["en-US"]) == false
        )
        #expect(
            SVGConditionalProcessing.evaluate(
                attributes: [:],
                context: context
            )
        )
    }

    @Test func viewBoxTransformMeetAlignsAndScalesUniformly() {
        let viewBox = CGRect(x: 0, y: 0, width: 30, height: 40)
        let viewport = CGSize(width: 50, height: 30)
        let par = SVGPreserveAspectRatio(align: .xMidYMid, meetOrSlice: .meet)
        let t = SVGPreserveAspectRatio.viewBoxTransform(
            viewBox: viewBox,
            viewportSize: viewport,
            preserveAspectRatio: par
        )
        #expect(CGPoint(x: 0, y: 0).applying(t) == CGPoint(x: 13.75, y: 0))
        #expect(CGPoint(x: 30, y: 40).applying(t) == CGPoint(x: 36.25, y: 30))
    }

    @Test func viewBoxTransformSliceCentersContent() {
        let viewBox = CGRect(x: 0, y: 0, width: 30, height: 40)
        let viewport = CGSize(width: 30, height: 60)
        let par = SVGPreserveAspectRatio(align: .xMidYMid, meetOrSlice: .slice)
        let t = SVGPreserveAspectRatio.viewBoxTransform(
            viewBox: viewBox,
            viewportSize: viewport,
            preserveAspectRatio: par
        )
        #expect(CGPoint(x: 15, y: 20).applying(t) == CGPoint(x: 15, y: 30))
    }

    @Test func viewBoxTransformNoneStretchesNonUniformly() {
        let viewBox = CGRect(x: 0, y: 0, width: 30, height: 40)
        let viewport = CGSize(width: 50, height: 30)
        let par = SVGPreserveAspectRatio(align: .none, meetOrSlice: .meet)
        let t = SVGPreserveAspectRatio.viewBoxTransform(
            viewBox: viewBox,
            viewportSize: viewport,
            preserveAspectRatio: par
        )
        #expect(CGPoint(x: 30, y: 40).applying(t) == CGPoint(x: 50, y: 30))
    }
}
