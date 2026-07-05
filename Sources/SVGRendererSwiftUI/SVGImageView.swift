import SwiftUI
import SVGCore
import SVGRenderer

/// SwiftUI view that renders an `SVGDocument` into a `Canvas`.
/// One-line ingestion path for app code.
public struct SVGImageView: View {

    private let commands: [SVGRenderCommand]
    private let intrinsicSize: CGSize?
    private let contentMode: SVGImageContentMode

    public init(document: SVGDocument, contentMode: SVGImageContentMode = .fit) {
        let sized = SVGImageView.applyingIntrinsicSize(document)
        self.commands = SVGRenderTree.lower(sized)
        self.intrinsicSize = sized.intrinsicSize
        self.contentMode = contentMode
    }

    public var body: some View {
        canvas
            .modifier(SVGImageLayoutModifier(
                intrinsicSize: intrinsicSize,
                contentMode: contentMode
            ))
    }

    private var canvas: some View {
        Canvas { context, size in
            var ctx = context
            applyContainerTransform(into: &ctx, size: size)
            SwiftUICanvasRenderer().execute(commands, context: &ctx)
        }
    }

    /// Maps document coordinates into the canvas according to `contentMode`.
    private func applyContainerTransform(into context: inout GraphicsContext, size: CGSize) {
        guard let intrinsic = intrinsicSize else { return }
        SVGImageContainerTransform.apply(
            to: &context,
            intrinsicSize: intrinsic,
            canvasSize: size,
            contentMode: contentMode
        )
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
