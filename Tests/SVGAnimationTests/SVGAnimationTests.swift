import Testing
import CoreGraphics
import Foundation
import SVGCore
import SVGParser
import SVGRendererSwiftUI
import SVGAnimation
import SVGConformance

@Suite("SVGAnimation")
@MainActor
struct SVGAnimationTests {

    private func w3cURL(_ testId: String) throws -> URL {
        let bundleURL = Bundle.module.url(
            forResource: "W3C-SVG-1.1/svg/\(testId)",
            withExtension: "svg"
        )
        if let bundleURL { return bundleURL }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repo
            .appendingPathComponent("SVGConformanceTests/Resources/W3C-SVG-1.1/svg/\(testId).svg")
    }

    @Test func parsesAnimateChildrenOnRect() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <rect x="10" y="10" width="20" height="20">
            <animate attributeName="width" from="20" to="40" dur="2s"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let rect) = doc.root.children.first else {
            Issue.record("expected rect child")
            return
        }
        #expect(rect.animations.count == 1)
        guard case .animate(let animate) = rect.animations[0] else {
            Issue.record("expected animate")
            return
        }
        #expect(animate.attributeName == "width")
        #expect(animate.from == "20")
        #expect(animate.to == "40")
        #expect(animate.timing.dur == 2)
    }

    @Test func samplesRectWidthLinearly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <rect x="0" y="0" width="10" height="10">
            <animate attributeName="width" begin="0s" dur="10s" fill="freeze" from="10" to="20"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        let mid = SVGAnimationEngine.sample(document: doc, at: 5)
        guard case .rect(let rect) = mid.root.children.first else {
            Issue.record("expected rect")
            return
        }
        #expect(abs(rect.size.width - 15) < 0.01)
        let end = SVGAnimationEngine.sample(document: doc, at: 10)
        guard case .rect(let frozen) = end.root.children.first else {
            Issue.record("expected rect")
            return
        }
        #expect(abs(frozen.size.width - 20) < 0.01)
    }

    @Test func animateElem22bParsesFourAnimations() throws {
        let url = try w3cURL("animate-elem-22-b")
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        let animatedRect = doc.root.children
            .flatMap { element -> [SVGElement] in
                guard case .group(let group) = element else { return [element] }
                return group.children
            }
            .first { element in
                if case .rect(let rect) = element, rect.animations.count == 4 {
                    return true
                }
                return false
            }
        #expect(animatedRect != nil)
    }

    @Test func animateElem22bAtNineSeconds() throws {
        let testId = "animate-elem-22-b"
        let url = try w3cURL(testId)
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        let sampled = SVGAnimationEngine.sample(document: doc, at: 9)
        guard case .group(let body) = sampled.root.children.first(where: {
            if case .group(let group) = $0 { return group.id == "test-body-content" }
            return false
        }) else {
            Issue.record("expected test-body-content group")
            return
        }
        guard let animated = body.children.first(where: {
            if case .rect(let rect) = $0 { return rect.animations.count == 4 }
            return false
        }), case .rect(let rect) = animated else {
            Issue.record("expected animated rect")
            return
        }
        #expect(abs(rect.origin.x - 25) < 0.5)
        #expect(abs(rect.origin.y - 50) < 0.5)
        #expect(abs(rect.size.width - 400) < 0.5)
        #expect(abs(rect.size.height - 240) < 0.5)

        let image = try SVGRasterizer.rasterize(
            sampled,
            pixelSize: CGSize(width: 480, height: 360)
        )
        #expect(image.width == 480)
        #expect(image.height == 360)
    }

    @Test func detectsAnimationsInDocument() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect width="10" height="10">
            <animate attributeName="width" dur="3s"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(SVGAnimationEngine.containsAnimations(in: doc))
        #expect(SVGAnimationEngine.suggestedDuration(in: doc) == 3)
    }

    @Test func discreteRepeatCountAnimatesOverFullDuration() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <rect x="0" y="0" width="10" height="10">
            <animate attributeName="height" calcMode="discrete" begin="0s" dur="4s" repeatCount="2"
              fill="freeze" from="200" to="20"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(SVGAnimationEngine.suggestedDuration(in: doc) == 8)

        func rectHeight(at time: Double) throws -> CGFloat {
            let sampled = SVGAnimationEngine.sample(document: doc, at: time)
            guard case .rect(let rect) = sampled.root.children.first else {
                Issue.record("expected rect")
                return 0
            }
            return rect.size.height
        }

        #expect(try rectHeight(at: 0) == 200)
        #expect(try rectHeight(at: 1.9) == 200)
        #expect(try rectHeight(at: 2) == 20)
        #expect(try rectHeight(at: 3.9) == 20)
        #expect(try rectHeight(at: 4) == 200)
        #expect(try rectHeight(at: 6) == 20)
        #expect(try rectHeight(at: 8) == 20)
    }

    @Test func animateElem02tLeftmostRectHeights() throws {
        let url = try w3cURL("animate-elem-02-t")
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        #expect(SVGAnimationEngine.suggestedDuration(in: doc) == 8)

        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 0), animationID: "an5") == 200)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 2), animationID: "an5") == 20)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 4), animationID: "an5") == 200)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 6), animationID: "an5") == 20)
    }

    @Test func animateElem02tAdditiveSumRectHeights() throws {
        let url = try w3cURL("animate-elem-02-t")
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())

        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 0), animationID: "an6") == 220)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 2), animationID: "an6") == 40)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 4), animationID: "an6") == 220)
        #expect(try rectHeight(in: SVGAnimationEngine.sample(document: doc, at: 6), animationID: "an6") == 40)
    }

    private func rectHeight(in doc: SVGDocument, animationID: String) throws -> CGFloat {
        func walk(_ elements: [SVGElement]) -> CGFloat? {
            for element in elements {
                if case .rect(let rect) = element,
                   rect.animations.contains(where: { $0.id == animationID }) {
                    return rect.size.height
                }
                if case .group(let group) = element, let found = walk(group.children) {
                    return found
                }
            }
            return nil
        }
        guard let height = walk(doc.root.children) else {
            Issue.record("expected rect with animation \(animationID)")
            return 0
        }
        return height
    }

    @Test func animateElem03tInterpolatesFillAtMidpoint() throws {
        let url = try w3cURL("animate-elem-03-t")
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        let sampled = SVGAnimationEngine.sample(document: doc, at: 3)
        let top = try #require(try textElements(in: sampled).first { abs($0.origin.y - 80) < 0.5 })
        guard case .color(let color) = top.paint.fill else {
            Issue.record("expected color fill")
            return
        }
        // #00f → #070 at 50%: blue channel falls, green channel rises.
        #expect(color.red < 0.05)
        #expect(color.green > 0.15)
        #expect(color.green < 0.35)
        #expect(color.blue > 0.35)
        #expect(color.blue < 0.65)
    }

    @Test func interpolatesHexFillColors() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect width="10" height="10" fill="#00f">
            <animate attributeType="CSS" attributeName="fill" begin="0s" dur="10s"
              from="#00f" to="#070"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        let mid = SVGAnimationEngine.sample(document: doc, at: 5)
        guard case .rect(let rect) = mid.root.children.first,
              case .color(let color) = rect.paint.fill else {
            Issue.record("expected rect with color fill")
            return
        }
        #expect(color.red < 0.05)
        #expect(color.green > 0.15)
        #expect(color.blue > 0.35)
    }

    @Test func animateElem03tInheritedPresentationAtSixSeconds() throws {
        let url = try w3cURL("animate-elem-03-t")
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        #expect(SVGAnimationEngine.suggestedDuration(in: doc) == 6)

        let sampled = SVGAnimationEngine.sample(document: doc, at: 6)
        let texts = try textElements(in: sampled)
        #expect(texts.count == 3)

        let top = try #require(texts.first { abs($0.origin.y - 80) < 0.5 })
        let middle = try #require(texts.first { abs($0.origin.y - 155) < 0.5 })
        let bottom = try #require(texts.first { abs($0.origin.y - 250) < 0.5 })

        #expect(abs(top.font.size - 40) < 0.5)
        #expect(top.explicitPresentation.contains("font-size"))
        #expect(!top.explicitPresentation.contains("fill"))
        #expect(try isGreenFill(top.paint.fill))

        #expect(abs(middle.font.size - 60) < 0.5)
        #expect(middle.explicitPresentation.contains("font-size"))
        #expect(middle.explicitPresentation.contains("fill"))
        #expect(try isBlueFill(middle.paint.fill))

        #expect(abs(bottom.font.size - 80) < 0.5)
        #expect(!bottom.explicitPresentation.contains("font-size"))
        #expect(!bottom.explicitPresentation.contains("fill"))
        #expect(try isGreenFill(bottom.paint.fill))

        let image = try SVGRasterizer.rasterize(
            sampled,
            pixelSize: CGSize(width: 480, height: 360)
        )
        #expect(image.width == 480)
        #expect(image.height == 360)
    }

    private func textElements(in doc: SVGDocument) throws -> [SVGText] {
        var results: [SVGText] = []
        func walk(_ elements: [SVGElement]) {
            for element in elements {
                if case .text(let text) = element, text.id != "revision" {
                    results.append(text)
                }
                if case .group(let group) = element {
                    walk(group.children)
                }
            }
        }
        walk(doc.root.children)
        return results
    }

    private func isGreenFill(_ paint: SVGPaint) throws -> Bool {
        guard case .color(let color) = paint else {
            Issue.record("expected color fill")
            return false
        }
        #expect(color.red < 0.05)
        #expect(color.green > 0.4)
        #expect(color.blue < 0.05)
        return true
    }

    private func isBlueFill(_ paint: SVGPaint) throws -> Bool {
        guard case .color(let color) = paint else {
            Issue.record("expected color fill")
            return false
        }
        #expect(color.red < 0.05)
        #expect(color.green < 0.05)
        #expect(color.blue > 0.9)
        return true
    }

    @Test func staticDocumentHasNoAnimations() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect width="10" height="10"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(!SVGAnimationEngine.containsAnimations(in: doc))
    }
}
