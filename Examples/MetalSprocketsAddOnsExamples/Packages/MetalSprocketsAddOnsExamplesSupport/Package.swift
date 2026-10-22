// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsAddOnsExamplesSupport",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "MetalSprocketsAddOnsExamplesSupport",
            targets: ["MetalSprocketsAddOnsExamplesSupport"]
        )
    ],
    dependencies: [
        .package(path: "../../../.."),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.4")),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.8")),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.6")),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.1.15")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.10"))
    ],
    targets: [
        .target(
            name: "MetalSprocketsAddOnsExamplesSupport",
            dependencies: [
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftMesh", package: "SwiftMesh")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsAddOnsExamplesSupportTests",
            dependencies: [
                "MetalSprocketsAddOnsExamplesSupport",
                .product(name: "GoldenImage", package: "GoldenImage"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "Interaction3D", package: "Interaction3D")
            ],
            resources: [
                .copy("Golden Images")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
