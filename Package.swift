// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TopNest",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "TopNest", targets: ["TopNest"]),
        .library(
            name: "TopNestMediaHelper",
            type: .dynamic,
            targets: ["TopNestMediaHelper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TopNest",
            path: "Sources/Vidget"
        ),
        .target(
            name: "TopNestMediaHelper",
            path: "Sources/TopNestMediaHelper",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
