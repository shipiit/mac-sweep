// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacSweep",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MacSweep", targets: ["MacSweep"]),
    ],
    targets: [
        .target(name: "MacSweepCore"),
        .executableTarget(name: "MacSweep", dependencies: ["MacSweepCore"]),
        .testTarget(name: "MacSweepCoreTests", dependencies: ["MacSweepCore"]),
    ],
    swiftLanguageModes: [.v5]
)
