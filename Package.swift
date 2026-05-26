// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Zyquo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "zyquo", targets: ["Zyquo"]),
        .library(name: "ZyquoCore", targets: ["ZyquoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Zyquo",
            dependencies: [
                "ZyquoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/Zyquo",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "ZyquoCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/ZyquoCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ZyquoTests",
            dependencies: ["Zyquo", "ZyquoCore"],
            path: "Tests/ZyquoTests"
        ),
        .testTarget(
            name: "ZyquoCoreTests",
            dependencies: ["ZyquoCore"],
            path: "Tests/ZyquoCoreTests"
        ),
    ]
)
