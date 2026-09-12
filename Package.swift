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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "SnapTradeMenuBarApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SnapTradeMenuBarApp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "SnapTradeMenuBarAppTests",
            dependencies: ["SnapTradeMenuBarApp"],
            path: "Tests/SnapTradeMenuBarAppTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
