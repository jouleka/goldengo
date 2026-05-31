// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Goldengo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoldengoCore", targets: ["GoldengoCore"]),
        .library(name: "GoldengoData", targets: ["GoldengoData"]),
        .library(name: "GoldengoConnectors", targets: ["GoldengoConnectors"]),
        .library(name: "GoldengoDesignSystem", targets: ["GoldengoDesignSystem"]),
        .library(name: "GoldengoFeatures", targets: ["GoldengoFeatures"]),
        .library(name: "GoldengoIntents", targets: ["GoldengoIntents"]),
        .library(name: "GoldengoImport", targets: ["GoldengoImport"]),
    ],
    targets: [
        .target(name: "GoldengoCore"),
        .testTarget(name: "GoldengoCoreTests", dependencies: ["GoldengoCore"]),
        .target(name: "GoldengoConnectors", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoConnectorsTests", dependencies: ["GoldengoConnectors"]),
        .target(name: "GoldengoData", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoDataTests", dependencies: ["GoldengoData"]),
        .target(name: "GoldengoDesignSystem"),
        .testTarget(name: "GoldengoDesignSystemTests", dependencies: ["GoldengoDesignSystem"]),
        .target(name: "GoldengoFeatures", dependencies: ["GoldengoCore", "GoldengoData", "GoldengoConnectors", "GoldengoDesignSystem", "GoldengoImport"]),
        .testTarget(name: "GoldengoFeaturesTests", dependencies: ["GoldengoFeatures"],
                    resources: [.copy("Fixtures/synthetic-statement.pdf")]),
        .target(name: "GoldengoIntents", dependencies: ["GoldengoCore", "GoldengoData"]),
        .testTarget(name: "GoldengoIntentsTests", dependencies: ["GoldengoIntents"]),
        .target(name: "GoldengoImport", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoImportTests", dependencies: ["GoldengoImport"],
                    exclude: ["Fixtures/make_fixture.py"],
                    resources: [.copy("Fixtures/synthetic-statement.pdf")]),
    ]
)
