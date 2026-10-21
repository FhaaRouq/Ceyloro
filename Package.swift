// swift-tools-version: 5.9
import PackageDescription

#if os(Windows)
let ceyloroPlatforms: [SupportedPlatform] = []
#else
let ceyloroPlatforms: [SupportedPlatform] = [.macOS(.v13)]
#endif

let package = Package(
    name: "Ceyloro",
    platforms: ceyloroPlatforms,
    products: [
        .executable(name: "Ceyloro", targets: ["Ceyloro"]),
        .library(name: "CeyloroEngine", type: .static, targets: ["CeyloroEngine"])
    ],
    targets: [
        .target(name: "CeyloroEngine"),
        .target(name: "CeyloroCore"),
        .executableTarget(
            name: "Ceyloro",
            dependencies: ["CeyloroCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "CeyloroEngineTests", dependencies: ["CeyloroEngine"]),
        .testTarget(name: "CeyloroCoreTests", dependencies: ["CeyloroCore"]),
        .testTarget(name: "CeyloroAppTests", dependencies: ["Ceyloro"])
    ]
)
