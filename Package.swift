// swift-tools-version: 5.9
import PackageDescription

#if os(Windows)
let ceyloroPlatforms: [SupportedPlatform] = []
let ceyloroProducts: [Product] = [
    .library(name: "CeyloroEngine", type: .static, targets: ["CeyloroEngine"])
]
let ceyloroTargets: [Target] = [
    .target(name: "CeyloroEngine"),
    .testTarget(name: "CeyloroEngineTests", dependencies: ["CeyloroEngine"])
]
#else
let ceyloroPlatforms: [SupportedPlatform] = [.macOS(.v13)]
let ceyloroProducts: [Product] = [
    .executable(name: "Ceyloro", targets: ["Ceyloro"]),
    .library(name: "CeyloroEngine", type: .static, targets: ["CeyloroEngine"])
]
let ceyloroTargets: [Target] = [
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
#endif

let package = Package(
    name: "Ceyloro",
    platforms: ceyloroPlatforms,
    products: ceyloroProducts,
    targets: ceyloroTargets
)
