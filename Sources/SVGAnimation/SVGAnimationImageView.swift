import SwiftUI
import SVGCore
import SVGParser
import SVGRendererSwiftUI

/// SwiftUI view that plays declarative SMIL animations via timeline sampling.
@MainActor
public struct SVGAnimationImageView: View {
    private let document: SVGDocument
    private let duration: Double
    private let aspectRatio: CGFloat

    @State private var isPlaying = true
    @State private var scrubTime: Double = 0
    @State private var playbackOrigin = Date.timeIntervalSinceReferenceDate

    public init(document: SVGDocument, initialTime: Double? = nil) {
        let sized = Self.sizedDocument(document)
        self.document = sized
        self.duration = SVGAnimationEngine.suggestedDuration(in: sized)
        let intrinsic = sized.intrinsicSize ?? sized.viewBox?.size
        self.aspectRatio = intrinsic.map { $0.width / max($0.height, 1) } ?? (4 / 3)
        _scrubTime = State(initialValue: initialTime ?? 0)
        _isPlaying = State(initialValue: initialTime == nil)
        if let initialTime {
            _playbackOrigin = State(initialValue: Date.timeIntervalSinceReferenceDate - initialTime)
        }
    }

    public init(data: Data, baseURL: URL? = nil, initialTime: Double? = nil) throws {
        let parsed = try SVGParser().parse(data: data, baseURL: baseURL)
        self.init(document: parsed, initialTime: initialTime)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            playbackControls
            animationCanvas
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                if isPlaying {
                    scrubTime = playbackTime(at: Date())
                    isPlaying = false
                } else {
                    if scrubTime >= duration {
                        scrubTime = 0
                    }
                    playbackOrigin = Date.timeIntervalSinceReferenceDate - scrubTime
                    isPlaying = true
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "Pause" : "Play")

            Slider(value: $scrubTime, in: 0...max(duration, 0.001), onEditingChanged: { editing in
                if editing {
                    isPlaying = false
                }
            })

            Text("\(formatTime(scrubTime)) / \(formatTime(duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .onChange(of: scrubTime) { _, _ in
            if !isPlaying {
                playbackOrigin = Date.timeIntervalSinceReferenceDate - scrubTime
            }
        }
    }

    private var animationCanvas: some View {
        ZStack {
            Color.white
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = playbackTime(at: context.date)
                let sampled = SVGAnimationEngine.sample(document: document, at: time)
                SVGImageView(document: sampled)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { date in
            guard isPlaying else { return }
            let time = max(0, min(duration, date.timeIntervalSinceReferenceDate - playbackOrigin))
            scrubTime = time
            if time >= duration {
                isPlaying = false
            }
        }
    }

    private func playbackTime(at date: Date) -> Double {
        if isPlaying {
            return max(0, min(duration, date.timeIntervalSinceReferenceDate - playbackOrigin))
        }
        return scrubTime
    }

    private func formatTime(_ seconds: Double) -> String {
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.0fs", seconds.rounded())
    }

    private static func sizedDocument(_ document: SVGDocument) -> SVGDocument {
        if document.intrinsicSize != nil { return document }
        var copy = document
        copy.intrinsicSize = document.viewBox?.size
        return copy
    }
}
