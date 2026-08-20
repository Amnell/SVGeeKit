#if canImport(AppKit) || canImport(UIKit)

import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SVGCore
import SVGParser
import SVGRendererSwiftUI

#if canImport(AppKit)
import AppKit
#endif

@Suite("SVG rendered image")
struct SVGRenderedImageTests {
    private static let greenRectSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">
      <rect width="20" height="10" fill="lime"/>
    </svg>
    """

    private static let noSizeSVG = """
    <svg xmlns="http://www.w3.org/2000/svg">
      <rect width="10" height="10" fill="lime"/>
    </svg>
    """

    @Test func rasterizesDataAtIntrinsicSize() throws {
        let rendered = try SVGRenderedImage(data: Data(Self.greenRectSVG.utf8))
        #expect(rendered.cgImage.width == 20)
        #expect(rendered.cgImage.height == 10)
        #expect(rendered.scale == 1)
        #expect(rendered.size == CGSize(width: 20, height: 10))

        let center = samplePixel(rendered.cgImage, x: 10, y: 5)
        #expect(center.g > 200)
    }

    @Test func rasterizesDataAtExplicitSizeAndScale() throws {
        let rendered = try SVGRenderedImage(
            data: Data(Self.greenRectSVG.utf8),
            size: CGSize(width: 40, height: 20),
            scale: 2
        )
        #expect(rendered.cgImage.width == 80)
        #expect(rendered.cgImage.height == 40)
        #expect(rendered.size == CGSize(width: 40, height: 20))
    }

    @Test func throwsWhenSizeIsUnknown() {
        #expect(throws: SVGRenderedImageError.missingSize) {
            _ = try SVGRenderedImage(data: Data(Self.noSizeSVG.utf8))
        }
    }

    @Test func rasterizesExplicitSizeWhenDocumentHasNone() throws {
        let rendered = try SVGRenderedImage(
            data: Data(Self.noSizeSVG.utf8),
            size: CGSize(width: 16, height: 16)
        )
        #expect(rendered.cgImage.width == 16)
        #expect(rendered.cgImage.height == 16)
    }

    @Test func loadsFromFileURL() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svgeekit-rendered-\(UUID().uuidString).svg")
        try Data(Self.greenRectSVG.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let rendered = try await SVGRenderedImage(url: fileURL, size: CGSize(width: 20, height: 10))
        #expect(rendered.cgImage.width == 20)
        #expect(rendered.cgImage.height == 10)
        let center = samplePixel(rendered.cgImage, x: 10, y: 5)
        #expect(center.g > 200)
    }

    @MainActor
    @Test func swiftUIImageWrapsBitmap() throws {
        let rendered = try SVGRenderedImage(data: Data(Self.greenRectSVG.utf8))
        _ = rendered.image
        _ = Image(rendered)
    }

    #if canImport(AppKit)
    @Test func nsImageMatchesPointSize() throws {
        let rendered = try SVGRenderedImage(data: Data(Self.greenRectSVG.utf8), cache: nil)
        #expect(rendered.nsImage.size == NSSize(width: 20, height: 10))
    }
    #endif

    @Test func cacheReusesRasterForSameContentAndSize() throws {
        let cache = SVGRenderedImageCache()
        let data = Data(Self.greenRectSVG.utf8)
        let first = try SVGRenderedImage(data: data, cache: cache)
        let second = try SVGRenderedImage(data: data, cache: cache)
        #expect(first.cgImage === second.cgImage)
    }

    @Test func cacheKeepsSeparateRastersPerSize() throws {
        let cache = SVGRenderedImageCache()
        let data = Data(Self.greenRectSVG.utf8)
        let small = try SVGRenderedImage(data: data, size: CGSize(width: 20, height: 10), cache: cache)
        let large = try SVGRenderedImage(data: data, size: CGSize(width: 40, height: 20), cache: cache)
        #expect(small.cgImage !== large.cgImage)
        #expect(small.cgImage.width == 20)
        #expect(large.cgImage.width == 40)
    }

    @Test func disabledCacheDoesNotReuseRasters() throws {
        let data = Data(Self.greenRectSVG.utf8)
        let first = try SVGRenderedImage(data: data, cache: nil)
        let second = try SVGRenderedImage(data: data, cache: nil)
        #expect(first.cgImage !== second.cgImage)
    }

    @Test func cacheMissAfterRemoveAll() throws {
        let cache = SVGRenderedImageCache()
        let data = Data(Self.greenRectSVG.utf8)
        let first = try SVGRenderedImage(data: data, cache: cache)
        cache.removeAll()
        let second = try SVGRenderedImage(data: data, cache: cache)
        #expect(first.cgImage !== second.cgImage)
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

#endif
