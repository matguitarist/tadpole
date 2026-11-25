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
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.2.1"),
        .package(url: "https://github.com/matguitarist/ArchiveKit", from: "0.2.0"),
        .package(url: "https://github.com/matguitarist/DownloadKit", from: "0.2.0"),
    ],
    targets: [
        .target(name: "TadpoleCore", dependencies: [
            .product(name: "ProcessKit", package: "ProcessKit"),
            .product(name: "ArchiveKit", package: "ArchiveKit"),
            .product(name: "DownloadKit", package: "DownloadKit"),
        ]),
        .testTarget(name: "TadpoleCoreTests", dependencies: [
            "TadpoleCore",
            .product(name: "ProcessKit", package: "ProcessKit"),
            .product(name: "ArchiveKit", package: "ArchiveKit"),
            .product(name: "DownloadKit", package: "DownloadKit"),
        ]),
    ]
)
