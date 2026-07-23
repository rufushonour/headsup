// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HeadsUp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "HeadsUp",
            path: "Sources/HeadsUp"
        )
    ]
)
