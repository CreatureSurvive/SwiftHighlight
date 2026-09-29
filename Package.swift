// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftHighlight",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftHighlight", targets: ["SwiftHighlight"]),
    ],
    targets: [
        .target(
            name: "SwiftHighlight",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .executableTarget(
            name: "SwiftHighlightBenchmarks",
            dependencies: ["SwiftHighlight"]
        ),
        .testTarget(
            name: "SwiftHighlightTests",
            dependencies: ["SwiftHighlight"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
