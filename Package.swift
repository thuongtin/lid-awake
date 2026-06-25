// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LidAwakeCore", targets: ["LidAwakeCore"]),
        .executable(name: "LidAwake", targets: ["LidAwake"]),
        .executable(name: "LidAwakeHelper", targets: ["LidAwakeHelper"])
    ],
    targets: [
        .target(name: "LidAwakeCore"),
        .executableTarget(
            name: "LidAwake",
            dependencies: ["LidAwakeCore"]
        ),
        .executableTarget(
            name: "LidAwakeHelper",
            dependencies: ["LidAwakeCore"]
        ),
        .testTarget(
            name: "LidAwakeCoreTests",
            dependencies: ["LidAwakeCore"]
        ),
        .testTarget(
            name: "LidAwakeTests",
            dependencies: [
                "LidAwake",
                "LidAwakeCore"
            ]
        )
    ]
)
