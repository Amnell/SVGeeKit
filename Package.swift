// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SVGeeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SVGKit", targets: ["SVGKit"]),
        .library(name: "SVGCore", targets: ["SVGCore"]),
        .library(name: "SVGParser", targets: ["SVGParser"]),
        .library(name: "SVGRenderer", targets: ["SVGRenderer"]),
        .library(name: "SVGRendererSwiftUI", targets: ["SVGRendererSwiftUI"]),
        .library(name: "SVGScript", targets: ["SVGScript"]),
        .library(name: "SVGAnimation", targets: ["SVGAnimation"]),
        .library(name: "SVGConformance", targets: ["SVGConformance"])
    ],
    targets: [
        .target(name: "SVGCore"),
        .target(name: "SVGParser", dependencies: ["SVGCore"]),
        .target(name: "SVGRenderer", dependencies: ["SVGCore"]),
        .target(
            name: "SVGRendererSwiftUI",
            dependencies: ["SVGCore", "SVGParser", "SVGRenderer"]
        ),
        .target(
            name: "SVGScript",
            dependencies: ["SVGCore", "SVGParser", "SVGRenderer", "SVGRendererSwiftUI"],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .target(
            name: "SVGAnimation",
            dependencies: ["SVGCore", "SVGParser", "SVGRenderer", "SVGRendererSwiftUI"]
        ),
        .target(
            name: "SVGKit",
            dependencies: ["SVGCore", "SVGParser", "SVGRenderer", "SVGRendererSwiftUI"]
        ),
        .target(
            name: "SVGConformance",
            dependencies: ["SVGKit", "SVGAnimation"]
        ),
        .executableTarget(
            name: "Viewer",
            dependencies: ["SVGKit", "SVGConformance", "SVGScript", "SVGAnimation"],
            path: "Apps/Viewer"
        ),
        .executableTarget(
            name: "Benchmarks",
            dependencies: ["SVGKit", "SVGConformance"],
            path: "Apps/Benchmarks"
        ),
        .testTarget(name: "SVGCoreTests", dependencies: ["SVGCore"]),
        .testTarget(name: "SVGParserTests", dependencies: ["SVGParser", "SVGRendererSwiftUI", "SVGConformance"]),
        .testTarget(
            name: "SVGRendererTests",
            dependencies: ["SVGParser", "SVGRenderer", "SVGRendererSwiftUI", "SVGConformance"],
            resources: [
                .copy("../SVGConformanceTests/Resources/W3C-SVG-1.1")
            ]
        ),
        .testTarget(
            name: "SVGConformanceTests",
            dependencies: ["SVGConformance"],
            resources: [
                .copy("Resources/W3C-SVG-1.1")
            ]
        ),
        .testTarget(
            name: "SVGScriptTests",
            dependencies: ["SVGScript", "SVGRendererSwiftUI", "SVGConformance"],
            resources: [
                .copy("../SVGConformanceTests/Resources/W3C-SVG-1.1")
            ]
        ),
        .testTarget(
            name: "SVGAnimationTests",
            dependencies: ["SVGAnimation", "SVGParser", "SVGRendererSwiftUI", "SVGConformance"],
            resources: [
                .copy("../SVGConformanceTests/Resources/W3C-SVG-1.1")
            ]
        )
    ]
)
