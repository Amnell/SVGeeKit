import SwiftUI
import SVGCore
import SVGRenderer

/// SwiftUI view that renders an `SVGDocument` into a `Canvas`.
/// One-line ingestion path for app code.
public struct SVGImageView: View {

    private let commands: [SVGRenderCommand]
    private let intrinsicSize: CGSize?

    public init(document: SVGDocument) {
        let sized = SVGImageView.applyingIntrinsicSize(document)
        self.commands = SVGRenderTree.lower(sized)
        self.intrinsicSize = sized.intrinsicSize
    }

    public var body: some View {
        Canvas { context, size in
            var ctx = context
            applyContainerTransform(into: &ctx, size: size)
            SwiftUICanvasRenderer().execute(commands, context: &ctx)
        }
        .frame(
            idealWidth: intrinsicSize?.width,
            idealHeight: intrinsicSize?.height
        )
    }

    /// When the rendered canvas size differs from the document intrinsic size
    /// (e.g. user-sized view), scale the entire command stream to fit.
    private func applyContainerTransform(into context: inout GraphicsContext, size: CGSize) {
        guard let intrinsic = intrinsicSize, intrinsic.width > 0, intrinsic.height > 0 else { return }
        guard size != intrinsic else { return }
        let sx = size.width / intrinsic.width
        let sy = size.height / intrinsic.height
        context.scaleBy(x: sx, y: sy)
    }

    /// Document used for lowering must carry an intrinsic size so the viewBox
    /// transform can be computed by the lowering pass.
    private static func applyingIntrinsicSize(_ document: SVGDocument) -> SVGDocument {
        if document.intrinsicSize != nil { return document }
        var copy = document
        copy.intrinsicSize = document.viewBox?.size
        return copy
    }
}
