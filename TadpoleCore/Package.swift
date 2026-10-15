// swift-tools-version: 6.0
import PackageDescription

// BG3 file formats and mod logic, kept free of UI code so it can be tested
// on its own (`swift test` here, or ⌘U in Xcode).
let package = Package(
    name: "TadpoleCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TadpoleCore", targets: ["TadpoleCore"]),
    ],
    targets: [
        .target(name: "TadpoleCore"),
        .testTarget(name: "TadpoleCoreTests", dependencies: ["TadpoleCore"]),
    ]
)
