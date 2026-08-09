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
        .package(url: "https://github.com/schwa/GeometryLite3D", from: "0.1.0"),
        .package(url: "https://github.com/schwa/MetalSupport", from: "1.0.3"),
        .package(url: "https://github.com/schwa/MetalSprockets", from: "0.1.11")
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
                .product(name: "MetalSprocketsUI", package: "MetalSprockets")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsAddOnsExamplesSupportTests",
            dependencies: ["MetalSprocketsAddOnsExamplesSupport"]
        )
    ],
    swiftLanguageModes: [.v6]
)
