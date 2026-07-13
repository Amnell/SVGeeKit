import Foundation
import Testing
import SVGCore
import SVGParser
import SVGRendererSwiftUI

@Suite("Hostile input")
struct HostileInputTests {

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 1 : seed
        }

        mutating func next() -> UInt64 {
            state ^= state << 7
            state ^= state >> 9
            return state
        }
    }

    private func randomData(count: Int, rng: inout SeededRNG) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<count {
                base[index] = UInt8.random(in: 0...255, using: &rng)
            }
        }
        return data
    }

    @Test func randomBytesDoNotTrapOnParse() {
        var rng = SeededRNG(seed: 0x5EED)
        for _ in 0..<256 {
            let count = Int.random(in: 0...8_192, using: &rng)
            let data = randomData(count: count, rng: &rng)
            _ = try? SVGParser().parseWithReport(data: data)
        }
    }

    @Test func malformedXMLThrows() {
        #expect(throws: SVGParseError.self) {
            _ = try SVGParser().parse(string: "<svg><rect")
        }
    }

    @MainActor
    @Test func svgImageViewSurvivesRandomBytes() {
        var rng = SeededRNG(seed: 0xB1EE)
        for _ in 0..<64 {
            let count = Int.random(in: 0...4_096, using: &rng)
            let data = randomData(count: count, rng: &rng)
            _ = SVGImageView(svgData: data)
        }
    }

    @Test func w3cCorpusSurvivesProductionParse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SVGConformanceTests/Resources/W3C-SVG-1.1/svg", isDirectory: true)
            .standardizedFileURL
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "svg" }

        #expect(urls.count >= 500)
        let parser = SVGParser()
        for url in urls {
            let data = try Data(contentsOf: url)
            _ = try? parser.parseWithReport(data: data)
        }
    }
}
