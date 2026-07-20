import Foundation
import Testing
import SVGParser
import SVGCore

@Suite("SVGHrefResolver")
struct SVGHrefResolverTests {

  private let base = URL(fileURLWithPath: "/tmp/svg-fixtures", isDirectory: true)

  @Test func fragmentReference() {
    let resolution = SVGHrefResolver.classify(href: "#gradient", policy: .restricted)
    #expect(resolution == .fragment("gradient"))
  }

  @Test func urlFunctionalFragment() {
    let resolution = SVGHrefResolver.classify(href: "url(#clip)", policy: .restricted)
    #expect(resolution == .fragment("clip"))
  }

  @Test func dataURIAllowedInProduction() {
    let href = "data:image/png;base64,AAAA"
    let resolution = SVGHrefResolver.classify(href: href, policy: .restricted)
    #expect(resolution == .dataURI(href))
  }

  @Test func networkSchemeRejected() {
    let resolution = SVGHrefResolver.classify(
      href: "https://example.com/icon.svg",
      policy: .localFiles(baseURL: base)
    )
    #expect(resolution == .rejected(.networkScheme))
  }

  @Test func relativeFileRejectedInProduction() {
    let resolution = SVGHrefResolver.classify(
      href: "../resources/SVGFreeSans.svg#ascii",
      policy: .restricted
    )
    #expect(resolution == .rejected(.restrictedPolicy))
  }

  @Test func relativeFileAllowedWithLocalPolicy() throws {
    let resolution = SVGHrefResolver.classify(
      href: "fonts/SVGFreeSans.svg#ascii",
      policy: .localFiles(baseURL: base)
    )
    guard case .localFile(let url) = resolution else {
      Issue.record("expected localFile, got \(resolution)")
      return
    }
    #expect(url.path.hasSuffix("/tmp/svg-fixtures/fonts/SVGFreeSans.svg"))
    #expect(url.fragment == "ascii")
  }

  @Test func pathTraversalRejected() {
    let resolution = SVGHrefResolver.classify(
      href: "../../../etc/passwd",
      policy: .localFiles(baseURL: base)
    )
    #expect(resolution == .rejected(.pathTraversal))
  }

  @Test func emptyHrefRejected() {
    let resolution = SVGHrefResolver.classify(href: "   ", policy: .restricted)
    #expect(resolution == .rejected(.emptyReference))
  }

  @Test func productionParserWarnsOnExternalImageHref() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
      <image href="../secret.png" width="10" height="10"/>
    </svg>
    """
    let result = try SVGParser().parseWithReport(string: svg)
    #expect(!result.report.warnings.isEmpty)
    if case .rejectedExternalReference(let href, let reason, _) = result.report.warnings[0].kind {
      #expect(href == "../secret.png")
      #expect(reason == .restrictedPolicy)
    } else {
      Issue.record("expected rejectedExternalReference warning")
    }
  }

  @Test func localFilesParserAllowsCoLocatedRasterHref() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("svgeekit-href-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pngData = Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
    try pngData.write(to: dir.appendingPathComponent("pixel.png"))

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
      <image href="pixel.png" width="10" height="10"/>
    </svg>
    """
    let result = try SVGParser(options: .localFiles(at: dir)).parseWithReport(string: svg)
    #expect(result.report.warnings.isEmpty)
    guard case .image = result.document.root.children.first else {
      Issue.record("expected image element")
      return
    }
  }

  @Test func resolveXMLBasePreservesDirectoryTrailingSlash() {
    let doc = URL(fileURLWithPath: "/tmp/W3C/svg", isDirectory: true)
    let resolved = SVGHrefResolver.resolveXMLBase("../images/", relativeTo: doc)
    #expect(resolved?.path == "/tmp/W3C/images")
    #expect(resolved?.hasDirectoryPath == true)
  }

  @Test func resolveHrefAgainstXMLBaseRewritesRelativeToDocument() {
    let doc = URL(fileURLWithPath: "/tmp/W3C/svg", isDirectory: true)
    let images = URL(fileURLWithPath: "/tmp/W3C/images", isDirectory: true)
    let href = SVGHrefResolver.resolveHref(
      "smiley.png",
      documentBase: doc,
      effectiveBase: images
    )
    #expect(href == "../images/smiley.png")
  }

  @Test func parserResolvesImageHrefViaXMLBaseOnElement() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("svgeekit-xmlbase-\(UUID().uuidString)", isDirectory: true)
    let svgDir = root.appendingPathComponent("svg", isDirectory: true)
    let imagesDir = root.appendingPathComponent("images", isDirectory: true)
    try FileManager.default.createDirectory(at: svgDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let pngData = Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
    try pngData.write(to: imagesDir.appendingPathComponent("smiley.png"))

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="10" height="10">
      <image xml:base="../images/" xlink:href="smiley.png" width="10" height="10"/>
      <g xml:base="../images/">
        <image xlink:href="smiley.png" width="10" height="10"/>
      </g>
      <image xlink:href="../images/smiley.png" width="10" height="10"/>
    </svg>
    """
    let doc = try SVGParser(options: .localFiles(at: svgDir)).parse(string: svg)
    let hrefs: [String] = doc.root.children.compactMap { child in
      switch child {
      case .image(let image): return image.href
      case .group(let group):
        if case .image(let image) = group.children.first { return image.href }
        return nil
      default: return nil
      }
    }
    #expect(hrefs.count == 3)
    #expect(hrefs.allSatisfy { $0 == "../images/smiley.png" })
  }
}
