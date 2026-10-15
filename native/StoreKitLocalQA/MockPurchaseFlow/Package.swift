// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MockPurchaseFlow",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PurchaseFlow", targets: ["PurchaseFlow"])],
    targets: [
        .target(name: "PurchaseFlow"),
        .testTarget(name: "PurchaseFlowTests", dependencies: ["PurchaseFlow"])
    ]
)
