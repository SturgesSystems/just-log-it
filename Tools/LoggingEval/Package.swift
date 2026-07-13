// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LoggingEval",
  platforms: [
    // Generable / Foundation Models APIs need 26.4+; host is macOS 27 beta.
    .macOS(.v26)
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
    )
  ]
)
