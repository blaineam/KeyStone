// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Keystone",
    defaultLocalization: "en",
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
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.20.9")),
        .package(url: "https://github.com/blaineam/TreeSitterLanguages", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Keystone",
            dependencies: [
                .product(name: "TreeSitter", package: "tree-sitter"),
                // Language parsers
                .product(name: "TreeSitterSwift", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPython", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSON", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSS", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterC", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCPP", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterGo", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRust", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRuby", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBash", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterYAML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterLanguages"),
            ],
            path: "Sources/Keystone",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .process("TextView/Appearance/Theme.xcassets")
            ]
        ),
        .testTarget(
            name: "KeystoneTests",
            dependencies: ["Keystone"],
            path: "Tests/KeystoneTests"
        ),
    ]
)
