import SwiftUI

enum SmokeCase: String, CaseIterable, Identifiable, Hashable {
    case examples
    case canvas
    case raster
    case animationEngine
    case animationView
    case script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .examples: return "Examples"
        case .canvas: return "Canvas"
        case .raster: return "Rasterizer"
        case .animationEngine: return "Animation engine"
        case .animationView: return "Animation view"
        case .script: return "Script"
        }
    }

    var subtitle: String {
        switch self {
        case .examples: return "All SVGs in the Examples folder"
        case .canvas: return "SVGImageView on SwiftUI Canvas"
        case .raster: return "SVGRasterizer → CGImage"
        case .animationEngine: return "SMIL sampling + SVGImageView"
        case .animationView: return "SVGAnimationImageView"
        case .script: return "SVGScriptImageView tap handlers"
        }
    }

    var requiresiOS17: Bool {
        self == .animationView || self == .script
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("System") {
                        Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    }
                    LabeledContent("App target") {
                        Text("iOS 16.0")
                    }
                } header: {
                    Text("Runtime")
                } footer: {
                    Text("Canvas, raster, and the animation engine should work here. Script and SVGAnimationImageView require iOS 17.")
                }

                Section("Checks") {
                    ForEach(SmokeCase.allCases) { smokeCase in
                        NavigationLink(value: smokeCase) {
                            SmokeCaseRow(smokeCase: smokeCase)
                        }
                    }
                }
            }
            .navigationTitle("SVGeeKit iOS 16")
            .navigationDestination(for: SmokeCase.self) { smokeCase in
                SmokeDestinationView(smokeCase: smokeCase)
                    .navigationTitle(smokeCase.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct SmokeCaseRow: View {
    let smokeCase: SmokeCase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(smokeCase.title)
                if smokeCase.requiresiOS17 {
                    Text("iOS 17+")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Color.orange, in: Capsule())
                }
            }
            Text(smokeCase.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
