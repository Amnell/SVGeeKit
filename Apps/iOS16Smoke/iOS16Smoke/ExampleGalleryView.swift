import SVGKit
import SwiftUI

struct ExampleFile: Identifiable {
    var id: String { url.lastPathComponent }
    let url: URL
    let data: Data

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

enum ExampleCatalog {
    static func load() -> [ExampleFile] {
        let urls = bundledSVGURLs()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ExampleFile(url: url, data: data)
        }
    }

    private static func bundledSVGURLs() -> [URL] {
        let bundle = Bundle.main
        let nested = bundle.urls(forResourcesWithExtension: "svg", subdirectory: "Examples") ?? []
        let urls = nested.isEmpty
            ? (bundle.urls(forResourcesWithExtension: "svg", subdirectory: nil) ?? [])
            : nested
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

struct ExampleGalleryView: View {
    private let examples: [ExampleFile]

    init() {
        examples = ExampleCatalog.load()
    }

    var body: some View {
        Group {
            if examples.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(examples) { example in
                            ExampleCard(example: example)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No SVGs in the bundle")
                .font(.title3.weight(.semibold))
            Text("Add files to Apps/iOS16Smoke/iOS16Smoke/Examples and rebuild.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExampleCard: View {
    let example: ExampleFile
    @State private var parseError: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(example.title)
                .font(.headline)
            SVGImageView(svgData: example.data, contentMode: .fit, parseError: $parseError)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 140, maxHeight: 420)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if let parseError {
                Text(parseError.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(example.title)
    }
}
