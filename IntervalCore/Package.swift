// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntervalCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IntervalCore", targets: ["IntervalCore"]),
    ],
    targets: [
        .target(name: "IntervalCore"),
        .testTarget(name: "IntervalCoreTests", dependencies: ["IntervalCore"]),
    ]
)
