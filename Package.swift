// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Consolepilot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ConsolepilotAppBinary", targets: ["Consolepilot"]),
        .executable(name: "consolepilot", targets: ["ConsolepilotCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "ConsolepilotCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            path: "Sources",
            exclude: ["App", "CLI"],
            resources: [.process("Infrastructure/Config/DefaultConfig.toml")]
        ),
        .executableTarget(
            name: "Consolepilot",
            dependencies: ["ConsolepilotCore"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "ConsolepilotCLI",
            dependencies: ["ConsolepilotCore"],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "ConsolepilotTests",
            dependencies: ["ConsolepilotCore"],
            path: "Tests"
        ),
    ]
)
