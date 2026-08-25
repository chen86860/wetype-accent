// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "wetype-accent",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "wetype-accent", targets: ["WeTypeAccent"]),
    .library(name: "WeTypeAccentCore", targets: ["WeTypeAccentCore"]),
  ],
  targets: [
    .target(name: "WeTypeAccentCore"),
    .executableTarget(
      name: "WeTypeAccent",
      dependencies: ["WeTypeAccentCore"]
    ),
    .testTarget(
      name: "WeTypeAccentCoreTests",
      dependencies: ["WeTypeAccentCore"]
    ),
  ]
)
