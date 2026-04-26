// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "go2web",
    platforms: [
        .macOS(.v10_14)
    ],
    targets: [
        .executableTarget(
            name: "go2web"
        )
    ]
)
