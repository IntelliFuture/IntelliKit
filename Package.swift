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
    .library(name: "IntelliKitNetworking", targets: ["IntelliKitNetworking"]),
    .library(name: "IntelliKitDiskCache", targets: ["IntelliKitDiskCache"]),
    .library(name: "IntelliKit", targets: ["IntelliKit"]),
  ],
  targets: [
    .target(name: "IntelliKitFoundation", path: "Sources/Foundation"),
    .target(name: "IntelliKitImageProcessing", path: "Sources/ImageProcessing"),
    .target(name: "IntelliKitConcurrency", path: "Sources/Concurrency"),
    .target(name: "IntelliKitFiles", path: "Sources/Files"),
    .target(name: "IntelliKitNetworking", path: "Sources/Networking"),
    .target(name: "IntelliKitDiskCache", path: "Sources/DiskCache"),
    .target(name: "IntelliKit", dependencies: ["IntelliKitFoundation", "IntelliKitImageProcessing", "IntelliKitConcurrency", "IntelliKitFiles", "IntelliKitNetworking", "IntelliKitDiskCache"]),
    .testTarget(name: "IntelliKitTests", dependencies: ["IntelliKit", "IntelliKitFoundation", "IntelliKitImageProcessing"]),
    .testTarget(name: "ConcurrencyTests", dependencies: ["IntelliKitConcurrency"]),
    .testTarget(name: "NetworkingTests", dependencies: ["IntelliKitNetworking"]),
    .testTarget(name: "DiskCacheTests", dependencies: ["IntelliKitDiskCache"]),
    .testTarget(name: "FilesTests", dependencies: ["IntelliKitFiles"]),
  ]
)
