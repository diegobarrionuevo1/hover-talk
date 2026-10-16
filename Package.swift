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
        // Pure, unit-testable logic. Rule: import Foundation/CoreGraphics only, never AppKit.
        .target(
            name: "HoverTalkCore"
        ),
        // AppKit menu-bar app entry point.
        .executableTarget(
            name: "HoverTalk",
            dependencies: ["HoverTalkCore"]
        ),
        .testTarget(
            name: "HoverTalkCoreTests",
            dependencies: ["HoverTalkCore"]
        ),
    ]
)
