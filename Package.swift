// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "ScreenDivider",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ScreenDivider",
            path: "Sources/ScreenDivider"
        )
    ]
)
