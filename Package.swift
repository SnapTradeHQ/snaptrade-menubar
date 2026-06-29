// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SnapTradeMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SnapTradeMenuBar", targets: ["SnapTradeMenuBarApp"])
    ],
    targets: [
        .executableTarget(
            name: "SnapTradeMenuBarApp",
            path: "Sources/SnapTradeMenuBarApp"
        )
    ]
)
