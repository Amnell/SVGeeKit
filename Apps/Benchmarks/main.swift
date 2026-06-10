import Foundation
import Darwin
import CoreGraphics
import SVGKit
import SVGConformance

@main
@MainActor
struct Benchmarks {

    struct Config {
        var iterations: Int = 5
        var warmup: Int = 1
        var filter: String? = nil
        var top: Int = 10
        var outputSize: CGSize = CGSize(width: 480, height: 360)
        var skipRasterize: Bool = false
        var inputs: [String] = []
    }

    struct Input {
        let id: String
        let url: URL
    }

    static func main() async throws {
        let config = parseArgs(CommandLine.arguments.dropFirst())

        let inputs: [Input]
        let sourceLabel: String
        if config.inputs.isEmpty {
            let suiteRoot = try locateW3CSuite()
            let index = try SVGTestSuiteIndex(rootDirectory: suiteRoot)
            inputs = index.cases
                .filter { !$0.isSkipped }
                .filter { config.filter == nil || $0.id.localizedCaseInsensitiveContains(config.filter!) }
                .map { Input(id: $0.id, url: $0.svgURL) }
            sourceLabel = "W3C suite — \(suiteRoot.path)"
        } else {
            let resolved = resolveInputs(config.inputs)
            inputs = resolved
                .filter { config.filter == nil || $0.id.localizedCaseInsensitiveContains(config.filter!) }
            sourceLabel = "custom inputs (\(config.inputs.count) arg\(config.inputs.count == 1 ? "" : "s"))"
        }

        guard !inputs.isEmpty else {
            print("No SVG files matched."); return
        }

        print("SVGeeKit Benchmarks")
        print("  source     : \(sourceLabel)")
        print("  files      : \(inputs.count)")
        print("  iterations : \(config.iterations) (+ \(config.warmup) warmup)")
        print("  raster size: \(Int(config.outputSize.width)) × \(Int(config.outputSize.height))")
        print("  rasterize  : \(config.skipRasterize ? "skipped" : "enabled")")
        print("")

        var perCaseTotals: [(id: String, total: Duration)] = []
        var phaseSamples: [Phase: [Duration]] = Dictionary(
            uniqueKeysWithValues: Phase.allCases.map { ($0, []) }
        )

        let parser = SVGParser()
        let clock = ContinuousClock()

        for (i, tc) in inputs.enumerated() {
            // Skip silently if anything fails to load; benchmarks shouldn't
            // mask correctness work — that's what the conformance suite is for.
            guard let data = try? Data(contentsOf: tc.url) else { continue }
            guard let warmDoc = try? parser.parse(data: data) else { continue }

            // Warmup runs (untimed) to settle caches.
            for _ in 0..<config.warmup {
                _ = try? parser.parse(data: data)
                _ = SVGRenderTree.lower(warmDoc)
                if !config.skipRasterize {
                    _ = try? SVGRasterizer.rasterize(warmDoc, pixelSize: config.outputSize)
                }
            }

            var caseTotal: Duration = .zero
            for _ in 0..<config.iterations {
                // read
                let readDur = clock.measure {
                    _ = (try? Data(contentsOf: tc.url)) ?? Data()
                }
                phaseSamples[.read]!.append(readDur)
                caseTotal += readDur

                // parse
                var parsed: SVGDocument?
                let parseDur = clock.measure {
                    parsed = try? parser.parse(data: data)
                }
                phaseSamples[.parse]!.append(parseDur)
                caseTotal += parseDur
                guard let document = parsed else { continue }

                // lower
                var commands: [SVGRenderCommand] = []
                let lowerDur = clock.measure {
                    commands = SVGRenderTree.lower(document)
                }
                phaseSamples[.lower]!.append(lowerDur)
                caseTotal += lowerDur
                _ = commands.count // prevent DCE

                // rasterize
                if !config.skipRasterize {
                    let rasterDur = clock.measure {
                        _ = try? SVGRasterizer.rasterize(document, pixelSize: config.outputSize)
                    }
                    phaseSamples[.rasterize]!.append(rasterDur)
                    caseTotal += rasterDur
                }
            }
            perCaseTotals.append((tc.id, caseTotal / config.iterations))

            if (i + 1) % 25 == 0 || i == inputs.count - 1 {
                FileHandle.standardError.write(
                    Data("  progress: \(i + 1)/\(inputs.count)\r".utf8)
                )
            }
        }
        FileHandle.standardError.write(Data("\n".utf8))

        print("Phase summary (across all per-iteration samples)")
        printPhaseHeader()
        for phase in Phase.allCases where !(phaseSamples[phase] ?? []).isEmpty {
            printPhaseRow(name: phase.label, samples: phaseSamples[phase]!)
        }

        print("")
        print("Top \(config.top) slowest cases (mean total per iteration)")
        let slowest = perCaseTotals
            .sorted { $0.total > $1.total }
            .prefix(config.top)
        let widestID = slowest.map(\.id.count).max() ?? 8
        for entry in slowest {
            let id = entry.id.padding(toLength: widestID, withPad: " ", startingAt: 0)
            print("  \(id)   \(format(entry.total))")
        }
    }

