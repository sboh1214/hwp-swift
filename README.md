# Hwp-Swift

> [hwp-swift.sboh.dev](https://hwp-swift.sboh.dev)

> 본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

[![CI](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml)
[![CD](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml)

한글 파일을 읽기 위한 스위프트 패키지

## 설치

### 요구 사항

Apple 플랫폼(macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+)은 추가 설치가
필요 없습니다 — 압축 해제에 SDK 내장 `Compression`을 씁니다.

Linux 등 그 외 플랫폼에서는 **zlib**이 필요합니다. 빌드에는 개발 헤더
(`apt install zlib1g-dev`, rpm 계열은 `dnf install zlib-devel`), 실행에는 zlib
런타임이 있어야 합니다. 공식 Swift 도커 이미지에는 이미 포함되어 있습니다.

### 스위프트 패키지 관리자

Xcode에서 ```File``` > ```Swift Packages``` > ```Add Package Dependency...``` 메뉴를 선택하세요.

또는 의존성을 아래와 같이 수동으로 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/sboh1214/hwp-swift.git", .upToNextMinor(from: "0.16.0")),
],
```

> 이 저장소는 1.0 전까지 파괴 변경을 minor 버전에 싣습니다. `from:`은 다음 minor의 파괴 변경을
> 자동 수용하므로(`0.16.0..<1.0.0`), `.upToNextMinor`로 고정하고 minor 업데이트는
> [릴리스 노트](https://github.com/sboh1214/hwp-swift/releases)를 확인한 뒤 올리는 것을 권장합니다.

## 라이브러리 구조

![Structure](https://github.com/sboh1214/hwp-swift/blob/main/.github/structure/Structure.png)

## 지원 범위와 테스트 자료

CoreHwp는 현재 읽기 전용 binary HWP reader에 초점을 둡니다. 파싱 실패는
`HwpError`로 반환하고, 아직 완전히 해석하지 못한 record/control은 raw payload를
보존합니다. 쓰기/저장은 아직 지원하지 않습니다.

자세한 reader 지원 범위는 [Sources/CoreHwp/AGENTS.md](Sources/CoreHwp/AGENTS.md),
fixture 기준과 확보 현황은
[Tests/CoreHwpTests/Fixtures/README.md](Tests/CoreHwpTests/Fixtures/README.md)를
참고하세요.

뷰어 타깃(`HwpKitCore` / `HwpKitNative` / `HwpKit`)은 SwiftUI 문서 뷰, 문서 내
검색(`HwpSearchController` + `HwpSearchBar`), 개요·책갈피 탐색 목록
(`HwpDocumentMetadata.outline`), PDF 내보내기(`HwpPDFExporter`), 쪽 축소판
(`HwpPageThumbnails`)을 제공합니다. PDF·축소판·검색 하이라이트 모두 화면 렌더와
같은 조판을 씁니다.

경계는 **바이트와 컴포넌트는 라이브러리, 호스트 chrome과 정책은 앱**입니다 —
검색 바처럼 호스트가 놓은 자리만 차지하는 컴포넌트는 제공하지만, 저장 패널·
인쇄·공유 UI와 Cmd+F 같은 전역 단축키는 앱이 정합니다. 개요 목록·축소판
그리드처럼 행 레이아웃과 플랫폼 chrome 분기가 붙는 목록 UI도 앱 몫입니다 —
재료(탐색 목록·비트맵)까지가 라이브러리입니다. 배선 예시는
[Sample/README.md](Sample/README.md)에 있습니다.

## 폰트

본 라이브러리는 **폰트를 동봉하지 않습니다.** HWP 문서가 지정한 글꼴은 실행 기기에
설치된 폰트로 해석하고, 없으면 명조/고딕 계열 시스템 폰트로 폴백합니다.

재현도를 높이려면 한글과컴퓨터가 무료 배포하는 **함초롬체**를 사용자가 정식 경로로
직접 설치하십시오. 시스템 폰트 디렉터리에 설치된 함초롬체는 별도 설정 없이 사용됩니다.

한컴오피스 앱 번들 안의 폰트(`Contents/Resources/Hnc/Shared/TTF/`)는 **기본적으로
사용하지 않습니다.** 그 디렉터리에는 한컴이 자사 오피스 안에서 쓰도록 라이선스받은
타사 폰트(Monotype·한양정보통신·윤디자인 등)가 섞여 있어, 제3자 앱이 아무 선택 없이
로드하는 것이 라이선스 범위 밖일 수 있기 때문입니다. 한글.app과의 실물 대조처럼
필요한 경우에만 opt-in 합니다.

```bash
HWP_HANCOM_FONTS=1 swift test
```

코드에서 직접 켜려면 `HwpFontResolver(usesInstalledHancomFonts: true)`를 씁니다.
켠 뒤 해당 폰트들의 라이선스 준수는 켠 쪽 책임입니다.

## 기여

[CONTRIBUTING.md](https://github.com/sboh1214/hwp-swift/blob/main/CONTRIBUTING.md)를 방문하세요.

## Special Thanks to

### edwardkim/rhwp

[edwardkim/rhwp](https://github.com/edwardkim/rhwp)의
[`hwp_spec_errata.md`](https://github.com/edwardkim/rhwp/blob/devel/mydocs/tech/hwp_spec_errata.md)는
공식 HWP 5.0 공개 문서와 실제 binary 동작이 다른 지점을 확인하는 데 큰 도움을 주었습니다.
CoreHwp는 이 정오표와 sample 분석을 보조 근거로 삼아 record layout, control payload,
bit field 해석을 검토하되, XCTest fixture는 실제 한글과컴퓨터 프로그램으로 생성하거나
재저장한 `.hwp`를 기준으로 유지합니다. 세부 대조 기록은
[Documentation/ErrataAudit.md](Documentation/ErrataAudit.md)에 정리했습니다.

## Trademark

"한글", "한컴", "HWP", "HWPX"는 주식회사 한글과컴퓨터의 등록 상표입니다. 본 프로젝트는 한글과컴퓨터와 제휴, 후원, 승인 관계가 없는 독립적인 오픈소스 프로젝트입니다.

"Hangul", "Hancom", "HWP", and "HWPX" are registered trademarks of Hancom Inc. This project is an independent open-source project with no affiliation, sponsorship, or endorsement by Hancom Inc.

## 라이센스

본 라이브러리는 LGPL 라이센스를 따릅니다.

본 라이브러리의 이름, 주소, 그리고 저작자를 표기하여 주십시오.

스위프트 패키지 매니저와 같이 본 라이브러리를 일체의 변경 없이 의존성으로서 사용한다면 코드 공개의 의무가 없습니다.

![GitHub](https://img.shields.io/github/license/sboh1214/hwp-swift)
