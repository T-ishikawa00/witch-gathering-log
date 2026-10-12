// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WitchReviewProbe", dependencies: [.package(path: "../../native/WitchGameCore")], targets: [.testTarget(name: "ReviewProbe", dependencies: [.product(name: "WitchGameCore", package: "WitchGameCore")])])
