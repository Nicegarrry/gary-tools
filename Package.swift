// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GaryTools",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GaryTools", targets: ["GaryTools"])],
    targets: [
        .target(
            name: "MenuBarBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "GaryCore",
            dependencies: []
        ),
        .executableTarget(
            name: "GaryTools",
            dependencies: ["GaryCore", "MenuBarBridge"]
        ),
        .testTarget(
            name: "GaryToolsTests",
            dependencies: ["GaryCore", "GaryTools"],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)
