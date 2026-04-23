// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LfhHelpWidget",
    platforms: [
        // Library targets iOS only; macOS is supported solely so pure-logic
        // tests (Identity, LfhHelpClient) run under `swift test` on CI.
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "LfhHelpWidget", targets: ["LfhHelpWidget"]),
    ],
    targets: [
        .target(
            name: "LfhHelpWidget",
            path: "Sources/LfhHelpWidget"
        ),
        .testTarget(
            name: "LfhHelpWidgetTests",
            dependencies: ["LfhHelpWidget"],
            path: "Tests/LfhHelpWidgetTests"
        ),
    ]
)
