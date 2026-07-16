// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TunnelDetourCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TunnelDetourCore", targets: ["TunnelDetourCore"]),
        .executable(name: "TunnelDetourApp", targets: ["TunnelDetourApp"]),
        .executable(name: "TunnelDetourHelper", targets: ["TunnelDetourHelper"])
    ],
    targets: [
        .target(
            name: "TunnelDetourCore",
            path: "Sources/TunnelDetourCore"
        ),
        .executableTarget(
            name: "TunnelDetourApp",
            dependencies: ["TunnelDetourCore"],
            path: "Sources/TunnelDetourApp"
        ),
        .executableTarget(
            name: "TunnelDetourHelper",
            dependencies: ["TunnelDetourCore"],
            path: "Sources/TunnelDetourHelper"
        ),
        .testTarget(
            name: "TunnelDetourTests",
            dependencies: ["TunnelDetourCore"],
            path: "Tests/TunnelDetourTests"
        )
    ]
)
