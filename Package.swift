// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Fabric",
    platforms: [.macOS(.v15), .iOS(.v18), .visionOS(.v2)],
    products: [
        .library(
            name: "Fabric",
            targets: ["Fabric"]
        ),
    ],
    dependencies: [
        // Local Satin package
        .package(path: "Satin"),

        // External dependencies
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.29.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.29.1"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/tayloraswift/swift-noise", from: "1.0.0"),
        .package(url: "https://github.com/vade/SwiftSimplify", branch: "master"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.1"),
        .package(url: "https://github.com/bradhowes/swift-math-parser", from: "3.5.0"),
        .package(url: "https://github.com/orchetect/OSCKit", from: "2.1.1"),
        .package(url: "https://github.com/orchetect/MIDIKit", from: "0.10.7"),
    ],
    targets: [
        // C++ support for SuperShapeGenerator
        .target(
            name: "FabricCore",
            dependencies: [
                .product(name: "SatinCore", package: "Satin"),
            ],
            path: "Fabric/Nodes/Geometry/SuperShape",
            sources: ["SuperShapeGenerator.mm"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
                .unsafeFlags(["-I", "Satin/Sources/SatinCore/include"]),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .unsafeFlags(["-I", "Satin/Sources/SatinCore/include"]),
            ]
        ),

        // Main Fabric framework
        .target(
            name: "Fabric",
            dependencies: [
                "FabricCore",
                .product(name: "Satin", package: "Satin"),
                .product(name: "SatinCore", package: "Satin"),
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLinalg", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Noise", package: "swift-noise"),
                .product(name: "SwiftSimplify", package: "SwiftSimplify"),
                .product(name: "Textual", package: "textual"),
                .product(name: "MathParser", package: "swift-math-parser"),
                .product(name: "OSCKit", package: "OSCKit"),
                .product(name: "MIDIKit", package: "MIDIKit"),
                .target(name: "Syphon", condition: .when(platforms: [.macOS])),
            ],
            path: "Fabric",
            exclude: [
                "Nodes/Geometry/SuperShape/SuperShapeGenerator.mm",
                "Nodes/Geometry/SuperShape/SuperShapeGenerator.h",
                "Nodes/Deprecated",
                "Nodes/Parameters/Number/Deprecated",
                "module.modulemap",
                "Fabric.h",
                "Fabric.docc",
            ],
            resources: [
                .copy("Effects"),
                .copy("EffectsTwoChannel"),
                .copy("EffectsThreeChannel"),
                .copy("Compute"),
                .copy("Shaders"),
                .copy("Materials"),
                .process("Fabric.xcassets"),
                .copy("lygia"),
            ],
            swiftSettings: [
                .define("FABRIC_SYPHON_ENABLED", .when(platforms: [.macOS])),
            ]
        ),

        // Syphon binary target (macOS only)
        .binaryTarget(
            name: "Syphon",
            path: "Frameworks/Syphon.xcframework"
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
