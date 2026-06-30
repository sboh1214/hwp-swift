# Hwp-Swift

> [hwp-swift.sboh.dev](https://hwp-swift.sboh.dev)

> 본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

[![CI](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml)
[![CD](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml)

한글 파일을 읽기 위한 스위프트 패키지

## 설치

### 스위프트 패키지 관리자

Xcode에서 ```File``` > ```Swift Packages``` > ```Add Package Dependency...``` 메뉴를 선택하세요.

또는 의존성을 아래와 같이 수동으로 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/sboh1214/hwp-swift.git", branch: "main"),
],
```

> 안정 릴리스가 태깅되면 `branch: "main"` 대신 `from: "x.y.z"`로 고정하는 것을 권장합니다.

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
