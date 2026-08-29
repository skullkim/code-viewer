// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeNavigator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodeNavigatorContract", targets: ["CodeNavigatorContract"]),
        .library(name: "CodeNavigatorCore", targets: ["CodeNavigatorCore"]),
        .executable(name: "CodeNavigator", targets: ["CodeNavigatorApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-kotlin", from: "1.1.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.23.5"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.2"),
    ],
    targets: [
        // The machine contract: value types + protocols shared by Core and App.
        // Deliberately has no dependencies, so a breaking change fails BOTH sides at compile time.
        .target(name: "CodeNavigatorContract"),

        // Engine: indexing, scanning, searching, watching, Neovim session. No UI.
        .target(
            name: "CodeNavigatorCore",
            dependencies: [
                "CodeNavigatorContract",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
            ]
        ),

        // SwiftUI application shell. Owned by frontend; depends on the contract,
        // and on Core only at the composition root.
        // App logic lives in a library target so it can carry tests; the executable
        // is only an entry point.
        .target(
            name: "CodeNavigatorAppKit",
            dependencies: ["CodeNavigatorContract", "CodeNavigatorCore"]
        ),
        .executableTarget(
            name: "CodeNavigatorApp",
            dependencies: ["CodeNavigatorAppKit"]
        ),

        .testTarget(
            name: "CodeNavigatorCoreTests",
            dependencies: ["CodeNavigatorCore", "CodeNavigatorContract"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CodeNavigatorAppKitTests",
            dependencies: ["CodeNavigatorAppKit", "CodeNavigatorContract"]
        ),
    ]
)
