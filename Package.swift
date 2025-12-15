// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cached-data",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CachedData",
            targets: ["CachedData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data.git", from: "1.4.0"),
        .package(url: "https://github.com/FlineDev/ErrorKit.git", from: "1.2.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CachedData",
            dependencies: [
                .product(name: "ErrorKit", package: "ErrorKit"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(
            name: "CachedDataTests",
            dependencies: ["CachedData"],
        ),
    ]
)
