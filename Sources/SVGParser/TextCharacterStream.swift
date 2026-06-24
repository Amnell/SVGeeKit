import Foundation
import SVGCore

/// Metadata captured during SAX for a flushed text segment (rotate frames).
struct TextSegmentMeta: Sendable {
    var opensRotate: [CGFloat]?
    var closesRotate: Bool = false
}

/// Applies SVG `xml:space` across SAX text runs at `</text>`.
enum TextCharacterStream {

    struct RawSegment: Sendable {
        var run: SVGTextRun
        var raw: String
        var meta: TextSegmentMeta
    }

  struct NormalizedText {
    var runs: [SVGTextRun]
    var meta: [TextSegmentMeta]
  }

    static func normalize(_ segments: [RawSegment]) -> NormalizedText {
        guard !segments.isEmpty else { return NormalizedText(runs: [], meta: []) }

        var output: [SVGTextRun] = []
        var outputMeta: [TextSegmentMeta] = []
        var pendingSpace = false
        var pendingOpensRotate: [CGFloat]?
        var atStart = true

        for (index, segment) in segments.enumerated() {
            let run = segment.run
            let hasOffset = run.dx != 0 || run.dy != 0
                || run.explicitX != nil || run.explicitY != nil
            var segmentRunIndex: Int?

            func ensureSegmentRun() {
                if segmentRunIndex != nil { return }
                flushPendingSpace(to: &output, pending: &pendingSpace)
                var applied = segment.meta
                if applied.opensRotate == nil, let pending = pendingOpensRotate {
                    applied.opensRotate = pending
                    pendingOpensRotate = nil
                }
                output.append(emptyRun(from: run))
                outputMeta.append(applied)
                segmentRunIndex = output.count - 1
            }

            if run.preserveSpace {
                var content = segment.raw
                if run.explicitX != nil || run.explicitY != nil {
                    content = String(content.drop(while: \.isWhitespace))
                    let nextHasExplicit = index + 1 < segments.count
                        && (segments[index + 1].run.explicitX != nil
                            || segments[index + 1].run.explicitY != nil)
                    if nextHasExplicit || index == segments.count - 1 {
                        while let last = content.last, last.isWhitespace {
                            content.removeLast()
                        }
                    }
                }
                guard !content.isEmpty else {
                    if segment.meta.closesRotate, let last = output.indices.last {
                        outputMeta[last].closesRotate = true
                    }
                    continue
                }
                if pendingSpace, !content.hasPrefix(" ") {
                    ensureSegmentRun()
                    output[segmentRunIndex!].string.append(" ")
                    pendingSpace = false
                }
                ensureSegmentRun()
                output[segmentRunIndex!].string.append(content)
                if segment.meta.closesRotate, let idx = segmentRunIndex {
                    outputMeta[idx].closesRotate = true
                }
                atStart = false
                continue
            }

            let raw = segment.raw
            let whitespaceOnly = !raw.isEmpty && raw.allSatisfy(\.isWhitespace)
            let nextHasExplicitX = index + 1 < segments.count && segments[index + 1].run.explicitX != nil
            let nextHasExplicitY = index + 1 < segments.count && segments[index + 1].run.explicitY != nil
            let prevHasExplicitX = index > 0 && segments[index - 1].run.explicitX != nil

            func emitParentLevelSpace(from template: SVGTextRun) {
                var spaceRun = emptyRun(from: template)
                spaceRun.explicitX = nil
                spaceRun.explicitY = nil
                spaceRun.dx = 0
                spaceRun.dy = 0
                spaceRun.baselineY = output.last?.baselineY ?? template.baselineY
                spaceRun.string = " "
                output.append(spaceRun)
                outputMeta.append(TextSegmentMeta())
            }

            if whitespaceOnly && !hasOffset {
                if segment.meta.opensRotate != nil {
                    pendingOpensRotate = segment.meta.opensRotate
                }
                if segment.meta.closesRotate, let last = output.indices.last {
                    outputMeta[last].closesRotate = true
                }
                if nextHasExplicitX && prevHasExplicitX {
                    continue
                }
                if (nextHasExplicitX || nextHasExplicitY) && !prevHasExplicitX && !output.isEmpty {
                    let next = segments[index + 1].run
                    var spaceRun = emptyRun(from: next)
                    spaceRun.string = " "
                    // Inter-tspan whitespace keeps the active baseline; only the
                    // following tspan's own characters pick up its explicit `y`.
                    spaceRun.explicitY = nil
                    spaceRun.explicitX = nil
                    spaceRun.baselineY = output.last?.baselineY ?? segment.run.baselineY
                    output.append(spaceRun)
                    outputMeta.append(TextSegmentMeta())
                    pendingSpace = false
                    continue
                }
                if !atStart {
                    pendingSpace = true
                }
                continue
            }

            var content = raw
            if run.explicitX != nil || run.explicitY != nil {
                content = String(content.drop(while: \.isWhitespace))
            } else if hasFormattingLeading(raw) {
                content = String(content.drop(while: \.isWhitespace))
                if index > 0, !content.isEmpty {
                    pendingSpace = true
                }
            }
            if index == segments.count - 1, !run.preserveSpace {
                while let last = content.last, last.isWhitespace {
                    content.removeLast()
                }
            } else if hasFormattingTrailing(raw), !run.preserveSpace {
                let before = content
                while let last = content.last, last.isWhitespace {
                    content.removeLast()
                }
                if !before.isEmpty, !content.isEmpty, before.count != content.count {
                    let nextHasExplicitY = index + 1 < segments.count
                        && segments[index + 1].run.explicitY != nil
                    if nextHasExplicitY {
                        content.append(" ")
                    } else {
                        pendingSpace = true
                    }
                }
            }
            if !run.preserveSpace {
                content = collapseInternalWhitespace(content)
            }

            guard !content.isEmpty else {
                if segment.meta.closesRotate, let last = output.indices.last {
                    outputMeta[last].closesRotate = true
                }
                continue
            }

            if pendingSpace {
                if content.first?.isWhitespace != true {
                    if run.explicitX != nil {
                        if run.explicitY != nil, pendingSpace, let last = output.indices.last {
                            if !output[last].string.hasSuffix(" ") {
                                output[last].string.append(" ")
                            }
                        }
                        pendingSpace = false
                    } else if segment.meta.opensRotate != nil || pendingOpensRotate != nil {
                        if segment.meta.opensRotate != nil, raw.first == " " {
                            // Inter-`<tspan>` space merged into a new rotate frame
                            // (e.g. before "specified" in text-tspan-02-b).
                            content = " " + content
                        } else {
                            // Separator before a new `rotate` frame stays on the parent
                            // cursor (e.g. -40° after "characters", 35° after "Not").
                            emitParentLevelSpace(from: run)
                        }
                        pendingSpace = false
                    } else if index == segments.count - 1, let last = output.indices.last {
                        if outputMeta[last].closesRotate {
                            var spaceRun = emptyRun(from: run)
                            spaceRun.string = " "
                            output.append(spaceRun)
                            outputMeta.append(TextSegmentMeta())
                        } else if !output[last].string.hasSuffix(" ") {
                            output[last].string.append(" ")
                        }
                        pendingSpace = false
                    } else if index > 0 {
                        content = " " + content
                        pendingSpace = false
                    }
                } else {
                    pendingSpace = false
                }
            }

            ensureSegmentRun()
            output[segmentRunIndex!].string.append(content)
            atStart = false

            if segment.meta.closesRotate, let idx = segmentRunIndex {
                outputMeta[idx].closesRotate = true
            }
        }

        let runs = output.filter { run in
            let hasOffset = run.dx != 0 || run.dy != 0
                || run.explicitX != nil || run.explicitY != nil
            return !run.string.isEmpty || hasOffset
        }

        let meta = zip(output, outputMeta)
            .filter { pair in
                let run = pair.0
                let hasOffset = run.dx != 0 || run.dy != 0
                    || run.explicitX != nil || run.explicitY != nil
                return !run.string.isEmpty || hasOffset
            }
            .map(\.1)

        return NormalizedText(runs: runs, meta: meta)
    }

