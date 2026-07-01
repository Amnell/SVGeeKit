import Testing
import CoreGraphics
import SVGParser
import SVGRendererSwiftUI

/// Regression: clip-path on a transformed `<g>` must be evaluated after the
/// group's transform is applied (SVG 1.1 §14.7.3). Batik-style gauge arcs
/// combine a scaled group with nested clip paths.
@Suite struct GroupClipTransformTests {
    @Test func clippedGradientArcRendersWithGroupTransform() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="60">
          <defs>
            <clipPath id="outer">
              <rect x="10" y="30" width="50" height="20"/>
            </clipPath>
            <clipPath id="arc">
              <path d="M 55 48 C 55 36 15 36 15 48 C 12 48 10 48 8 48 C 8 30 57 30 57 48 C 54 48 52 48 55 48 Z"/>
            </clipPath>
            <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1" y2="0"
              gradientTransform="matrix(50,0,0,50,8,40)">
              <stop offset="0" stop-color="lime"/>
              <stop offset="1" stop-color="red"/>
            </linearGradient>
          </defs>
          <rect width="80" height="60" fill="white"/>
          <g clip-path="url(#outer)" transform="matrix(1,0,0,0.8,0,5)">
            <g clip-path="url(#arc)">
              <path d="M 8 30 v 18 h 50 v -18 z" fill="url(#g)"/>
            </g>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        let image = try SVGRasterizer.rasterize(doc, pixelSize: CGSize(width: 80, height: 60), scale: 1)

        var greenOrRed = 0
        for y in 22...42 {
            for x in 12...55 {
                if sample(image, x: x, y: y).g > 150 || sample(image, x: x, y: y).r > 150 {
                    greenOrRed += 1
                }
            }
        }
        #expect(greenOrRed > 40)
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
