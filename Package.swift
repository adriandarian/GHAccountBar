// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GHAccountBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "GHAccountBar", targets: ["GHAccountBar"]),
        .library(name: "GHAccountBarCore", targets: ["GHAccountBarCore"]),
    ],
    targets: [
        .target(
            name: "GHAccountBarCore"
        ),
        .executableTarget(
            name: "GHAccountBar",
            dependencies: ["GHAccountBarCore"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "GHAccountBarTests",
            dependencies: ["GHAccountBarCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
