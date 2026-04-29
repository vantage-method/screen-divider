// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "ScreenDivider",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ScreenDivider",
            path: "Sources/ScreenDivider"
        )
    ]
)
