import AppKit
import SwiftUI
import SVGConformance

struct TestDetailView: View {
    let row: TestRow
    @Environment(TestStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !row.metadata.isEmpty {
                    metadataSection
                }
                tilesGrid
                sourceSection
            }
            .padding(20)
        }
        .navigationTitle(row.id)
        .navigationSubtitle(row.tag.capitalized)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: row.status)
                    Text(StatusStyle.label(for: row.status))
                        .font(.title3.weight(.semibold))
                }
                if let detail = row.record.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
                if let frac = row.record.mismatchedFraction, frac > 0 {
                    Text(String(format: "Mismatched: %.4f%% · max channel Δ %d",
                                frac * 100,
                                row.record.diffMaxChannel ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.approve(testCaseID: row.id) }
            } label: {
                Label("Approve baseline", systemImage: "checkmark.seal")
            }
            .help("Copy the current render to baseline.png and mark this test as passing")
            .disabled(row.actualURL == nil)
        }
    }

    private var tilesGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 16) {
            ImageTile(title: "SVGeeKit render", url: row.actualURL,
                      placeholder: "No render")
            ImageTile(title: "Approved baseline", url: row.baselineURL,
                      placeholder: "No baseline")
            ReferenceTile(row: row)
            DiffTile(row: row)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test description").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                if let title = row.metadata.title, title != row.id {
                    Text(title).font(.subheadline.weight(.semibold))
                }
                if let desc = row.metadata.description {
                    Text(desc).font(.callout)
                }
                MetadataParagraphBlock(
                    title: "Test description",
                    paragraphs: row.metadata.testDescriptionParagraphs
                )
                MetadataParagraphBlock(
                    title: "Pass criteria",
                    paragraphs: row.metadata.passCriteriaParagraphs
                )
                MetadataParagraphBlock(
                    title: "Operator script",
                    paragraphs: row.metadata.operatorScriptParagraphs
                )
                MetadataChips(metadata: row.metadata)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source").font(.headline)
            ScrollView {
                Text(row.svgSource)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }
}

private struct ImageTile: View {
    let title: String
    let url: URL?
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ZStack {
                Color.white
                if let url, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct ReferenceTile: View {
    let row: TestRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("W3C reference").font(.headline)
                Spacer()
                if row.referenceURL != nil {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([row.expectedReferenceURL])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }
            ZStack {
                Color.white
                if let url = row.referenceURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    VStack(spacing: 6) {
                        Text("Not vendored")
                            .foregroundStyle(.secondary)
                        Text("Drop the reference PNG at:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.expectedReferenceURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct MetadataParagraphBlock: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        if !paragraphs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct MetadataChips: View {
    let metadata: SVGTestMetadata

    var body: some View {
        let items = chipItems
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items, id: \.label) { item in
                    Text("\(item.label): \(item.value)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                }
            }
        }
    }

    private var chipItems: [(label: String, value: String)] {
        var items: [(String, String)] = []
        if let author = metadata.author { items.append(("author", author)) }
        if let reviewer = metadata.reviewer { items.append(("reviewer", reviewer)) }
        if let status = metadata.status { items.append(("status", status)) }
        return items
    }
}

private struct DiffTile: View {
    let row: TestRow

    enum DiffTarget: String, CaseIterable, Identifiable {
        case baseline = "Approved baseline"
        case reference = "W3C reference"
        var id: String { rawValue }
    }

    @State private var target: DiffTarget = .baseline

    private var comparisonURL: URL? {
        switch target {
        case .baseline: return row.baselineURL
        case .reference: return row.referenceURL
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diff highlight").font(.headline)
                Spacer()
                Picker("", selection: $target) {
                    ForEach(DiffTarget.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text("Our render vs. \(target.rawValue.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                CheckerboardBackground()
                diffContent
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        if let comparisonURL,
           let actualURL = row.actualURL,
           let expected = SVGSnapshotDiffer.loadPNG(comparisonURL),
           let actual = SVGSnapshotDiffer.loadPNG(actualURL) {
            if let highlight = try? SVGSnapshotDiffer.makeDiffHighlightImage(
                expected: expected,
                actual: actual
            ) {
                Image(nsImage: nsImage(from: highlight))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                VStack(spacing: 4) {
                    Text("Size mismatch")
                        .foregroundStyle(.secondary)
                    Text("render \(actual.width)×\(actual.height) vs \(target.rawValue.lowercased()) \(expected.width)×\(expected.height)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
            }
        } else {
            Text(missingText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
        }
    }

    private var missingText: String {
        if row.actualURL == nil { return "Need a render" }
        switch target {
        case .baseline: return "Need an approved baseline"
        case .reference: return "W3C reference not vendored"
        }
    }

    private func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
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
