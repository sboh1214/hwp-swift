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
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/OLEKit.git", exact: "0.3.1"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1"),

        .package(url: "https://github.com/Quick/Nimble", exact: "9.2.1"),
    ],
    targets: [
        .target(
            name: "CoreHwp",
            dependencies: [
                "OLEKit",
                "SWCompression",
            ]
        ),
        .testTarget(
            name: "CoreHwpTests",
            dependencies: [
                "CoreHwp",
                "Nimble",
            ]
        ),
    ]
)
