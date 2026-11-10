// swift-tools-version: 6.0
import PackageDescription

// Pure Swift, no UIKit: calendar logic, page-template geometry and text rules.
// Runs on macOS too, so `swift test` works without a simulator.
let package = Package(
    name: "PlannerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlannerCore", targets: ["PlannerCore"]),
    ],
    targets: [
        .target(name: "PlannerCore"),
        .testTarget(name: "PlannerCoreTests", dependencies: ["PlannerCore"]),
    ]
)
