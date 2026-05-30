// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Goldengo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoldengoCore", targets: ["GoldengoCore"]),
    ],
    targets: [
        .target(name: "GoldengoCore"),
        .testTarget(name: "GoldengoCoreTests", dependencies: ["GoldengoCore"]),
    ]
)
