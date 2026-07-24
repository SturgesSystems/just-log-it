// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LoggingEval",
  platforms: [
    // Usage metrics and capability-aware reasoning context options are macOS 27 APIs.
    .macOS("27.0")
  ],
  products: [
    .executable(name: "logging-eval", targets: ["LoggingEval"])
  ],
  dependencies: [
    .package(path: "../../Packages/JustLogItCore")
  ],
  targets: [
    .executableTarget(
      name: "LoggingEval",
      dependencies: [
        .product(name: "JustLogItCore", package: "JustLogItCore")
      ]
    ),
    .testTarget(
      name: "LoggingEvalTests",
      dependencies: [
        "LoggingEval",
        .product(name: "JustLogItCore", package: "JustLogItCore"),
      ]
    ),
  ]
)
