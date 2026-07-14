// swift-tools-version:5.9

import PackageDescription

// Linux는 CoreHwp(파서)와 CoreHwpTests만 지원한다
// (HwpKitCore/HwpKitNative/HwpKit)은 CoreText·CoreGraphics 등 Apple 전용
// 프레임워크에 의존하므로 Darwin에서만 빌드한다.
#if canImport(Darwin)
    let buildsViewerTargets = true
#else
    let buildsViewerTargets = false
#endif

var products: [Product] = [
    .library(name: "CoreHwp", targets: ["CoreHwp"]),
]

var targets: [Target] = [
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
]

if buildsViewerTargets {
    products += [
        .library(name: "HwpKitCore", targets: ["HwpKitCore"]),
        .library(name: "HwpKitNative", targets: ["HwpKitNative"]),
        .library(name: "HwpKit", targets: ["HwpKit"]),
    ]
    targets += [
        .target(
            name: "HwpKitCore",
            dependencies: [
                "CoreHwp",
            ],
            exclude: [
                "AGENTS.md",
            ]
        ),
        .target(
            name: "HwpKitNative",
            dependencies: [
                "HwpKitCore",
                "CoreHwp",
            ],
            exclude: [
                "AGENTS.md",
            ]
        ),
        .target(
            name: "HwpKit",
            dependencies: [
                "HwpKitNative",
            ],
            exclude: [
                "AGENTS.md",
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
                "HwpKitNative",
                "HwpKitCore",
                "CoreHwp",
                .product(name: "Nimble", package: "Nimble"),
            ],
            exclude: [
                "BlockSnapshots",
            ]
        ),
    ]
}

let package = Package(
    name: "Hwp-Swift",
    // 뷰어 타깃(HwpKitCore/Native/HwpKit)은 PlatformImage·CoreImage 등
    // macOS/iOS 전용 API에 의존하므로 그 둘만 선언한다 — tvOS/watchOS를
    // 선언하면 뷰어 프로덕트가 그 목적지에도 노출돼 크로스 컴파일이 실패한다
    // (canImport(Darwin)은 매니페스트 호스트에서 평가돼 항상 참, #1).
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/CoreOffice/OLEKit.git", exact: "0.3.1"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1"),

        .package(url: "https://github.com/Quick/Nimble", exact: "13.8.0"),

        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0"),
    ],
    targets: targets
)
