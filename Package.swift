// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomeloCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PomeloCore", targets: ["PomeloCore"])
    ],
    targets: [
        .target(name: "PomeloCore"),
        .testTarget(name: "PomeloCoreTests", dependencies: ["PomeloCore"])
    ]
)
