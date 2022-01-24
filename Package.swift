// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MNAVChapters",
    platforms: [
        .macOS("10.15.4"),
        .iOS("13.4")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MNAVChapters",
            targets: ["MNAVChapters"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "MNAVChapters",
            cxxSettings: [
                .headerSearchPath("../MNAVChapters/include"),
                .define("TARGET_OS_OSX", to: "1", .when(platforms: [.macOS]))
            ]
        ),
    ]
)
