// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsAddOns",
    products: [
        .library(
            name: "MetalSprocketsAddOns",
            targets: ["MetalSprocketsAddOns"]
        ),
    ],
    targets: [
        .target(
            name: "MetalSprocketsAddOns"
        ),
        .testTarget(
            name: "MetalSprocketsAddOnsTests",
            dependencies: ["MetalSprocketsAddOns"]
        ),
    ]
)
