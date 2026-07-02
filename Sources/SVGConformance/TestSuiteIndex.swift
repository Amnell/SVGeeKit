import Foundation

/// Discovered case from the vendored test suite.
public struct SVGTestCase: Sendable, Hashable {
    public let id: String
    public let svgURL: URL
    public let referencePNGURL: URL?
    public let tag: SVGFeatureTag
    public let isSkipped: Bool
    public let skipReason: String?
    /// When set, sample declarative SMIL at this document time (seconds) before rasterizing.
    public let sampleAt: Double?
}

/// Optional override entries that complement filename-derived tagging.
public struct SVGTestOverride: Codable, Sendable {
    public var tag: String?
    public var skip: String?
    /// When `true`, overrides a matching `skipTags` entry and forces the test to run.
    public var run: Bool?
    /// Document timeline offset (seconds) for SMIL sampling before render.
    public var sampleAt: Double?
}

/// Top-level shape of `overrides.json`. The file may be either this object
/// or a flat `[String: SVGTestOverride]` map (legacy / minimal cases).
public struct SVGOverridesFile: Codable, Sendable {
    public var skipTags: [String]?
    public var skipReason: String?
    public var tests: [String: SVGTestOverride]?
}

/// Indexes the vendored W3C SVG 1.1 test suite that ships under
/// `Tests/Resources/W3C-SVG-1.1/`.
public struct SVGTestSuiteIndex {

    public let cases: [SVGTestCase]

    /// Loads tests from a vendored W3C-shaped layout:
    ///   <root>/svg/*.svg
    ///   <root>/png/*.png        (optional)
    ///   <root>/overrides.json   (optional)
    public init(rootDirectory root: URL) throws {
        let svgDir = root.appendingPathComponent("svg", isDirectory: true)
        let pngDir = root.appendingPathComponent("png", isDirectory: true)
        let overridesURL = root.appendingPathComponent("overrides.json")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: svgDir.path) else {
            self.cases = []
            return
        }

        let (perTestOverrides, skipTags, defaultSkipReason) = Self.loadOverrides(overridesURL)

        let svgs = try fileManager
            .contentsOfDirectory(at: svgDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "svg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        self.cases = svgs.map { url in
            let filename = url.lastPathComponent
            let id = (filename as NSString).deletingPathExtension
            let overrideEntry = perTestOverrides[id]
            let tag: SVGFeatureTag = {
                if let raw = overrideEntry?.tag, let t = SVGFeatureTag(rawValue: raw) { return t }
                return SVGFeatureTag.fromW3CFilename(filename)
            }()
            let png = pngDir.appendingPathComponent("\(id).png")
            let pngExists = fileManager.fileExists(atPath: png.path)

            let (skipped, reason) = Self.skipDecision(
                explicit: overrideEntry?.skip,
                run: overrideEntry?.run,
                tag: tag,
                skipTags: skipTags,
                defaultReason: defaultSkipReason
            )

            return SVGTestCase(
                id: id,
                svgURL: url,
                referencePNGURL: pngExists ? png : nil,
                tag: tag,
                isSkipped: skipped,
                skipReason: reason,
                sampleAt: overrideEntry?.sampleAt
            )
        }
    }

    private static func loadOverrides(
        _ url: URL
    ) -> (perTest: [String: SVGTestOverride], skipTags: Set<SVGFeatureTag>, defaultReason: String?) {
        guard let data = try? Data(contentsOf: url) else {
            return ([:], [], nil)
        }
        let decoder = JSONDecoder()
        // Preferred shape: structured object with `skipTags` / `tests`.
        if let file = try? decoder.decode(SVGOverridesFile.self, from: data) {
            let tagSet = Set((file.skipTags ?? []).compactMap { SVGFeatureTag(rawValue: $0) })
            return (file.tests ?? [:], tagSet, file.skipReason)
        }
        // Legacy shape: flat per-test map.
        let flat = (try? decoder.decode([String: SVGTestOverride].self, from: data)) ?? [:]
        return (flat, [], nil)
    }

    private static func skipDecision(
        explicit: String?,
        run: Bool?,
        tag: SVGFeatureTag,
        skipTags: Set<SVGFeatureTag>,
        defaultReason: String?
    ) -> (Bool, String?) {
        if let explicit { return (true, explicit) }
        if run == true { return (false, nil) }
        if skipTags.contains(tag) {
            return (true, defaultReason ?? "feature family not yet supported")
        }
        return (false, nil)
    }
}
