import CoreGraphics

/// SVG `preserveAspectRatio` attribute (SVG 1.1 §7.8).
public struct SVGPreserveAspectRatio: Equatable, Sendable {
    public enum Align: Equatable, Sendable {
        case none
        case xMinYMin, xMinYMid, xMinYMax
        case xMidYMin, xMidYMid, xMidYMax
        case xMaxYMin, xMaxYMid, xMaxYMax
    }

    public enum MeetOrSlice: Equatable, Sendable {
        case meet
        case slice
    }

    public var align: Align
    public var meetOrSlice: MeetOrSlice

    public static let `default` = SVGPreserveAspectRatio(align: .xMidYMid, meetOrSlice: .meet)

    public init(align: Align, meetOrSlice: MeetOrSlice = .meet) {
        self.align = align
        self.meetOrSlice = meetOrSlice
    }

    /// Maps a `viewBox` rectangle into a viewport of `viewportSize`.
    public static func viewBoxTransform(
        viewBox: CGRect,
        viewportSize: CGSize,
        preserveAspectRatio: SVGPreserveAspectRatio
    ) -> CGAffineTransform {
        let vw = viewportSize.width
        let vh = viewportSize.height
        let vbw = viewBox.width
        let vbh = viewBox.height

        let sx: CGFloat
        let sy: CGFloat
        let tx: CGFloat
        let ty: CGFloat

        if preserveAspectRatio.align == .none {
            sx = vw / vbw
            sy = vh / vbh
            tx = 0
            ty = 0
        } else {
            let scaleX = vw / vbw
            let scaleY = vh / vbh
            let scale = preserveAspectRatio.meetOrSlice == .meet
                ? min(scaleX, scaleY)
                : max(scaleX, scaleY)
            sx = scale
            sy = scale
            let newW = vbw * scale
            let newH = vbh * scale
            tx = xOffset(preserveAspectRatio.align, viewport: vw, content: newW)
            ty = yOffset(preserveAspectRatio.align, viewport: vh, content: newH)
        }

        return CGAffineTransform(translationX: tx, y: ty)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
    }

    private static func xOffset(_ align: Align, viewport: CGFloat, content: CGFloat) -> CGFloat {
        switch align {
        case .xMinYMin, .xMinYMid, .xMinYMax: return 0
        case .xMidYMin, .xMidYMid, .xMidYMax: return (viewport - content) / 2
        case .xMaxYMin, .xMaxYMid, .xMaxYMax: return viewport - content
        case .none: return 0
        }
    }

    private static func yOffset(_ align: Align, viewport: CGFloat, content: CGFloat) -> CGFloat {
        switch align {
        case .xMinYMin, .xMidYMin, .xMaxYMin: return 0
        case .xMinYMid, .xMidYMid, .xMaxYMid: return (viewport - content) / 2
        case .xMinYMax, .xMidYMax, .xMaxYMax: return viewport - content
        case .none: return 0
        }
    }
}
