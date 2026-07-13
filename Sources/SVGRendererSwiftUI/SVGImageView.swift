import SwiftUI
import SVGCore
import SVGParser
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

    /// Parse and render SVG bytes. Never throws — on parse failure the canvas is empty.
    public init(
        svgData: Data,
        parser: SVGParser = SVGParser(),
        contentMode: SVGImageContentMode = .fit
    ) {
        switch Self.parsedView(svgData: svgData, parser: parser, contentMode: contentMode) {
        case .success(let view):
            self = view
        case .failure:
            self.init(commands: [], intrinsicSize: nil, contentMode: contentMode)
        }
    }

    /// Like `init(svgData:parser:contentMode:)` but records hard parse failures in `parseError`.
    public init(
        svgData: Data,
        parser: SVGParser = SVGParser(),
        contentMode: SVGImageContentMode = .fit,
        parseError: Binding<Error?>
    ) {
        switch Self.parsedView(svgData: svgData, parser: parser, contentMode: contentMode) {
        case .success(let view):
            parseError.wrappedValue = nil
            self = view
        case .failure(let error):
            parseError.wrappedValue = error
            self.init(commands: [], intrinsicSize: nil, contentMode: contentMode)
        }
    }

    private init(commands: [SVGRenderCommand], intrinsicSize: CGSize?, contentMode: SVGImageContentMode) {
        self.commands = commands
        self.intrinsicSize = intrinsicSize
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

    private static func parsedView(
        svgData: Data,
        parser: SVGParser,
        contentMode: SVGImageContentMode
    ) -> Result<SVGImageView, Error> {
        do {
            let document = try parser.parse(data: svgData)
            return .success(SVGImageView(document: document, contentMode: contentMode))
        } catch {
            return .failure(error)
        }
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
