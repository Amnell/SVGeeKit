import Testing
import Foundation
import SVGRenderer
@testable import SVGRenderer

@Suite("SVG image data loading")
struct SVGImageDataLoaderTests {

    private static let redPixelPNG = """
    data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
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
}
