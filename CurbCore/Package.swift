// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CurbCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CurbCore", targets: ["CurbCore"]),
        .executable(name: "curbeval", targets: ["curbeval"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CurbCore",
            exclude: ["Model/.gitkeep", "Engine/.gitkeep", "Parse/.gitkeep", "Vision/.gitkeep"]
        ),
        .executableTarget(
            name: "curbeval",
            dependencies: [
                "CurbCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CurbCoreTests",
            dependencies: ["CurbCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
