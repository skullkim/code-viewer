// swift-tools-version: 6.0
import PackageDescription

// Mirror of the frontend targets so the pure logic can be developed test-first while the
// real package manifest is being updated. File paths match the destination exactly.
let package = Package(
    name: "CodeNavigatorAppKitMirror",
    platforms: [.macOS(.v14)],
    targets: [
        // Symlinked to the real contract sources so the logic is developed against the
        // actual types, never a copy that could drift from them.
        .target(name: "CodeNavigatorContract"),
        .target(name: "CodeNavigatorAppKit", dependencies: ["CodeNavigatorContract"]),
        .testTarget(name: "CodeNavigatorAppKitTests", dependencies: ["CodeNavigatorAppKit", "CodeNavigatorContract"]),
    ]
)
