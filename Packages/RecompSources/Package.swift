// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecompSources",
    platforms: [.tvOS(.v17), .macOS(.v13)],
    products: [.library(name: "RecompSources", targets: ["RecompSources"])],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git",
                 revision: "1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0"),
    ],
    targets: [
        .target(name: "RecompSources", dependencies: ["AMSMB2"],
                resources: [.process("Resources")]),
        .testTarget(name: "RecompSourcesTests", dependencies: ["RecompSources"]),
    ]
)