    enum Phase: CaseIterable, Hashable {
        case read, parse, lower, rasterize
        var label: String {
            switch self {
            case .read: return "read"
            case .parse: return "parse"
            case .lower: return "lower"
            case .rasterize: return "rasterize"
            }
        }
    }

    static func printPhaseHeader() {
        print("  " + columns(["phase", "n", "mean", "median", "p95", "max"]))
    }

    static func printPhaseRow(name: String, samples: [Duration]) {
        let sorted = samples.sorted()
        let mean = sorted.reduce(Duration.zero, +) / sorted.count
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let maxV = sorted.last ?? .zero
        print("  " + columns([
            name, "\(sorted.count)",
            format(mean), format(median), format(p95), format(maxV)
        ]))
    }

    /// Renders a fixed 6-column row: first column 10 wide left-aligned,
    /// remaining columns 10 wide right-aligned.
    static func columns(_ cells: [String]) -> String {
        precondition(cells.count == 6)
        let first = cells[0].padding(toLength: 10, withPad: " ", startingAt: 0)
        let rest = cells.dropFirst().map { String(repeating: " ", count: max(0, 10 - $0.count)) + $0 }
        return ([first] + rest).joined(separator: " ")
    }

    static func format(_ d: Duration) -> String {
        let ns = Double(d.components.attoseconds) / 1_000_000_000 + Double(d.components.seconds) * 1_000_000_000
        if ns < 1_000 { return String(format: "%.0f ns", ns) }
        if ns < 1_000_000 { return String(format: "%.2f µs", ns / 1_000) }
        if ns < 1_000_000_000 { return String(format: "%.2f ms", ns / 1_000_000) }
        return String(format: "%.2f s", ns / 1_000_000_000)
    }

