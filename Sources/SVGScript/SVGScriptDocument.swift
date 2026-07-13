#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import SVGCore
import SVGParser
import SVGRenderer

public enum SVGScriptError: Error, Equatable {
  case scriptUnavailable
  case evaluationFailed(String)
}

/// Mutable SVG document with an ECMAScript runtime (JavaScriptCore).
@MainActor
@Observable
public final class SVGScriptDocument {

  public private(set) var document: SVGDocument
  /// Bumped after script-driven DOM mutations so SwiftUI views re-render.
  public private(set) var contentRevision: UInt = 0
  @ObservationIgnored private lazy var runtime: SVGScriptRuntime = SVGScriptRuntime(owner: self)

  public init(data: Data, baseURL: URL? = nil) throws {
    let options = baseURL.map { SVGParserOptions.localFiles(at: $0) } ?? .production
    let parsed = try SVGParser(options: options).parse(
      data: data,
      options: options,
      sourceURL: nil
    )
    self.document = parsed
  }

  public init(document: SVGDocument) {
    self.document = document
  }

  public func dispatchLoad() {
    runtime.evaluateScriptBlocks()
    let defaultType = document.scriptMetadata.contentScriptType
    guard Self.shouldDispatchEventHandlers(defaultType: defaultType) else { return }
    for handler in document.scriptMetadata.rootHandlers where handler.event == "load" {
      runtime.dispatch(handler: handler, targetPath: SVGElementPath(indices: []))
    }
  }

  public func dispatchClick(at point: CGPoint) {
    guard Self.shouldDispatchEventHandlers(defaultType: document.scriptMetadata.contentScriptType) else {
      return
    }
    guard let hit = SVGHitTester.hitTest(document: document, at: point) else { return }
    guard let match = SVGHitTester.handlerOwnerPath(
      hitPath: hit.path,
      document: document,
      event: "click"
    ) else { return }
    runtime.dispatch(handler: match.handler, targetPath: hit.path)
  }

  fileprivate func domDocumentObject() -> SVGScriptDOMDocument {
    SVGScriptDOMDocument(owner: self)
  }

  fileprivate func domElementObject(path: SVGElementPath) -> SVGScriptDOMElement {
    SVGScriptDOMElement(owner: self, path: path)
  }

  fileprivate func applyAttribute(at path: SVGElementPath, name: String, value: String) {
    try? document.setAttribute(at: path, name: name, value: value)
    contentRevision &+= 1
  }

  private static func shouldDispatchEventHandlers(defaultType: String?) -> Bool {
    SVGScriptRuntime.shouldRunScript(type: nil, defaultType: defaultType)
  }
}

@MainActor
final class SVGScriptRuntime {
  private weak var owner: SVGScriptDocument?
  private let context: JSContext

  init(owner: SVGScriptDocument) {
    self.owner = owner
    self.context = JSContext()!
    context.exceptionHandler = { _, exception in
      if let value = exception?.toString() {
        print("SVGScript JS error: \(value)")
      }
    }
    let consoleLog: @convention(block) (String) -> Void = { message in
      print("SVGScript: \(message)")
    }
    context.setObject(consoleLog, forKeyedSubscript: "__svgLog" as NSString)
    context.evaluateScript("""
      var console = { log: function(msg) { __svgLog(String(msg)); } };
      """)
    let document = owner.domDocumentObject()
    context.setObject(document, forKeyedSubscript: "document" as NSString)
  }

  func evaluateScriptBlocks() {
    guard let owner else { return }
    let defaultType = owner.document.scriptMetadata.contentScriptType
    for block in owner.document.scriptMetadata.blocks {
      guard Self.shouldRunScript(type: block.type, defaultType: defaultType) else { continue }
      _ = context.evaluateScript(block.source)
    }
  }

  func dispatch(handler: SVGEventHandler, targetPath: SVGElementPath) {
    guard let owner else { return }
    let target = owner.domElementObject(path: targetPath)
    let event = SVGScriptDOMEvent(target: target)
    context.setObject(event, forKeyedSubscript: "evt" as NSString)
    _ = context.evaluateScript(handler.script)
  }

  static func shouldRunScript(type: String?, defaultType: String?) -> Bool {
    let effective = (type ?? defaultType ?? "application/ecmascript")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return effective == "text/ecmascript" || effective == "application/ecmascript"
  }
}

@MainActor
@objc protocol SVGScriptDOMDocumentJSExport: JSExport {
  func getElementById(_ id: String) -> SVGScriptDOMElement?
}

@MainActor
final class SVGScriptDOMDocument: NSObject, SVGScriptDOMDocumentJSExport {
  private weak var owner: SVGScriptDocument?

  init(owner: SVGScriptDocument) {
    self.owner = owner
  }

  func getElementById(_ id: String) -> SVGScriptDOMElement? {
    guard let owner,
          let path = owner.document.scriptMetadata.elementIndex[id] else { return nil }
    return owner.domElementObject(path: path)
  }
}

@MainActor
@objc protocol SVGScriptDOMElementJSExport: JSExport {
  func setAttribute(_ name: String, _ value: String)
  var ownerDocument: SVGScriptDOMDocument? { get }
}

@MainActor
final class SVGScriptDOMElement: NSObject, SVGScriptDOMElementJSExport {
  private weak var owner: SVGScriptDocument?
  private let path: SVGElementPath

  init(owner: SVGScriptDocument, path: SVGElementPath) {
    self.owner = owner
    self.path = path
  }

  func setAttribute(_ name: String, _ value: String) {
    guard let owner else { return }
    owner.applyAttribute(at: path, name: name, value: value)
  }

  var ownerDocument: SVGScriptDOMDocument? {
    owner?.domDocumentObject()
  }
}

@MainActor
@objc protocol SVGScriptDOMEventJSExport: JSExport {
  var target: SVGScriptDOMElement? { get }
}

@MainActor
final class SVGScriptDOMEvent: NSObject, SVGScriptDOMEventJSExport {
  let target: SVGScriptDOMElement?

  init(target: SVGScriptDOMElement?) {
    self.target = target
  }
}

#endif
