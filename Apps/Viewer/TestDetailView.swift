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
            ImageTile(title: "W3C reference", url: row.referenceURL,
                      placeholder: "Not vendored")
            DiffTile(row: row)
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
                CheckerboardBackground()
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

private struct DiffTile: View {
    let row: TestRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diff overlay").font(.headline)
            ZStack {
                CheckerboardBackground()
                if let baseline = row.baselineURL.flatMap({ NSImage(contentsOf: $0) }),
                   let actual = row.actualURL.flatMap({ NSImage(contentsOf: $0) }) {
                    Image(nsImage: actual)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .opacity(0.5)
                        .overlay {
                            Image(nsImage: baseline)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .blendMode(.difference)
                                .opacity(0.5)
                        }
                } else {
                    Text("Need both baseline and render")
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