    static func parseArgs(_ args: ArraySlice<String>) -> Config {
        var c = Config()
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--iterations", "-n":
                if let v = it.next(), let n = Int(v) { c.iterations = max(1, n) }
            case "--warmup":
                if let v = it.next(), let n = Int(v) { c.warmup = max(0, n) }
            case "--filter", "-f":
                c.filter = it.next()
            case "--top":
                if let v = it.next(), let n = Int(v) { c.top = max(1, n) }
            case "--no-rasterize":
                c.skipRasterize = true
            case "--help", "-h":
                printUsage(); exit(0)
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write(Data("Unknown arg: \(arg)\n".utf8))
                    printUsage(); exit(2)
                }
                c.inputs.append(arg)
            }
        }
        return c
    }

    static func printUsage() {
        print("""
        Usage: swift run -c release Benchmarks [options] [files…]

        Files: zero or more paths. Each may be:
          * an .svg file
          * a directory (recursively scanned for *.svg)
          * a glob pattern (e.g. 'samples/*.svg' or 'corpus/**/*.svg' — quote to
            keep the shell from expanding it; otherwise rely on shell expansion)
        If no files are given, the vendored W3C SVG 1.1 corpus is used.

        Options:
          -n, --iterations N   Timed iterations per case (default 5)
              --warmup N       Untimed warmup iterations per case (default 1)
          -f, --filter STR     Only run cases whose id contains STR
              --top N          Print N slowest cases (default 10)
              --no-rasterize   Skip the SwiftUI ImageRenderer phase
          -h, --help           Show this help
        """)
    }

    /// Expand positional args (files, directories, or glob patterns) into a
    /// flat list of inputs. Directories are walked recursively for *.svg.
    /// Patterns containing wildcard characters are expanded with glob(3).
    static func resolveInputs(_ args: [String]) -> [Input] {
        var out: [Input] = []
        var seen = Set<String>()
        let fm = FileManager.default

        func add(_ url: URL) {
            let resolved = url.standardizedFileURL.path
            guard seen.insert(resolved).inserted else { return }
            let id = url.deletingPathExtension().lastPathComponent
            out.append(Input(id: id, url: URL(fileURLWithPath: resolved)))
        }

        func walk(_ url: URL) {
            guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
            for case let item as URL in en where item.pathExtension.lowercased() == "svg" {
                add(item)
            }
        }

        for raw in args {
            let expanded = (raw as NSString).expandingTildeInPath
            if expanded.contains("*") || expanded.contains("?") || expanded.contains("[") {
                var g = glob_t()
                defer { globfree(&g) }
                if glob(expanded, GLOB_TILDE | GLOB_BRACE, nil, &g) == 0 {
                    let count = Int(g.gl_pathc)
                    for i in 0..<count {
                        if let cstr = g.gl_pathv[i] {
                            let p = String(cString: cstr)
                            let u = URL(fileURLWithPath: p)
                            var isDir: ObjCBool = false
                            if fm.fileExists(atPath: p, isDirectory: &isDir) {
                                if isDir.boolValue { walk(u) } else { add(u) }
                            }
                        }
                    }
                } else {
                    FileHandle.standardError.write(Data("No matches for: \(raw)\n".utf8))
                }
                continue
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
                let u = URL(fileURLWithPath: expanded)
                if isDir.boolValue { walk(u) } else { add(u) }
            } else {
                FileHandle.standardError.write(Data("Not found: \(raw)\n".utf8))
            }
        }
        return out
    }

    /// Locates the vendored W3C suite that lives under the test target's
    /// Resources folder. We resolve relative to this source file rather than
    /// CWD so the executable works from any launch directory.
    static func locateW3CSuite(file: String = #filePath) throws -> URL {
        let here = URL(fileURLWithPath: file)
        // <pkg>/Apps/Benchmarks/main.swift → walk up to package root.
        let pkgRoot = here
            .deletingLastPathComponent()  // Apps/Benchmarks
            .deletingLastPathComponent()  // Apps
            .deletingLastPathComponent()  // <pkg>
        let suite = pkgRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1",
                                    isDirectory: true)
        guard FileManager.default.fileExists(atPath: suite.path) else {
            struct MissingSuite: Error, CustomStringConvertible {
                let path: String
                var description: String { "W3C suite not found at \(path)" }
            }
            throw MissingSuite(path: suite.path)
        }
        return suite
    }
}

private extension Duration {
    /// Nanosecond-precision divide. Sufficient for benchmark aggregation;
    /// avoids Int128 so we stay compatible with macOS 14.
    static func / (lhs: Duration, rhs: Int) -> Duration {
        guard rhs > 0 else { return .zero }
        let nsTotal = Double(lhs.components.seconds) * 1_000_000_000
            + Double(lhs.components.attoseconds) / 1_000_000_000
        let nsPer = nsTotal / Double(rhs)
        let seconds = Int64(nsPer / 1_000_000_000)
        let atto = Int64((nsPer - Double(seconds) * 1_000_000_000) * 1_000_000_000)
        return Duration(secondsComponent: seconds, attosecondsComponent: atto)
    }
}
