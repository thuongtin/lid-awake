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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(name: "LidAwakeCore"),
        .executableTarget(
            name: "LidAwake",
            dependencies: [
                "LidAwakeCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "@executable_path/../Frameworks"
                ])
            ]
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
