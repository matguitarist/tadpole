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
    dependencies: [
        // The Script Extender's log is parsed and shown with the log viewer the apps share.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.3.0"),
    ],
    targets: [
        .target(name: "TadpoleCore", dependencies: [.product(name: "LogKit", package: "LogKit")]),
        .testTarget(name: "TadpoleCoreTests", dependencies: ["TadpoleCore"]),
    ]
)
