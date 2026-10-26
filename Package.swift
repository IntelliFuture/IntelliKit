// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "IntelliKit",
  platforms: [.iOS(.v16), .macOS(.v13)],
  products: [
    .library(name: "IntelliKitFoundation", targets: ["IntelliKitFoundation"]),
    .library(name: "IntelliKitImageProcessing", targets: ["IntelliKitImageProcessing"]),
    .library(name: "IntelliKitConcurrency", targets: ["IntelliKitConcurrency"]),
    .library(name: "IntelliKitFiles", targets: ["IntelliKitFiles"]),
    .library(name: "IntelliKit", targets: ["IntelliKit"]),
  ],
  targets: [
    .target(name: "IntelliKitFoundation", path: "Sources/Foundation"),
    .target(name: "IntelliKitImageProcessing", path: "Sources/ImageProcessing"),
    .target(name: "IntelliKitConcurrency", path: "Sources/Concurrency"),
    .target(name: "IntelliKitFiles", path: "Sources/Files"),
    .target(name: "IntelliKit", dependencies: ["IntelliKitFoundation", "IntelliKitImageProcessing", "IntelliKitConcurrency", "IntelliKitFiles"]),
    .testTarget(name: "IntelliKitTests", dependencies: ["IntelliKit", "IntelliKitFoundation", "IntelliKitImageProcessing"]),
    .testTarget(name: "ConcurrencyTests", dependencies: ["IntelliKitConcurrency"]),
    .testTarget(name: "FilesTests", dependencies: ["IntelliKitFiles"]),
  ]
)
