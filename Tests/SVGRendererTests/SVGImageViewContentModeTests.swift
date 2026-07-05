import CoreGraphics
import SwiftUI
import Testing
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite struct SVGImageViewContentModeTests {
    private static let wideGreenRectSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
      <rect width="200" height="100" fill="lime"/>
    </svg>
    """

    @MainActor
    @Test func fitLetterboxesNonMatchingFrame() throws {
        var document = try SVGParser().parse(string: Self.wideGreenRectSVG)
        document.intrinsicSize = CGSize(width: 200, height: 100)

        let image = try rasterize(
            document: document,
            contentMode: .fit,
            frameSize: CGSize(width: 100, height: 100)
        )

        let letterbox = samplePixel(image, x: 50, y: 5)
        #expect(letterbox.g < 50)

        let content = samplePixel(image, x: 50, y: 50)
        #expect(content.g > 200)
    }

    @MainActor
    @Test func fillCoversEntireFrame() throws {
        var document = try SVGParser().parse(string: Self.wideGreenRectSVG)
        document.intrinsicSize = CGSize(width: 200, height: 100)

        let image = try rasterize(
            document: document,
            contentMode: .fill,
            frameSize: CGSize(width: 100, height: 100)
        )

        let center = samplePixel(image, x: 50, y: 50)
        #expect(center.g > 200)

        let edge = samplePixel(image, x: 5, y: 95)
        #expect(edge.g > 200)
    }

    @MainActor
    @Test func stretchDistortsToFillFrame() throws {
        var document = try SVGParser().parse(string: Self.wideGreenRectSVG)
        document.intrinsicSize = CGSize(width: 200, height: 100)

        let fitImage = try rasterize(
            document: document,
            contentMode: .fit,
            frameSize: CGSize(width: 100, height: 100)
        )
        let stretchImage = try rasterize(
            document: document,
            contentMode: .stretch,
            frameSize: CGSize(width: 100, height: 100)
        )

        let fitLetterbox = samplePixel(fitImage, x: 50, y: 5)
        let stretchLetterbox = samplePixel(stretchImage, x: 50, y: 5)
        #expect(fitLetterbox.g < 50)
        #expect(stretchLetterbox.g > 200)
    }

    @MainActor
    @Test func fitMatchesIntrinsicFrameWithoutLetterboxing() throws {
        var document = try SVGParser().parse(string: Self.wideGreenRectSVG)
        document.intrinsicSize = CGSize(width: 200, height: 100)

        let image = try rasterize(
            document: document,
            contentMode: .fit,
            frameSize: CGSize(width: 200, height: 100)
        )

        let corner = samplePixel(image, x: 5, y: 5)
        let center = samplePixel(image, x: 100, y: 50)
        #expect(corner.g > 200)
        #expect(center.g > 200)
    }

    @MainActor
    private func rasterize(
        document: SVGDocument,
        contentMode: SVGImageContentMode,
        frameSize: CGSize
    ) throws -> CGImage {
        let view = SVGImageView(document: document, contentMode: contentMode)
            .frame(width: frameSize.width, height: frameSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(frameSize)
        guard let image = renderer.cgImage else {
            throw RasterizeError.noImage
        }
        return image
    }

    private enum RasterizeError: Error {
        case noImage
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
