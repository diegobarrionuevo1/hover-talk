// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HoverTalk",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "HoverTalk", targets: ["HoverTalk"]),
    ],
    targets: [
        // Pure, unit-testable logic. Rule: Foundation, CoreGraphics and NaturalLanguage only, never AppKit.
        .target(
            name: "HoverTalkCore"
        ),
        // AppKit menu-bar app entry point.
        .executableTarget(
            name: "HoverTalk",
            dependencies: ["HoverTalkCore"]
        ),
        // Development only, never bundled into the app: sanitizes screen captures into
        // public test fixtures. Rule: Foundation only.
        .target(
            name: "HoverTalkFixtureKit"
        ),
        // Development only: `swift run HoverTalkCapture` writes sanitized fixtures. Not a declared
        // product; `scripts/bundle.sh` builds only the `HoverTalk` product, so it is never bundled.
        .executableTarget(
            name: "HoverTalkCapture",
            dependencies: ["HoverTalkFixtureKit"]
        ),
        .testTarget(
            name: "HoverTalkCoreTests",
            dependencies: ["HoverTalkCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HoverTalkFixtureKitTests",
            dependencies: ["HoverTalkFixtureKit"]
        ),
    ]
)
