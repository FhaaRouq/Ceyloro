// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pomelo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pomelo", targets: ["Pomelo"])
    ],
    targets: [
        .target(name: "PomeloCore"),
        .executableTarget(
            name: "Pomelo",
            dependencies: ["PomeloCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "PomeloCoreTests", dependencies: ["PomeloCore"]),
        .testTarget(name: "PomeloAppTests", dependencies: ["Pomelo"])
    ]
)
