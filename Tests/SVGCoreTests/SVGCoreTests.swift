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
}
