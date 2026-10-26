// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "IntelliKit",
  platforms: [.iOS(.v16), .macOS(.v13)],
  products: [
    .library(name: "IntelliKitFoundation", targets: ["IntelliKitFoundation"]),
    .library(name: "IntelliKitImageProcessing", targets: ["IntelliKitImageProcessing"]),
    .library(name: "IntelliKit", targets: ["IntelliKit"]),
  ],
  targets: [
    .target(name: "IntelliKitFoundation", path: "Sources/Foundation"),
    .target(name: "IntelliKitImageProcessing", path: "Sources/ImageProcessing"),
    .target(name: "IntelliKit", dependencies: ["IntelliKitFoundation", "IntelliKitImageProcessing"]),
    .testTarget(name: "IntelliKitTests", dependencies: ["IntelliKit", "IntelliKitFoundation", "IntelliKitImageProcessing"]),
  ]
)
