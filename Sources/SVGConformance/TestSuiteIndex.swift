import Foundation

/// Discovered case from the vendored test suite.
public struct SVGTestCase: Sendable, Hashable {
    public let id: String
    public let svgURL: URL
    public let referencePNGURL: URL?
    public let tag: SVGFeatureTag
    public let isSkipped: Bool
    public let skipReason: String?
}

/// Optional override entries that complement filename-derived tagging.
public struct SVGTestOverride: Codable, Sendable {
    public var tag: String?
    public var skip: String?
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

        let overrides: [String: SVGTestOverride] = {
            guard let data = try? Data(contentsOf: overridesURL) else { return [:] }
            return (try? JSONDecoder().decode([String: SVGTestOverride].self, from: data)) ?? [:]
        }()

        let svgs = try fileManager
            .contentsOfDirectory(at: svgDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "svg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        self.cases = svgs.map { url in
            let filename = url.lastPathComponent
            let id = (filename as NSString).deletingPathExtension
            let overrideEntry = overrides[id]
            let tag: SVGFeatureTag = {
                if let raw = overrideEntry?.tag, let t = SVGFeatureTag(rawValue: raw) { return t }
                return SVGFeatureTag.fromW3CFilename(filename)
            }()
            let png = pngDir.appendingPathComponent("\(id).png")
            let pngExists = fileManager.fileExists(atPath: png.path)
            return SVGTestCase(
                id: id,
                svgURL: url,
                referencePNGURL: pngExists ? png : nil,
                tag: tag,
                isSkipped: overrideEntry?.skip != nil,
                skipReason: overrideEntry?.skip
            )
        }
    }
}
