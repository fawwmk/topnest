// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TopNest",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "TopNest", targets: ["TopNest"])
    ],
    targets: [
        .executableTarget(
            name: "TopNest",
            path: "Sources/Vidget"
        )
    ]
)
