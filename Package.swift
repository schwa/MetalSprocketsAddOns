// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MetalSprocketsAddOns",
    platforms: [
        .iOS("18.5"),
        .macOS("15.5"),
        .visionOS("2.5")
    ],
    products: [
        .library(name: "MetalSprocketsAddOns", targets: ["MetalSprocketsAddOns"]),
        .library(name: "MetalSprocketsAddOnsShaders", targets: ["MetalSprocketsAddOnsShaders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/earcut-swift", from: "0.1.0"),
        .package(url: "https://github.com/schwa/GeometryLite3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", from: "0.1.4"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MetalSprocketsAddOns",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "earcut", package: "earcut-swift"),
                "MetalSprocketsAddOnsShaders",
                "MikkTSpace",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .target(
            name: "MetalSprocketsAddOnsShaders",
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
            ],
            resources: [
                .copy("Golden Images")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .target(
            name: "MikkTSpace",
            publicHeadersPath: ".",
        )
    ]
)
