// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Hwp-Swift",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "CoreHwp", targets: ["CoreHwp"]),
        .library(name: "HwpKitCore", targets: ["HwpKitCore"]),
        .library(name: "HwpKitNative", targets: ["HwpKitNative"]),
        .library(name: "HwpKit", targets: ["HwpKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/OLEKit.git", exact: "0.3.1"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1"),

        .package(url: "https://github.com/Quick/Nimble", exact: "13.8.0"),

        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CoreHwp",
            dependencies: [
                "OLEKit",
                "SWCompression",
            ],
            exclude: [
                "AGENTS.md",
                "Models/Section/AGENTS.md",
                "Utils/AGENTS.md",
            ]
        ),
        .target(
            name: "HwpKitCore",
            dependencies: [
                "CoreHwp",
            ]
        ),
        .target(
            name: "HwpKitNative",
            dependencies: [
                "HwpKitCore",
                "CoreHwp",
            ]
        ),
        .target(
            name: "HwpKit",
            dependencies: [
                "HwpKitNative",
            ]
        ),
        .testTarget(
            name: "CoreHwpTests",
            dependencies: [
                "CoreHwp",
                "OLEKit",
                "Nimble",
            ],
            exclude: [
                "AGENTS.md",
                "Fixtures",
            ]
        ),
        .testTarget(
            name: "HwpKitCoreTests",
            dependencies: [
                "HwpKitCore",
                "CoreHwp",
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
        .testTarget(
            name: "HwpKitNativeTests",
            dependencies: [
                "HwpKitNative",
                "CoreHwp",
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
        .testTarget(
            name: "HwpKitTests",
            dependencies: [
                "HwpKit",
                "CoreHwp",
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
    ]
)
