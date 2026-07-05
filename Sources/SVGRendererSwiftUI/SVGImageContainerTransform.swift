import CoreGraphics
import SwiftUI

public enum SVGImageContainerTransform {
    public struct Result: Equatable {
        public var scaleX: CGFloat
        public var scaleY: CGFloat
        public var translationX: CGFloat
        public var translationY: CGFloat
        public var clipsToCanvas: Bool

        public var affineTransform: CGAffineTransform {
            CGAffineTransform(translationX: translationX, y: translationY)
                .scaledBy(x: scaleX, y: scaleY)
        }

        public func userSpacePoint(from canvasPoint: CGPoint) -> CGPoint {
            canvasPoint.applying(affineTransform.inverted())
        }
    }

    public static func compute(
        intrinsicSize: CGSize,
        canvasSize: CGSize,
        contentMode: SVGImageContentMode
    ) -> Result? {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let sx = canvasSize.width / intrinsicSize.width
        let sy = canvasSize.height / intrinsicSize.height

        switch contentMode {
        case .stretch:
            guard sx != 1 || sy != 1 else { return nil }
            return Result(
                scaleX: sx,
                scaleY: sy,
                translationX: 0,
                translationY: 0,
                clipsToCanvas: false
            )
        case .fit, .fill:
            let scale = contentMode == .fit ? min(sx, sy) : max(sx, sy)
            guard scale > 0 else { return nil }
            let renderedWidth = intrinsicSize.width * scale
            let renderedHeight = intrinsicSize.height * scale
            return Result(
                scaleX: scale,
                scaleY: scale,
                translationX: (canvasSize.width - renderedWidth) / 2,
                translationY: (canvasSize.height - renderedHeight) / 2,
                clipsToCanvas: contentMode == .fill
            )
        }
    }

    public static func apply(
        to context: inout GraphicsContext,
        intrinsicSize: CGSize,
        canvasSize: CGSize,
        contentMode: SVGImageContentMode
    ) {
        guard let transform = compute(
            intrinsicSize: intrinsicSize,
            canvasSize: canvasSize,
            contentMode: contentMode
        ) else { return }

        if transform.clipsToCanvas {
            context.clip(to: Path(CGRect(origin: .zero, size: canvasSize)))
        }
        context.translateBy(x: transform.translationX, y: transform.translationY)
        context.scaleBy(x: transform.scaleX, y: transform.scaleY)
    }
}

/// Shared layout sizing for SVG image views.
public struct SVGImageLayoutModifier: ViewModifier {
    public let intrinsicSize: CGSize?
    public let contentMode: SVGImageContentMode

    public init(intrinsicSize: CGSize?, contentMode: SVGImageContentMode) {
        self.intrinsicSize = intrinsicSize
        self.contentMode = contentMode
    }

    public func body(content: Content) -> some View {
        if contentMode == .stretch,
           let intrinsicSize,
           intrinsicSize.width > 0,
           intrinsicSize.height > 0 {
            content
                .frame(
                    idealWidth: intrinsicSize.width,
                    idealHeight: intrinsicSize.height
                )
        } else if let intrinsicSize,
                  intrinsicSize.width > 0,
                  intrinsicSize.height > 0 {
            content
                .aspectRatio(
                    intrinsicSize.width / intrinsicSize.height,
                    contentMode: contentMode.swiftUIContentMode
                )
                .frame(
                    idealWidth: intrinsicSize.width,
                    idealHeight: intrinsicSize.height
                )
        } else {
            content
        }
    }
}
