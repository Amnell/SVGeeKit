import Testing
import CoreGraphics
import Foundation
import SVGCore
import SVGParser
import SVGRenderer
import SVGRendererSwiftUI
import SVGConformance
import SVGScript

@Suite("SVGScript")
@MainActor
struct SVGScriptTests {

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

  @Test func parsesScriptHandle01Metadata() throws {
    let url = try w3cURL("script-handle-01-b")
    let data = try Data(contentsOf: url)
    let doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: url)
    #expect(doc.scriptMetadata.blocks.count == 1)
    #expect(doc.scriptMetadata.blocks[0].source.contains("onMouseClick"))
    #expect(doc.scriptMetadata.handlersByElementID["target"]?.contains(where: { $0.event == "click" }) == true)
    #expect(doc.scriptMetadata.elementIndex["target"] != nil)
    #expect(doc.scriptMetadata.elementIndex["testPassed"] != nil)
  }

  @Test func scriptHandle01bAfterClick() throws {
    let url = try w3cURL("script-handle-01-b")
    let data = try Data(contentsOf: url)
    let scriptDoc = try SVGScriptDocument(data: data, baseURL: url.deletingLastPathComponent())
    scriptDoc.dispatchLoad()
    scriptDoc.dispatchClick(at: CGPoint(x: 70, y: 170))

    let doc = scriptDoc.document
    let targetPath = doc.scriptMetadata.elementIndex["target"]!
    let passedPath = doc.scriptMetadata.elementIndex["testPassed"]!

    guard case .group(let target) = doc.element(at: targetPath) else {
      Issue.record("expected target group"); return
    }
    guard case .group(let passed) = doc.element(at: passedPath) else {
      Issue.record("expected testPassed group"); return
    }
    #expect(target.visibility == .hidden)
    #expect(passed.visibility == .visible)
    if case .text(let passedText) = passed.children.first {
      #expect(passedText.paint.visibility == .visible)
      #expect(passedText.string.contains("Scripting Test Passed"))
    } else {
      Issue.record("expected passed text child")
    }

    let image = try SVGRasterizer.rasterize(
      scriptDoc.document,
      pixelSize: CGSize(width: 480, height: 360)
    )
    #expect(image.width == 480)
    #expect(image.height == 360)
  }

  @Test func scriptSpecify01fDoesNotRunBogusOnload() throws {
    let url = try w3cURL("script-specify-01-f")
    let data = try Data(contentsOf: url)
    let scriptDoc = try SVGScriptDocument(data: data, baseURL: url.deletingLastPathComponent())
    scriptDoc.dispatchLoad()

    let doc = scriptDoc.document
    let passedPath = doc.scriptMetadata.elementIndex["testPassed"]!
    let failedPath = doc.scriptMetadata.elementIndex["testFailed"]!
    guard case .text(let passed) = doc.element(at: passedPath) else {
      Issue.record("expected passed text"); return
    }
    guard case .text(let failed) = doc.element(at: failedPath) else {
      Issue.record("expected failed text"); return
    }
    #expect(passed.paint.visibility == SVGVisibility.visible)
    #expect(failed.paint.visibility == SVGVisibility.hidden)
  }

  @Test func scriptHandle01bHitTestIgnoresTransparentFrame() throws {
    let url = try w3cURL("script-handle-01-b")
    let data = try Data(contentsOf: url)
    let doc = try SVGConformanceFixtureParsing.parse(data: data, svgURL: url)
    let hit = SVGHitTester.hitTest(document: doc, at: CGPoint(x: 70, y: 170))
    #expect(hit != nil)
    let match = SVGHitTester.handlerOwnerPath(hitPath: hit!.path, document: doc, event: "click")
    #expect(match?.handler.script.contains("onMouseClick") == true)
  }

  @Test func hiddenGroupProducesNoRenderCommands() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
      <g id="hidden" visibility="hidden">
        <rect x="0" y="0" width="10" height="10" fill="red"/>
      </g>
    </svg>
    """
    let doc = try SVGParser().parse(string: svg)
    let commands = SVGRenderTree.lower(doc)
    let hasFill = commands.contains { command in
      if case .fillPath = command { return true }
      return false
    }
    #expect(!hasFill)
  }
}
