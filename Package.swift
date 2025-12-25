// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Keystone",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Keystone",
            targets: ["Keystone"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", from: "0.24.0"),
    ],
    targets: [
        .target(
            name: "Keystone",
            dependencies: [
                .product(name: "TreeSitter", package: "tree-sitter"),
            ],
            path: "Sources/Keystone"
        ),
        .testTarget(
            name: "KeystoneTests",
            dependencies: ["Keystone"],
            path: "Tests/KeystoneTests"
        ),
    ]
)
