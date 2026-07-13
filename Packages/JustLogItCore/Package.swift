// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JustLogItCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "JustLogItCore", targets: ["JustLogItCore"])
    ],
    targets: [
        .target(name: "JustLogItCore"),
        .testTarget(name: "JustLogItCoreTests", dependencies: ["JustLogItCore"])
    ]
)
