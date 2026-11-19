// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StayLitCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StayLitCore", targets: ["StayLitCore"]),
    ],
    targets: [
        .target(name: "StayLitCore"),
        .testTarget(name: "StayLitCoreTests", dependencies: ["StayLitCore"]),
    ],
    swiftLanguageModes: [.v6]
)
