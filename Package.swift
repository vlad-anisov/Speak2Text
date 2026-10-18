// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "dictate",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "dictate",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/dictate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
