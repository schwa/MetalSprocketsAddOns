// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsAddOns",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "MetalSprocketsAddOns", targets: ["MetalSprocketsAddOns"]),
        .library(name: "MetalSprocketsAddOnsShaders", targets: ["MetalSprocketsAddOnsShaders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/schwa/GeometryLite3D", from: "0.1.0"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", from: "0.1.4"),
        .package(url: "https://github.com/schwa/MetalSupport", from: "1.0.1"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MetalSprocketsAddOns",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                "MetalSprocketsAddOnsShaders",
            ],
        ),
        .target(
            name: "MetalSprocketsAddOnsShaders",
            dependencies: [
                .product(name: "MetalSprocketsShaders", package: "MetalSprockets"),
            ],
            exclude: ["Metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsAddOnsTests",
            dependencies: [
                "MetalSprocketsAddOns",
                "MetalSprocketsAddOnsShaders",
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            resources: [
                .copy("Golden Images")
            ],
        ),

    ]
)