    static func assignRotations(
        runs: inout [SVGTextRun],
        rootRotate: [CGFloat],
        meta: [TextSegmentMeta]
    ) {
        guard !runs.isEmpty else { return }
        let needsRotation = !rootRotate.isEmpty || meta.contains { $0.opensRotate != nil }
        guard needsRotation else { return }

        var stack: [RotateCursor] = [RotateCursor(values: rootRotate)]

        for i in runs.indices {
            guard !runs[i].string.isEmpty else { continue }

            if i < meta.count, let frame = meta[i].opensRotate {
                if !stack.isEmpty {
                    stack[stack.count - 1].index = stack[stack.count - 1].values.count
                }
                stack.append(RotateCursor(values: frame))
            }

            if !stack.isEmpty {
                var cursor = stack[stack.count - 1]
                runs[i].rotations = runs[i].string.map { _ in cursor.consume() }
                stack[stack.count - 1] = cursor
            }

            if i < meta.count, meta[i].closesRotate, stack.count > 1 {
                stack.removeLast()
            }
        }
    }

    // MARK: - Private

    private static func flushPendingSpace(to output: inout [SVGTextRun], pending: inout Bool) {
        guard pending, let last = output.indices.last else {
            pending = false
            return
        }
        if !output[last].string.hasSuffix(" ") {
            output[last].string.append(" ")
        }
        pending = false
    }

    private static func emptyRun(from template: SVGTextRun) -> SVGTextRun {
        var run = template
        run.string = ""
        run.rotations = nil
        return run
    }

    private static func hasFormattingLeading(_ raw: String) -> Bool {
        for char in raw {
            if char.isNewline { return true }
            if !char.isWhitespace { return false }
        }
        return false
    }

    private static func hasFormattingTrailing(_ raw: String) -> Bool {
        guard raw.contains(where: \.isNewline) else { return false }
        guard let lastContent = raw.lastIndex(where: { !$0.isWhitespace }) else { return false }
        return raw[raw.index(after: lastContent)...].contains(where: \.isNewline)
    }

    private static func collapseInternalWhitespace(_ raw: String) -> String {
        var result = ""
        var inSpace = false
        for char in raw {
            if char.isWhitespace {
                if !inSpace {
                    result.append(" ")
                    inSpace = true
                }
            } else {
                result.append(char)
                inSpace = false
            }
        }
        return result
    }
}

/// Consumes SVG `rotate` list values in document order.
struct RotateCursor {
    var values: [CGFloat]
    var index: Int = 0

    mutating func consume() -> CGFloat {
        guard !values.isEmpty else { return 0 }
        if index < values.count {
            let angle = values[index]
            index += 1
            return angle
        }
        return values[values.count - 1]
    }
}
