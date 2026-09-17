// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DuoBar",
            path: "Sources/DuoBar"
        )
    ]
)
