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
        .package(url: "https://github.com/blaineam/TreeSitterLanguages", from: "2.0.0"),
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
                .product(name: "TreeSitterJava", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPHP", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSQL", package: "TreeSitterLanguages"),
                // Highlight query files
                .product(name: "TreeSitterSwiftQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPythonQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSONQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTMLQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSSQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCPPQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterGoQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRustQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRubyQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBashQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterYAMLQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPHPQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSQLQueries", package: "TreeSitterLanguages"),
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
