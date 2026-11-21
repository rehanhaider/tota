// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tota",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Tota",
            path: "Sources/Tota",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
