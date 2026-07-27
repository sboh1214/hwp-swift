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
    // CoreHwp(파서)는 tvOS/watchOS도 지원하므로 의존성(SWCompression 등)의
    // 최소 버전과 맞춰 선언한다. platforms 생략은 프로덕트를 숨기지 않고 기본
    // (낮은) 배포 타깃을 부여할 뿐이라 CoreHwp를 회귀시킨다. 뷰어 타깃은
    // buildsViewerTargets(위)와 소비자의 프로덕트 선택으로 제외된다 —
    // tvOS/watchOS 소비자는 CoreHwp 프로덕트만 고르면 뷰어 타깃은 빌드되지
    // 않는다 (#1).
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
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
