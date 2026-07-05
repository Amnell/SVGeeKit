#if canImport(JavaScriptCore) && canImport(SwiftUI)
import CoreGraphics
import SwiftUI
import SVGCore
import SVGRenderer
import SVGRendererSwiftUI

/// SwiftUI view that renders a scriptable SVG and forwards pointer clicks to ECMAScript handlers.
public struct SVGScriptImageView: View {

  @State private var scriptDocument: SVGScriptDocument
  private let intrinsicSize: CGSize?
  private let contentMode: SVGImageContentMode

  public init(
    data: Data,
    baseURL: URL? = nil,
    contentMode: SVGImageContentMode = .fit
  ) throws {
    let doc = try SVGScriptDocument(data: data, baseURL: baseURL)
    let sized = Self.sizedDocument(doc.document)
    _scriptDocument = State(initialValue: SVGScriptDocument(document: sized))
    intrinsicSize = sized.intrinsicSize ?? sized.viewBox?.size
    self.contentMode = contentMode
  }

  public init(
    scriptDocument: SVGScriptDocument,
    contentMode: SVGImageContentMode = .fit
  ) {
    let sized = Self.sizedDocument(scriptDocument.document)
    _scriptDocument = State(initialValue: SVGScriptDocument(document: sized))
    intrinsicSize = sized.intrinsicSize ?? sized.viewBox?.size
    self.contentMode = contentMode
  }

  public var body: some View {
    GeometryReader { proxy in
      Canvas { context, size in
        var ctx = context
        applyContainerTransform(into: &ctx, canvasSize: size)
        // Observe revision so Canvas re-draws after script mutations.
        let _ = scriptDocument.contentRevision
        let commands = SVGRenderTree.lower(scriptDocument.document)
        SwiftUICanvasRenderer().execute(commands, context: &ctx)
      }
      .contentShape(Rectangle())
      .onTapGesture { location in
        let point = userSpacePoint(location: location, canvasSize: proxy.size)
        scriptDocument.dispatchClick(at: point)
      }
    }
    .modifier(SVGImageLayoutModifier(
      intrinsicSize: intrinsicSize,
      contentMode: contentMode
    ))
    .frame(maxWidth: .infinity)
    .task {
      scriptDocument.dispatchLoad()
    }
  }

  private func applyContainerTransform(into context: inout GraphicsContext, canvasSize: CGSize) {
    guard let intrinsic = intrinsicSize else { return }
    SVGImageContainerTransform.apply(
      to: &context,
      intrinsicSize: intrinsic,
      canvasSize: canvasSize,
      contentMode: contentMode
    )
  }

  private func userSpacePoint(location: CGPoint, canvasSize: CGSize) -> CGPoint {
    guard let intrinsic = intrinsicSize,
          let transform = SVGImageContainerTransform.compute(
            intrinsicSize: intrinsic,
            canvasSize: canvasSize,
            contentMode: contentMode
          ) else {
      return location
    }
    return transform.userSpacePoint(from: location)
  }

  private static func sizedDocument(_ document: SVGDocument) -> SVGDocument {
    if document.intrinsicSize != nil { return document }
    var copy = document
    copy.intrinsicSize = document.viewBox?.size
    return copy
  }
}

#endif
