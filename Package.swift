// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimMediaDrop",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SimMediaDrop",
            path: "Sources/SimMediaDrop"
        )
    ]
)
