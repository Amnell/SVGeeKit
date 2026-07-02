import Foundation

/// Stable path from `SVGDocument.root.children` into the element tree.
public struct SVGElementPath: Equatable, Sendable, Codable {
  public var indices: [Int]

  public init(indices: [Int] = []) {
    self.indices = indices
  }
}

public struct SVGScriptBlock: Sendable, Equatable {
  public var type: String?
  public var source: String

  public init(type: String? = nil, source: String) {
    self.type = type
    self.source = source
  }
}

public struct SVGEventHandler: Sendable, Equatable {
  public var event: String
  public var script: String

  public init(event: String, script: String) {
    self.event = event
    self.script = script
  }
}

public struct SVGScriptMetadata: Sendable, Equatable {
  public var contentScriptType: String?
  public var blocks: [SVGScriptBlock]
  public var handlersByElementID: [String: [SVGEventHandler]]
  public var rootHandlers: [SVGEventHandler]
  public var elementIndex: [String: SVGElementPath]

  public init(
    contentScriptType: String? = nil,
    blocks: [SVGScriptBlock] = [],
    handlersByElementID: [String: [SVGEventHandler]] = [:],
    rootHandlers: [SVGEventHandler] = [],
    elementIndex: [String: SVGElementPath] = [:]
  ) {
    self.contentScriptType = contentScriptType
    self.blocks = blocks
    self.handlersByElementID = handlersByElementID
    self.rootHandlers = rootHandlers
    self.elementIndex = elementIndex
  }
}
