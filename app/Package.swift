// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "brbui",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "brbui",
      path: "Sources/brbui",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "brbuiTests",
      dependencies: ["brbui"],
      path: "Tests/brbuiTests",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
