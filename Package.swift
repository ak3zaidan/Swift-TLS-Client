// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-tls-client",
    platforms: [
        .iOS(.v17) // Specify iOS as the only platform
    ],
    products: [
        .library(
            name: "swift-tls-client",
            targets: ["swift-tls-client"]),
    ],
    targets: [
        .target(
            name: "swift-tls-client",
            dependencies: []),
        .testTarget(
            name: "swift-tls-clientTests",
            dependencies: ["swift-tls-client"]),
    ]
)
