import Testing
import Foundation
import SVGCore
import SVGRenderer
@testable import SVGRenderer

@Suite("SVG image data loading")
struct SVGImageDataLoaderTests {

    private static let redPixelPNG = """
    data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """

    private static let svgDataURI = """
    data:image/svg+xml;base64,PHN2Zy8+
    """

    @Test func dataURIDecodesBase64PNG() {
        let data = SVGImageDataLoader.dataFromDataURI(Self.redPixelPNG)
        #expect(data != nil)
        #expect(data?.isEmpty == false)
    }

    @Test func loadReturnsDataForDataURI() {
        let data = SVGImageDataLoader.load(href: Self.redPixelPNG, baseURL: nil)
        #expect(data != nil)
    }

    @Test func rejectsRelativeFileUnderRestrictedPolicy() {
        let data = SVGImageDataLoader.load(
            href: "pixel.png",
            policy: .restricted
        )
        #expect(data == nil)
    }

    @Test func rejectsSVGFileHrefWithoutReading() {
        let data = SVGImageDataLoader.load(
            href: "../images/rects.svg",
            baseURL: URL(fileURLWithPath: "/tmp/svg", isDirectory: true)
        )
        #expect(data == nil)
    }

    @Test func rejectsSVGDataURI() {
        #expect(SVGImageDataLoader.isRasterDataURI(Self.svgDataURI) == false)
        #expect(SVGImageDataLoader.load(href: Self.svgDataURI, baseURL: nil) == nil)
    }

    @Test func rejectsXMLPayload() {
        let xml = Data("<?xml version=\"1.0\"?><svg/>".utf8)
        #expect(SVGImageDataLoader.isRasterData(xml) == false)
    }

    @Test func acceptsRasterExtensions() {
        #expect(SVGImageDataLoader.isRasterFileHref("../images/smiley.png"))
        #expect(SVGImageDataLoader.isRasterFileHref("../images/struct-image-02.jpg"))
        #expect(SVGImageDataLoader.isRasterFileHref("photo.jpeg"))
        #expect(SVGImageDataLoader.isRasterFileHref("../images/rects.svg") == false)
    }
}
