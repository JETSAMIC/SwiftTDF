// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTDF",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftTDF", targets: ["SwiftTDF"]),
    ],
    targets: [
        .target(name: "SwiftTDF"),
        .testTarget(name: "SwiftTDFTests", dependencies: ["SwiftTDF"]),
    ],
    swiftLanguageModes: [.v6]
)
