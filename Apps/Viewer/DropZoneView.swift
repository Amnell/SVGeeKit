import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SVGAnimation
import SVGCore
import SVGKit
import SVGParser

struct DropZoneView: View {
    @State private var state: LoadState = .empty
    @State private var isTargeted: Bool = false
    @State private var sourceURL: URL?
    @State private var loadTask: Task<Void, Never>?
    @AppStorage("viewer.showLiveCanvas") private var showLiveCanvas: Bool = true
    @AppStorage("viewer.showRaster") private var showRaster: Bool = true
    @AppStorage("viewer.showSource") private var showSource: Bool = false

    private enum LoadState {
        case empty
        case loading(URL)
        case loaded(SVGDocument, source: String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url: url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var toolbar: some View {
        HStack {
            Button {
                openPanel()
            } label: {
                Label("Open SVG…", systemImage: "folder")
            }
            if let sourceURL {
                Text(sourceURL.lastPathComponent)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("Live", isOn: $showLiveCanvas)
                .toggleStyle(.button)
                .help("Show the live SwiftUI Canvas tile")
            Toggle("Raster", isOn: $showRaster)
                .toggleStyle(.button)
                .help("Show the rasterized PNG tile")
            Toggle("Source", isOn: $showSource)
                .toggleStyle(.button)
                .help("Show the raw SVG source text")
            if case .loaded = state {
                Button("Clear") { reset() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .empty:
            DropPrompt(isTargeted: isTargeted) { openPanel() }
        case .loading:
            ProgressView("Parsing…")
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Failed to load SVG",
                systemImage: "xmark.octagon",
                description: Text(message)
            )
        case .loaded(let document, let source):
            LoadedSVGView(
                document: document,
                source: source,
                showLiveCanvas: $showLiveCanvas,
                showRaster: $showRaster,
                showSource: $showSource
            )
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    private func load(url: URL) {
        loadTask?.cancel()
        sourceURL = url
        state = .loading(url)
        loadTask = Task {
            // Read + parse off the main actor; only the result hop is on-main.
            let result: Result<(SVGDocument, String), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: url)
                    let document = try SVGParser().parse(
                        data: data,
                        baseURL: url.deletingLastPathComponent()
                    )
                    let source = String(data: data, encoding: .utf8) ?? ""
                    return .success((document, source))
                } catch {
                    return .failure(error)
                }
            }.value
            if Task.isCancelled { return }
            switch result {
            case .success(let (document, source)):
                state = .loaded(document, source: source)
            case .failure(let error):
                state = .failed(String(describing: error))
            }
        }
    }

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        state = .empty
        sourceURL = nil
    }
}

private struct DropPrompt: View {
    let isTargeted: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop an SVG file here")
                .font(.title3.weight(.medium))
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose file…", action: onOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.08)
                              : Color.secondary.opacity(0.04))
                )
        )
    }
}

private struct LoadedSVGView: View {
    let document: SVGDocument
    let source: String
    @Binding var showLiveCanvas: Bool
    @Binding var showRaster: Bool
    @Binding var showSource: Bool

    @State private var rasterScale: CGFloat = 1
    @State private var rasterImage: NSImage?
    @State private var rasterError: String?

    private var intrinsic: CGSize {
        document.intrinsicSize ?? document.viewBox?.size ?? CGSize(width: 480, height: 360)
    }

    private var hasAnimations: Bool {
        SVGAnimationEngine.containsAnimations(in: document)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intrinsicChips
                tiles
                if showSource {
                    sourceSection
                }
            }
            .padding(.bottom, 16)
        }
        .task(id: source) {
            guard showRaster else { return }
            await refreshRaster()
        }
    }

    private var intrinsicChips: some View {
        HStack(spacing: 8) {
            Chip(label: "size", value: "\(Int(intrinsic.width)) × \(Int(intrinsic.height))")
            if let vb = document.viewBox {
                Chip(label: "viewBox",
                     value: "\(fmt(vb.minX)) \(fmt(vb.minY)) \(fmt(vb.width)) \(fmt(vb.height))")
            }
            Spacer()
            Picker("Raster scale", selection: $rasterScale) {
                Text("1×").tag(CGFloat(1))
                Text("2×").tag(CGFloat(2))
                Text("3×").tag(CGFloat(3))
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(!showRaster)
            .onChange(of: rasterScale) { _, _ in
                guard showRaster else { return }
                Task { await refreshRaster() }
            }
        }
    }

    private var tiles: some View {
        let visibleCount = (showLiveCanvas ? 1 : 0) + (showRaster ? 1 : 0)
        let columns: [GridItem] = visibleCount >= 2
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 16) {
            if showLiveCanvas {
                if hasAnimations {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SVGAnimationImageView (live SMIL)").font(.headline)
                        SVGAnimationImageView(document: document)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SVGImageView (live SwiftUI Canvas)").font(.headline)
                        CheckerboardTile {
                            SVGImageView(document: document)
                                .frame(width: intrinsic.width, height: intrinsic.height)
                        }
                    }
                }
            }
            if showRaster {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Static PNG (SVGRasterizer)").font(.headline)
                    CheckerboardTile {
                        if let rasterImage {
                            Image(nsImage: rasterImage)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                        } else if let rasterError {
                            Text(rasterError)
                                .foregroundStyle(.red)
                                .font(.callout)
                                .padding(8)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
        }
        .onChange(of: showRaster) { _, newValue in
            if newValue {
                Task { await refreshRaster() }
            } else {
                rasterImage = nil
                rasterError = nil
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source").font(.headline)
            ScrollView {
                Text(source)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    @MainActor
    private func refreshRaster() async {
        do {
            let cg = try SVGRasterizer.rasterize(
                document,
                pixelSize: intrinsic,
                scale: rasterScale
            )
            let pixelSize = NSSize(width: cg.width, height: cg.height)
            rasterImage = NSImage(cgImage: cg, size: pixelSize)
            rasterError = nil
        } catch {
            rasterImage = nil
            rasterError = String(describing: error)
        }
    }

    private func fmt(_ v: CGFloat) -> String {
        v.rounded() == v ? "\(Int(v))" : String(format: "%.2f", Double(v))
    }
}

private struct CheckerboardTile<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Checkerboard()
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let tile: CGFloat = 12
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c) % 2 == 0 { continue }
                    let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile,
                                      width: tile, height: tile)
                    ctx.fill(Path(rect), with: .color(.gray.opacity(0.15)))
                }
            }
        }
    }
}

private struct Chip: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(label): \(value)")
            .font(.caption.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}
