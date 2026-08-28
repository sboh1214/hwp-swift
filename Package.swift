// swift-tools-version:5.9

import PackageDescription

// Linux는 CoreHwp(파서)와 CoreHwpTests만 지원한다
// (HwpKitCore/HwpKitNative/HwpKit)은 CoreText·CoreGraphics 등 Apple 전용
// 프레임워크에 의존하므로 Darwin에서만 빌드한다.
#if canImport(Darwin)
    let buildsForApplePlatforms = true
#else
    let buildsForApplePlatforms = false
#endif

/// raw DEFLATE 해제의 백엔드는 위 **호스트** 분기가 아니라 **타깃** 조건으로
/// 가른다. Apple은 SDK 내장 `Compression`을 쓰고 그 외 플랫폼은 system zlib을
/// `CHwpZlib`로 링크하는데, 그 선택은 `HwpInflate`의 `canImport(Compression)`
/// 즉 타깃 기준이다. 매니페스트의 `#if`는 호스트에서 평가되므로 여기서 가르면
/// macOS 호스트에서 Linux 타깃으로 크로스 컴파일할 때 (`--swift-sdk`) 모듈만
/// 사라져 `no such module 'CHwpZlib'`가 된다. 비-Apple 소비자는 빌드에 zlib
/// 개발 헤더가, 실행에 zlib 런타임이 필요하다 (README "설치").
let nonApplePlatforms: [Platform] = [.linux, .android, .windows, .openbsd, .wasi]

var products: [Product] = [
    .library(name: "CoreHwp", targets: ["CoreHwp"]),
]

var targets: [Target] = [
    // `SWCompression`은 프로덕션 의존성이 아니다 — 테스트가 입력 합성
    // (`Deflate.compress`)과 압축 해제 기준선으로만 쓴다 (#101).
    .target(
        name: "CoreHwp",
        dependencies: [
            "OLEKit",
            .target(name: "CHwpZlib", condition: .when(platforms: nonApplePlatforms)),
        ],
        exclude: [
            "AGENTS.md",
            "Hwpx/AGENTS.md",
            "Models/Section/AGENTS.md",
            "Utils/AGENTS.md",
        ]
    ),
    .testTarget(
        name: "CoreHwpTests",
        dependencies: [
            "CoreHwp",
            "OLEKit",
            "SWCompression",
            "Nimble",
        ],
        exclude: [
            "AGENTS.md",
            "Fixtures",
        ]
    ),
    // 타깃 자체는 플랫폼과 무관하게 선언한다. Apple 빌드에서는 위 조건부
    // 의존 간선이 꺼져 아무도 import하지 않으므로 module map도 읽히지 않는다.
    .systemLibrary(
        name: "CHwpZlib",
        path: "Sources/CHwpZlib",
        providers: [.apt(["zlib1g-dev"]), .yum(["zlib-devel"])]
    ),
]

if buildsForApplePlatforms {
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
                "CoreHwp",
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
                "RenderGoldens",
            ]
        ),
    ]
}

let package = Package(
    name: "Hwp-Swift",
    // CoreHwp(파서)는 tvOS/watchOS도 지원하므로 의존성(SWCompression 등)의
    // 최소 버전과 맞춰 선언한다. platforms 생략은 프로덕트를 숨기지 않고 기본
    // (낮은) 배포 타깃을 부여할 뿐이라 CoreHwp를 회귀시킨다. 뷰어 타깃은
    // buildsForApplePlatforms(위)와 소비자의 프로덕트 선택으로 제외된다 —
    // tvOS/watchOS 소비자는 CoreHwp 프로덕트만 고르면 뷰어 타깃은 빌드되지
    // 않는다 (#1). SWCompression 은 이제 testTarget 전용이지만 platforms 는
    // 패키지 단위라 이 하한을 그대로 유지해야 한다.
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
