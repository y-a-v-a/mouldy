// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mould",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mould", targets: ["MouldApp"]),
    ],
    targets: [
        .target(name: "MouldCore"),
        .target(name: "MouldRender", dependencies: ["MouldCore"]),
        .executableTarget(name: "MouldApp", dependencies: ["MouldCore", "MouldRender"]),
        .testTarget(name: "MouldCoreTests", dependencies: ["MouldCore"]),
        .testTarget(name: "MouldRenderTests", dependencies: ["MouldCore", "MouldRender"]),
    ]
)
