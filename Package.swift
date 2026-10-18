// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Speak2Text",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.1.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5"),
    ],
    targets: [
        .executableTarget(
            name: "Speak2Text",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Speak2Text",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
