import SwiftUI
import SVGCore
import SVGParser
import SVGRenderer

/// SwiftUI view that renders an `SVGDocument` into a `Canvas`.
/// One-line ingestion path for app code.
public struct SVGImageView: View {

    private let contents: Contents
    private let contentMode: SVGImageContentMode

    public init(document: SVGDocument, contentMode: SVGImageContentMode = .fit) {
        let sized = SVGImageView.applyingIntrinsicSize(document)
        self.contents = .rendered(
            commands: SVGRenderTree.lower(sized),
            intrinsicSize: sized.intrinsicSize
        )
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
            self.init(emptyContentMode: contentMode)
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
            self.init(emptyContentMode: contentMode)
        }
    }

    /// Fetch SVG bytes from `url` and render them. Never throws — the canvas stays empty
    /// while loading and after a load or parse failure.
    ///
    /// This loads the SVG document itself. Referenced resources inside the document still
    /// follow `parser`'s resource policy (production default: no network `href` fetch).
    public init(
        url: URL?,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        contentMode: SVGImageContentMode = .fit
    ) {
        self.init(
            remoteRequest: url.map { URLRequest(url: $0) },
            parser: parser,
            session: session,
            contentMode: contentMode,
            parseError: nil
        )
    }

    /// Like `init(url:parser:session:contentMode:)` but records load or parse failures in `parseError`.
    public init(
        url: URL?,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        contentMode: SVGImageContentMode = .fit,
        parseError: Binding<Error?>
    ) {
        self.init(
            remoteRequest: url.map { URLRequest(url: $0) },
            parser: parser,
            session: session,
            contentMode: contentMode,
            parseError: parseError
        )
    }

    /// Fetch SVG bytes using `urlRequest` and render them. Never throws — the canvas stays
    /// empty while loading and after a load or parse failure.
    public init(
        urlRequest: URLRequest,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        contentMode: SVGImageContentMode = .fit
    ) {
        self.init(
            remoteRequest: urlRequest,
            parser: parser,
            session: session,
            contentMode: contentMode,
            parseError: nil
        )
    }

    /// Like `init(urlRequest:parser:session:contentMode:)` but records load or parse failures
    /// in `parseError`.
    public init(
        urlRequest: URLRequest,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        contentMode: SVGImageContentMode = .fit,
        parseError: Binding<Error?>
    ) {
        self.init(
            remoteRequest: urlRequest,
            parser: parser,
            session: session,
            contentMode: contentMode,
            parseError: parseError
        )
    }

    fileprivate init(emptyContentMode contentMode: SVGImageContentMode) {
        self.contents = .rendered(commands: [], intrinsicSize: nil)
        self.contentMode = contentMode
    }

    private init(
        remoteRequest request: URLRequest?,
        parser: SVGParser,
        session: URLSession,
        contentMode: SVGImageContentMode,
        parseError: Binding<Error?>?
    ) {
        self.contents = .remote(
            request: request,
            parser: parser,
            session: session,
            parseError: parseError
        )
        self.contentMode = contentMode
    }

    public var body: some View {
        switch contents {
        case .rendered(let commands, let intrinsicSize):
            renderedCanvas(commands: commands, intrinsicSize: intrinsicSize)
        case .remote(let request, let parser, let session, let parseError):
            SVGRemoteImageView(
                request: request,
                parser: parser,
                session: session,
                contentMode: contentMode,
                parseError: parseError
            )
        }
    }

    @ViewBuilder
    private func renderedCanvas(
        commands: [SVGRenderCommand],
        intrinsicSize: CGSize?
    ) -> some View {
        Canvas { context, size in
            var ctx = context
            applyContainerTransform(into: &ctx, size: size, intrinsicSize: intrinsicSize)
            SwiftUICanvasRenderer().execute(commands, context: &ctx)
        }
        .modifier(SVGImageLayoutModifier(
            intrinsicSize: intrinsicSize,
            contentMode: contentMode
        ))
    }

    /// Maps document coordinates into the canvas according to `contentMode`.
    private func applyContainerTransform(
        into context: inout GraphicsContext,
        size: CGSize,
        intrinsicSize: CGSize?
    ) {
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

    private enum Contents {
        case rendered(commands: [SVGRenderCommand], intrinsicSize: CGSize?)
        case remote(
            request: URLRequest?,
            parser: SVGParser,
            session: URLSession,
            parseError: Binding<Error?>?
        )
    }
}

/// Loads a remote (or `file:`) SVG document and hands it to `SVGImageView`.
private struct SVGRemoteImageView: View {
    let request: URLRequest?
    let parser: SVGParser
    let session: URLSession
    let contentMode: SVGImageContentMode
    var parseError: Binding<Error?>?

    @State private var document: SVGDocument?

    var body: some View {
        Group {
            if let document {
                SVGImageView(document: document, contentMode: contentMode)
            } else {
                SVGImageView(emptyContentMode: contentMode)
            }
        }
        .task(id: request) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        document = nil
        parseError?.wrappedValue = nil
        guard let request else { return }
        do {
            let loaded = try await SVGRemoteImageLoader.document(
                for: request,
                session: session,
                options: parser.options,
                conditionalContext: parser.conditionalContext
            )
            guard !Task.isCancelled else { return }
            document = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            document = nil
            parseError?.wrappedValue = error
        }
    }
}
