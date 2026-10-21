// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ceyloro",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Ceyloro", targets: ["Ceyloro"])
    ],
    targets: [
        .target(name: "CeyloroCore"),
        .executableTarget(
            name: "Ceyloro",
            dependencies: ["CeyloroCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "CeyloroCoreTests", dependencies: ["CeyloroCore"]),
        .testTarget(name: "CeyloroAppTests", dependencies: ["Ceyloro"])
    ]
)
