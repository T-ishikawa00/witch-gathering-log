// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WitchGameCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WitchGameCore", targets: ["WitchGameCore"])],
    targets: [
        .target(name: "WitchGameCore", resources: [.process("Resources")]),
        .testTarget(name: "WitchGameCoreTests", dependencies: ["WitchGameCore"], resources: [.copy("Fixtures")])
    ]
)
