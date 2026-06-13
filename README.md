# Hwp-Swift

> If you want English version of documentation, please contact to [sboh1214@gmail.com](sboh1214@gmail.com)

> 본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

[![CI](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml)
[![CD](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml)
[![codecov](https://codecov.io/gh/sboh1214/hwp-swift/branch/main/graph/badge.svg)](https://codecov.io/gh/sboh1214/hwp-swift)

한글 파일을 읽고 쓰기 위한 스위프트 패키지

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

## 기여

[CONTRIBUTING.md](https://github.com/sboh1214/hwp-swift/blob/main/CONTRIBUTING.md)를 방문하세요.

## 라이센스

본 라이브러리는 LGPL 라이센스를 따릅니다.

본 라이브러리의 이름, 주소, 그리고 저작자를 표기하여 주십시오.

스위프트 패키지 매니저와 같이 본 라이브러리를 일체의 변경 없이 의존성으로서 사용한다면 코드 공개의 의무가 없습니다.

![GitHub](https://img.shields.io/github/license/sboh1214/hwp-swift)
