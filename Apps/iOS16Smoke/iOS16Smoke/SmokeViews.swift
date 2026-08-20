import SVGAnimation
import SVGKit
import SVGScript
import SwiftUI
import UIKit

struct SmokeDestinationView: View {
    let smokeCase: SmokeCase

    var body: some View {
        switch smokeCase {
        case .examples:
            ExampleGalleryView()
        case .canvas:
            CanvasSmokeView()
        case .raster:
            RasterSmokeView()
        case .animationEngine:
            AnimationEngineSmokeView()
        case .animationView:
            if #available(iOS 17, *) {
                LiveAnimationSmokeView()
            } else {
                UnavailableOnThisOSView(feature: "SVGAnimationImageView is marked @available(iOS 17, *)")
            }
        case .script:
            if #available(iOS 17, *) {
                ScriptSmokeView()
            } else {
                UnavailableOnThisOSView(feature: "SVGScriptImageView is marked @available(iOS 17, *)")
            }
        }
    }
}

private struct UnavailableOnThisOSView: View {
    let feature: String
    private let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.iphone")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Requires iOS 17")
                .font(.title2.weight(.semibold))
            Text(feature)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Running \(systemVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewCard<Content: View>: View {
    let caption: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct CanvasSmokeView: View {
    var body: some View {
        PreviewCard(caption: "Live SwiftUI Canvas via SVGImageView. If this draws, the iOS 16 core path works.") {
            SVGImageView(svgData: Data(Fixtures.canvas.utf8), contentMode: .fit)
                .padding(12)
        }
    }
}

private struct RasterSmokeView: View {
    @State private var image: CGImage?
    @State private var errorMessage: String?

    var body: some View {
        PreviewCard(caption: "Offscreen CGImage from SVGRasterizer, shown as UIImage.") {
            Group {
                if let image {
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            do {
                let document = try SVGParser().parse(data: Data(Fixtures.canvas.utf8))
                image = try SVGRasterizer.rasterize(
                    document,
                    pixelSize: CGSize(width: 240, height: 160),
                    scale: 2
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AnimationEngineSmokeView: View {
    private let duration = 2.0
    private let document: SVGDocument

    init() {
        document = (try? SVGParser().parse(data: Data(Fixtures.animate.utf8))) ?? SVGDocument()
    }

    var body: some View {
        PreviewCard(caption: "SVGAnimationEngine.sample looping over 2s, rendered with SVGImageView. This is the iOS 16 animation path.") {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
                SVGImageView(
                    document: SVGAnimationEngine.sample(document: document, at: time),
                    contentMode: .fit
                )
                .padding(12)
            }
        }
    }
}

@available(iOS 17, *)
private struct LiveAnimationSmokeView: View {
    private let document: SVGDocument

    init() {
        document = (try? SVGParser().parse(data: Data(Fixtures.animate.utf8))) ?? SVGDocument()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SVGAnimationImageView(document: document, contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text("Gated SVGAnimationImageView. On iOS 16 this screen should be replaced by the lock message.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

@available(iOS 17, *)
private struct ScriptSmokeView: View {
    private let scriptView: SVGScriptImageView?

    init() {
        scriptView = try? SVGScriptImageView(data: Data(Fixtures.scriptClick.utf8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let scriptView {
                    scriptView
                } else {
                    Text("Failed to parse script fixture")
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Tap the red square. It should turn green. On iOS 16 this screen should be replaced by the lock message.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
